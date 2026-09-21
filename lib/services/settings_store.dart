import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_seed_color.dart';
import '../models/identity.dart';
import '../models/relay.dart';

/// Storage seam so tests can fake [SettingsStore.secretStore].
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

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

/// Reports [error] through [FlutterError.reportError] instead of throwing.
void _reportPersistenceError(String what, Object error, StackTrace stack) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'sputnik',
      context: ErrorDescription(what),
    ),
  );
}

/// Loads a notifier's persisted value and wires it to save on every change.
/// Used to bind each of the app's settings notifiers without repeating the
/// "load, assign, add a saving listener" sequence for each one.
Future<void> bindPersisted<T>(
  ValueNotifier<T> notifier,
  Future<T> Function() load,
  Future<void> Function(T value) save,
) async {
  try {
    notifier.value = await load();
  } catch (error, stack) {
    _reportPersistenceError('loading persisted $T', error, stack);
    return;
  }
  var pending = Future<void>.value();
  notifier.addListener(() {
    final value = notifier.value;
    pending = pending.then((_) async {
      try {
        await save(value);
      } catch (error, stack) {
        _reportPersistenceError('saving $T', error, stack);
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
  static const _loadMediaKey = 'load_media';
  static const _loadNoteImagesKey = 'load_note_images';
  static const _hiddenPaymentTargetTypesKey = 'hidden_payment_target_types';

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

  /// Drops leftovers such as the plaintext profile cache from before Hive.
  static Future<void> removeObsoleteKeys() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _obsoleteKeys) {
      await prefs.remove(key);
    }
  }

  static Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_themeModeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
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

  static Future<AppSeedColor> loadSeedColor() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_seedColorKey);
    return AppSeedColor.values.firstWhere(
      (color) => color.name == name,
      orElse: () => AppSeedColor.blue,
    );
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

  static Future<List<Identity>> loadIdentities() async {
    final raw = await secretStore.read(_identitiesKey);
    if (raw == null) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    final identities = <Identity>[];
    var migratedAny = false;
    var migrationFailed = false;

    for (final item in decoded) {
      final Identity identity;
      final String? legacyPrivkeyHex;
      try {
        final map = item as Map<String, dynamic>;
        identity = Identity.fromJson(map);
        final legacy = map['privkeyHex'];
        legacyPrivkeyHex = legacy is String ? legacy : null;
      } catch (_) {
        // Skip malformed identity entries.
        continue;
      }
      identities.add(identity);
      if (legacyPrivkeyHex == null) continue;

      // Migrate a private key that used to live inline here.
      try {
        if (await loadPrivateKey(identity.pubkeyHex) == null) {
          await savePrivateKey(identity.pubkeyHex, legacyPrivkeyHex);
        }
        migratedAny = true;
      } catch (_) {
        migrationFailed = true;
      }
    }

    // Rewriting the index would drop an inline key that failed to migrate.
    if (migratedAny && !migrationFailed) await saveIdentities(identities);

    return identities;
  }

  static Future<void> saveIdentities(List<Identity> identities) async {
    await secretStore.write(
      _identitiesKey,
      jsonEncode([for (final identity in identities) identity.toJson()]),
    );
  }

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

  /// One secure-storage entry per identity, read only when needed.
  static Future<String?> loadPrivateKey(String pubkeyHex) {
    return secretStore.read('$_identitySecretPrefix$pubkeyHex');
  }

  static Future<void> savePrivateKey(String pubkeyHex, String privkeyHex) {
    return secretStore.write('$_identitySecretPrefix$pubkeyHex', privkeyHex);
  }

  static Future<void> deletePrivateKey(String pubkeyHex) {
    return secretStore.delete('$_identitySecretPrefix$pubkeyHex');
  }

  static Future<bool> loadLoadMedia() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loadMediaKey) ?? false;
  }

  static Future<void> saveLoadMedia(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loadMediaKey, value);
  }

  static Future<bool> loadLoadNoteImages() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loadNoteImagesKey) ?? false;
  }

  static Future<void> saveLoadNoteImages(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loadNoteImagesKey, value);
  }

  static Future<Set<String>> loadHiddenPaymentTargetTypes() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_hiddenPaymentTargetTypesKey) ?? []).toSet();
  }

  static Future<void> saveHiddenPaymentTargetTypes(Set<String> types) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenPaymentTargetTypesKey, types.toList());
  }
}
