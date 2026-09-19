import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';

// Refuses to store one identity's private key, like a locked keystore might.
class _LockedSlotSecretStore extends FakeSecretStore {
  _LockedSlotSecretStore(this._pubkeyHex);

  final String _pubkeyHex;

  @override
  Future<void> write(String key, String value) {
    if (key == 'identity_secret_$_pubkeyHex') throw StateError('locked');
    return super.write(key, value);
  }
}

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

  test('deleting a private key makes it unreadable again', () async {
    await SettingsStore.savePrivateKey('a' * 64, 'seckeyhex');
    await SettingsStore.deletePrivateKey('a' * 64);

    expect(await SettingsStore.loadPrivateKey('a' * 64), isNull);
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
      // The format used before private keys got their own secure-storage
      // slot: privkeyHex embedded right in the identity index.
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

      final identities = await SettingsStore.loadIdentities();

      expect(identities, hasLength(1));
      expect(identities.single.pubkeyHex, 'a' * 64);
      expect(await SettingsStore.loadPrivateKey('a' * 64), 'legacy-secret');

      // The index itself no longer carries the secret, so this doesn't
      // need to migrate again next time.
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

    final identities = await SettingsStore.loadIdentities();

    expect(identities, hasLength(2));
    expect(await SettingsStore.loadPrivateKey('a' * 64), 'secret-a');
    expect(await store.read('identities'), contains('secret-b'));
  });

  test('migration does not clobber an already-recovered private key', () async {
    await SettingsStore.savePrivateKey('a' * 64, 'current-secret');
    await SettingsStore.secretStore.write(
      'identities',
      jsonEncode([
        {'pubkeyHex': 'a' * 64, 'privkeyHex': 'stale-secret', 'createdAt': 0},
      ]),
    );

    await SettingsStore.loadIdentities();

    expect(await SettingsStore.loadPrivateKey('a' * 64), 'current-secret');
  });

  test('load media defaults to on', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await SettingsStore.loadLoadMedia(), isTrue);
  });

  test('load media persists once saved', () async {
    SharedPreferences.setMockInitialValues({});

    await SettingsStore.saveLoadMedia(false);

    expect(await SettingsStore.loadLoadMedia(), isFalse);
  });

  test('hidden payment target types default to none hidden', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await SettingsStore.loadHiddenPaymentTargetTypes(), isEmpty);
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
