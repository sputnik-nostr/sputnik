import '../nostr/nostr.dart';
import 'note.dart';
import 'relative_time.dart';

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
