import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sputnik/models/identity_index.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/faulty_secret_store.dart';
import 'support/identity_storage.dart';
import 'support/reported_errors.dart';

// Fails every delete, like a keyring whose unlock prompt was dismissed.
class _UndeletableSecretStore extends FakeSecretStore {
  _UndeletableSecretStore([super.initial]);

  var failDeletes = true;

  @override
  Future<void> delete(String key) {
    if (failDeletes) throw PlatformException(code: 'KeyringLocked');
    return super.delete(key);
  }
}

void main() {
  late HeldIdentity listed;
  late HeldIdentity lost;
  late UnlistedKey lostKey;

  FakeSecretStore store() => SettingsStore.secretStore as FakeSecretStore;

  Future<List<String>> listedAfterRestart() async => [
    for (final identity in (await SettingsStore.loadIdentityIndex()).identities)
      identity.pubkeyHex,
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    listed = newHeldIdentity();
    lost = newHeldIdentity();
    lostKey = (name: lost.pubkeyHex, pubkeyHex: lost.pubkeyHex);
    SettingsStore.secretStore = FakeSecretStore({
      ...currentStorage([listed]),
      'identity_secret_${lost.pubkeyHex}': lost.privkeyHex,
    });
  });

  group('keys that no identity refers to', () {
    test('are found by the identity they belong to', () async {
      expect(await SettingsStore.reconcileStoredKeys(), [lostKey]);
    });

    test('are found in an entry of any name', () async {
      SettingsStore.secretStore = FakeSecretStore({
        ...currentStorage([listed]),
        'identity_secret_somewhere': lost.privkeyHex,
      });

      expect(await SettingsStore.reconcileStoredKeys(), [
        (name: 'somewhere', pubkeyHex: lost.pubkeyHex),
      ]);
    });

    test('are found once, however many entries hold them', () async {
      await store().write('identity_secret_somewhere', lost.privkeyHex);

      expect(await SettingsStore.reconcileStoredKeys(), hasLength(1));
    });

    test('come in a fixed order', () async {
      final another = newHeldIdentity();
      await store().write(
        'identity_secret_${another.pubkeyHex}',
        another.privkeyHex,
      );

      final found = await SettingsStore.reconcileStoredKeys();

      expect(
        found.map((key) => key.pubkeyHex),
        [lost.pubkeyHex, another.pubkeyHex]..sort(),
      );
    });

    test('do not include the keys of listed identities', () async {
      expect(
        (await SettingsStore.reconcileStoredKeys()).map((k) => k.pubkeyHex),
        isNot(contains(listed.pubkeyHex)),
      );

      // Neither those still named after their pubkey.
      SettingsStore.secretStore = FakeSecretStore(legacyStorage([listed]));
      expect(await SettingsStore.reconcileStoredKeys(), isEmpty);
    });

    test(
      'do not include what is no private key or not an identity key',
      () async {
        await store().write('identity_secret_${'a' * 64}', 'not a key');
        await store().write('identity_secret_${'b' * 64}', '00' * 32);
        await store().write('some_other_secret', newHeldIdentity().privkeyHex);
        await store().write('legacy_note', lost.privkeyHex);

        expect(await SettingsStore.reconcileStoredKeys(), [lostKey]);
      },
    );

    test('are not looked for when the index cannot be read', () async {
      await store().write('identities', 'not an index');

      await expectLater(
        SettingsStore.reconcileStoredKeys(),
        throwsFormatException,
      );
    });
  });

  group('listing a key again', () {
    test('lists its identity, with the key where it is', () async {
      final index = await SettingsStore.restoreIdentity(lostKey);

      expect(index.identities.map((i) => i.pubkeyHex), [
        listed.pubkeyHex,
        lost.pubkeyHex,
      ]);
      expect(
        await SettingsStore.loadPrivateKey(lost.pubkeyHex),
        lost.privkeyHex,
      );
      expect(await SettingsStore.reconcileStoredKeys(), isEmpty);
    });

    test(
      'moves a key named after its pubkey into a slot at the next start',
      () async {
        await SettingsStore.restoreIdentity(lostKey);

        final index = await SettingsStore.loadIdentityIndex();

        final slot = index.slotOf(lost.pubkeyHex);
        expect(slot, isNotNull);
        expect(store().values['identity_secret_$slot'], lost.privkeyHex);
        expect(
          store().values.containsKey('identity_secret_${lost.pubkeyHex}'),
          isFalse,
        );
      },
    );

    test('keeps the slot a key is in already', () async {
      SettingsStore.secretStore = FakeSecretStore({
        ...currentStorage([listed]),
        'identity_secret_somewhere': lost.privkeyHex,
      });

      final index = await SettingsStore.restoreIdentity((
        name: 'somewhere',
        pubkeyHex: lost.pubkeyHex,
      ));

      expect(index.slotOf(lost.pubkeyHex), 'somewhere');
      expect(await SettingsStore.reconcileStoredKeys(), isEmpty);
      expect(
        await SettingsStore.loadPrivateKey(lost.pubkeyHex),
        lost.privkeyHex,
      );
    });

    test(
      'starts from the stored index, without dropping any identity',
      () async {
        final index = await SettingsStore.restoreIdentity(lostKey);

        expect(index.contains(listed.pubkeyHex), isTrue);
        expect(await listedAfterRestart(), [listed.pubkeyHex, lost.pubkeyHex]);
      },
    );

    test('lists the identity once when asked twice', () async {
      await SettingsStore.restoreIdentity(lostKey);
      final index = await SettingsStore.restoreIdentity(lostKey);

      expect(index.identities, hasLength(2));
    });

    test('does nothing when the key is gone or is another one', () async {
      await store().delete('identity_secret_${lost.pubkeyHex}');
      await expectLater(
        SettingsStore.restoreIdentity(lostKey),
        throwsStateError,
      );

      await store().write(
        'identity_secret_${lost.pubkeyHex}',
        listed.privkeyHex,
      );
      await expectLater(
        SettingsStore.restoreIdentity(lostKey),
        throwsStateError,
      );

      expect(storedIndex(store().values).contains(lost.pubkeyHex), isFalse);
    });
  });

  group('copies of a listed identity\'s key that nothing refers to', () {
    test('are deleted, and the entry the app uses is not', () async {
      await store().write(
        'identity_secret_${listed.pubkeyHex}',
        listed.privkeyHex,
      );
      await store().write('identity_secret_stray', listed.privkeyHex);

      final found = await SettingsStore.reconcileStoredKeys();

      expect(found, [lostKey]);
      expect(store().values.keys.toSet(), {
        'identities',
        'identity_secret_slot0',
        'identity_secret_${lost.pubkeyHex}',
      });
      expect(
        await SettingsStore.loadPrivateKey(listed.pubkeyHex),
        listed.privkeyHex,
      );
    });

    test('are deleted next to a key that has no slot yet too', () async {
      SettingsStore.secretStore = FakeSecretStore({
        ...legacyStorage([listed]),
        'identity_secret_stray': listed.privkeyHex,
      });

      await SettingsStore.reconcileStoredKeys();

      expect(store().values.keys.toSet(), {
        'identities',
        'identity_secret_${listed.pubkeyHex}',
      });
    });

    test('are kept when the identity\'s own entry holds another key', () async {
      await store().write('identity_secret_slot0', 'something else');
      await store().write('identity_secret_stray', listed.privkeyHex);

      expect(await SettingsStore.reconcileStoredKeys(), [lostKey]);

      expect(store().values['identity_secret_stray'], listed.privkeyHex);
    });

    test('are kept when the identity\'s own entry is missing', () async {
      await store().delete('identity_secret_slot0');
      await store().write(
        'identity_secret_${listed.pubkeyHex}',
        listed.privkeyHex,
      );

      await SettingsStore.reconcileStoredKeys();

      // The only copy there is: dual reading still finds it.
      expect(
        await SettingsStore.loadPrivateKey(listed.pubkeyHex),
        listed.privkeyHex,
      );
    });

    test('are left alone when they cannot be deleted, and reported', () async {
      final undeletable = _UndeletableSecretStore({
        ...currentStorage([listed]),
        'identity_secret_stray': listed.privkeyHex,
      });
      SettingsStore.secretStore = undeletable;
      final reported = captureReportedErrors();

      await SettingsStore.reconcileStoredKeys();

      expect(reported, hasLength(1));
      expect(undeletable.values['identity_secret_stray'], listed.privkeyHex);
    });

    test(
      'left by a move that could not delete them are gone at the next start',
      () async {
        final undeletable = _UndeletableSecretStore(legacyStorage([listed]));
        SettingsStore.secretStore = undeletable;
        final reported = captureReportedErrors();
        await SettingsStore.loadIdentityIndex();
        expect(reported, hasLength(1));
        expect(
          undeletable.values.keys,
          contains('identity_secret_${listed.pubkeyHex}'),
        );

        undeletable.failDeletes = false;
        await SettingsStore.reconcileStoredKeys();

        for (final name in undeletable.values.keys) {
          expect(name, isNot(contains(listed.pubkeyHex)));
        }
        expect(
          await SettingsStore.loadPrivateKey(listed.pubkeyHex),
          listed.privkeyHex,
        );
      },
    );
  });

  test('never removes the last copy of a key, whatever is stored', () async {
    final random = Random(20261018);
    final held = [for (var i = 0; i < 3; i++) newHeldIdentity()];

    for (var round = 0; round < 300; round++) {
      final storage = <String, String>{};
      var index = IdentityIndex.empty;
      for (var i = 0; i < held.length; i++) {
        switch (random.nextInt(3)) {
          case 1:
            index = index.withIdentity(held[i].identity);
          case 2:
            index = index.withIdentity(held[i].identity, slot: 'slot$i');
        }
        // The key, or something else, in every place a copy could be.
        for (final name in [held[i].pubkeyHex, 'slot$i', 'orphan$i', 'stray']) {
          switch (random.nextInt(4)) {
            case 0:
              storage['identity_secret_$name'] = held[i].privkeyHex;
            case 1:
              storage['identity_secret_$name'] = 'not a key';
          }
        }
      }
      storage['identities'] = index.encode();
      final before = FakeSecretStore(storage);
      final after = FakeSecretStore(storage);
      SettingsStore.secretStore = after;

      await SettingsStore.reconcileStoredKeys();

      for (final h in held) {
        final reason = 'round $round, ${h.pubkeyHex.substring(0, 8)}';
        if (isStored(before.values, h.privkeyHex)) {
          expect(isStored(after.values, h.privkeyHex), isTrue, reason: reason);
        }
        SettingsStore.secretStore = before;
        final readBefore = await SettingsStore.loadPrivateKey(h.pubkeyHex);
        SettingsStore.secretStore = after;
        expect(
          await SettingsStore.loadPrivateKey(h.pubkeyHex),
          readBefore,
          reason: reason,
        );
      }
      // Whatever was not a key is left alone.
      for (final entry in before.values.entries) {
        if (entry.value == 'not a key') {
          expect(after.values[entry.key], entry.value);
        }
      }
    }
  });

  group('whichever storage call fails', () {
    test('looking through the keys loses none', () async {
      final seed = {
        ...currentStorage([listed]),
        'identity_secret_${listed.pubkeyHex}': listed.privkeyHex,
        'identity_secret_stray': listed.privkeyHex,
        'identity_secret_${lost.pubkeyHex}': lost.privkeyHex,
      };
      captureReportedErrors();

      await forEveryFault(
        seed: seed,
        scenario: SettingsStore.reconcileStoredKeys,
        check: (fault, after, error) async {
          for (final held in [listed, lost]) {
            expect(
              isStored(after.values, held.privkeyHex),
              isTrue,
              reason: '$fault: a key is gone',
            );
          }
          expect(
            await SettingsStore.loadPrivateKey(listed.pubkeyHex),
            listed.privkeyHex,
            reason: fault,
          );

          // The next start settles it: the copies are gone, the lost key is
          // still on offer.
          final offered = await SettingsStore.reconcileStoredKeys();
          expect(offered, [lostKey], reason: fault);
          expect(after.values.keys.toSet(), {
            'identities',
            'identity_secret_slot0',
            'identity_secret_${lost.pubkeyHex}',
          }, reason: fault);
        },
      );
    });

    test(
      'listing a key again loses none and lists none without a key',
      () async {
        await forEveryFault(
          seed: {
            ...currentStorage([listed]),
            'identity_secret_${lost.pubkeyHex}': lost.privkeyHex,
          },
          scenario: () => SettingsStore.restoreIdentity(lostKey),
          check: (fault, after, error) async {
            expect(
              after.values['identity_secret_${lost.pubkeyHex}'],
              lost.privkeyHex,
              reason: fault,
            );

            // The next start lists the key's identity or still offers it.
            final index = storedIndex(after.values);
            final offered = await SettingsStore.reconcileStoredKeys();
            expect(
              index.contains(lost.pubkeyHex) || offered.contains(lostKey),
              isTrue,
              reason: '$fault: neither listed nor offered',
            );
            expect(index.contains(listed.pubkeyHex), isTrue, reason: fault);
            for (final identity in index.identities) {
              expect(
                await SettingsStore.loadPrivateKey(identity.pubkeyHex),
                isNotNull,
                reason: '$fault: ${identity.pubkeyHex} is listed without a key',
              );
            }
          },
        );
      },
    );
  });
}
