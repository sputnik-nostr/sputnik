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
      fetchPostsByAuthors([pubkeyHex]);

  Future<List<NostrPost>> fetchPostsByAuthors(List<String> pubkeysHex) =>
      _fetchPosts(authors: pubkeysHex);

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
    final wanted = authors?.map((a) => a.toLowerCase()).toSet();
    final filters = [
      if (wanted == null)
        NostrFilter(kinds: const [1], limit: limit)
      else
        for (final chunk in chunkedAuthors(wanted.toList()))
          NostrFilter(kinds: const [1], authors: chunk, limit: limit),
    ];

    final eventsByFilter = await Future.wait(
      filters.map((filter) => client.query(relayUrls, filter)),
    );

    final eventsById = {
      for (final events in eventsByFilter)
        for (final event in events)
          if (event.kind == 1 &&
              (wanted == null || wanted.contains(event.pubkey)))
            event.id: event,
    };
    final matching = eventsById.values.toList()..sort(compareNewestFirst);

    return matching.take(limit).map(nostrPostFromEvent).toList();
  }
}
