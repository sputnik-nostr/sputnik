import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/models/note_mapper.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/post_screen.dart';

import 'support/in_memory_relay_client.dart';

void main() {
  final a = 'a1' * 32;
  final b = 'b2' * 32;
  final author = 'cc' * 32;

  Note note({bool liked = false, bool reposted = false, String? of}) => Note(
    id: 'dd' * 32,
    pubkey: author,
    displayName: 'Carol',
    content: 'hello',
    createdAt: DateTime(2024),
    likedByMe: liked,
    repostedByMe: reposted,
    reactionsOf: of,
  );

  group('likedBy and repostedBy', () {
    test('only hold for the identity the flags were worked out for', () {
      final mine = note(liked: true, reposted: true, of: a);

      expect(mine.likedBy(a), isTrue);
      expect(mine.repostedBy(a), isTrue);
      expect(mine.likedBy(b), isFalse);
      expect(mine.repostedBy(b), isFalse);
    });

    test('keep the two apart', () {
      expect(note(liked: true, of: a).repostedBy(a), isFalse);
      expect(note(reposted: true, of: a).likedBy(a), isFalse);
    });

    test('compare pubkeys without regard to case', () {
      final mine = note(liked: true, reposted: true, of: a.toUpperCase());

      expect(mine.likedBy(a), isTrue);
      expect(mine.repostedBy(a.toUpperCase()), isTrue);
    });

    test('do not hold with no identity', () {
      final mine = note(liked: true, reposted: true, of: a);

      expect(mine.likedBy(null), isFalse);
      expect(mine.repostedBy(null), isFalse);
    });

    test('do not hold for flags that were never worked out for anyone', () {
      final unclaimed = note(liked: true, reposted: true);

      expect(unclaimed.likedBy(a), isFalse);
      expect(unclaimed.repostedBy(a), isFalse);
      expect(unclaimed.likedBy(null), isFalse);
    });
  });

  group('JSON', () {
    test('keeps whose reactions the flags are', () {
      final restored = Note.fromJson(
        note(liked: true, reposted: true, of: a).toJson(),
      );

      expect(restored.reactionsOf, a);
      expect(restored.likedBy(a), isTrue);
      expect(restored.likedBy(b), isFalse);
    });

    test('leaves it out when it is not set', () {
      expect(note().toJson().containsKey('reactionsOf'), isFalse);
    });

    test('a note saved without it describes nobody', () {
      final json = note().toJson()
        ..['likedByMe'] = true
        ..['repostedByMe'] = true;
      expect(json.containsKey('reactionsOf'), isFalse);

      final restored = Note.fromJson(json);

      expect(restored.likedByMe, isTrue);
      expect(restored.likedBy(a), isFalse);
      expect(restored.repostedBy(a), isFalse);
    });
  });

  group('copyWith', () {
    test('keeps whose reactions the flags are, unless told otherwise', () {
      final mine = note(liked: true, of: a);

      expect(mine.copyWith(likeCount: 3).reactionsOf, a);
      expect(mine.copyWith(reactionsOf: b).reactionsOf, b);
    });
  });

  group('applyReactionCounts', () {
    final reactions = {
      note().id: PostReactions(
        likerPubkeys: [a, author],
        reposterPubkeys: [author],
      ),
    };

    test('works the flags out for one identity and says which', () {
      final forA = applyReactionCounts([note()], reactions, myPubkeyHex: a);
      final forB = applyReactionCounts([note()], reactions, myPubkeyHex: b);

      expect(forA.single.likedBy(a), isTrue);
      expect(forA.single.repostedBy(a), isFalse);
      expect(forA.single.likedBy(b), isFalse);
      expect(forB.single.reactionsOf, b);
      expect(forB.single.likedBy(b), isFalse);
      expect(forB.single.likedBy(a), isFalse);
      expect(forA.single.likeCount, 2);
      expect(forB.single.likeCount, 2);
    });

    test('takes the identity in either case', () {
      final notes = applyReactionCounts(
        [note()],
        reactions,
        myPubkeyHex: a.toUpperCase(),
      );

      expect(notes.single.reactionsOf, a);
      expect(notes.single.likedBy(a), isTrue);
    });

    test('with no identity flags nothing', () {
      final notes = applyReactionCounts([note()], reactions);

      expect(notes.single.likedByMe, isFalse);
      expect(notes.single.repostedByMe, isFalse);
      expect(notes.single.likeCount, 2);
    });

    test('leaves a note with no reaction data as it was', () {
      final before = note(liked: true, of: a);

      final after = applyReactionCounts([before], const {}, myPubkeyHex: b);

      expect(after.single.likedBy(a), isTrue);
      expect(after.single.reactionsOf, a);
    });
  });

  group('the post screen', () {
    // The thread knows exactly who reacted, so it decides over what the note
    // came with.
    testWidgets('shows the reactions of the identity that is active', (
      tester,
    ) async {
      final focus = fakeEvent(id: 'ee', pubkey: author, content: 'focused');
      final likeByA = fakeEvent(
        id: 'f1',
        pubkey: a,
        kind: 7,
        tags: [
          ['e', focus.id],
        ],
        content: '+',
      );
      final relay = InMemoryRelayClient([focus, likeByA]);
      selectedRelaysNotifier.value = {'wss://relay.example'};

      Future<void> open(String? identity) async {
        activeIdentityPubkeyNotifier.value = identity;
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: PostScreen(
              note: Note(
                id: focus.id,
                pubkey: focus.pubkey,
                displayName: 'Carol',
                content: focus.content,
                createdAt: focus.createdAt,
              ),
              threadRepository: RelayThreadRepository(
                client: relay,
                reactionsRepository: RelayReactionsRepository(client: relay),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await open(a);
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await open(b);
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      await open(null);
      expect(find.byIcon(Icons.favorite), findsNothing);
    });
  });
}
