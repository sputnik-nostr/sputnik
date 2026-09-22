import '../nostr/models/nostr_media.dart';
import 'time_format.dart';

/// Skips malformed entries, since bookmarks outlive the code that wrote them.
List<NostrMedia> _mediaFromJson(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map<String, dynamic> && item['url'] is String)
        NostrMedia.fromJson(item),
  ];
}

/// A text note as shown in the UI, with author profile data and counts.
class Note {
  const Note({
    required this.id,
    required this.pubkey,
    required this.displayName,
    required this.handle,
    required this.content,
    required this.postedAt,
    required this.createdAt,
    this.pictureUrl,
    this.replyCount = 0,
    this.repostCount = 0,
    this.likeCount = 0,
    this.isReply = false,
    this.likedByMe = false,
    this.repostedByMe = false,
    this.media = const [],
    this.repostedByPubkey,
    this.repostedByDisplayName,
    this.repostedAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      json['createdAt'] as int,
    );
    return Note(
      id: json['id'] as String,
      pubkey: json['pubkey'] as String,
      displayName: json['displayName'] as String,
      handle: json['handle'] as String,
      content: json['content'] as String,
      postedAt: relativeTime(createdAt),
      createdAt: createdAt,
      pictureUrl: json['pictureUrl'] as String?,
      replyCount: json['replyCount'] as int? ?? 0,
      repostCount: json['repostCount'] as int? ?? 0,
      likeCount: json['likeCount'] as int? ?? 0,
      isReply: json['isReply'] as bool? ?? false,
      likedByMe: json['likedByMe'] as bool? ?? false,
      repostedByMe: json['repostedByMe'] as bool? ?? false,
      media: _mediaFromJson(json['media']),
      repostedByPubkey: json['repostedByPubkey'] as String?,
      repostedByDisplayName: json['repostedByDisplayName'] as String?,
      repostedAt: (json['repostedAt'] as int?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(json['repostedAt'] as int),
    );
  }

  final String id;
  final String pubkey;
  final String displayName;
  final String handle;
  final String content;
  final String postedAt;
  final DateTime createdAt;
  final String? pictureUrl;
  final int replyCount;
  final int repostCount;
  final int likeCount;
  final bool isReply;

  /// Whether the active identity already liked/reposted this, per the
  /// relays' reaction data.
  final bool likedByMe;
  final bool repostedByMe;
  final List<NostrMedia> media;

  /// Who reposted this note, and when, if this entry is here as a repost
  /// rather than the note itself; [postedAt] still reflects the original.
  final String? repostedByPubkey;
  final String? repostedByDisplayName;
  final DateTime? repostedAt;

  Note copyWith({
    String? displayName,
    String? pictureUrl,
    int? replyCount,
    int? repostCount,
    int? likeCount,
    bool? likedByMe,
    bool? repostedByMe,
  }) {
    return Note(
      id: id,
      pubkey: pubkey,
      displayName: displayName ?? this.displayName,
      handle: handle,
      content: content,
      postedAt: postedAt,
      createdAt: createdAt,
      pictureUrl: pictureUrl ?? this.pictureUrl,
      replyCount: replyCount ?? this.replyCount,
      repostCount: repostCount ?? this.repostCount,
      likeCount: likeCount ?? this.likeCount,
      isReply: isReply,
      likedByMe: likedByMe ?? this.likedByMe,
      repostedByMe: repostedByMe ?? this.repostedByMe,
      media: media,
      repostedByPubkey: repostedByPubkey,
      repostedByDisplayName: repostedByDisplayName,
      repostedAt: repostedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pubkey': pubkey,
      'displayName': displayName,
      'handle': handle,
      'content': content,
      'createdAt': createdAt.millisecondsSinceEpoch,
      if (pictureUrl != null) 'pictureUrl': pictureUrl,
      'replyCount': replyCount,
      'repostCount': repostCount,
      'likeCount': likeCount,
      if (isReply) 'isReply': true,
      if (likedByMe) 'likedByMe': true,
      if (repostedByMe) 'repostedByMe': true,
      if (media.isNotEmpty) 'media': [for (final m in media) m.toJson()],
      if (repostedByPubkey != null) 'repostedByPubkey': repostedByPubkey,
      if (repostedByDisplayName != null)
        'repostedByDisplayName': repostedByDisplayName,
      if (repostedAt != null) 'repostedAt': repostedAt!.millisecondsSinceEpoch,
    };
  }
}
