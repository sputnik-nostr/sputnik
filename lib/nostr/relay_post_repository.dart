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
  Future<List<NostrPost>> fetchPosts() async {
    final events = await client.query(
      relayUrls,
      NostrFilter(kinds: const [1], limit: limit),
    );

    events.sort(compareNewestFirst);

    return events.take(limit).map(nostrPostFromEvent).toList();
  }
}
