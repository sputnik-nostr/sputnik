import '../nostr/nostr.dart';
import 'note.dart';

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
    pubkey: post.authorPubkey,
    displayName: authorMetadata?.resolvedName ?? shortPubkey(post.authorPubkey),
    pictureUrl: authorMetadata?.picture,
    content: post.content,
    createdAt: post.createdAt,
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
          authorMetadata: profilesByPubkey[post.authorPubkey],
          repostedByMetadata: post.repostedByPubkey == null
              ? null
              : profilesByPubkey[post.repostedByPubkey],
        ),
      )
      .toList();
}
