import '../nip10.dart';
import '../nip92.dart';
import 'nostr_event.dart';
import 'nostr_media.dart';

NostrPost nostrPostFromEvent(NostrEvent event) {
  return NostrPost(
    id: event.id,
    authorPubkey: event.pubkey,
    content: event.content,
    createdAt: event.createdAt,
    isReply: replyParentId(event) != null,
    media: noteMedia(event.content, event.tags),
  );
}

class NostrPost {
  const NostrPost({
    required this.id,
    required this.authorPubkey,
    required this.content,
    required this.createdAt,
    this.isReply = false,
    this.media = const [],
    this.repostedByPubkey,
    this.repostedAt,
  });

  /// A NIP-18 pointer, so every other field still describes [original].
  factory NostrPost.repost(
    NostrPost original, {
    required String byPubkey,
    required DateTime at,
  }) {
    return NostrPost(
      id: original.id,
      authorPubkey: original.authorPubkey,
      content: original.content,
      createdAt: original.createdAt,
      isReply: original.isReply,
      media: original.media,
      repostedByPubkey: byPubkey,
      repostedAt: at,
    );
  }

  final String id;
  final String authorPubkey;
  final String content;
  final DateTime createdAt;
  final bool isReply;
  final List<NostrMedia> media;

  /// Who reposted this, and when, if this entry is a repost (kind 6).
  final String? repostedByPubkey;
  final DateTime? repostedAt;
}
