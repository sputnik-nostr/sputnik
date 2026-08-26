import '../nostr/nostr.dart';
import 'note.dart';
import 'relative_time.dart';

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
