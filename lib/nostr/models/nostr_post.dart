import '../nip10.dart';
import '../nip19.dart';
import 'nostr_event.dart';

/// Builds a [NostrPost] whose author is the short pubkey until a profile loads.
NostrPost nostrPostFromEvent(NostrEvent event) {
  final handle = shortPubkey(event.pubkey);
  return NostrPost(
    id: event.id,
    author: NostrAuthor(
      pubkey: event.pubkey,
      displayName: handle,
      handle: handle,
    ),
    content: event.content,
    createdAt: event.createdAt,
    isReply: replyParentId(event) != null,
  );
}

class NostrAuthor {
  const NostrAuthor({
    required this.pubkey,
    required this.displayName,
    required this.handle,
  });

  final String pubkey;
  final String displayName;
  final String handle;
}

class NostrPost {
  const NostrPost({
    required this.id,
    required this.author,
    required this.content,
    required this.createdAt,
    this.replyCount = 0,
    this.repostCount = 0,
    this.likeCount = 0,
    this.isReply = false,
  });

  final String id;
  final NostrAuthor author;
  final String content;
  final DateTime createdAt;
  final int replyCount;
  final int repostCount;
  final int likeCount;
  final bool isReply;
}
