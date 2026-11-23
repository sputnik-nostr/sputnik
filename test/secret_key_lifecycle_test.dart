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

  group('withSecretKey', () {
    setUp(() async {
      await SettingsStore.savePrivateKey(me.publicKeyHex, me.privateKeyHex);
    });

    testWidgets('lends a usable key and wipes it once use returns', (
      tester,
    ) async {
      final messenger = await pumpMessenger(tester);
      SecretKey? lent;

      final result = await withSecretKey<String>(
        identity,
        messenger,
        signFailure: 'Could not sign',
        use: (secretKey) async {
          lent = secretKey;
          expect(isWiped(secretKey), isFalse);
          return xonlyPubkeyHex(secretKey);
        },
      );

      expect(result, me.publicKeyHex);
      expect(isWiped(lent!), isTrue);
    });

    testWidgets('wipes the key when use rejects it as invalid', (tester) async {
      final messenger = await pumpMessenger(tester);
      SecretKey? lent;

      final result = await withSecretKey<String>(
        identity,
        messenger,
        signFailure: 'Could not sign',
        use: (secretKey) async {
          lent = secretKey;
          throw ArgumentError('invalid secp256k1 secret key');
        },
      );
      await tester.pump();

      expect(result, isNull);
      expect(find.text('Could not sign'), findsOneWidget);
      expect(isWiped(lent!), isTrue);
    });

    testWidgets('wipes the key and passes on any other error', (tester) async {
      final messenger = await pumpMessenger(tester);
      SecretKey? lent;

      await expectLater(
        withSecretKey<String>(
          identity,
          messenger,
          signFailure: 'Could not sign',
          use: (secretKey) async {
            lent = secretKey;
            throw StateError('relay went away');
          },
        ),
        throwsStateError,
      );

      expect(isWiped(lent!), isTrue);
    });

    testWidgets('wipes the key when use throws before returning a future', (
      tester,
    ) async {
      final messenger = await pumpMessenger(tester);
      SecretKey? lent;

      await expectLater(
        withSecretKey<String>(
          identity,
          messenger,
          signFailure: 'Could not sign',
          use: (secretKey) {
            lent = secretKey;
            throw StateError('failed synchronously');
          },
        ),
        throwsStateError,
      );

      expect(isWiped(lent!), isTrue);
    });

    testWidgets('says so when the identity has no key', (tester) async {
      SettingsStore.secretStore = FakeSecretStore();
      final messenger = await pumpMessenger(tester);
      var called = false;

      final result = await withSecretKey<String>(
        identity,
        messenger,
        signFailure: 'Could not sign',
        use: (secretKey) async {
          called = true;
          return 'signed';
        },
      );
      await tester.pump();

      expect(result, isNull);
      expect(called, isFalse);
      expect(
        find.text("Could not find this identity's private key"),
        findsOneWidget,
      );
    });

    testWidgets('never lends a key that is not the identity\'s', (
      tester,
    ) async {
      await SettingsStore.savePrivateKey(me.publicKeyHex, other.privateKeyHex);
      final messenger = await pumpMessenger(tester);
      var called = false;

      final result = await withSecretKey<String>(
        identity,
        messenger,
        signFailure: 'Could not sign',
        use: (secretKey) async {
          called = true;
          return 'signed';
        },
      );
      await tester.pump();

      expect(result, isNull);
      expect(called, isFalse);
      expect(
        find.text("Could not find this identity's private key"),
        findsOneWidget,
      );
    });
  });
}
