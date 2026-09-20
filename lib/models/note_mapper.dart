import '../nostr/nostr.dart';
import 'note.dart';
import 'time_format.dart';

/// Sets like and repost counts from [reactionsByPostId], where present.
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

/// Prefers the profile name in [authorMetadata] over the post's placeholder.
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
    isReply: post.isReply,
  );
}

/// Maps [posts], looking up each author in [profilesByPubkey].
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

/// Fetches author profiles and reaction counts for [posts] concurrently, then
/// maps them to notes. [knownMetadata] skips the profile fetch.
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
