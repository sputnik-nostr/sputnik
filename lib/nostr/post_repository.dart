import 'models/nostr_post.dart';

abstract class PostRepository {
  Future<List<NostrPost>> fetchPosts();
}
