class NostrAuthor {
  const NostrAuthor({
    required this.pubkey,
    required this.displayName,
    required this.handle,
  });

  factory NostrAuthor.fromJson(Map<String, dynamic> json) {
    return NostrAuthor(
      pubkey: json['pubkey'] as String,
      displayName: json['displayName'] as String,
      handle: json['handle'] as String,
    );
  }

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
  });

  factory NostrPost.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? const {};
    return NostrPost(
      id: json['id'] as String,
      author: NostrAuthor.fromJson(json['author'] as Map<String, dynamic>),
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      replyCount: stats['replies'] as int? ?? 0,
      repostCount: stats['reposts'] as int? ?? 0,
      likeCount: stats['likes'] as int? ?? 0,
    );
  }

  final String id;
  final NostrAuthor author;
  final String content;
  final DateTime createdAt;
  final int replyCount;
  final int repostCount;
  final int likeCount;
}
