import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/services/identity_store.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/faulty_secret_store.dart';
import 'support/identity_storage.dart';
import 'support/reported_errors.dart';

/// Notes, for each call, whether the plaintext entry was still in preferences.
class _PreferencesWatchingSecretStore extends FakeSecretStore {
  final calls = <({String call, bool entryStillThere})>[];

  Future<void> _note(String call) async {
    final prefs = await SharedPreferences.getInstance();
    calls.add((call: call, entryStillThere: prefs.containsKey('identities')));
  }

  @override
  Future<String?> read(String key) async {
    await _note('read $key');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    await _note('write $key');
    return super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await _note('delete $key');
    return super.delete(key);
  }
}

// Refuses some writes, like a keyring that locked.
class _LockedWritesSecretStore extends FakeSecretStore {
  _LockedWritesSecretStore(this.fails);

  final bool Function(String key) fails;

  @override
  Future<void> write(String key, String value) {
    if (fails(key)) throw PlatformException(code: 'KeyringLocked');
    return super.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HeldIdentity a;
  late HeldIdentity b;

  FakeSecretStore store() => SettingsStore.secretStore as FakeSecretStore;

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  void plaintextInPreferences(String raw) {
    SharedPreferences.setMockInitialValues({
      'identities': raw,
      'theme_mode': 'dark',
    });
  }

  setUp(() {
    a = newHeldIdentity();
    b = newHeldIdentity();
    plaintextInPreferences(plaintextIdentities([a, b]));
    SettingsStore.secretStore = FakeSecretStore();
    IdentityStore.reset();
    identitiesNotifier.value = const [];
    activeIdentityPubkeyNotifier.value = null;
  });

  tearDown(IdentityStore.reset);

  Future<List<String>> loadedPubkeys() async => [
    for (final identity in (await SettingsStore.loadIdentityIndex()).identities)
      identity.pubkeyHex,
  ];

  group(
    'identities that builds from before secure storage kept in preferences',
    () {
      test('are moved into secure storage, and out of preferences', () async {
        final index = await SettingsStore.loadIdentityIndex();

        expect(index.identities.map((i) => i.pubkeyHex), [
          a.pubkeyHex,
          b.pubkeyHex,
        ]);
        expect(index.identities.first.createdAt, a.identity.createdAt);
        for (final held in [a, b]) {
          expect(
            await SettingsStore.loadPrivateKey(held.pubkeyHex),
            held.privkeyHex,
          );
          expect(index.slotOf(held.pubkeyHex), isNotNull);
        }
        expect((await prefs()).getKeys(), {'theme_mode'});
        expect(store().values.keys, hasLength(3));
        expect(
          store().values.keys,
          isNot(contains('identities_from_preferences')),
        );
      });

      test(
        'are listed before preferences are asked which one is active',
        () async {
          SharedPreferences.setMockInitialValues({
            'identities': plaintextIdentities([a, b]),
            'active_identity_pubkey': b.pubkeyHex,
            'theme_mode': 'dark',
          });

          final index = await SettingsStore.loadIdentityIndex();

          expect(index.active, b.pubkeyHex);
          expect((await prefs()).getKeys(), {'theme_mode'});
        },
      );

      test('are put after the identities that are listed already', () async {
        final x = newHeldIdentity();
        SettingsStore.secretStore = FakeSecretStore(currentStorage([x]));

        expect(await loadedPubkeys(), [x.pubkeyHex, a.pubkeyHex, b.pubkeyHex]);
      });

      test('are listed once, and keep the key stored for them', () async {
        SettingsStore.secretStore = FakeSecretStore(currentStorage([a]));

        expect(await loadedPubkeys(), [a.pubkeyHex, b.pubkeyHex]);
        expect(await SettingsStore.loadPrivateKey(a.pubkeyHex), a.privkeyHex);
        expect((await prefs()).containsKey('identities'), isFalse);
      });

      test('get their key stored when only their entry is', () async {
        SettingsStore.secretStore = FakeSecretStore({
          'identities': currentStorage([a, b])['identities']!,
        });

        await SettingsStore.loadIdentityIndex();

        expect(await SettingsStore.loadPrivateKey(a.pubkeyHex), a.privkeyHex);
        expect(await SettingsStore.loadPrivateKey(b.pubkeyHex), b.privkeyHex);
      });

      test('are listed when only their key is stored', () async {
        SettingsStore.secretStore = FakeSecretStore({
          'identity_secret_${a.pubkeyHex}': a.privkeyHex,
        });

        expect(await loadedPubkeys(), [a.pubkeyHex, b.pubkeyHex]);
        for (final name in store().values.keys) {
          expect(name, isNot(contains(a.pubkeyHex)));
        }
      });

      test(
        'leave preferences only after everything is stored and read back',
        () async {
          final watching = _PreferencesWatchingSecretStore();
          SettingsStore.secretStore = watching;

          await SettingsStore.loadIdentityIndex();

          final writes = watching.calls.where(
            (c) => c.call.startsWith('write'),
          );
          expect(writes, isNotEmpty);
          expect(writes.map((c) => c.entryStillThere), everyElement(isTrue));
          // The read that follows each write checks it.
          final reads = watching.calls.take(
            watching.calls.lastIndexWhere((c) => c.call.startsWith('write')) +
                2,
          );
          expect(reads.map((c) => c.entryStillThere), everyElement(isTrue));
          expect((await prefs()).containsKey('identities'), isFalse);
        },
      );

      test('stay in preferences while the index cannot be written', () async {
        SettingsStore.secretStore = _LockedWritesSecretStore(
          (key) => key == 'identities',
        );
        final reported = captureReportedErrors();

        final index = await SettingsStore.loadIdentityIndex();

        expect(reported, hasLength(1));
        expect(index.identities, isEmpty);
        expect((await prefs()).getString('identities'), contains(a.privkeyHex));

        // The next start, with storage working, moves them.
        SettingsStore.secretStore = FakeSecretStore(store().values);
        expect(await loadedPubkeys(), [a.pubkeyHex, b.pubkeyHex]);
        expect((await prefs()).containsKey('identities'), isFalse);
      });

      test('stay in preferences while a key cannot be stored', () async {
        SettingsStore.secretStore = _LockedWritesSecretStore(
          (key) => key.startsWith('identity_secret_'),
        );
        captureReportedErrors();

        await SettingsStore.loadIdentityIndex();

        expect((await prefs()).getString('identities'), contains(b.privkeyHex));
        expect(store().values.keys, isNot(contains('identities')));
      });

      test('stay in preferences when the index cannot be read', () async {
        SettingsStore.secretStore = FaultySecretStore(store(), failCall: 1);
        final reported = captureReportedErrors();

        await SettingsStore.loadIdentityIndex();

        expect(reported, hasLength(1));
        expect((await prefs()).getString('identities'), contains(a.privkeyHex));
      });

      test(
        'are not touched by the cleanup of settings that nothing reads',
        () async {
          SharedPreferences.setMockInitialValues({
            'identities': plaintextIdentities([a, b]),
            'profile_cache': '{}',
            'theme_mode': 'dark',
          });

          await SettingsStore.removeObsoleteKeys();

          expect((await prefs()).getKeys(), {'identities', 'theme_mode'});
        },
      );

      test('are moved whichever of the startup steps comes first', () async {
        SharedPreferences.setMockInitialValues({
          'identities': plaintextIdentities([a, b]),
          'profile_cache': '{}',
        });

        await Future.wait([
          SettingsStore.removeObsoleteKeys(),
          IdentityStore.load(),
        ]);

        expect(identitiesNotifier.value.map((i) => i.pubkeyHex), [
          a.pubkeyHex,
          b.pubkeyHex,
        ]);
        expect((await prefs()).getKeys(), isEmpty);
        expect(await SettingsStore.loadPrivateKey(b.pubkeyHex), b.privkeyHex);
      });

      test('are shown by the app after its first start', () async {
        await IdentityStore.load();

        expect(identitiesNotifier.value.map((i) => i.pubkeyHex), [
          a.pubkeyHex,
          b.pubkeyHex,
        ]);
        expect(activeIdentityPubkeyNotifier.value, a.pubkeyHex);
        expect(IdentityStore.unlisted.value, isEmpty);
      });
    },
  );

  group('what cannot become an identity', () {
    Future<void> expectBackedUpAndGone(String raw) async {
      expect(store().values['identities_from_preferences'], raw);
      expect((await prefs()).containsKey('identities'), isFalse);
    }

    test('is copied as it was before preferences let go of it', () async {
      const raw = '[{"pubkeyHex": "broken"';
      plaintextInPreferences(raw);

      final index = await SettingsStore.loadIdentityIndex();

      expect(index.identities, isEmpty);
      await expectBackedUpAndGone(raw);
    });

    test('is copied too when it is not a list of identities', () async {
      for (final raw in ['{"a": 1}', '"text"', '42', '']) {
        SettingsStore.secretStore = FakeSecretStore();
        plaintextInPreferences(raw);

        await SettingsStore.loadIdentityIndex();

        await expectBackedUpAndGone(raw);
      }
    });

    test('is not copied when preferences hold a list of nothing', () async {
      plaintextInPreferences('[]');

      await SettingsStore.loadIdentityIndex();

      expect(store().values, isEmpty);
      expect((await prefs()).containsKey('identities'), isFalse);
    });

    test('leaves the identities beside it to be adopted', () async {
      final other = newHeldIdentity();
      final raw = jsonEncode([
        {...a.identity.toJson(), 'privkeyHex': other.privkeyHex},
        {...b.identity.toJson(), 'privkeyHex': b.privkeyHex},
        {
          'pubkeyHex': 'f' * 64,
          'createdAt': 'yesterday',
          'privkeyHex': '11' * 32,
        },
        'junk',
      ]);
      plaintextInPreferences(raw);

      final index = await SettingsStore.loadIdentityIndex();

      expect(index.identities.map((i) => i.pubkeyHex), [b.pubkeyHex]);
      expect(await SettingsStore.loadPrivateKey(a.pubkeyHex), isNull);
      await expectBackedUpAndGone(raw);
    });

    test('is kept in preferences when it cannot be copied', () async {
      const raw = 'not json';
      plaintextInPreferences(raw);
      SettingsStore.secretStore = _LockedWritesSecretStore(
        (key) => key == 'identities_from_preferences',
      );
      final reported = captureReportedErrors();

      await SettingsStore.loadIdentityIndex();

      expect(reported, hasLength(1));
      expect((await prefs()).getString('identities'), raw);
    });

    test('does not replace the key that is stored for the identity', () async {
      final raw = plaintextIdentities([a, b]);
      SettingsStore.secretStore = FakeSecretStore({
        ...currentStorage([a]),
        'identity_secret_slot0': 'another key',
      });

      final index = await SettingsStore.loadIdentityIndex();

      expect(store().values['identity_secret_slot0'], 'another key');
      expect(index.identities.map((i) => i.pubkeyHex), [
        a.pubkeyHex,
        b.pubkeyHex,
      ]);
      await expectBackedUpAndGone(raw);
    });

    test('is not mistaken for an identity an unreadable entry names', () async {
      SettingsStore.secretStore = FakeSecretStore({
        'identities': jsonEncode([
          {'pubkeyHex': a.pubkeyHex},
        ]),
      });

      await SettingsStore.loadIdentityIndex();

      await expectBackedUpAndGone(plaintextIdentities([a, b]));
      expect(await SettingsStore.loadPrivateKey(b.pubkeyHex), b.privkeyHex);
    });
  });

  test('whichever storage call fails, no key is lost on the way out of preferences', () async {
    final raw = jsonEncode([
      {...a.identity.toJson(), 'privkeyHex': a.privkeyHex},
      'junk',
      {...b.identity.toJson(), 'privkeyHex': b.privkeyHex},
    ]);
    final x = newHeldIdentity();
    captureReportedErrors();

    await forEveryFault(
      seed: currentStorage([x]),
      reset: () async => plaintextInPreferences(raw),
      scenario: SettingsStore.loadIdentityIndex,
      check: (fault, after, error) async {
        final stillThere = (await prefs()).containsKey('identities');

        // Right after the failure: each key is in preferences or in secure
        // storage, and so is the entry that was not an identity.
        if (!stillThere) {
          expect(
            after.values['identities_from_preferences'],
            raw,
            reason: fault,
          );
          for (final held in [a, b]) {
            expect(
              isStored(after.values, held.privkeyHex),
              isTrue,
              reason: fault,
            );
          }
        }
        expect(isStored(after.values, x.privkeyHex), isTrue, reason: fault);
        expect(
          storedIndex(after.values).contains(x.pubkeyHex),
          isTrue,
          reason: fault,
        );

        // A start that works finishes the move.
        final index = await SettingsStore.loadIdentityIndex();
        expect(index.identities.map((i) => i.pubkeyHex), [
          x.pubkeyHex,
          a.pubkeyHex,
          b.pubkeyHex,
        ], reason: fault);
        for (final held in [x, a, b]) {
          expect(
            await SettingsStore.loadPrivateKey(held.pubkeyHex),
            held.privkeyHex,
            reason: fault,
          );
        }
        expect(after.values['identities_from_preferences'], raw, reason: fault);
        expect(
          (await prefs()).containsKey('identities'),
          isFalse,
          reason: fault,
        );
      },
    );
  });
}
