import '../main.dart';
import '../nostr/nostr.dart';
import 'note.dart';
import 'time_format.dart';

/// Sets like/repost counts, and whether [myPubkeyHex] is among them, from
/// [reactionsByPostId], where present.
List<Note> applyReactionCounts(
  List<Note> notes,
  Map<String, PostReactions> reactionsByPostId, {
  String? myPubkeyHex,
}) {
  final me = myPubkeyHex?.toLowerCase();
  return notes.map((note) {
    final reactions = reactionsByPostId[note.id];
    if (reactions == null) return note;
    return note.copyWith(
      likeCount: reactions.likeCount,
      repostCount: reactions.repostCount,
      likedByMe: me != null && reactions.likerPubkeys.contains(me),
      repostedByMe: me != null && reactions.reposterPubkeys.contains(me),
    );
  }).toList();
}

/// Prefers the profile name in [authorMetadata] over the post's placeholder,
/// and [repostedByMetadata] for whoever reposted it, if [post] is a repost.
Note noteFromNostrPost(
  NostrPost post, {
  NostrMetadata? authorMetadata,
  NostrMetadata? repostedByMetadata,
}) {
  final repostedByPubkey = post.repostedByPubkey;
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
    media: post.media,
    repostedByPubkey: repostedByPubkey,
    repostedByDisplayName: repostedByPubkey == null
        ? null
        : (repostedByMetadata?.resolvedName ?? shortPubkey(repostedByPubkey)),
    repostedAt: post.repostedAt,
  );
}

/// Maps [posts], looking up each author and reposter in [profilesByPubkey].
List<Note> notesFromPosts(
  List<NostrPost> posts,
  Map<String, NostrMetadata> profilesByPubkey,
) {
  return posts
      .map(
        (post) => noteFromNostrPost(
          post,
          authorMetadata: profilesByPubkey[post.author.pubkey],
          repostedByMetadata: post.repostedByPubkey == null
              ? null
              : profilesByPubkey[post.repostedByPubkey],
        ),
      )
      .toList();
}

/// Fetches profiles and reaction counts for [posts], then maps them to
/// notes. [knownMetadata] skips the fetch for pubkeys it already covers.
Future<List<Note>> hydratePosts(
  List<NostrPost> posts,
  Set<String> relayUrls, {
  Map<String, NostrMetadata>? knownMetadata,
}) async {
  final known = knownMetadata ?? const <String, NostrMetadata>{};
  final needed = {
    for (final post in posts) post.author.pubkey,
    for (final post in posts)
      if (post.repostedByPubkey != null) post.repostedByPubkey!,
  }..removeAll(known.keys);

  final profilesFuture = needed.isEmpty
      ? Future.value(known)
      : const RelayProfileRepository()
            .fetchProfiles(needed, relayUrls)
            .then((fetched) => {...known, ...fetched});
  final reactionsFuture = const RelayReactionsRepository().fetchReactions(
    posts.map((post) => post.id).toList(),
    relayUrls,
  );

  final notes = notesFromPosts(posts, await profilesFuture);
  return applyReactionCounts(
    notes,
    await reactionsFuture,
    myPubkeyHex: activeIdentityPubkeyNotifier.value,
  );
}
