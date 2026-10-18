import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_seed_color.dart';
import '../models/identity.dart';
import '../models/identity_index.dart';
import '../models/relay.dart';
import '../nostr/hex.dart';
import '../nostr/keys.dart';
import 'error_reporting.dart';

/// Storage seam so tests can fake [SettingsStore.secretStore].
abstract class SecretStore {
  Future<String?> read(String key);
  Future<Map<String, String>> readAll();
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// flutter_secure_storage, which stores entries differently per platform. On
/// Android each one is encrypted on its own, but entry names stay plaintext,
/// so a key's entry is named after a random slot rather than after its pubkey.
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
  Future<Map<String, String>> readAll() => _storage.readAll();

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

/// A private key in secure storage that no identity in the index refers to,
/// stored under [name]: the identity it belongs to is [pubkeyHex].
typedef UnlistedKey = ({String name, String pubkeyHex});

class SettingsStore {
  SettingsStore._();

  static const _themeModeKey = 'theme_mode';
  static const _seedColorKey = 'seed_color';
  static const _selectedRelaysKey = 'selected_relays';
  static const _customRelaysKey = 'custom_relays';
  static const _identitiesKey = 'identities';
  static const _activeIdentityPubkeyKey = 'active_identity_pubkey';
  static const _identitySecretPrefix = 'identity_secret_';
  static const _plaintextIdentitiesBackupKey = 'identities_from_preferences';
  // Named before note images had their own switch; kept so the setting stays.
  static const _loadProfileImagesKey = 'load_media';
  static const _loadNoteImagesKey = 'load_note_images';
  static const _autoVerifyNip05Key = 'auto_verify_nip05';
  static const _hiddenPaymentTargetTypesKey = 'hidden_payment_target_types';
  static const _confirmBeforeReactingKey = 'confirm_before_reacting';

  /// Keys earlier versions wrote and nothing reads now. Not `identities`: while
  /// it holds private keys in plaintext it holds the only copy of them, and
  /// this runs alongside the startup, in no particular order, so only
  /// [_adoptPlaintextIdentities] may remove it, once the keys are stored.
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

  static String _secretName(String name) => '$_identitySecretPrefix$name';

  static final _random = Random.secure();

  /// A name for a key's entry that says nothing about whose key it holds.
  static String _newSlot() =>
      hexEncode([for (var i = 0; i < 16; i++) _random.nextInt(256)]);

  /// The pubkey of [privkeyHex], or null if it is not a secp256k1 key.
  static String? _pubkeyHexOf(String privkeyHex) {
    try {
      final secretKey = SecretKey.fromHex(privkeyHex);
      try {
        return xonlyPubkeyHex(secretKey);
      } finally {
        secretKey.wipe();
      }
    } on ArgumentError {
      return null;
    }
  }

  /// The private key kept for [pubkeyHex]: in its slot or, if it has none or
  /// the slot is empty, under the name older versions gave it.
  static Future<String?> _readKey(IdentityIndex index, String pubkeyHex) async {
    final slot = index.slotOf(pubkeyHex);
    if (slot != null) {
      final stored = await secretStore.read(_secretName(slot));
      if (stored != null) return stored;
    }
    return secretStore.read(_secretName(pubkeyHex));
  }

  /// The identity index, after bringing what older versions stored up to date:
  /// identities kept in preferences, private keys inside the index or named
  /// after their pubkey, and the active identity kept in preferences.
  ///
  /// Throws if the index can't be read. Until it can, nothing may be added or
  /// removed: every change starts from the index in storage.
  static Future<IdentityIndex> loadIdentityIndex() => _serialized(() async {
    // Each step starts from the index in storage, so a step that failed after
    // its write took effect cannot leave the next one working on a stale copy.
    await _adoptPlaintextIdentities();
    await _moveKeysToSlots();
    await _adoptActivePointer();
    return _readIndex();
  });

  /// Builds from before private keys moved to secure storage kept the
  /// identities, keys included, in preferences. Moves them into secure storage.
  ///
  /// Each key goes into a slot and the identities into the index, both read
  /// back, and only then does the entry leave preferences. Anything the entry
  /// holds that can't become an identity as it is (damaged JSON, a key that is
  /// not its pubkey's, a different key stored for that pubkey already) is first
  /// copied as it was into secure storage, so that nothing is lost silently. A
  /// failure leaves the entry in preferences, to be tried again at the next
  /// start.
  static Future<void> _adoptPlaintextIdentities() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.get(_identitiesKey);
      if (raw == null) return;

      final plain = _parsePlaintextIdentities(raw);
      var complete = plain.complete;
      final index = await _readIndex();
      var adopted = index;
      for (final held in plain.held) {
        final pubkeyHex = held.identity.pubkeyHex;
        if (adopted.contains(pubkeyHex) &&
            adopted.identities.every((i) => i.pubkeyHex != pubkeyHex)) {
          complete = false; // An entry this version cannot read names it.
          continue;
        }
        final stored = await _readKey(adopted, pubkeyHex);
        if (stored != null && stored != held.privkeyHex) {
          complete = false; // The key that is stored stays.
          continue;
        }
        if (stored == null) {
          final slot = adopted.slotOf(pubkeyHex) ?? _newSlot();
          await _writeVerified(_secretName(slot), held.privkeyHex);
          adopted = adopted.contains(pubkeyHex)
              ? adopted.withSlot(pubkeyHex, slot)
              : adopted.withIdentity(held.identity, slot: slot);
        } else if (!adopted.contains(pubkeyHex)) {
          adopted = adopted.withIdentity(held.identity);
        }
      }
      if (adopted.encode() != index.encode()) {
        await _writeVerified(_identitiesKey, adopted.encode());
      }
      if (!complete) {
        await _writeVerified(_plaintextIdentitiesBackupKey, '$raw');
      }
      await prefs.remove(_identitiesKey);
    } catch (error, stack) {
      reportError('moving identities out of preferences', error, stack);
    }
  }

  /// The identities in a plaintext preferences entry whose private key is their
  /// own, and whether those are all it holds.
  static ({List<({Identity identity, String privkeyHex})> held, bool complete})
  _parsePlaintextIdentities(Object raw) {
    final held = <({Identity identity, String privkeyHex})>[];
    final List<dynamic> items;
    try {
      items = jsonDecode(raw as String) as List<dynamic>;
    } catch (_) {
      return (held: held, complete: false);
    }
    var complete = true;
    for (final item in items) {
      try {
        final map = item as Map<String, dynamic>;
        final identity = Identity.fromJson(map);
        final privkeyHex = map['privkeyHex'] as String;
        if (_pubkeyHexOf(privkeyHex) != identity.pubkeyHex) {
          throw const FormatException("the key is not the identity's");
        }
        held.add((identity: identity, privkeyHex: privkeyHex));
      } catch (_) {
        complete = false;
      }
    }
    return (held: held, complete: complete);
  }

  /// Gives each private key that is not in a slot yet one: those an older
  /// version stored inside the index, and those it named after the pubkey.
  ///
  /// A key is copied and read back first, then the index naming its slot is
  /// saved and read back, and only then is the old pubkey-named copy deleted. A
  /// failure at any step leaves every key where it was found, at worst also in
  /// a slot nothing refers to. What can't be moved stays where it is, in the
  /// index too, and is tried again at the next start.
  static Future<void> _moveKeysToSlots() async {
    final index = await _readIndex();
    var moved = index;
    final namedAfterPubkey = <String>[];
    for (final pending in index.keysToMove) {
      try {
        final pubkeyHex = pending.pubkeyHex;
        final existingSlot = pending.slot;
        final inSlot = existingSlot == null
            ? null
            : await secretStore.read(_secretName(existingSlot));
        final named = await secretStore.read(_secretName(pubkeyHex));
        final copies = {?inSlot, ?named, ?pending.inlineKey};
        if (copies.isEmpty) continue;
        if (copies.length > 1) {
          throw StateError(
            'different private keys are stored for one identity',
          );
        }
        final privkeyHex = copies.single;
        if (_pubkeyHexOf(privkeyHex) != pubkeyHex) {
          throw StateError("the stored private key is not the identity's");
        }

        final slot = existingSlot ?? _newSlot();
        if (inSlot == null) {
          await _writeVerified(_secretName(slot), privkeyHex);
        }
        moved = moved.withSlot(pubkeyHex, slot).withoutInlineKey(pubkeyHex);
        if (named != null) namedAfterPubkey.add(pubkeyHex);
      } catch (error, stack) {
        reportError('moving a private key into its own entry', error, stack);
      }
    }
    if (moved.encode() == index.encode()) return;

    try {
      await _writeVerified(_identitiesKey, moved.encode());
    } catch (error, stack) {
      reportError('saving the identity index', error, stack);
      return;
    }
    for (final pubkeyHex in namedAfterPubkey) {
      try {
        await secretStore.delete(_secretName(pubkeyHex));
      } catch (error, stack) {
        reportError(
          'deleting a private key entry named after its pubkey',
          error,
          stack,
        );
      }
    }
  }

  /// Moves the active identity from preferences, which anyone who can read the
  /// app's files can read, into the index.
  static Future<void> _adoptActivePointer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pubkeyHex = prefs.getString(_activeIdentityPubkeyKey);
      if (pubkeyHex == null) return;

      final index = await _readIndex();
      if (index.active == null && index.contains(pubkeyHex)) {
        await _writeVerified(
          _identitiesKey,
          index.withActive(pubkeyHex).encode(),
        );
      }
      await prefs.remove(_activeIdentityPubkeyKey);
    } catch (error, stack) {
      reportError('moving the active identity into the index', error, stack);
    }
  }

  /// Stores [privkeyHex] in a slot of its own for [identity] and lists the
  /// identity.
  ///
  /// The key goes first, so an identity is never listed without one. Throws if
  /// either can't be saved, and then the identity is not listed.
  static Future<IdentityIndex> addIdentity(
    Identity identity,
    String privkeyHex,
  ) => _serialized(() async {
    final index = await _readIndex();
    if (index.contains(identity.pubkeyHex)) return index;

    final slot = _newSlot();
    await _writeVerified(_secretName(slot), privkeyHex);
    final next = index.withIdentity(identity, slot: slot);
    await _writeVerified(_identitiesKey, next.encode());
    return next;
  });

  /// Deletes the key of [pubkeyHex], then unlists the identity.
  ///
  /// Throws if the key can't be deleted, and then the identity stays listed:
  /// unlisting it first would leave a key that nothing refers to any more. If
  /// only the unlisting fails, the identity stays listed without a key and can
  /// be deleted again.
  static Future<IdentityIndex> removeIdentity(String pubkeyHex) =>
      _serialized(() async {
        final index = await _readIndex();
        final slot = index.slotOf(pubkeyHex);
        if (slot != null) await secretStore.delete(_secretName(slot));
        // The copy older versions named after the pubkey, if never moved.
        await secretStore.delete(_secretName(pubkeyHex));
        final next = index.without(pubkeyHex);
        await _writeVerified(_identitiesKey, next.encode());
        return next;
      });

  /// Looks through the private keys in secure storage for ones the index does
  /// not account for, such as a key whose identity never made it into the
  /// index, and returns those of identities that are not listed so that they
  /// can be listed again.
  ///
  /// Any other copy of the key of a listed identity, which a failure part way
  /// through a move can leave behind, is deleted when the identity's own entry
  /// holds the same key.
  ///
  /// This hands every stored key to the app for as long as it takes to look at
  /// it, so it is not meant to run more often than a start.
  static Future<List<UnlistedKey>> reconcileStoredKeys() =>
      _serialized(() async {
        final index = await _readIndex();
        final stored = await secretStore.readAll();
        final unlisted = <UnlistedKey>[];
        final strayCopies = <String>[];
        for (final entry in stored.entries) {
          if (!entry.key.startsWith(_identitySecretPrefix)) continue;
          final name = entry.key.substring(_identitySecretPrefix.length);
          if (index.refersTo(name)) continue;
          final pubkeyHex = _pubkeyHexOf(entry.value);
          if (pubkeyHex == null) continue;

          if (!index.contains(pubkeyHex)) {
            if (unlisted.every((key) => key.pubkeyHex != pubkeyHex)) {
              unlisted.add((name: name, pubkeyHex: pubkeyHex));
            }
            continue;
          }
          final own = stored[_secretName(index.slotOf(pubkeyHex) ?? pubkeyHex)];
          if (own == entry.value) strayCopies.add(name);
        }

        for (final name in strayCopies) {
          try {
            await secretStore.delete(_secretName(name));
          } catch (error, stack) {
            reportError('deleting a stray copy of a private key', error, stack);
          }
        }
        return unlisted..sort((a, b) => a.pubkeyHex.compareTo(b.pubkeyHex));
      });

  /// Lists the identity of [key] again, with the key where it is.
  ///
  /// Throws if the key is gone or no longer the identity's, and then nothing
  /// is changed.
  static Future<IdentityIndex> restoreIdentity(UnlistedKey key) =>
      _serialized(() async {
        final index = await _readIndex();
        if (index.contains(key.pubkeyHex)) return index;

        final stored = await secretStore.read(_secretName(key.name));
        if (stored == null || _pubkeyHexOf(stored) != key.pubkeyHex) {
          throw StateError('the key is no longer stored');
        }
        final identity = Identity(
          pubkeyHex: key.pubkeyHex,
          createdAt: DateTime.now(),
        );
        // A key named after its pubkey has no slot: the next start moves it.
        final next = index.withIdentity(
          identity,
          slot: key.name == key.pubkeyHex ? null : key.name,
        );
        await _writeVerified(_identitiesKey, next.encode());
        return next;
      });

  /// Records the active identity in the index, where only the app can read it.
  /// Does nothing for a pubkey that is not listed.
  static Future<void> saveActiveIdentityPubkey(String? pubkeyHex) =>
      _serialized(() async {
        final index = await _readIndex();
        if (pubkeyHex != null && !index.contains(pubkeyHex)) return;
        if (index.active == pubkeyHex) return;
        await _writeVerified(
          _identitiesKey,
          index.withActive(pubkeyHex).encode(),
        );
      });

  /// Read from secure storage each time it is needed, never cached.
  static Future<String?> loadPrivateKey(String pubkeyHex) async =>
      _readKey(await _readIndex(), pubkeyHex);

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

  /// Stores a key under the name versions before slots gave it, which
  /// [loadPrivateKey] still finds. Tests use it to give an identity a key
  /// without an index; [addIdentity] is how the app stores one.
  @visibleForTesting
  static Future<void> savePrivateKey(String pubkeyHex, String privkeyHex) {
    return secretStore.write(_secretName(pubkeyHex), privkeyHex);
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
