import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/compose_screen.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';

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

    SettingsStore.secretStore = FakeSecretStore();
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

  Future<void> openQuoteComposeScreen(
    WidgetTester tester,
    RelayClient relayClient,
    Note quoting,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ComposeScreen(quoting: quoting, relayClient: relayClient),
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

  final quoted = Note(
    id: 'aa' * 32,
    pubkey: 'bb' * 32,
    displayName: 'Alice',
    handle: 'alice',
    content: 'quoted note',
    postedAt: 'now',
    createdAt: DateTime.now(),
  );

  testWidgets(
    'quoting a note shows a preview of it and enables the post button with '
    'no comment required',
    (tester) async {
      final fakeClient = _FakeRelayClient(RelayPublishOutcome.accepted);
      await openQuoteComposeScreen(tester, fakeClient, quoted);

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('quoted note'), findsOneWidget);

      final postButton = tester.widget<FilledButton>(
        find.byKey(const Key('composePostButton')),
      );
      expect(postButton.onPressed, isNotNull);
    },
  );

  testWidgets(
    'confirming a quote with no comment publishes a q tag and just the note '
    'reference as content',
    (tester) async {
      final fakeClient = _FakeRelayClient(RelayPublishOutcome.accepted);
      await openQuoteComposeScreen(tester, fakeClient, quoted);

      await tester.tap(find.byKey(const Key('composePostButton')));
      await tester.pumpAndSettle();
      expect(find.text('Post quote to relays?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmPostButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Quote posted to'), findsOneWidget);

      final published = fakeClient.lastPublished!;
      expect(published.kind, 1);
      expect(published.tags, [
        ['q', quoted.id, '', quoted.pubkey],
      ]);
      expect(
        published.content,
        'nostr:${neventFromHex(quoted.id, authorPubkeyHex: quoted.pubkey)}',
      );
    },
  );

  testWidgets('confirming a quote with a comment prepends it before the note '
      'reference', (tester) async {
    final fakeClient = _FakeRelayClient(RelayPublishOutcome.accepted);
    await openQuoteComposeScreen(tester, fakeClient, quoted);

    await tester.enterText(
      find.byKey(const Key('composeTextField')),
      'nice post',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('composePostButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmPostButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final published = fakeClient.lastPublished!;
    expect(
      published.content,
      'nice post\n\nnostr:${neventFromHex(quoted.id, authorPubkeyHex: quoted.pubkey)}',
    );
  });
}
