import '../nostr/nostr.dart';
import 'note.dart';

Note noteFromNostrPost(NostrPost post) {
  return Note(
    pubkey: post.author.pubkey,
    displayName: post.author.displayName,
    handle: post.author.handle,
    content: post.content,
    postedAt: _relativeTime(post.createdAt),
    replyCount: post.replyCount,
    repostCount: post.repostCount,
    likeCount: post.likeCount,
  );
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}
