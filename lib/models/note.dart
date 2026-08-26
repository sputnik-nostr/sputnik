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
  });

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

  Note copyWith({int? replyCount, int? repostCount, int? likeCount}) {
    return Note(
      id: id,
      pubkey: pubkey,
      displayName: displayName,
      handle: handle,
      content: content,
      postedAt: postedAt,
      createdAt: createdAt,
      pictureUrl: pictureUrl,
      replyCount: replyCount ?? this.replyCount,
      repostCount: repostCount ?? this.repostCount,
      likeCount: likeCount ?? this.likeCount,
    );
  }
}
