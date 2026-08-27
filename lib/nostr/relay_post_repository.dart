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
    if (events.isEmpty) return null;
    return nostrPostFromEvent(events.first);
  }

  Future<List<NostrPost>> _fetchPosts({List<String>? authors}) async {
    final events = await client.query(
      relayUrls,
      NostrFilter(kinds: const [1], authors: authors, limit: limit),
    );

    events.sort(compareNewestFirst);

    return events.take(limit).map(nostrPostFromEvent).toList();
  }
}
