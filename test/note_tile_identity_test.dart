import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/bookmarks_screen.dart';
import 'package:sputnik/screens/home_screen.dart';
import 'package:sputnik/screens/post_screen.dart';
import 'package:sputnik/screens/search_screen.dart';
import 'package:sputnik/services/settings_store.dart';
import 'package:sputnik/widgets/note_tile.dart';

import 'support/fake_secret_store.dart';
import 'support/in_memory_relay_client.dart';
import 'support/no_reactions.dart';

// Tiles outlive an identity switch: they sit in tabs under Settings, where the
// switch is made. Whatever they offer for the active identity has to follow it.
void main() {
  late NostrKeyPair a;
  late NostrKeyPair b;
  late NostrEvent eventOfA;
  late Note noteOfA;
  late InMemoryRelayClient relay;

  final delete = find.byIcon(Icons.delete_outline);

  setUp(() async {
    a = generateNostrKeyPair();
    b = generateNostrKeyPair();
    SettingsStore.secretStore = FakeSecretStore();
    await SettingsStore.savePrivateKey(a.publicKeyHex, a.privateKeyHex);
    await SettingsStore.savePrivateKey(b.publicKeyHex, b.privateKeyHex);
    identitiesNotifier.value = [
      Identity(pubkeyHex: a.publicKeyHex, createdAt: DateTime(2026, 1, 1)),
      Identity(pubkeyHex: b.publicKeyHex, createdAt: DateTime(2026, 1, 2)),
    ];
    activeIdentityPubkeyNotifier.value = a.publicKeyHex;
    selectedRelaysNotifier.value = {'wss://relay.example'};
    profileCacheNotifier.value = const {};
    myFollowingNotifier.value = const {};

    eventOfA = fakeEvent(
      id: 'cc',
      pubkey: a.publicKeyHex,
      content: 'written as identity A',
    );
    noteOfA = Note(
      id: eventOfA.id,
      pubkey: eventOfA.pubkey,
      displayName: 'A',
      content: eventOfA.content,
      createdAt: eventOfA.createdAt,
    );
    notesNotifier.value = [noteOfA];
    followingNotesNotifier.value = const [];
    bookmarkedNotesNotifier.value = const {};
    relay = InMemoryRelayClient([eventOfA]);
    RelayClient.instance = relay;
  });

  tearDown(() {
    notesNotifier.value = null;
    followingNotesNotifier.value = null;
    bookmarkedNotesNotifier.value = const {};
    profileCacheNotifier.value = const {};
  });

  Future<void> switchTo(WidgetTester tester, String? pubkeyHex) async {
    activeIdentityPubkeyNotifier.value = pubkeyHex;
    await tester.pumpAndSettle();
  }

  group('NoteTile', () {
    Future<void> pumpTile(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NoteTile(note: noteOfA)),
      ),
    );

    testWidgets('offers Delete on the active identity\'s notes only', (
      tester,
    ) async {
      await pumpTile(tester);
      expect(delete, findsOneWidget);

      await switchTo(tester, b.publicKeyHex);
      expect(delete, findsNothing);

      await switchTo(tester, a.publicKeyHex);
      expect(delete, findsOneWidget);

      await switchTo(tester, null);
      expect(delete, findsNothing);
    });

    testWidgets('keeps its other actions through a switch', (tester) async {
      await pumpTile(tester);
      await switchTo(tester, b.publicKeyHex);

      expect(find.byKey(const Key('replyButton')), findsOneWidget);
      expect(find.byIcon(Icons.repeat), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    });
  });

  group('lists', () {
    testWidgets('Global stops offering Delete on A\'s note once B is active', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HomeScreen())),
      );
      await tester.tap(find.text('Global'));
      await tester.pumpAndSettle();
      expect(delete, findsOneWidget);

      await switchTo(tester, b.publicKeyHex);

      expect(find.text('written as identity A'), findsOneWidget);
      expect(delete, findsNothing);
    });

    testWidgets(
      'Bookmarks stops offering Delete on A\'s note once B is active',
      (tester) async {
        bookmarkedNotesNotifier.value = {noteOfA.id: noteOfA};
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: BookmarksScreen())),
        );
        expect(delete, findsOneWidget);

        await switchTo(tester, b.publicKeyHex);

        expect(find.text('written as identity A'), findsOneWidget);
        expect(delete, findsNothing);
      },
    );

    testWidgets('a Bookmarks list built after the switch never offers it', (
      tester,
    ) async {
      bookmarkedNotesNotifier.value = {noteOfA.id: noteOfA};
      activeIdentityPubkeyNotifier.value = b.publicKeyHex;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BookmarksScreen())),
      );

      expect(find.text('written as identity A'), findsOneWidget);
      expect(delete, findsNothing);
    });

    testWidgets('a Search result stops offering Delete once B is active', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SearchScreen())),
      );
      await tester.enterText(find.byType(TextField), noteFromHex(eventOfA.id));
      await tester.pumpAndSettle();
      expect(find.text('written as identity A'), findsOneWidget);
      expect(delete, findsOneWidget);

      await switchTo(tester, b.publicKeyHex);

      expect(find.text('written as identity A'), findsOneWidget);
      expect(delete, findsNothing);
    });

    testWidgets('a post stops offering Delete once B is active', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PostScreen(
            note: noteOfA,
            threadRepository: RelayThreadRepository(
              client: relay,
              reactionsRepository: const NoReactions(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(delete, findsOneWidget);

      await switchTo(tester, b.publicKeyHex);

      expect(find.text('written as identity A'), findsOneWidget);
      expect(delete, findsNothing);
    });
  });
}
