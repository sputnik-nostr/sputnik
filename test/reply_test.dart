import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/compose_screen.dart';
import 'package:sputnik/screens/post_screen.dart';
import 'package:sputnik/services/settings_store.dart';
import 'package:sputnik/widgets/note_tile.dart';

import 'support/fake_secret_store.dart';
import 'support/in_memory_relay_client.dart';
import 'support/no_reactions.dart';

Note _noteOf(NostrEvent event, {String name = 'Someone'}) => Note(
  id: event.id,
  pubkey: event.pubkey,
  displayName: name,
  handle: name,
  content: event.content,
  postedAt: '1m',
  createdAt: event.createdAt,
);

DateTime _at(int minutes) =>
    DateTime.fromMillisecondsSinceEpoch(1700000000000 + minutes * 60000);

void main() {
  late Identity identity;

  setUp(() async {
    final keypair = generateNostrKeyPair();
    identity = Identity(
      pubkeyHex: keypair.publicKeyHex,
      createdAt: DateTime.now(),
    );
    identitiesNotifier.value = [identity];
    activeIdentityPubkeyNotifier.value = identity.pubkeyHex;
    selectedRelaysNotifier.value = const {};
    loadMediaNotifier.value = true;

    SettingsStore.secretStore = FakeSecretStore();
    await SettingsStore.savePrivateKey(
      identity.pubkeyHex,
      keypair.privateKeyHex,
    );
  });

  group('replying', () {
    late NostrEvent parent;
    late InMemoryRelayClient client;

    setUp(() {
      parent = fakeEvent(
        id: 'aa01',
        pubkey: 'bb',
        content: 'the parent',
        tags: [
          ['p', 'cc' * 32],
        ],
      );
      client = InMemoryRelayClient([parent]);
      selectedRelaysNotifier.value = {'wss://relay.example'};
    });

    Future<void> openReply(WidgetTester tester, {Note? replyTo}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ComposeScreen(
                    relayClient: client,
                    replyTo: replyTo ?? _noteOf(parent),
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

    Future<void> submit(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('composeTextField')),
        'my reply',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('composePostButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmPostButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('shows what is being replied to', (tester) async {
      await openReply(tester);

      expect(find.textContaining('Replying to'), findsOneWidget);
      expect(find.text('the parent'), findsOneWidget);
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Post your reply'), findsOneWidget);
    });

    testWidgets('publishes a note threaded under the parent', (tester) async {
      await openReply(tester);

      await submit(tester);

      final published = client.published.single;
      expect(published.kind, 1);
      expect(published.content, 'my reply');
      expect(published.pubkey, identity.pubkeyHex);
      expect(published.tags, [
        ['e', parent.id, '', 'root', parent.pubkey],
        ['p', parent.pubkey],
        ['p', 'cc' * 32],
      ]);
      expect(find.textContaining('Reply posted to'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(ComposeScreen), findsNothing);
    });

    testWidgets('does not publish when the parent cannot be loaded', (
      tester,
    ) async {
      client.events.clear();
      await openReply(tester);

      await submit(tester);

      expect(client.published, isEmpty);
      expect(
        find.text('Could not load the note you are replying to'),
        findsOneWidget,
      );
      expect(find.byType(ComposeScreen), findsOneWidget);
    });

    testWidgets('the confirmation says it is a reply', (tester) async {
      await openReply(tester);

      await tester.enterText(find.byKey(const Key('composeTextField')), 'hi');
      await tester.pump();
      await tester.tap(find.byKey(const Key('composePostButton')));
      await tester.pumpAndSettle();

      expect(find.text('Post reply to relays?'), findsOneWidget);
      expect(client.published, isEmpty);
    });
  });

  group('post screen', () {
    late NostrEvent root, mid, focus, child, grandchild;
    late InMemoryRelayClient client;

    setUp(() {
      root = fakeEvent(
        id: '01',
        pubkey: 'b1',
        content: 'root post',
        createdAt: _at(0),
      );
      mid = fakeEvent(
        id: '02',
        pubkey: 'b2',
        content: 'middle post',
        createdAt: _at(1),
        tags: [
          ['e', root.id, '', 'root'],
        ],
      );
      focus = fakeEvent(
        id: '03',
        pubkey: 'b3',
        content: 'focused post',
        createdAt: _at(2),
        tags: [
          ['e', root.id, '', 'root'],
          ['e', mid.id, '', 'reply'],
        ],
      );
      child = fakeEvent(
        id: '04',
        pubkey: 'b4',
        content: 'child reply',
        createdAt: _at(3),
        tags: [
          ['e', root.id, '', 'root'],
          ['e', focus.id, '', 'reply'],
        ],
      );
      grandchild = fakeEvent(
        id: '05',
        pubkey: 'b5',
        content: 'grandchild reply',
        createdAt: _at(4),
        tags: [
          ['e', root.id, '', 'root'],
          ['e', child.id, '', 'reply'],
        ],
      );
      client = InMemoryRelayClient([root, mid, focus, child, grandchild]);
    });

    Future<void> openPost(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PostScreen(
            note: _noteOf(focus),
            threadRepository: RelayThreadRepository(
              client: client,
              reactionsRepository: const NoReactions(),
            ),
            relayClient: client,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows ancestors above the viewed note', (tester) async {
      await openPost(tester);

      // They sit just above the fold until the reader scrolls up.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
      await tester.pumpAndSettle();

      final rootY = tester.getTopLeft(find.text('root post')).dy;
      final midY = tester.getTopLeft(find.text('middle post')).dy;
      final focusY = tester.getTopLeft(find.text('focused post')).dy;

      expect(rootY, lessThan(midY));
      expect(midY, lessThan(focusY));
    });

    testWidgets('slides the direct parent into view above the viewed note', (
      tester,
    ) async {
      await openPost(tester);

      final midY = tester.getTopLeft(find.text('middle post')).dy;
      final focusY = tester.getTopLeft(find.text('focused post')).dy;
      expect(midY, lessThan(focusY));
      expect(midY, greaterThanOrEqualTo(0));
      // Older ancestors stay above the fold.
      expect(find.text('root post'), findsNothing);
    });

    testWidgets('says so when the note it replies to cannot be found', (
      tester,
    ) async {
      client.events.remove(mid);
      await openPost(tester);

      expect(find.textContaining('was not found on your relays'), findsOne);
      expect(find.text('middle post'), findsNothing);
    });

    testWidgets('a top-level note has no missing parent notice', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PostScreen(
            note: _noteOf(root),
            threadRepository: RelayThreadRepository(
              client: client,
              reactionsRepository: const NoReactions(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('was not found'), findsNothing);
    });

    testWidgets('indents nested replies', (tester) async {
      await openPost(tester);

      final childX = tester.getTopLeft(find.text('child reply')).dx;
      final grandchildX = tester.getTopLeft(find.text('grandchild reply')).dx;

      expect(grandchildX, greaterThan(childX));
    });

    testWidgets('replying from the header adds the reply to the thread', (
      tester,
    ) async {
      await openPost(tester);

      selectedRelaysNotifier.value = {'wss://relay.example'};
      await tester.tap(find.byKey(const Key('replyToPostButton')));
      await tester.pumpAndSettle();
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(find.textContaining('Replying to'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('composeTextField')),
        'fresh reply',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('composePostButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmPostButton')));
      // The publish has its relays; none keeps the reload off the network.
      selectedRelaysNotifier.value = const {};
      await tester.pumpAndSettle();

      expect(find.byType(ComposeScreen), findsNothing);
      expect(find.text('fresh reply'), findsOneWidget);
      expect(
        client.published.single.tags,
        anyElement(equals(['p', focus.pubkey])),
      );
    });

    testWidgets('a reply tile has its own reply button', (tester) async {
      await openPost(tester);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(NoteTile, 'child reply'),
          matching: find.byKey(const Key('replyButton')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(find.text('child reply'), findsWidgets);
    });
  });
}
