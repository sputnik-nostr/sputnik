import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/models/note_mapper.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/bookmarks_screen.dart';
import 'package:sputnik/screens/home_screen.dart';
import 'package:sputnik/services/bookmark_store.dart';
import 'package:sputnik/services/feed_loader.dart';
import 'package:sputnik/services/settings_store.dart';
import 'package:sputnik/widgets/bookmark_button.dart';
import 'package:sputnik/widgets/note_tile.dart';
import 'package:sputnik/widgets/reaction_buttons.dart';

import 'support/fake_secret_store.dart';
import 'support/in_memory_relay_client.dart';

/// Can hold a publish back, to change the screen while a like is in flight, or
/// the reactions of a feed, to switch identity while it is being loaded.
class _Relay extends InMemoryRelayClient {
  _Relay(super.events);

  Completer<void>? holdPublish;
  Completer<void>? holdReactions;

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    if (filter.kinds?.contains(7) ?? false) await holdReactions?.future;
    return super.query(relayUrls, filter);
  }

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

  group('when the identity changes', () {
    Future<void> switchTo(WidgetTester tester, NostrKeyPair keys) async {
      activeIdentityPubkeyNotifier.value = keys.publicKeyHex;
      await tester.pumpAndSettle();
    }

    testWidgets('a like made as A is not B\'s', (tester) async {
      await pumpFollowing(tester, [noteOf(x), noteOf(y)]);
      await like(tester, 'note X');
      expect(liked('note X'), findsOneWidget);

      await switchTo(tester, b);

      expect(liked('note X'), findsNothing);
      expect(notLiked('note X'), findsOneWidget);
    });

    testWidgets('B can like what A liked, as B', (tester) async {
      await pumpFollowing(tester, [noteOf(x)]);
      await like(tester, 'note X');
      await switchTo(tester, b);

      await like(tester, 'note X');

      expect(liked('note X'), findsOneWidget);
      expect(
        [for (final e in relay.published) e.pubkey],
        [a.publicKeyHex, b.publicKeyHex],
      );
    });

    testWidgets('a repost made as A is not B\'s', (tester) async {
      await pumpFollowing(tester, [noteOf(x)]);
      await tester.tap(find.byIcon(Icons.repeat));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(relay.published.single.kind, 6);
      expect(find.byTooltip('Reposted (hold to quote)'), findsOneWidget);

      await switchTo(tester, b);

      expect(find.byTooltip('Reposted (hold to quote)'), findsNothing);
      expect(find.byTooltip('Repost (hold to quote)'), findsOneWidget);
    });

    testWidgets('a button that nothing around it rebuilds follows the identity '
        'too', (tester) async {
      final byA = noteOf(x).copyWith(
        likedByMe: true,
        repostedByMe: true,
        reactionsOf: a.publicKeyHex,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                LikeButton(note: byA),
                RepostButton(note: byA),
              ],
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byTooltip('Reposted (hold to quote)'), findsOneWidget);

      await switchTo(tester, b);

      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byTooltip('Reposted (hold to quote)'), findsNothing);
    });

    testWidgets('a like still being published when it changes is not B\'s', (
      tester,
    ) async {
      await pumpFollowing(tester, [noteOf(x)]);
      relay.holdPublish = Completer<void>();
      await tester.tap(notLiked('note X'));
      await tester.pumpAndSettle();

      await switchTo(tester, b);
      relay.holdPublish!.complete();
      await tester.pumpAndSettle();

      expect(relay.published.single.pubkey, a.publicKeyHex);
      expect(liked('note X'), findsNothing);
      expect(notLiked('note X'), findsOneWidget);
    });

    testWidgets('likes found for A on the global feed are not B\'s', (
      tester,
    ) async {
      followingNotesNotifier.value = const [];
      notesNotifier.value = applyReactionCounts(
        [noteOf(x), noteOf(y)],
        {
          x.id: PostReactions(likerPubkeys: [a.publicKeyHex, author]),
          y.id: PostReactions(reposterPubkeys: [a.publicKeyHex]),
        },
        myPubkeyHex: a.publicKeyHex,
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HomeScreen())),
      );
      await tester.tap(find.text('Global'));
      await tester.pumpAndSettle();
      expect(liked('note X'), findsOneWidget, reason: 'A liked X');
      expect(find.byTooltip('Reposted (hold to quote)'), findsOneWidget);

      await switchTo(tester, b);

      expect(liked('note X'), findsNothing);
      expect(notLiked('note X'), findsOneWidget);
      expect(find.byTooltip('Reposted (hold to quote)'), findsNothing);
      expect(find.text('2'), findsOneWidget, reason: 'A and Bob still count');
    });

    NostrEvent likeBy(String id, NostrKeyPair keys, NostrEvent liked) =>
        fakeEvent(
          id: id,
          pubkey: keys.publicKeyHex,
          kind: 7,
          tags: [
            ['e', liked.id],
          ],
          content: '+',
        );

    testWidgets('a refresh as B shows what B liked, not what A did', (
      tester,
    ) async {
      relay.events.addAll([likeBy('f1', a, x), likeBy('f2', b, y)]);
      followingNotesNotifier.value = const [];
      await tester.runAsync(loadGlobalFeed);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HomeScreen())),
      );
      await tester.tap(find.text('Global'));
      await tester.pumpAndSettle();
      expect(liked('note X'), findsOneWidget, reason: 'A liked X');
      expect(liked('note Y'), findsNothing);

      await switchTo(tester, b);
      expect(liked('note X'), findsNothing);

      await tester.runAsync(loadGlobalFeed);
      await tester.pumpAndSettle();

      expect(liked('note Y'), findsOneWidget, reason: 'B liked Y');
      expect(liked('note X'), findsNothing);
    });

    test(
      'reactions that arrive after the switch are worked out for B',
      () async {
        relay.events.addAll([likeBy('f1', a, x), likeBy('f2', b, y)]);
        final hold = relay.holdReactions = Completer<void>();
        addTearDown(() {
          if (!hold.isCompleted) hold.complete();
        });
        final loading = loadGlobalFeed();
        await pumpEventQueue();
        expect(notesNotifier.value, isNotEmpty, reason: 'the page is showing');

        activeIdentityPubkeyNotifier.value = b.publicKeyHex;
        hold.complete();
        await loading;

        final shown = {for (final note in notesNotifier.value!) note.id: note};
        expect(
          shown[y.id]!.likedBy(b.publicKeyHex),
          isTrue,
          reason: 'B liked Y',
        );
        expect(shown[x.id]!.likedBy(b.publicKeyHex), isFalse);
        expect(
          shown[x.id]!.likedBy(a.publicKeyHex),
          isFalse,
          reason: 'not A\'s',
        );
      },
    );
  });

  group('bookmarks', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('reaction_scope_test');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      await BookmarkStore.close();
      await Hive.close();
      await dir.delete(recursive: true);
    });

    Future<Map<String, Note>> restart() async {
      await BookmarkStore.close();
      return BookmarkStore.load(directory: dir);
    }

    Future<void> showBookmarks(
      WidgetTester tester,
      Map<String, Note> notes,
    ) async {
      bookmarkedNotesNotifier.value = notes;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BookmarksScreen())),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a note bookmarked as A stays liked for A, not for B', (
      tester,
    ) async {
      final hydrated = applyReactionCounts(
        [noteOf(x)],
        {
          x.id: PostReactions(likerPubkeys: [a.publicKeyHex]),
        },
        myPubkeyHex: a.publicKeyHex,
      );
      await tester.runAsync(() async {
        await BookmarkStore.load(directory: dir);
        await BookmarkStore.save({x.id: hydrated.single});
      });
      final restored = await tester.runAsync(restart);

      await showBookmarks(tester, restored!);
      expect(liked('note X'), findsOneWidget);

      activeIdentityPubkeyNotifier.value = b.publicKeyHex;
      await tester.pumpAndSettle();

      expect(liked('note X'), findsNothing);
      expect(notLiked('note X'), findsOneWidget);
    });

    testWidgets('a bookmark saved before notes said whose likes they hold is '
        'not trusted', (tester) async {
      final legacy = {
        ...noteOf(x).toJson(),
        'likedByMe': true,
        'repostedByMe': true,
      };
      await tester.runAsync(() async {
        await BookmarkStore.load(directory: dir);
        await Hive.box<String>('bookmarks').put(x.id, jsonEncode(legacy));
      });
      final restored = await tester.runAsync(restart);
      expect(restored!.keys, [x.id]);

      await showBookmarks(tester, restored);

      expect(liked('note X'), findsNothing);
      expect(notLiked('note X'), findsOneWidget);
    });
  });
}
