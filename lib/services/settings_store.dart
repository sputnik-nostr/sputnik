import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_seed_color.dart';
import '../models/identity.dart';
import '../models/identity_index.dart';
import '../models/relay.dart';
import '../nostr/keys.dart';
import 'error_reporting.dart';

/// Storage seam so tests can fake [SettingsStore.secretStore].
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// flutter_secure_storage, which stores entries differently per platform. On
/// Android each one is encrypted on its own, but entry names stay plaintext.
/// On Linux they all share one libsecret item, a JSON object that is decrypted
/// whole on every call and found by the application ID, so changing that ID
/// hides every key until they are migrated.
class _SecureSecretStore implements SecretStore {
  const _SecureSecretStore();

  /// The default would erase every stored key on a keystore error.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Keeps the default if [load] finds nothing; a failed load is never saved.
Future<void> bindPersisted<T>(
  ValueNotifier<T> notifier,
  Future<T?> Function() load,
  Future<void> Function(T value) save,
) async {
  try {
    final loaded = await load();
    if (loaded != null) notifier.value = loaded;
  } catch (error, stack) {
    reportError('loading persisted $T', error, stack);
    return;
  }
  var pending = Future<void>.value();
  notifier.addListener(() {
    final value = notifier.value;
    pending = pending.then((_) async {
      try {
        await save(value);
      } catch (error, stack) {
        reportError('saving $T', error, stack);
      }
    });
  });
}

class SettingsStore {
  SettingsStore._();

  static const _themeModeKey = 'theme_mode';
  static const _seedColorKey = 'seed_color';
  static const _selectedRelaysKey = 'selected_relays';
  static const _customRelaysKey = 'custom_relays';
  static const _identitiesKey = 'identities';
  static const _activeIdentityPubkeyKey = 'active_identity_pubkey';
  static const _identitySecretPrefix = 'identity_secret_';
  // Named before note images had their own switch; kept so the setting stays.
  static const _loadProfileImagesKey = 'load_media';
  static const _loadNoteImagesKey = 'load_note_images';
  static const _autoVerifyNip05Key = 'auto_verify_nip05';
  static const _hiddenPaymentTargetTypesKey = 'hidden_payment_target_types';
  static const _confirmBeforeReactingKey = 'confirm_before_reacting';

  /// Keys earlier versions wrote and nothing reads now.
  static const _obsoleteKeys = [
    'profile_cache',
    'bookmarked_ids',
    'current_user_profile',
    'note_media_mode',
  ];

  /// Backs the identity index and each identity's private key.
  @visibleForTesting
  static SecretStore secretStore = const _SecureSecretStore();

  /// How [loadSecretKey] turns stored hex into a key; tests watch the keys.
  @visibleForTesting
  static SecretKey Function(String hex) secretKeyFromHex = SecretKey.fromHex;

  static Future<bool?> _loadFlag(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key);
  }

  static Future<void> _saveFlag(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  /// Drops leftovers such as the plaintext profile cache from before Hive.
  static Future<void> removeObsoleteKeys() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _obsoleteKeys) {
      await prefs.remove(key);
    }
  }

  static Future<ThemeMode?> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_themeModeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null,
    };
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  static Future<AppSeedColor?> loadSeedColor() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSeedColor.values.asNameMap()[prefs.getString(_seedColorKey)];
  }

  static Future<void> saveSeedColor(AppSeedColor color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seedColorKey, color.name);
  }

  static Future<Set<String>> loadSelectedRelays(Set<String> knownRelays) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_selectedRelaysKey);
    if (saved == null) return defaultRelays.toSet();

    final stillKnown = saved
        .where(isRelayUrl)
        .toSet()
        .intersection(knownRelays);
    if (stillKnown.isEmpty) {
      await saveSelectedRelays(defaultRelays.toSet());
      return defaultRelays.toSet();
    }
    return stillKnown;
  }

  static Future<void> saveSelectedRelays(Set<String> relays) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedRelaysKey, relays.toList());
  }

  static Future<Set<String>> loadCustomRelays() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_customRelaysKey);
    if (saved == null) return {};
    return saved.where(isRelayUrl).toSet();
  }

  static Future<void> saveCustomRelays(Set<String> relays) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customRelaysKey, relays.toList());
  }

  /// The index change in progress, if any.
  static Future<void>? _running;

  /// Runs index changes one at a time. Each starts from the index in storage,
  /// so none may begin before the one ahead of it has written.
  static Future<T> _serialized<T>(Future<T> Function() change) async {
    for (var running = _running; running != null; running = _running) {
      await running;
    }
    final done = Completer<void>();
    _running = done.future;
    try {
      return await change();
    } finally {
      _running = null;
      done.complete();
    }
  }

  static Future<IdentityIndex> _readIndex() async {
    final raw = await secretStore.read(_identitiesKey);
    return raw == null ? IdentityIndex.empty : IdentityIndex.parse(raw);
  }

  /// Stores [value] and reads it back, so it only counts as stored once it
  /// can be read again.
  static Future<void> _writeVerified(String key, String value) async {
    await secretStore.write(key, value);
    if (await secretStore.read(key) != value) {
      throw StateError('secure storage did not keep $key');
    }
  }

  /// The identity index, after moving any private key that an older version
  /// stored inside it into an entry of its own.
  ///
  /// Throws if the index can't be read. Until it can, nothing may be added or
  /// removed: every change starts from the index in storage.
  static Future<IdentityIndex> loadIdentityIndex() => _serialized(() async {
    final index = await _readIndex();

    var migrated = index;
    for (final inline in index.inlineKeys) {
      try {
        if (await loadPrivateKey(inline.pubkeyHex) == null) {
          await _writeVerified(
            '$_identitySecretPrefix${inline.pubkeyHex}',
            inline.privkeyHex,
          );
        }
        migrated = migrated.withoutInlineKey(inline.pubkeyHex);
      } catch (error, stack) {
        // The key stays inline, and in every later write, until it is stored.
        reportError('moving a private key out of the index', error, stack);
      }
    }
    if (migrated.encode() == index.encode()) return index;

    try {
      await _writeVerified(_identitiesKey, migrated.encode());
    } catch (error, stack) {
      reportError('saving the identity index', error, stack);
      return index;
    }
    return migrated;
  });

  /// Stores [privkeyHex] for [identity] and lists the identity.
  ///
  /// The key goes first, so an identity is never listed without one. Throws if
  /// either can't be saved, and then the identity is not listed.
  static Future<IdentityIndex> addIdentity(
    Identity identity,
    String privkeyHex,
  ) => _serialized(() async {
    final index = await _readIndex();
    if (index.contains(identity.pubkeyHex)) return index;

    await _writeVerified(
      '$_identitySecretPrefix${identity.pubkeyHex}',
      privkeyHex,
    );
    final next = index.withIdentity(identity);
    await _writeVerified(_identitiesKey, next.encode());
    return next;
  });

  /// Deletes the key of [pubkeyHex], then unlists the identity.
  ///
  /// Throws if the key can't be deleted, and then the identity stays listed:
  /// unlisting it first would leave a key that nothing refers to any more.
  static Future<IdentityIndex> removeIdentity(String pubkeyHex) =>
      _serialized(() async {
        final index = await _readIndex();
        await secretStore.delete('$_identitySecretPrefix$pubkeyHex');
        final next = index.without(pubkeyHex);
        await _writeVerified(_identitiesKey, next.encode());
        return next;
      });

  static Future<String?> loadActiveIdentityPubkey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeIdentityPubkeyKey);
  }

  static Future<void> saveActiveIdentityPubkey(String? pubkeyHex) async {
    final prefs = await SharedPreferences.getInstance();
    if (pubkeyHex == null) {
      await prefs.remove(_activeIdentityPubkeyKey);
    } else {
      await prefs.setString(_activeIdentityPubkeyKey, pubkeyHex);
    }
  }

  /// Read from secure storage each time it is needed, never cached.
  static Future<String?> loadPrivateKey(String pubkeyHex) {
    return secretStore.read('$_identitySecretPrefix$pubkeyHex');
  }

  /// [loadPrivateKey] as a [SecretKey], or null if it is missing, malformed or
  /// not the key of [pubkeyHex], so a key kept under the wrong name never
  /// signs.
  static Future<SecretKey?> loadSecretKey(String pubkeyHex) async {
    final privkeyHex = await loadPrivateKey(pubkeyHex);
    if (privkeyHex == null) return null;

    final SecretKey secretKey;
    try {
      secretKey = secretKeyFromHex(privkeyHex);
    } on ArgumentError {
      return null;
    }
    var matches = false;
    try {
      matches = xonlyPubkeyHex(secretKey) == pubkeyHex;
    } on ArgumentError {
      // Valid hex, but not a point on the curve (zero, or above the order).
    } finally {
      if (!matches) secretKey.wipe();
    }
    return matches ? secretKey : null;
  }

  static Future<void> savePrivateKey(String pubkeyHex, String privkeyHex) {
    return secretStore.write('$_identitySecretPrefix$pubkeyHex', privkeyHex);
  }

  static Future<bool?> loadLoadProfileImages() =>
      _loadFlag(_loadProfileImagesKey);

  static Future<void> saveLoadProfileImages(bool value) =>
      _saveFlag(_loadProfileImagesKey, value);

  static Future<bool?> loadLoadNoteImages() => _loadFlag(_loadNoteImagesKey);

  static Future<void> saveLoadNoteImages(bool value) =>
      _saveFlag(_loadNoteImagesKey, value);

  static Future<bool?> loadAutoVerifyNip05() => _loadFlag(_autoVerifyNip05Key);

  static Future<void> saveAutoVerifyNip05(bool value) =>
      _saveFlag(_autoVerifyNip05Key, value);

  static Future<bool?> loadConfirmBeforeReacting() =>
      _loadFlag(_confirmBeforeReactingKey);

  static Future<void> saveConfirmBeforeReacting(bool value) =>
      _saveFlag(_confirmBeforeReactingKey, value);

  static Future<Set<String>?> loadHiddenPaymentTargetTypes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_hiddenPaymentTargetTypesKey)?.toSet();
  }

  static Future<void> saveHiddenPaymentTargetTypes(Set<String> types) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenPaymentTargetTypesKey, types.toList());
  }
}
