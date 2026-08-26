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

    return events.take(limit).map(_toPost).toList();
  }

  NostrPost _toPost(NostrEvent event) {
    final shortPubkey = event.pubkey.substring(0, 8);
    return NostrPost(
      id: event.id,
      author: NostrAuthor(
        pubkey: event.pubkey,
        displayName: shortPubkey,
        handle: shortPubkey,
      ),
      content: event.content,
      createdAt: event.createdAt,
    );
  }
}
