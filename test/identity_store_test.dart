import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/identity_index.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/identity_store.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/faulty_secret_store.dart';
import 'support/reported_errors.dart';

typedef _Held = ({Identity identity, String privkeyHex});

_Held _newIdentity() {
  final keyPair = generateNostrKeyPair();
  return (
    identity: Identity(pubkeyHex: keyPair.publicKeyHex, createdAt: DateTime(1)),
    privkeyHex: keyPair.privateKeyHex,
  );
}

/// Secure storage as a version with per-identity entries and a plain index
/// left it.
Map<String, String> _storageHolding(List<_Held> held) => {
  'identities': held
      .fold(IdentityIndex.empty, (index, h) => index.withIdentity(h.identity))
      .encode(),
  for (final h in held) 'identity_secret_${h.identity.pubkeyHex}': h.privkeyHex,
};

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
    store = FakeSecretStore();
    SettingsStore.secretStore = store;
    identitiesNotifier.value = const [];
    activeIdentityPubkeyNotifier.value = null;
    IdentityStore.status.value = IdentityStatus.ready;
  });

  group('load', () {
    test('lists the identities in the index', () async {
      final a = _newIdentity();
      final b = _newIdentity();
      store = FakeSecretStore(_storageHolding([a, b]));
      SettingsStore.secretStore = store;

      await IdentityStore.load();

      expect(_shown(), [a.identity.pubkeyHex, b.identity.pubkeyHex]);
    });

    test('shows no identities when there are none', () async {
      await IdentityStore.load();

      expect(identitiesNotifier.value, isEmpty);
    });

    test(
      'shows nothing new and says so when the index cannot be read',
      () async {
        final reported = captureReportedErrors();
        SettingsStore.secretStore = FaultySecretStore(
          FakeSecretStore(_storageHolding([_newIdentity()])),
          failCall: 1,
        );

        await IdentityStore.load();

        expect(identitiesNotifier.value, isEmpty);
        expect(reported, hasLength(1));
      },
    );
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
      final held = _newIdentity();
      final inner = FakeSecretStore(_storageHolding([held]));
      SettingsStore.secretStore = FaultySecretStore(inner, failCall: 1);
      await IdentityStore.load();
      expect(IdentityStore.status.value, IdentityStatus.unavailable);
      expect(identitiesNotifier.value, isEmpty);

      SettingsStore.secretStore = inner;
      await IdentityStore.load();

      expect(IdentityStore.status.value, IdentityStatus.ready);
      expect(_shown(), [held.identity.pubkeyHex]);
    });

    test('nothing is added or removed until the identities are read', () async {
      final held = _newIdentity();
      store = FakeSecretStore(_storageHolding([held]));
      final watched = FaultySecretStore(store);
      SettingsStore.secretStore = watched;
      IdentityStore.status.value = IdentityStatus.unavailable;

      await expectLater(
        IdentityStore.add('a' * 64, 'secret'),
        throwsStateError,
      );
      await expectLater(IdentityStore.remove(held.identity), throwsStateError);

      expect(watched.calls, isEmpty);
      expect(store.values, _storageHolding([held]));
    });
  });

  group('add', () {
    test('lists the identity, makes it active and keeps its key', () async {
      final held = _newIdentity();

      await IdentityStore.add(held.identity.pubkeyHex, held.privkeyHex);

      expect(_shown(), [held.identity.pubkeyHex]);
      expect(activeIdentityPubkeyNotifier.value, held.identity.pubkeyHex);
      expect(
        await SettingsStore.loadPrivateKey(held.identity.pubkeyHex),
        held.privkeyHex,
      );
      expect(await _listedAfterRestart(), [held.identity.pubkeyHex]);
    });

    test('starts from the stored index, not from what is shown', () async {
      final stored = _newIdentity();
      final added = _newIdentity();
      store = FakeSecretStore(_storageHolding([stored]));
      SettingsStore.secretStore = store;
      // Nothing was loaded: the app shows no identities.

      await IdentityStore.add(added.identity.pubkeyHex, added.privkeyHex);

      expect(_shown(), [stored.identity.pubkeyHex, added.identity.pubkeyHex]);
      expect(await _listedAfterRestart(), _shown());
    });

    test(
      'changes nothing that is shown when the index cannot be read',
      () async {
        final held = _newIdentity();
        SettingsStore.secretStore = FaultySecretStore(store, failCall: 1);

        await expectLater(
          IdentityStore.add(held.identity.pubkeyHex, held.privkeyHex),
          throwsStateError,
        );

        expect(identitiesNotifier.value, isEmpty);
        expect(store.values, isEmpty);
      },
    );

    test(
      'changes nothing that is shown when the key cannot be saved',
      () async {
        final held = _newIdentity();
        SettingsStore.secretStore = FaultySecretStore(store, failCall: 2);

        await expectLater(
          IdentityStore.add(held.identity.pubkeyHex, held.privkeyHex),
          throwsStateError,
        );

        expect(identitiesNotifier.value, isEmpty);
        expect(activeIdentityPubkeyNotifier.value, isNull);
      },
    );
  });

  group('remove', () {
    late _Held first;
    late _Held second;

    setUp(() async {
      first = _newIdentity();
      second = _newIdentity();
      store = FakeSecretStore(_storageHolding([first, second]));
      SettingsStore.secretStore = store;
      await IdentityStore.load();
      activeIdentityPubkeyNotifier.value = first.identity.pubkeyHex;
    });

    test(
      'deletes the key, unlists the identity and moves the active one',
      () async {
        await IdentityStore.remove(first.identity);

        expect(_shown(), [second.identity.pubkeyHex]);
        expect(activeIdentityPubkeyNotifier.value, second.identity.pubkeyHex);
        expect(
          await SettingsStore.loadPrivateKey(first.identity.pubkeyHex),
          isNull,
        );
        expect(await _listedAfterRestart(), _shown());
      },
    );

    test('leaves the active identity alone when another one goes', () async {
      await IdentityStore.remove(second.identity);

      expect(_shown(), [first.identity.pubkeyHex]);
      expect(activeIdentityPubkeyNotifier.value, first.identity.pubkeyHex);
    });

    test('leaves no active identity once the last one is gone', () async {
      await IdentityStore.remove(first.identity);
      await IdentityStore.remove(second.identity);

      expect(identitiesNotifier.value, isEmpty);
      expect(activeIdentityPubkeyNotifier.value, isNull);
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

        expect(_shown(), [first.identity.pubkeyHex, second.identity.pubkeyHex]);
        expect(activeIdentityPubkeyNotifier.value, first.identity.pubkeyHex);
        expect(
          await SettingsStore.loadPrivateKey(first.identity.pubkeyHex),
          first.privkeyHex,
        );
      },
    );
  });

  group('whichever storage call fails', () {
    test(
      'adding an identity loses no key and lists none without a key',
      () async {
        final existing = _newIdentity();
        final added = _newIdentity();
        final existingPubkey = existing.identity.pubkeyHex;
        final addedPubkey = added.identity.pubkeyHex;

        await forEveryFault(
          seed: _storageHolding([existing]),
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
      final removed = _newIdentity();
      final kept = _newIdentity();
      final removedPubkey = removed.identity.pubkeyHex;
      final keptPubkey = kept.identity.pubkeyHex;

      await forEveryFault(
        seed: _storageHolding([removed, kept]),
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
          final keyKept = after.values.containsKey(
            'identity_secret_$removedPubkey',
          );
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
    });

    test('moving keys out of the index never leaves one nowhere', () async {
      final a = _newIdentity();
      final b = _newIdentity();
      captureReportedErrors();
      final inline = jsonEncode([
        for (final h in [a, b])
          {...h.identity.toJson(), 'privkeyHex': h.privkeyHex},
      ]);

      await forEveryFault(
        seed: {'identities': inline},
        scenario: IdentityStore.load,
        check: (fault, after, error) async {
          // Right after the failure, before any restart: every key is stored.
          for (final h in [a, b]) {
            expect(
              after.values.values.any((v) => v.contains(h.privkeyHex)),
              isTrue,
              reason: '$fault: a key is stored nowhere',
            );
          }

          // And the next start can still reach all of them.
          expect(await _listedAfterRestart(), [
            a.identity.pubkeyHex,
            b.identity.pubkeyHex,
          ], reason: fault);
          for (final h in [a, b]) {
            expect(
              await SettingsStore.loadPrivateKey(h.identity.pubkeyHex),
              h.privkeyHex,
              reason: fault,
            );
          }
        },
      );
    });
  });
}
