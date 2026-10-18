import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/identity_index.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/reported_errors.dart';

// Refuses to store one identity's private key, like a locked keystore might.
class _LockedSlotSecretStore extends FakeSecretStore {
  _LockedSlotSecretStore(this._pubkeyHex);

  final String _pubkeyHex;
  var locked = true;

  @override
  Future<void> write(String key, String value) {
    if (locked && key == 'identity_secret_$_pubkeyHex') {
      throw StateError('locked');
    }
    return super.write(key, value);
  }
}

// Refuses to delete anything, like a locked keyring whose prompt was dismissed.
class _UndeletableSecretStore extends FakeSecretStore {
  var failDeletes = false;

  @override
  Future<void> delete(String key) {
    if (failDeletes) throw PlatformException(code: 'KeyringLocked');
    return super.delete(key);
  }
}

// Reports success for writes it does not keep, like a store that lost them.
class _ForgetfulSecretStore extends FakeSecretStore {
  _ForgetfulSecretStore(this.forgets);

  final bool Function(String key) forgets;

  @override
  Future<void> write(String key, String value) async {
    if (!forgets(key)) await super.write(key, value);
  }
}

Identity _identity(String pubkeyHex) =>
    Identity(pubkeyHex: pubkeyHex, createdAt: DateTime(2026));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SettingsStore.secretStore = FakeSecretStore();
  });

  test('drops persisted relays that no longer pass validation', () async {
    SharedPreferences.setMockInitialValues({
      'custom_relays': <String>[
        'wss://good.example.com',
        'wss://relay.damus.io@158.51.42.7',
        'not a url',
      ],
    });

    expect(await SettingsStore.loadCustomRelays(), {'wss://good.example.com'});
  });

  test(
    'drops persisted selected relays that no longer pass validation',
    () async {
      SharedPreferences.setMockInitialValues({
        'selected_relays': <String>[
          'wss://good.example.com',
          'wss://relay.damus.io@158.51.42.7',
        ],
      });

      final selected = await SettingsStore.loadSelectedRelays({
        'wss://good.example.com',
        'wss://relay.damus.io@158.51.42.7',
      });

      expect(selected, {'wss://good.example.com'});
    },
  );

  test('removing an identity makes its private key unreadable again', () async {
    await SettingsStore.addIdentity(_identity('a' * 64), 'seckeyhex');
    final index = await SettingsStore.removeIdentity('a' * 64);

    expect(index.identities, isEmpty);
    expect(await SettingsStore.loadPrivateKey('a' * 64), isNull);
    expect((await SettingsStore.loadIdentityIndex()).identities, isEmpty);
  });

  test('each identity has its own private key slot', () async {
    await SettingsStore.savePrivateKey('a' * 64, 'seckey-a');
    await SettingsStore.savePrivateKey('b' * 64, 'seckey-b');

    expect(await SettingsStore.loadPrivateKey('a' * 64), 'seckey-a');
    expect(await SettingsStore.loadPrivateKey('b' * 64), 'seckey-b');
  });

  test(
    'migrates a legacy identity whose private key was stored inline',
    () async {
      // The old format: privkeyHex inline in the identity index.
      await SettingsStore.secretStore.write(
        'identities',
        jsonEncode([
          {
            'pubkeyHex': 'a' * 64,
            'privkeyHex': 'legacy-secret',
            'createdAt': DateTime(2024).millisecondsSinceEpoch,
          },
        ]),
      );

      final identities = (await SettingsStore.loadIdentityIndex()).identities;

      expect(identities, hasLength(1));
      expect(identities.single.pubkeyHex, 'a' * 64);
      expect(await SettingsStore.loadPrivateKey('a' * 64), 'legacy-secret');

      // No secret is left in the index, so it won't migrate again.
      final rewritten = await SettingsStore.secretStore.read('identities');
      expect(rewritten, isNot(contains('legacy-secret')));
    },
  );

  test('a failed migration keeps the inline key in the index', () async {
    final store = _LockedSlotSecretStore('b' * 64);
    SettingsStore.secretStore = store;
    await store.write(
      'identities',
      jsonEncode([
        {'pubkeyHex': 'a' * 64, 'privkeyHex': 'secret-a', 'createdAt': 0},
        {'pubkeyHex': 'b' * 64, 'privkeyHex': 'secret-b', 'createdAt': 0},
      ]),
    );

    final reported = captureReportedErrors();

    final identities = (await SettingsStore.loadIdentityIndex()).identities;

    expect(identities, hasLength(2));
    expect(await SettingsStore.loadPrivateKey('a' * 64), 'secret-a');
    expect(await store.read('identities'), contains('secret-b'));
    expect(reported, hasLength(1));
  });

  test('migration does not clobber an already-recovered private key', () async {
    await SettingsStore.savePrivateKey('a' * 64, 'current-secret');
    await SettingsStore.secretStore.write(
      'identities',
      jsonEncode([
        {'pubkeyHex': 'a' * 64, 'privkeyHex': 'stale-secret', 'createdAt': 0},
      ]),
    );

    await SettingsStore.loadIdentityIndex();

    expect(await SettingsStore.loadPrivateKey('a' * 64), 'current-secret');
  });

  group('changing the identity index', () {
    final a = 'a' * 64;
    final b = 'b' * 64;
    final c = 'c' * 64;

    Future<List<String>> listed() async => [
      for (final identity
          in (await SettingsStore.loadIdentityIndex()).identities)
        identity.pubkeyHex,
    ];

    test('adding an identity stores its key and lists it', () async {
      final index = await SettingsStore.addIdentity(_identity(a), 'seckey-a');

      expect(index.identities.map((i) => i.pubkeyHex), [a]);
      expect(await SettingsStore.loadPrivateKey(a), 'seckey-a');
      expect(await listed(), [a]);
    });

    test('adding an identity twice lists it once', () async {
      await SettingsStore.addIdentity(_identity(a), 'seckey-a');
      await SettingsStore.addIdentity(_identity(a), 'seckey-a');

      expect(await listed(), [a]);
    });

    test(
      'a change starts from the stored index, not from a loaded one',
      () async {
        final store = SettingsStore.secretStore;
        await SettingsStore.addIdentity(_identity(a), 'seckey-a');
        final loaded = await SettingsStore.loadIdentityIndex();

        // Another window lists a second identity after this one loaded.
        final other = IdentityIndex.parse((await store.read('identities'))!)
            .withIdentity(_identity(b));
        await store.write('identities', other.encode());

        await SettingsStore.addIdentity(_identity(c), 'seckey-c');

        expect(loaded.identities, hasLength(1));
        expect(await listed(), [a, b, c]);
      },
    );

    test('changes made at the same time do not overwrite each other', () async {
      await Future.wait([
        SettingsStore.addIdentity(_identity(a), 'seckey-a'),
        SettingsStore.addIdentity(_identity(b), 'seckey-b'),
        SettingsStore.addIdentity(_identity(c), 'seckey-c'),
      ]);

      expect(await listed(), [a, b, c]);
    });

    test('removing an identity leaves the others alone', () async {
      await SettingsStore.addIdentity(_identity(a), 'seckey-a');
      await SettingsStore.addIdentity(_identity(b), 'seckey-b');

      await SettingsStore.removeIdentity(a);

      expect(await listed(), [b]);
      expect(await SettingsStore.loadPrivateKey(a), isNull);
      expect(await SettingsStore.loadPrivateKey(b), 'seckey-b');
    });

    test('a key that cannot be deleted keeps its identity listed', () async {
      final store = _UndeletableSecretStore();
      SettingsStore.secretStore = store;
      await SettingsStore.addIdentity(_identity(a), 'seckey-a');

      store.failDeletes = true;
      await expectLater(
        SettingsStore.removeIdentity(a),
        throwsA(isA<PlatformException>()),
      );

      expect(await listed(), [a]);
      expect(await SettingsStore.loadPrivateKey(a), 'seckey-a');
    });

    test('an identity whose key was not kept is not listed', () async {
      final store = _ForgetfulSecretStore(
        (key) => key.startsWith('identity_secret_'),
      );
      SettingsStore.secretStore = store;

      await expectLater(
        SettingsStore.addIdentity(_identity(a), 'seckey-a'),
        throwsStateError,
      );

      expect(await store.read('identities'), isNull);
    });

    test('an index that was not kept does not count as saved', () async {
      final store = _ForgetfulSecretStore((key) => key == 'identities');
      SettingsStore.secretStore = store;

      await expectLater(
        SettingsStore.addIdentity(_identity(a), 'seckey-a'),
        throwsStateError,
      );

      expect(await listed(), isEmpty);
    });

    test('an index that cannot be read is not written over', () async {
      final store = SettingsStore.secretStore;
      await store.write('identities', '{"version": 3, "identities": []}');

      await expectLater(
        SettingsStore.addIdentity(_identity(a), 'seckey-a'),
        throwsFormatException,
      );
      await expectLater(SettingsStore.removeIdentity(a), throwsFormatException);

      expect(
        await store.read('identities'),
        '{"version": 3, "identities": []}',
      );
    });
  });

  group('keys an older version stored inside the index', () {
    final a = 'a' * 64;
    final b = 'b' * 64;
    final c = 'c' * 64;

    Future<_LockedSlotSecretStore> lockedLegacyStore() async {
      final store = _LockedSlotSecretStore(b);
      SettingsStore.secretStore = store;
      await store.write(
        'identities',
        jsonEncode([
          {'pubkeyHex': a, 'privkeyHex': 'secret-a', 'createdAt': 0},
          {'pubkeyHex': b, 'privkeyHex': 'secret-b', 'createdAt': 0},
        ]),
      );
      return store;
    }

    test('stay in the index through adding and removing identities', () async {
      final store = await lockedLegacyStore();
      captureReportedErrors();
      await SettingsStore.loadIdentityIndex();

      await SettingsStore.addIdentity(_identity(c), 'secret-c');
      await SettingsStore.removeIdentity(a);

      expect(await store.read('identities'), contains('secret-b'));
      expect(await SettingsStore.loadPrivateKey(b), isNull);
    });

    test('are moved once their entry can be written', () async {
      final store = await lockedLegacyStore();
      captureReportedErrors();
      await SettingsStore.loadIdentityIndex();
      await SettingsStore.addIdentity(_identity(c), 'secret-c');

      store.locked = false;
      await SettingsStore.loadIdentityIndex();

      expect(await SettingsStore.loadPrivateKey(b), 'secret-b');
      expect(await store.read('identities'), isNot(contains('secret-b')));
    });

    test('are not lost with an entry that cannot be read', () async {
      final store = SettingsStore.secretStore;
      final damaged = {
        'pubkeyHex': b,
        'createdAt': '0',
        'privkeyHex': 'secret-b',
      };
      await store.write(
        'identities',
        jsonEncode([
          {'pubkeyHex': a, 'createdAt': 0},
          damaged,
        ]),
      );

      await SettingsStore.loadIdentityIndex();
      await SettingsStore.addIdentity(_identity(c), 'secret-c');
      await SettingsStore.removeIdentity(a);

      final entries =
          (jsonDecode((await store.read('identities'))!)
                  as Map<String, dynamic>)['identities']
              as List<dynamic>;
      expect(entries, contains(equals(damaged)));
      expect(entries, hasLength(2));
    });
  });

  test('removes the keys old versions left behind, and only those', () async {
    SharedPreferences.setMockInitialValues({
      'profile_cache': '{"a":1}',
      'bookmarked_ids': ['x'],
      'current_user_profile': '{}',
      'note_media_mode': 'always',
      'theme_mode': 'dark',
      'load_media': true,
    });

    await SettingsStore.removeObsoleteKeys();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), unorderedEquals(['theme_mode', 'load_media']));
  });

  test('profile images default to on', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await SettingsStore.loadLoadProfileImages(), isNull);
    expect(loadProfileImagesNotifier.defaultValue, isTrue);
  });

  test('profile image loading persists once saved', () async {
    SharedPreferences.setMockInitialValues({});

    await SettingsStore.saveLoadProfileImages(false);

    expect(await SettingsStore.loadLoadProfileImages(), isFalse);
  });

  test('note images default to loading automatically', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await SettingsStore.loadLoadNoteImages(), isNull);
    expect(loadNoteImagesNotifier.defaultValue, isTrue);
  });

  test('note image loading persists once saved', () async {
    SharedPreferences.setMockInitialValues({});

    await SettingsStore.saveLoadNoteImages(false);

    expect(await SettingsStore.loadLoadNoteImages(), isFalse);
  });

  test('hidden payment target types default to none hidden', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await SettingsStore.loadHiddenPaymentTargetTypes(), isNull);
    expect(hiddenPaymentTargetTypesNotifier.defaultValue, isEmpty);
  });

  test('hidden payment target types persist once saved', () async {
    SharedPreferences.setMockInitialValues({});

    await SettingsStore.saveHiddenPaymentTargetTypes({'monero', 'paypal'});

    expect(await SettingsStore.loadHiddenPaymentTargetTypes(), {
      'monero',
      'paypal',
    });
  });
}
