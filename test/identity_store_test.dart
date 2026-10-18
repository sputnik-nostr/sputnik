import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/identity_store.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/faulty_secret_store.dart';
import 'support/identity_storage.dart';
import 'support/reported_errors.dart';

List<String> _shown() => [
  for (final identity in identitiesNotifier.value) identity.pubkeyHex,
];

/// What the next start finds listed.
Future<List<String>> _listedAfterRestart() async => [
  for (final identity in (await SettingsStore.loadIdentityIndex()).identities)
    identity.pubkeyHex,
];

void main() {
  late FakeSecretStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    IdentityStore.reset();
    store = FakeSecretStore();
    SettingsStore.secretStore = store;
    identitiesNotifier.value = const [];
    activeIdentityPubkeyNotifier.value = null;
  });

  tearDown(IdentityStore.reset);

  group('load', () {
    test('lists the identities in the index', () async {
      final a = newHeldIdentity();
      final b = newHeldIdentity();
      store = FakeSecretStore(currentStorage([a, b]));
      SettingsStore.secretStore = store;

      await IdentityStore.load();

      expect(_shown(), [a.pubkeyHex, b.pubkeyHex]);
    });

    test('shows no identities when there are none', () async {
      await IdentityStore.load();

      expect(identitiesNotifier.value, isEmpty);
      expect(activeIdentityPubkeyNotifier.value, isNull);
    });

    test(
      'shows nothing new and says so when the index cannot be read',
      () async {
        final reported = captureReportedErrors();
        SettingsStore.secretStore = FaultySecretStore(
          FakeSecretStore(currentStorage([newHeldIdentity()])),
          failCall: 1,
        );

        await IdentityStore.load();

        expect(identitiesNotifier.value, isEmpty);
        expect(reported, hasLength(1));
      },
    );

    test('makes the identity that was picked the active one', () async {
      final a = newHeldIdentity();
      final b = newHeldIdentity();
      SettingsStore.secretStore = FakeSecretStore(
        currentStorage([a, b], active: b.pubkeyHex),
      );

      await IdentityStore.load();

      expect(activeIdentityPubkeyNotifier.value, b.pubkeyHex);
    });

    test('makes the first identity active while none was picked', () async {
      final a = newHeldIdentity();
      final b = newHeldIdentity();
      SettingsStore.secretStore = FakeSecretStore(currentStorage([a, b]));

      await IdentityStore.load();

      expect(activeIdentityPubkeyNotifier.value, a.pubkeyHex);
    });

    test(
      'brings what the last version without slots stored up to date',
      () async {
        final a = newHeldIdentity();
        final b = newHeldIdentity();
        SharedPreferences.setMockInitialValues({
          'active_identity_pubkey': b.pubkeyHex,
          'theme_mode': 'dark',
        });
        store = FakeSecretStore(legacyStorage([a, b]));
        SettingsStore.secretStore = store;

        await IdentityStore.load();

        expect(_shown(), [a.pubkeyHex, b.pubkeyHex]);
        expect(activeIdentityPubkeyNotifier.value, b.pubkeyHex);
        for (final held in [a, b]) {
          final key = await SettingsStore.loadSecretKey(held.pubkeyHex);
          expect(key, isNotNull);
          expect(xonlyPubkeyHex(key!), held.pubkeyHex);
          key.wipe();
        }
        // Nothing that names an identity is left outside the index.
        for (final name in store.values.keys) {
          expect(name, isNot(contains(a.pubkeyHex)));
          expect(name, isNot(contains(b.pubkeyHex)));
        }
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), {'theme_mode'});
      },
    );

    test('does not leave an identity active that is not listed', () async {
      final a = newHeldIdentity();
      SettingsStore.secretStore = FakeSecretStore(
        currentStorage([a], active: 'f' * 64),
      );

      await IdentityStore.load();

      expect(activeIdentityPubkeyNotifier.value, a.pubkeyHex);
    });
  });

  group('status', () {
    test(
      'is ready once the identities are read, even when there are none',
      () async {
        await IdentityStore.load();

        expect(IdentityStore.status.value, IdentityStatus.ready);
      },
    );

    test('says they are being read, then that they cannot be', () async {
      captureReportedErrors();
      SettingsStore.secretStore = FaultySecretStore(store, failCall: 1);
      final seen = <IdentityStatus>[];
      void record() => seen.add(IdentityStore.status.value);
      IdentityStore.status.addListener(record);
      addTearDown(() => IdentityStore.status.removeListener(record));

      await IdentityStore.load();

      expect(seen, [IdentityStatus.loading, IdentityStatus.unavailable]);
    });

    test('a retry reads what the first attempt could not', () async {
      captureReportedErrors();
      final held = newHeldIdentity();
      final inner = FakeSecretStore(currentStorage([held]));
      SettingsStore.secretStore = FaultySecretStore(inner, failCall: 1);
      await IdentityStore.load();
      expect(IdentityStore.status.value, IdentityStatus.unavailable);
      expect(identitiesNotifier.value, isEmpty);

      SettingsStore.secretStore = inner;
      await IdentityStore.load();

      expect(IdentityStore.status.value, IdentityStatus.ready);
      expect(_shown(), [held.pubkeyHex]);
      expect(activeIdentityPubkeyNotifier.value, held.pubkeyHex);
    });

    test('nothing is added or removed until the identities are read', () async {
      final held = newHeldIdentity();
      store = FakeSecretStore(currentStorage([held]));
      final watched = FaultySecretStore(store);
      SettingsStore.secretStore = watched;
      IdentityStore.status.value = IdentityStatus.unavailable;

      await expectLater(
        IdentityStore.add('a' * 64, 'secret'),
        throwsStateError,
      );
      await expectLater(IdentityStore.remove(held.identity), throwsStateError);

      expect(watched.calls, isEmpty);
      expect(store.values, currentStorage([held]));
    });
  });

  group('keys that no identity refers to', () {
    late HeldIdentity listed;
    late HeldIdentity lost;
    late UnlistedKey lostKey;

    setUp(() {
      listed = newHeldIdentity();
      lost = newHeldIdentity();
      lostKey = (name: lost.pubkeyHex, pubkeyHex: lost.pubkeyHex);
      store = FakeSecretStore({
        ...currentStorage([listed]),
        'identity_secret_${lost.pubkeyHex}': lost.privkeyHex,
      });
      SettingsStore.secretStore = store;
    });

    test('are offered once the identities are read', () async {
      await IdentityStore.load();

      expect(_shown(), [listed.pubkeyHex]);
      expect(IdentityStore.unlisted.value, [lostKey]);
    });

    test('are not offered when the identities cannot be read', () async {
      captureReportedErrors();
      SettingsStore.secretStore = FaultySecretStore(store, failCall: 1);

      await IdentityStore.load();

      expect(IdentityStore.unlisted.value, isEmpty);
    });

    test('are not offered any more once they have been listed', () async {
      await IdentityStore.load();
      await IdentityStore.restore(lostKey);

      await IdentityStore.load();

      expect(IdentityStore.unlisted.value, isEmpty);
    });

    test('a search that fails does not fail the load', () async {
      final reported = captureReportedErrors();
      // Loading reads the index twice; the search reads it once more, then
      // every stored key.
      SettingsStore.secretStore = FaultySecretStore(store, failCall: 4);

      await IdentityStore.load();

      expect(IdentityStore.status.value, IdentityStatus.ready);
      expect(_shown(), [listed.pubkeyHex]);
      expect(IdentityStore.unlisted.value, isEmpty);
      expect(reported, hasLength(1));
    });

    test(
      'are listed again on request, as the active one if there is none',
      () async {
        store = FakeSecretStore({
          'identity_secret_${lost.pubkeyHex}': lost.privkeyHex,
        });
        SettingsStore.secretStore = store;
        await IdentityStore.load();

        await IdentityStore.restore(lostKey);
        await IdentityStore.activeSaved;

        expect(_shown(), [lost.pubkeyHex]);
        expect(activeIdentityPubkeyNotifier.value, lost.pubkeyHex);
        expect(storedIndex(store.values).active, lost.pubkeyHex);
        expect(IdentityStore.unlisted.value, isEmpty);
        expect(
          await SettingsStore.loadPrivateKey(lost.pubkeyHex),
          lost.privkeyHex,
        );
      },
    );

    test('leave the active identity alone when listed again', () async {
      await IdentityStore.load();
      expect(activeIdentityPubkeyNotifier.value, listed.pubkeyHex);

      await IdentityStore.restore(lostKey);

      expect(_shown(), [listed.pubkeyHex, lost.pubkeyHex]);
      expect(activeIdentityPubkeyNotifier.value, listed.pubkeyHex);
    });

    test('are not offered any more once the identity has been added', () async {
      await IdentityStore.load();
      expect(IdentityStore.unlisted.value, [lostKey]);

      await IdentityStore.add(lost.pubkeyHex, lost.privkeyHex);

      expect(IdentityStore.unlisted.value, isEmpty);
      expect(_shown(), [listed.pubkeyHex, lost.pubkeyHex]);

      // The next start drops the copy that was on offer: the key is kept in
      // the slot of the identity that was added.
      await IdentityStore.load();
      expect(IdentityStore.unlisted.value, isEmpty);
      expect(
        store.values.containsKey('identity_secret_${lost.pubkeyHex}'),
        isFalse,
      );
      expect(
        await SettingsStore.loadPrivateKey(lost.pubkeyHex),
        lost.privkeyHex,
      );
    });

    test('stay on offer when listing them again fails', () async {
      await IdentityStore.load();
      // The index is read, then the key, then the index is written.
      SettingsStore.secretStore = FaultySecretStore(store, failCall: 3);

      await expectLater(IdentityStore.restore(lostKey), throwsStateError);

      expect(_shown(), [listed.pubkeyHex]);
      expect(IdentityStore.unlisted.value, [lostKey]);
    });

    test('cannot be listed while the identities are unknown', () async {
      IdentityStore.status.value = IdentityStatus.unavailable;

      await expectLater(IdentityStore.restore(lostKey), throwsStateError);
    });
  });

  group('the active identity', () {
    late HeldIdentity a;
    late HeldIdentity b;

    setUp(() async {
      a = newHeldIdentity();
      b = newHeldIdentity();
      store = FakeSecretStore(currentStorage([a, b], active: a.pubkeyHex));
      SettingsStore.secretStore = store;
      await IdentityStore.load();
    });

    test('is saved in the index when it changes', () async {
      activeIdentityPubkeyNotifier.value = b.pubkeyHex;
      await IdentityStore.activeSaved;

      expect(storedIndex(store.values).active, b.pubkeyHex);
      expect(storedIndex(store.values).identities, hasLength(2));
    });

    test('is the same one after a restart', () async {
      activeIdentityPubkeyNotifier.value = b.pubkeyHex;
      await IdentityStore.activeSaved;
      activeIdentityPubkeyNotifier.value = null;
      identitiesNotifier.value = const [];

      await IdentityStore.load();

      expect(activeIdentityPubkeyNotifier.value, b.pubkeyHex);
    });

    test('is not kept in preferences', () async {
      activeIdentityPubkeyNotifier.value = b.pubkeyHex;
      await IdentityStore.activeSaved;

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('is saved in the order it was changed', () async {
      activeIdentityPubkeyNotifier.value = b.pubkeyHex;
      activeIdentityPubkeyNotifier.value = a.pubkeyHex;
      activeIdentityPubkeyNotifier.value = b.pubkeyHex;
      activeIdentityPubkeyNotifier.value = a.pubkeyHex;
      await IdentityStore.activeSaved;

      expect(storedIndex(store.values).active, a.pubkeyHex);
    });

    test('is reported, not lost, when it cannot be saved', () async {
      final reported = captureReportedErrors();
      SettingsStore.secretStore = FaultySecretStore(store, failCall: 1);

      activeIdentityPubkeyNotifier.value = b.pubkeyHex;
      await IdentityStore.activeSaved;

      expect(reported, hasLength(1));
      expect(storedIndex(store.values).active, a.pubkeyHex);
      expect(storedIndex(store.values).identities, hasLength(2));

      // Storage works again, and the next change goes through.
      SettingsStore.secretStore = store;
      activeIdentityPubkeyNotifier.value = a.pubkeyHex;
      activeIdentityPubkeyNotifier.value = b.pubkeyHex;
      await IdentityStore.activeSaved;
      expect(storedIndex(store.values).active, b.pubkeyHex);
    });

    test('is only saved once the identities have been read', () async {
      IdentityStore.reset();
      final watched = FaultySecretStore(store);
      SettingsStore.secretStore = watched;

      activeIdentityPubkeyNotifier.value = b.pubkeyHex;
      await IdentityStore.activeSaved;

      expect(watched.calls, isEmpty);
    });

    test('is saved after a retry, when the first read failed', () async {
      IdentityStore.reset();
      captureReportedErrors();
      SettingsStore.secretStore = FaultySecretStore(store, failCall: 1);
      await IdentityStore.load();
      expect(IdentityStore.status.value, IdentityStatus.unavailable);

      SettingsStore.secretStore = store;
      await IdentityStore.load();
      activeIdentityPubkeyNotifier.value = b.pubkeyHex;
      await IdentityStore.activeSaved;

      expect(storedIndex(store.values).active, b.pubkeyHex);
    });
  });

  group('add', () {
    test('lists the identity, makes it active and keeps its key', () async {
      final held = newHeldIdentity();

      await IdentityStore.add(held.pubkeyHex, held.privkeyHex);

      expect(_shown(), [held.pubkeyHex]);
      expect(activeIdentityPubkeyNotifier.value, held.pubkeyHex);
      expect(
        await SettingsStore.loadPrivateKey(held.pubkeyHex),
        held.privkeyHex,
      );
      expect(await _listedAfterRestart(), [held.pubkeyHex]);
    });

    test('makes the new identity the one the next start opens', () async {
      final first = newHeldIdentity();
      final second = newHeldIdentity();
      await IdentityStore.load();
      await IdentityStore.add(first.pubkeyHex, first.privkeyHex);
      await IdentityStore.add(second.pubkeyHex, second.privkeyHex);
      await IdentityStore.activeSaved;

      identitiesNotifier.value = const [];
      activeIdentityPubkeyNotifier.value = null;
      await IdentityStore.load();

      expect(_shown(), [first.pubkeyHex, second.pubkeyHex]);
      expect(activeIdentityPubkeyNotifier.value, second.pubkeyHex);
    });

    test('starts from the stored index, not from what is shown', () async {
      final stored = newHeldIdentity();
      final added = newHeldIdentity();
      store = FakeSecretStore(currentStorage([stored]));
      SettingsStore.secretStore = store;
      // Nothing was loaded: the app shows no identities.

      await IdentityStore.add(added.pubkeyHex, added.privkeyHex);

      expect(_shown(), [stored.pubkeyHex, added.pubkeyHex]);
      expect(await _listedAfterRestart(), _shown());
    });

    test(
      'changes nothing that is shown when the index cannot be read',
      () async {
        final held = newHeldIdentity();
        SettingsStore.secretStore = FaultySecretStore(store, failCall: 1);

        await expectLater(
          IdentityStore.add(held.pubkeyHex, held.privkeyHex),
          throwsStateError,
        );

        expect(identitiesNotifier.value, isEmpty);
        expect(store.values, isEmpty);
      },
    );

    test(
      'changes nothing that is shown when the key cannot be saved',
      () async {
        final held = newHeldIdentity();
        SettingsStore.secretStore = FaultySecretStore(store, failCall: 2);

        await expectLater(
          IdentityStore.add(held.pubkeyHex, held.privkeyHex),
          throwsStateError,
        );

        expect(identitiesNotifier.value, isEmpty);
        expect(activeIdentityPubkeyNotifier.value, isNull);
      },
    );
  });

  group('remove', () {
    late HeldIdentity first;
    late HeldIdentity second;

    setUp(() async {
      first = newHeldIdentity();
      second = newHeldIdentity();
      store = FakeSecretStore(
        currentStorage([first, second], active: first.pubkeyHex),
      );
      SettingsStore.secretStore = store;
      await IdentityStore.load();
    });

    test(
      'deletes the key, unlists the identity and moves the active one',
      () async {
        await IdentityStore.remove(first.identity);
        await IdentityStore.activeSaved;

        expect(_shown(), [second.pubkeyHex]);
        expect(activeIdentityPubkeyNotifier.value, second.pubkeyHex);
        expect(await SettingsStore.loadPrivateKey(first.pubkeyHex), isNull);
        expect(isStored(store.values, first.privkeyHex), isFalse);
        expect(await _listedAfterRestart(), _shown());
        expect(storedIndex(store.values).active, second.pubkeyHex);
      },
    );

    test('leaves the active identity alone when another one goes', () async {
      await IdentityStore.remove(second.identity);

      expect(_shown(), [first.pubkeyHex]);
      expect(activeIdentityPubkeyNotifier.value, first.pubkeyHex);
    });

    test('leaves no active identity once the last one is gone', () async {
      await IdentityStore.remove(first.identity);
      await IdentityStore.remove(second.identity);
      await IdentityStore.activeSaved;

      expect(identitiesNotifier.value, isEmpty);
      expect(activeIdentityPubkeyNotifier.value, isNull);
      expect(storedIndex(store.values).active, isNull);
      expect(store.values.keys, ['identities']);
    });

    test(
      'changes nothing that is shown when the key cannot be deleted',
      () async {
        // The index is read first, then the key is deleted.
        SettingsStore.secretStore = FaultySecretStore(store, failCall: 2);

        await expectLater(
          IdentityStore.remove(first.identity),
          throwsStateError,
        );

        expect(_shown(), [first.pubkeyHex, second.pubkeyHex]);
        expect(activeIdentityPubkeyNotifier.value, first.pubkeyHex);
        expect(
          await SettingsStore.loadPrivateKey(first.pubkeyHex),
          first.privkeyHex,
        );
      },
    );
  });

  group('whichever storage call fails', () {
    test(
      'adding an identity loses no key and lists none without a key',
      () async {
        final existing = newHeldIdentity();
        final added = newHeldIdentity();
        final existingPubkey = existing.pubkeyHex;
        final addedPubkey = added.pubkeyHex;

        await forEveryFault(
          seed: currentStorage([existing], active: existingPubkey),
          reset: () async {
            identitiesNotifier.value = [existing.identity];
            activeIdentityPubkeyNotifier.value = existingPubkey;
          },
          scenario: () => IdentityStore.add(addedPubkey, added.privkeyHex),
          check: (fault, after, error) async {
            final shown = _shown();
            final active = activeIdentityPubkeyNotifier.value;

            final listed = await _listedAfterRestart();
            expect(listed, contains(existingPubkey), reason: fault);
            expect(
              await SettingsStore.loadPrivateKey(existingPubkey),
              existing.privkeyHex,
              reason: fault,
            );
            for (final pubkey in listed) {
              expect(
                await SettingsStore.loadPrivateKey(pubkey),
                isNotNull,
                reason: '$fault: $pubkey is listed without a key',
              );
            }

            if (error == null) {
              expect(listed, [existingPubkey, addedPubkey], reason: fault);
              expect(shown, listed, reason: fault);
              expect(active, addedPubkey, reason: fault);
              expect(
                await SettingsStore.loadPrivateKey(addedPubkey),
                added.privkeyHex,
                reason: fault,
              );
            } else {
              // A failed add shows nothing that was not saved.
              expect(shown, [existingPubkey], reason: fault);
              expect(active, existingPubkey, reason: fault);
            }
          },
        );
      },
    );

    test('removing an identity leaves no key behind its listing', () async {
      final removed = newHeldIdentity();
      final kept = newHeldIdentity();
      final removedPubkey = removed.pubkeyHex;
      final keptPubkey = kept.pubkeyHex;

      // Once with the keys in slots, once with them named after the pubkey.
      for (final seed in [
        currentStorage([removed, kept], active: removedPubkey),
        legacyStorage([removed, kept]),
      ]) {
        await forEveryFault(
          seed: seed,
          reset: () async {
            identitiesNotifier.value = [removed.identity, kept.identity];
            activeIdentityPubkeyNotifier.value = removedPubkey;
          },
          scenario: () => IdentityStore.remove(removed.identity),
          check: (fault, after, error) async {
            final shown = _shown();

            final listed = await _listedAfterRestart();
            expect(listed, contains(keptPubkey), reason: fault);
            expect(
              await SettingsStore.loadPrivateKey(keptPubkey),
              kept.privkeyHex,
              reason: fault,
            );

            // The key is deleted first, so it never outlives the listing. The
            // other way round, a deleted key may still have a listing left.
            final keyKept = isStored(after.values, removed.privkeyHex);
            expect(
              !listed.contains(removedPubkey) && keyKept,
              isFalse,
              reason: '$fault: a key was left behind with nothing listing it',
            );

            if (error == null) {
              expect(listed, [keptPubkey], reason: fault);
              expect(keyKept, isFalse, reason: fault);
              expect(shown, [keptPubkey], reason: fault);
            } else {
              // A failed removal shows nothing that was not saved.
              expect(shown, [removedPubkey, keptPubkey], reason: fault);
              expect(
                activeIdentityPubkeyNotifier.value,
                removedPubkey,
                reason: fault,
              );
            }
          },
        );
      }
    });

    test('saving the active identity never costs an identity', () async {
      final a = newHeldIdentity();
      final b = newHeldIdentity();

      await forEveryFault(
        seed: currentStorage([a, b], active: a.pubkeyHex),
        scenario: () => SettingsStore.saveActiveIdentityPubkey(b.pubkeyHex),
        check: (fault, after, error) async {
          final index = storedIndex(after.values);
          expect(index.identities.map((i) => i.pubkeyHex), [
            a.pubkeyHex,
            b.pubkeyHex,
          ], reason: fault);
          expect(
            await SettingsStore.loadPrivateKey(a.pubkeyHex),
            a.privkeyHex,
            reason: fault,
          );
          expect(
            await SettingsStore.loadPrivateKey(b.pubkeyHex),
            b.privkeyHex,
            reason: fault,
          );
          expect(index.activePubkey, error == null ? b.pubkeyHex : isNotNull);
        },
      );
    });
  });
}
