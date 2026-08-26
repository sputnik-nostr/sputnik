class Note {
  const Note({
    required this.id,
    required this.pubkey,
    required this.displayName,
    required this.handle,
    required this.content,
    required this.postedAt,
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
  final String? pictureUrl;
  final int replyCount;
  final int repostCount;
  final int likeCount;
}
