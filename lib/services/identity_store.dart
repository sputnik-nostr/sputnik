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
/// once it is saved, so what the app shows is what a restart will find.
class IdentityStore {
  IdentityStore._();

  static final status = ValueNotifier(IdentityStatus.ready);

  /// Reads the identities from secure storage, and again to retry. Never
  /// throws: if they can't be read, [status] says so.
  static Future<void> load() async {
    status.value = IdentityStatus.loading;
    try {
      final index = await SettingsStore.loadIdentityIndex();
      identitiesNotifier.value = index.identities;
      status.value = IdentityStatus.ready;
    } catch (error, stack) {
      reportError('loading identities', error, stack);
      status.value = IdentityStatus.unavailable;
    }
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
}
