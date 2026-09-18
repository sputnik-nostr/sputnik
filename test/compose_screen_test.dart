import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/compose_screen.dart';
import 'package:sputnik/services/settings_store.dart';

class _FakeSecretStore implements SecretStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class _FakeRelayClient extends RelayClient {
  _FakeRelayClient(this._outcome, {this.message});

  final RelayPublishOutcome _outcome;
  final String? message;
  NostrEvent? lastPublished;

  @override
  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) async {
    lastPublished = event;
    return {
      for (final url in relayUrls)
        url: RelayPublishResult(_outcome, message: message),
    };
  }
}

void main() {
  late Identity identity;

  setUp(() async {
    // Avoid HomeScreen's indefinite loading spinner, which would keep
    // pumpAndSettle spinning forever.
    notesNotifier.value = const [];
    followingNotesNotifier.value = const [];

    // A fresh, throwaway keypair generated for this test run only -- never
    // a real saved identity.
    final keypair = generateNostrKeyPair();
    identity = Identity(
      pubkeyHex: keypair.publicKeyHex,
      createdAt: DateTime.now(),
    );
    identitiesNotifier.value = [identity];
    activeIdentityPubkeyNotifier.value = identity.pubkeyHex;
    selectedRelaysNotifier.value = {'wss://relay.example'};

    SettingsStore.secretStore = _FakeSecretStore();
    await SettingsStore.savePrivateKey(
      identity.pubkeyHex,
      keypair.privateKeyHex,
    );
  });

  Future<void> openComposeScreenViaFab(WidgetTester tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.byKey(const Key('composeFab')));
    await tester.pumpAndSettle();
  }

  Future<void> openComposeScreen(
    WidgetTester tester,
    RelayClient relayClient,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ComposeScreen(relayClient: relayClient),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping the compose FAB opens the compose screen', (
    tester,
  ) async {
    await openComposeScreenViaFab(tester);

    expect(find.byType(ComposeScreen), findsOneWidget);

    final textField = tester.widget<TextField>(
      find.byKey(const Key('composeTextField')),
    );
    expect(textField.autofocus, isTrue);
  });

  testWidgets('the post button is disabled until text is entered', (
    tester,
  ) async {
    await openComposeScreenViaFab(tester);

    FilledButton postButton() =>
        tester.widget<FilledButton>(find.byKey(const Key('composePostButton')));

    expect(postButton().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('composeTextField')),
      'gm nostr',
    );
    await tester.pump();

    expect(postButton().onPressed, isNotNull);
  });

  testWidgets('closing the compose screen returns to the root screen', (
    tester,
  ) async {
    await openComposeScreenViaFab(tester);

    await tester.tap(find.byKey(const Key('composeCloseButton')));
    await tester.pumpAndSettle();

    expect(find.byType(ComposeScreen), findsNothing);
    expect(find.byKey(const Key('composeFab')), findsOneWidget);
  });

  testWidgets('posting asks for confirmation before signing and publishing', (
    tester,
  ) async {
    final fakeClient = _FakeRelayClient(RelayPublishOutcome.accepted);
    await openComposeScreen(tester, fakeClient);

    await tester.enterText(
      find.byKey(const Key('composeTextField')),
      'gm nostr',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('composePostButton')));
    await tester.pumpAndSettle();

    expect(find.text('Post to relays?'), findsOneWidget);
    expect(fakeClient.lastPublished, isNull);
  });

  testWidgets('canceling the confirmation does not publish anything', (
    tester,
  ) async {
    final fakeClient = _FakeRelayClient(RelayPublishOutcome.accepted);
    await openComposeScreen(tester, fakeClient);

    await tester.enterText(
      find.byKey(const Key('composeTextField')),
      'gm nostr',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('composePostButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fakeClient.lastPublished, isNull);
    expect(find.byType(ComposeScreen), findsOneWidget);
  });

  testWidgets('confirming publishes a signed event and closes on success', (
    tester,
  ) async {
    final fakeClient = _FakeRelayClient(RelayPublishOutcome.accepted);
    await openComposeScreen(tester, fakeClient);

    await tester.enterText(
      find.byKey(const Key('composeTextField')),
      'gm nostr',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('composePostButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmPostButton')));
    // A couple of bounded pumps -- enough to let the dialog close and the
    // (fake, non-delayed) sign+publish resolve -- rather than
    // pumpAndSettle, which would advance the fake clock straight through
    // the SnackBar's whole auto-dismiss duration before we get to check it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Posted to'), findsOneWidget);

    final published = fakeClient.lastPublished;
    expect(published, isNotNull);
    expect(published!.pubkey, identity.pubkeyHex);
    expect(published.kind, 1);
    expect(published.content, 'gm nostr');

    await tester.pumpAndSettle();
    expect(find.byType(ComposeScreen), findsNothing);
  });

  testWidgets('a rejected publish keeps the compose screen open', (
    tester,
  ) async {
    final fakeClient = _FakeRelayClient(
      RelayPublishOutcome.rejected,
      message: 'blocked: spam',
    );
    await openComposeScreen(tester, fakeClient);

    await tester.enterText(
      find.byKey(const Key('composeTextField')),
      'gm nostr',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('composePostButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmPostButton')));
    await tester.pumpAndSettle();

    expect(fakeClient.lastPublished, isNotNull);
    expect(find.byType(ComposeScreen), findsOneWidget);
    expect(find.text('blocked: spam'), findsOneWidget);
  });
}
