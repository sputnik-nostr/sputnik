import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../models/identity.dart';
import 'error_reporting.dart';
import 'settings_store.dart';

/// Whether the identities have been read from secure storage.
enum IdentityStatus {
  /// They are known, even if there are none.
  ready,

  /// They are being read.
  loading,

  /// They could not be read, so nothing is known about them. Showing none
  /// would be wrong, and adding one would write to an index nobody has seen.
  unavailable,
}

/// The identities this device holds, mirrored in [identitiesNotifier].
///
/// Every change goes to secure storage first and reaches the notifiers only
/// once it is saved, so what the app shows is what a restart will find. The
/// one exception is picking the active identity: that shows at once and is
/// saved right after.
class IdentityStore {
  IdentityStore._();

  static final status = ValueNotifier(IdentityStatus.ready);

  /// Keys in secure storage that no identity refers to, which the user can
  /// list again: left over from an identity that never made it into the index.
  static final unlisted = ValueNotifier<List<UnlistedKey>>(const []);

  /// Reads the identities and the active one from secure storage, and again to
  /// retry. Never throws: if they can't be read, [status] says so.
  static Future<void> load() async {
    status.value = IdentityStatus.loading;
    try {
      final index = await SettingsStore.loadIdentityIndex();
      identitiesNotifier.value = index.identities;
      activeIdentityPubkeyNotifier.value = index.activePubkey;
      status.value = IdentityStatus.ready;
    } catch (error, stack) {
      reportError('loading identities', error, stack);
      status.value = IdentityStatus.unavailable;
      return;
    }
    // Only now: before this the stored choice is unknown, not absent.
    activeIdentityPubkeyNotifier
      ..removeListener(_saveActive)
      ..addListener(_saveActive);

    try {
      unlisted.value = await SettingsStore.reconcileStoredKeys();
    } catch (error, stack) {
      reportError('looking for keys that are not listed', error, stack);
    }
  }

  static var _activeSaved = Future<void>.value();

  /// Saves each change of the active identity, one after the other.
  static void _saveActive() {
    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    _activeSaved = _activeSaved.then((_) async {
      try {
        await SettingsStore.saveActiveIdentityPubkey(pubkeyHex);
      } catch (error, stack) {
        reportError('saving the active identity', error, stack);
      }
    });
  }

  /// Completes once the changes of the active identity so far are saved.
  @visibleForTesting
  static Future<void> get activeSaved => _activeSaved;

  /// Forgets the singleton's state, as the next test needs it.
  @visibleForTesting
  static void reset() {
    activeIdentityPubkeyNotifier.removeListener(_saveActive);
    status.value = IdentityStatus.ready;
    unlisted.value = const [];
  }

  static void _requireReady() {
    if (status.value != IdentityStatus.ready) {
      throw StateError('the identities have not been read yet');
    }
  }

  /// Saves [privkeyHex] and lists its identity as the active one. Throws, with
  /// nothing changed, if either can't be saved.
  static Future<void> add(String pubkeyHex, String privkeyHex) async {
    _requireReady();
    final index = await SettingsStore.addIdentity(
      Identity(pubkeyHex: pubkeyHex, createdAt: DateTime.now()),
      privkeyHex,
    );
    identitiesNotifier.value = index.identities;
    _noLongerUnlisted(pubkeyHex);
    activeIdentityPubkeyNotifier.value = pubkeyHex;
  }

  /// Deletes the key of [identity], then unlists it. Throws, with nothing
  /// changed, if the key can't be deleted.
  static Future<void> remove(Identity identity) async {
    _requireReady();
    final index = await SettingsStore.removeIdentity(identity.pubkeyHex);
    final remaining = index.identities;
    identitiesNotifier.value = remaining;
    if (activeIdentityPubkeyNotifier.value == identity.pubkeyHex) {
      activeIdentityPubkeyNotifier.value = remaining.isEmpty
          ? null
          : remaining.first.pubkeyHex;
    }
  }

  /// Lists the identity of [key] again, as the active one if there is none.
  /// Throws, with nothing changed, if that can't be saved.
  static Future<void> restore(UnlistedKey key) async {
    _requireReady();
    final index = await SettingsStore.restoreIdentity(key);
    identitiesNotifier.value = index.identities;
    _noLongerUnlisted(key.pubkeyHex);
    activeIdentityPubkeyNotifier.value ??= key.pubkeyHex;
  }

  /// A key whose identity is listed now, however it got there, is not on offer.
  static void _noLongerUnlisted(String pubkeyHex) {
    unlisted.value = [
      for (final key in unlisted.value)
        if (key.pubkeyHex != pubkeyHex) key,
    ];
  }
}
