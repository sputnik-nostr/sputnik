import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/nostr_post.dart';
import 'post_repository.dart';
import 'relay_client.dart';

class RelayPostRepository implements PostRepository {
  const RelayPostRepository({
    required this.relayUrls,
    this.limit = 30,
    this.client = const RelayClient(),
  });

  final Set<String> relayUrls;
  final int limit;
  final RelayClient client;

  @override
  Future<List<NostrPost>> fetchPosts() => _fetchPosts();

  Future<List<NostrPost>> fetchPostsByAuthor(String pubkeyHex) =>
      _fetchPosts(authors: [pubkeyHex]);

  Future<NostrPost?> fetchPostById(String id) async {
    final events = await client.query(
      relayUrls,
      NostrFilter(ids: [id], kinds: const [1], limit: 1),
    );
    final wantedId = id.toLowerCase();
    for (final event in events) {
      if (event.kind == 1 && event.id == wantedId) {
        return nostrPostFromEvent(event);
      }
    }
    return null;
  }

  Future<List<NostrPost>> _fetchPosts({List<String>? authors}) async {
    final events = await client.query(
      relayUrls,
      NostrFilter(kinds: const [1], authors: authors, limit: limit),
    );

    final wanted = authors?.map((a) => a.toLowerCase()).toSet();
    final matching = [
      for (final event in events)
        if (event.kind == 1 &&
            (wanted == null || wanted.contains(event.pubkey)))
          event,
    ]..sort(compareNewestFirst);

    return matching.take(limit).map(nostrPostFromEvent).toList();
  }
}
