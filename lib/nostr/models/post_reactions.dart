/// The pubkeys that liked (kind 7) or reposted (kind 6) a single post.
class PostReactions {
  const PostReactions({
    this.likerPubkeys = const [],
    this.reposterPubkeys = const [],
  });

  final List<String> likerPubkeys;
  final List<String> reposterPubkeys;

  int get likeCount => likerPubkeys.length;
  int get repostCount => reposterPubkeys.length;
}
