import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/models/note_mapper.dart';
import 'package:sputnik/nostr/nostr.dart';

void main() {
  final originalAuthorPubkey = 'aa' * 32;
  final reposterPubkey = 'bb' * 32;

  final original = NostrPost(
    id: 'cc' * 32,
    author: NostrAuthor(
      pubkey: originalAuthorPubkey,
      displayName: shortPubkey(originalAuthorPubkey),
      handle: shortPubkey(originalAuthorPubkey),
    ),
    content: 'the original note',
    createdAt: DateTime(2024, 1, 1),
  );

  test('a repost keeps the original author but names who reposted it', () {
    final repostPost = NostrPost.repost(
      original,
      byPubkey: reposterPubkey,
      at: DateTime(2024, 6, 1),
    );

    final notes = notesFromPosts(
      [repostPost],
      {
        originalAuthorPubkey: const NostrMetadata(name: 'Alice'),
        reposterPubkey: const NostrMetadata(name: 'Bob'),
      },
    );

    expect(notes, hasLength(1));
    final note = notes.single;
    expect(note.id, original.id);
    expect(note.pubkey, originalAuthorPubkey);
    expect(note.displayName, 'Alice');
    expect(note.content, 'the original note');
    expect(note.repostedByPubkey, reposterPubkey);
    expect(note.repostedByDisplayName, 'Bob');
    expect(note.repostedAt, DateTime(2024, 6, 1));
  });

  test(
    'a repost by someone with no known profile falls back to a short pubkey',
    () {
      final repostPost = NostrPost.repost(
        original,
        byPubkey: reposterPubkey,
        at: DateTime(2024, 6, 1),
      );

      final notes = notesFromPosts(
        [repostPost],
        {originalAuthorPubkey: const NostrMetadata(name: 'Alice')},
      );

      expect(notes.single.repostedByDisplayName, shortPubkey(reposterPubkey));
    },
  );

  test('a plain (non-repost) note has no repost fields set', () {
    final notes = notesFromPosts([original], {});

    final note = notes.single;
    expect(note.repostedByPubkey, isNull);
    expect(note.repostedByDisplayName, isNull);
    expect(note.repostedAt, isNull);
  });
}
