import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/publishing.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';

void main() {
  final me = generateNostrKeyPair();
  final other = generateNostrKeyPair();
  final identity = Identity(pubkeyHex: me.publicKeyHex, createdAt: DateTime(0));

  late GlobalKey<ScaffoldMessengerState> messengerKey;
  late List<SecretKey> created;

  setUp(() {
    SettingsStore.secretStore = FakeSecretStore();
    created = [];
    SettingsStore.secretKeyFromHex = (hex) {
      final key = SecretKey.fromHex(hex);
      created.add(key);
      return key;
    };
    messengerKey = GlobalKey<ScaffoldMessengerState>();
  });

  tearDown(() => SettingsStore.secretKeyFromHex = SecretKey.fromHex);

  Future<ScaffoldMessengerState> pumpMessenger(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(scaffoldMessengerKey: messengerKey, home: const Scaffold()),
    );
    return messengerKey.currentState!;
  }

  /// A [SecretKey] refuses to be used once it has been wiped.
  bool isWiped(SecretKey key) {
    try {
      xonlyPubkeyHex(key);
      return false;
    } on StateError {
      return true;
    }
  }

  group('loadSecretKey', () {
    test('hands out the key stored for the identity', () async {
      await SettingsStore.savePrivateKey(me.publicKeyHex, me.privateKeyHex);

      final key = await SettingsStore.loadSecretKey(me.publicKeyHex);

      expect(key, isNotNull);
      expect(xonlyPubkeyHex(key!), me.publicKeyHex);
    });

    test('treats a key that belongs to another pubkey as missing', () async {
      await SettingsStore.savePrivateKey(me.publicKeyHex, other.privateKeyHex);

      expect(await SettingsStore.loadSecretKey(me.publicKeyHex), isNull);
      expect(created, hasLength(1));
      expect(isWiped(created.single), isTrue);
    });

    test('treats a malformed key as missing', () async {
      await SettingsStore.savePrivateKey(me.publicKeyHex, 'not a key');

      expect(await SettingsStore.loadSecretKey(me.publicKeyHex), isNull);
      expect(created, isEmpty);
    });

    test('treats a value that is no secp256k1 key as missing', () async {
      // Valid hex, but zero and values above the group order are not keys.
      for (final value in ['00' * 32, 'ff' * 32]) {
        created.clear();
        await SettingsStore.savePrivateKey(me.publicKeyHex, value);

        expect(await SettingsStore.loadSecretKey(me.publicKeyHex), isNull);
        expect(isWiped(created.single), isTrue, reason: value);
      }
    });

    test('is null for an identity without a stored key', () async {
      expect(await SettingsStore.loadSecretKey(me.publicKeyHex), isNull);
      expect(created, isEmpty);
    });
  });

  testWidgets('withSecretKey never lends a key that is not the identity\'s', (
    tester,
  ) async {
    await SettingsStore.savePrivateKey(me.publicKeyHex, other.privateKeyHex);
    final messenger = await pumpMessenger(tester);
    var lent = false;

    final result = await tester.runAsync(
      () => withSecretKey<String>(
        identity,
        messenger,
        signFailure: 'Could not sign',
        use: (secretKey) async {
          lent = true;
          return 'signed';
        },
      ),
    );
    await tester.pump();

    expect(result, isNull);
    expect(lent, isFalse);
    expect(
      find.text("Could not find this identity's private key"),
      findsOneWidget,
    );
  });
}
