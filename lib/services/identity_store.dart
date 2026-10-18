import '../app_state.dart';
import '../models/identity.dart';
import 'error_reporting.dart';
import 'settings_store.dart';

/// The identities this device holds, mirrored in [identitiesNotifier].
///
/// Every change goes to secure storage first and reaches the notifiers only
/// once it is saved, so what the app shows is what a restart will find.
class IdentityStore {
  IdentityStore._();

  /// Reads the identities from secure storage. Never throws: if they can't be
  /// read, the notifiers stay as they are.
  static Future<void> load() async {
    try {
      final index = await SettingsStore.loadIdentityIndex();
      identitiesNotifier.value = index.identities;
    } catch (error, stack) {
      reportError('loading identities', error, stack);
    }
  }

  /// Saves [privkeyHex] and lists its identity as the active one. Throws, with
  /// nothing changed, if either can't be saved.
  static Future<void> add(String pubkeyHex, String privkeyHex) async {
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
