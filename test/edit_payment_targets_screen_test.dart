import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/models/payment_target_types.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/edit_payment_targets_screen.dart';
import 'package:sputnik/screens/edit_profile_screen.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/in_memory_relay_client.dart';

void main() {
  late Identity identity;
  late InMemoryRelayClient client;

  setUp(() async {
    final keypair = generateNostrKeyPair();
    identity = Identity(
      pubkeyHex: keypair.publicKeyHex,
      createdAt: DateTime.now(),
    );
    identitiesNotifier.value = [identity];
    activeIdentityPubkeyNotifier.value = identity.pubkeyHex;
    selectedRelaysNotifier.value = {'wss://relay.example'};
    profileCacheNotifier.value = const {};

    SettingsStore.secretStore = FakeSecretStore();
    await SettingsStore.savePrivateKey(
      identity.pubkeyHex,
      keypair.privateKeyHex,
    );

    client = InMemoryRelayClient([
      fakeEvent(
        id: '0a',
        pubkey: identity.pubkeyHex,
        kind: 10133,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        tags: [
          ['payto', 'xmr', '4abc', 'extra'],
          ['payto', 'paypal', 'me@example.com'],
          ['alt', 'kept'],
        ],
      ),
    ]);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EditPaymentTargetsScreen(relayClient: client)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('savePaymentTargetsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSavePaymentTargetsButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('lists the published targets', (tester) async {
    await open(tester);

    expect(find.widgetWithText(TextField, '4abc'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'me@example.com'), findsOneWidget);
    expect(find.text('Monero'), findsOneWidget);
  });

  testWidgets('saving unchanged rows keeps their tags exactly', (tester) async {
    await open(tester);

    await save(tester);

    final event = client.published.single;
    expect(event.kind, 10133);
    expect(event.tags, [
      ['alt', 'kept'],
      ['payto', 'xmr', '4abc', 'extra'],
      ['payto', 'paypal', 'me@example.com'],
    ]);
  });

  testWidgets('adds, edits and removes targets', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(const Key('removePaymentTargetButton')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addPaymentTargetButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('paymentTargetAddressField')).last,
      '  bc1qexample  ',
    );
    await save(tester);

    expect(client.published.single.tags, [
      ['alt', 'kept'],
      ['payto', 'paypal', 'me@example.com'],
      ['payto', knownPaymentTargetTypeFirst, 'bc1qexample'],
    ]);
    expect(find.textContaining('Updated payment targets on 1/1'), findsOne);
  });

  testWidgets('an empty or spaced address blocks saving', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(const Key('addPaymentTargetButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('savePaymentTargetsButton')));
    await tester.pumpAndSettle();
    expect(find.text('Enter an address'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('paymentTargetAddressField')).last,
      'has space',
    );
    await tester.tap(find.byKey(const Key('savePaymentTargetsButton')));
    await tester.pumpAndSettle();
    expect(find.text('An address has no spaces'), findsOneWidget);
    expect(client.published, isEmpty);
  });

  testWidgets('removing every target publishes an empty set', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(const Key('removePaymentTargetButton')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('removePaymentTargetButton')).first);
    await tester.pumpAndSettle();
    await save(tester);

    expect(client.published.single.tags, [
      ['alt', 'kept'],
    ]);
  });

  testWidgets('warns when the published targets could not be checked', (
    tester,
  ) async {
    client.events.clear();
    client.relaysAnswer = false;
    await open(tester);

    expect(
      find.byKey(const Key('retryLoadPaymentTargetsButton')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('savePaymentTargetsButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be checked'), findsWidgets);
    expect(client.published, isEmpty);
  });

  testWidgets('a rejected publish keeps the screen open', (tester) async {
    client.publishOutcome = RelayPublishOutcome.rejected;
    await open(tester);

    await save(tester);
    await tester.pumpAndSettle();

    expect(find.byType(EditPaymentTargetsScreen), findsOneWidget);
    expect(
      find.text('Could not publish your payment targets to any relay'),
      findsOneWidget,
    );
  });

  testWidgets('the edit profile screen links to it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EditProfileScreen(relayClient: client)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('editPaymentTargetsTile')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('editPaymentTargetsTile')));
    await tester.pumpAndSettle();

    expect(find.byType(EditPaymentTargetsScreen), findsOneWidget);
  });
}

// The type a newly added row starts on.
final knownPaymentTargetTypeFirst = paymentTargetTypes.keys.first;
