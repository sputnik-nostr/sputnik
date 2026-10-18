import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/models/note_mapper.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/bookmarks_screen.dart';
import 'package:sputnik/screens/home_screen.dart';
import 'package:sputnik/services/settings_store.dart';
import 'package:sputnik/widgets/bookmark_button.dart';
import 'package:sputnik/widgets/note_tile.dart';

import 'support/fake_secret_store.dart';
import 'support/in_memory_relay_client.dart';

/// Can hold a publish back, to change the screen while a like is in flight.
class _Relay extends InMemoryRelayClient {
  _Relay(super.events);

  Completer<void>? holdPublish;

  @override
  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) async {
    await holdPublish?.future;
    return super.publish(event, relayUrls);
  }
}

// A like or repost indicator belongs to one note and one identity. Neither the
// position of a row in a list nor the identity that was active when relays were
// asked may decide what a row shows.
void main() {
  late NostrKeyPair a;
  late NostrKeyPair b;
  late _Relay relay;

  final author = 'bb' * 32;
  final base = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  NostrEvent eventNamed(String id, String content, {required int minutesAgo}) =>
      fakeEvent(
        id: id,
        pubkey: author,
        content: content,
        createdAt: base.subtract(Duration(minutes: minutesAgo)),
      );

  final x = eventNamed('1a', 'note X', minutesAgo: 1);
  final y = eventNamed('2b', 'note Y', minutesAgo: 2);
  final z = eventNamed('3c', 'note Z', minutesAgo: 3);
  final n = eventNamed('4d', 'note N, never liked', minutesAgo: 0);

  Note noteOf(NostrEvent event) => Note(
    id: event.id,
    pubkey: event.pubkey,
    displayName: 'Bob',
    content: event.content,
    createdAt: event.createdAt,
  );

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
    myFollowingNotifier.value = {author};
    confirmBeforeReactingNotifier.value = false;
    notesNotifier.value = null;
    followingNotesNotifier.value = null;
    bookmarkedNotesNotifier.value = const {};
    relay = _Relay([x, y, z, n]);
    RelayClient.instance = relay;
  });

  tearDown(() {
    confirmBeforeReactingNotifier.value = true;
    followingNotesNotifier.value = null;
    notesNotifier.value = null;
    bookmarkedNotesNotifier.value = const {};
  });

  Finder inRow(String text, IconData icon) => find.descendant(
    of: find.widgetWithText(NoteTile, text),
    matching: find.byIcon(icon),
  );

  Finder liked(String text) => inRow(text, Icons.favorite);
  Finder notLiked(String text) => inRow(text, Icons.favorite_border);

  Future<void> pumpFollowing(WidgetTester tester, List<Note> notes) async {
    followingNotesNotifier.value = notes;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeScreen())),
    );
    await tester.pumpAndSettle();
  }

  Future<void> like(WidgetTester tester, String text) async {
    await tester.tap(notLiked(text));
    await tester.pumpAndSettle();
  }

  group('indexOfNoteRow', () {
    final notes = [noteOf(x), noteOf(y)];

    test('finds a note by the key of its row', () {
      expect(indexOfNoteRow(notes, ValueKey(x.id)), 0);
      expect(indexOfNoteRow(notes, ValueKey(y.id)), 1);
    });

    test('knows nothing of a note that is not in the list', () {
      expect(indexOfNoteRow(notes, ValueKey(z.id)), isNull);
    });

    test('leaves other rows alone, such as the footer that loads more', () {
      expect(indexOfNoteRow(notes, ValueKey(notes.length)), isNull);
      expect(indexOfNoteRow(notes, GlobalKey()), isNull);
    });
  });

  group('when a list shifts', () {
    // What the relays report on a refresh once A has liked [event].
    Note likedByA(NostrEvent event) => applyReactionCounts(
      [noteOf(event)],
      {
        event.id: PostReactions(likerPubkeys: [a.publicKeyHex]),
      },
      myPubkeyHex: a.publicKeyHex,
    ).single;

    testWidgets('a note added on top does not inherit the like of the one it '
        'pushed down', (tester) async {
      await pumpFollowing(tester, [noteOf(x), noteOf(y)]);
      await like(tester, 'note X');
      expect(liked('note X'), findsOneWidget);

      followingNotesNotifier.value = [noteOf(n), likedByA(x), noteOf(y)];
      await tester.pumpAndSettle();

      expect(liked('note N, never liked'), findsNothing);
      expect(notLiked('note N, never liked'), findsOneWidget);
      expect(liked('note X'), findsOneWidget, reason: 'the relays say so');
      expect(liked('note Y'), findsNothing);
    });

    testWidgets('a note does not get the like of one removed above it', (
      tester,
    ) async {
      await pumpFollowing(tester, [noteOf(x), noteOf(y), noteOf(z)]);
      await like(tester, 'note X');

      followingNotesNotifier.value = [noteOf(y), noteOf(z)];
      await tester.pumpAndSettle();

      expect(liked('note Y'), findsNothing);
      expect(liked('note Z'), findsNothing);
    });

    testWidgets('a liked note keeps its like when a note above it is deleted', (
      tester,
    ) async {
      final mine = fakeEvent(
        id: '5e',
        pubkey: a.publicKeyHex,
        content: 'note M, written by me',
        createdAt: base.add(const Duration(minutes: 1)),
      );
      relay.events.add(mine);
      await pumpFollowing(tester, [noteOf(mine), noteOf(x), noteOf(y)]);
      await like(tester, 'note X');

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(NoteTile, 'note M, written by me'),
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('note M, written by me'), findsNothing);
      expect(liked('note X'), findsOneWidget, reason: 'nothing refreshed it');
      expect(liked('note Y'), findsNothing);
    });

    testWidgets('a liked note keeps its like while the refresh that pushed it '
        'down is hydrated', (tester) async {
      await pumpFollowing(tester, [noteOf(x), noteOf(y)]);
      await like(tester, 'note X');

      // The new page as it first appears, before its reactions are fetched.
      followingNotesNotifier.value = [noteOf(n), noteOf(x), noteOf(y)];
      await tester.pumpAndSettle();

      expect(liked('note X'), findsOneWidget);
      expect(liked('note N, never liked'), findsNothing);
      expect(liked('note Y'), findsNothing);
    });

    testWidgets('a like still being published does not land on the note that '
        'took its place', (tester) async {
      await pumpFollowing(tester, [noteOf(x), noteOf(y)]);
      relay.holdPublish = Completer<void>();
      await tester.tap(notLiked('note X'));
      await tester.pumpAndSettle();

      followingNotesNotifier.value = [noteOf(n), noteOf(x), noteOf(y)];
      await tester.pumpAndSettle();
      relay.holdPublish!.complete();
      await tester.pumpAndSettle();

      expect(relay.published.single.kind, 7);
      expect(liked('note N, never liked'), findsNothing);
      expect(liked('note Y'), findsNothing);
    });

    testWidgets('a tile with no key that is handed another note starts clean', (
      tester,
    ) async {
      Widget tile(NostrEvent event) => MaterialApp(
        home: Scaffold(body: NoteTile(note: noteOf(event))),
      );
      await tester.pumpWidget(tile(x));
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await tester.pumpWidget(tile(n));
      await tester.pumpAndSettle();

      expect(find.text('note N, never liked'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });

    testWidgets(
      'removing a bookmark keeps the others\' likes with their notes',
      (tester) async {
        bookmarkedNotesNotifier.value = {
          for (final event in [x, y, z]) event.id: noteOf(event),
        };
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: BookmarksScreen())),
        );
        await like(tester, 'note Y');
        expect(liked('note Y'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.widgetWithText(NoteTile, 'note X'),
            matching: find.byType(BookmarkButton),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('note X'), findsNothing);
        expect(liked('note Y'), findsOneWidget);
        expect(liked('note Z'), findsNothing);
      },
    );
  });
}
