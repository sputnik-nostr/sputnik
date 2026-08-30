import '../nostr/nostr.dart';
import 'note.dart';
import 'time_format.dart';

// Applies reaction counts to a [List] of notes.
List<Note> applyReactionCounts(
  List<Note> notes,
  Map<String, PostReactions> reactionsByPostId,
) {
  return notes.map((note) {
    final reactions = reactionsByPostId[note.id];
    if (reactions == null) return note;
    return note.copyWith(
      likeCount: reactions.likeCount,
      repostCount: reactions.repostCount,
    );
  }).toList();
}

// Turns a [NostrPost] into a [Note].
Note noteFromNostrPost(NostrPost post, {NostrMetadata? authorMetadata}) {
  return Note(
    id: post.id,
    pubkey: post.author.pubkey,
    displayName: authorMetadata?.resolvedName ?? post.author.displayName,
    handle: post.author.handle,
    pictureUrl: authorMetadata?.picture,
    content: post.content,
    postedAt: relativeTime(post.createdAt),
    createdAt: post.createdAt,
    replyCount: post.replyCount,
    repostCount: post.repostCount,
    likeCount: post.likeCount,
  );
}

// Turns a [List] of [NostrPost]s into a [List] of [Note]s.
List<Note> notesFromPosts(
  List<NostrPost> posts,
  Map<String, NostrMetadata> profilesByPubkey,
) {
  return posts
      .map(
        (post) => noteFromNostrPost(
          post,
          authorMetadata: profilesByPubkey[post.author.pubkey],
        ),
      )
      .toList();
}

// Fetches author profiles, either from the cache or by network request, as well
// as reaction counts for [posts] concurrently. These are then mapped into notes
// with reaction counts applied.
Future<List<Note>> hydratePosts(
  List<NostrPost> posts,
  Set<String> relayUrls, {
  Map<String, NostrMetadata>? knownMetadata,
}) async {
  final profilesFuture = knownMetadata != null
      ? Future.value(knownMetadata)
      : const RelayProfileRepository().fetchProfiles(
          posts.map((post) => post.author.pubkey).toSet(),
          relayUrls,
        );
  final reactionsFuture = const RelayReactionsRepository().fetchReactions(
    posts.map((post) => post.id).toList(),
    relayUrls,
  );

  final notes = notesFromPosts(posts, await profilesFuture);
  return applyReactionCounts(notes, await reactionsFuture);
}
