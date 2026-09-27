import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/post_screen.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/in_memory_relay_client.dart';
import 'support/no_reactions.dart';

Note _noteOf(NostrEvent event) => Note(
  id: event.id,
  pubkey: event.pubkey,
  displayName: 'Me',
  handle: 'me',
  content: event.content,
  postedAt: '1m',
  createdAt: event.createdAt,
);

void main() {
  late Identity identity;
  late NostrEvent ownPost;
  late InMemoryRelayClient client;

  setUp(() async {
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

    ownPost = fakeEvent(
      id: 'aa',
      pubkey: identity.pubkeyHex,
      content: 'my own note',
    );
    client = InMemoryRelayClient([ownPost]);
    notesNotifier.value = [_noteOf(ownPost)];
    followingNotesNotifier.value = [_noteOf(ownPost)];
  });

  Future<void> openPost(WidgetTester tester, NostrEvent event) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PostScreen(
                  note: _noteOf(event),
                  threadRepository: RelayThreadRepository(
                    client: client,
                    reactionsRepository: const NoReactions(),
                  ),
                  relayClient: client,
                ),
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

  testWidgets('shows a delete button for your own focused note', (
    tester,
  ) async {
    await openPost(tester, ownPost);

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets("someone else's focused note has no delete button", (
    tester,
  ) async {
    final othersPost = fakeEvent(id: 'bb', pubkey: 'cc', content: 'not mine');
    final othersClient = InMemoryRelayClient([othersPost]);
    await tester.pumpWidget(
      MaterialApp(
        home: PostScreen(
          note: _noteOf(othersPost),
          threadRepository: RelayThreadRepository(
            client: othersClient,
            reactionsRepository: const NoReactions(),
          ),
          relayClient: othersClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets(
    'deleting your own note publishes a NIP-09 deletion, drops it from the '
    'cached feeds, and returns to the previous screen',
    (tester) async {
      await openPost(tester, ownPost);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Delete this note?'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(client.published.single.kind, 5);
      expect(client.published.single.tags, [
        ['e', ownPost.id],
        ['k', '1'],
      ]);
      expect(find.byType(PostScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(notesNotifier.value, isEmpty);
      expect(followingNotesNotifier.value, isEmpty);
    },
  );

  testWidgets('canceling the confirmation keeps the note and the screen open', (
    tester,
  ) async {
    await openPost(tester, ownPost);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(client.published, isEmpty);
    expect(find.byType(PostScreen), findsOneWidget);
    expect(notesNotifier.value!.map((n) => n.id), [ownPost.id]);
  });
}
