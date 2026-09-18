import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/nostr_post.dart';
import 'nip10.dart';
import 'post_repository.dart';
import 'relay_client.dart';

// Replies are dropped after the query, so ask for more to still fill a page.
const _replyOverfetch = 3;

// Bounds the queries one page can cost when most results are dropped.
const _maxPageRounds = 4;

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
  Future<List<NostrPost>> fetchPosts({bool includeReplies = true}) =>
      _fetchPosts(includeReplies: includeReplies);

  Future<List<NostrPost>> fetchPostsByAuthor(String pubkeyHex) =>
      fetchPostsByAuthors([pubkeyHex]);

  Future<List<NostrPost>> fetchPostsByAuthors(
    List<String> pubkeysHex, {
    bool includeReplies = true,
  }) => _fetchPosts(authors: pubkeysHex, includeReplies: includeReplies);

  Future<NostrPost?> fetchPostById(String id) async {
    final event = await fetchEventById(id);
    return event == null ? null : nostrPostFromEvent(event);
  }

  Future<NostrEvent?> fetchEventById(String id) async {
    final events = await client.query(
      relayUrls,
      NostrFilter(ids: [id], kinds: const [1], limit: 1),
    );
    final wantedId = id.toLowerCase();
    for (final event in events) {
      if (event.kind == 1 && event.id == wantedId) return event;
    }
    return null;
  }

  Future<List<NostrPost>> _fetchPosts({
    List<String>? authors,
    bool includeReplies = true,
  }) async {
    final page = await fetchPage(
      authors: authors,
      includeReplies: includeReplies,
    );
    return page.posts;
  }

  // Pass the previous page's [PostPage.next] as [until] to get the next page.
  Future<PostPage> fetchPage({
    List<String>? authors,
    bool includeReplies = true,
    DateTime? until,
  }) async {
    final wanted = authors?.map((a) => a.toLowerCase()).toSet();
    final queryLimit = includeReplies ? limit : limit * _replyOverfetch;
    final found = <String, NostrEvent>{};
    var cursor = until;
    var exhausted = false;

    for (
      var round = 0;
      round < _maxPageRounds && found.length < limit;
      round++
    ) {
      final filters = [
        if (wanted == null)
          NostrFilter(kinds: const [1], until: cursor, limit: queryLimit)
        else
          for (final chunk in chunkedAuthors(wanted.toList()))
            NostrFilter(
              kinds: const [1],
              authors: chunk,
              until: cursor,
              limit: queryLimit,
            ),
      ];
      final eventsByFilter = await Future.wait(
        filters.map((filter) => client.query(relayUrls, filter)),
      );

      final valid = [
        for (final events in eventsByFilter)
          [
            for (final event in events)
              if (event.kind == 1 &&
                  (wanted == null || wanted.contains(event.pubkey)))
                event,
          ],
      ];
      // Only a chunk that hit the limit can have older posts left to fetch.
      DateTime? horizon;
      for (var i = 0; i < valid.length; i++) {
        if (eventsByFilter[i].length < queryLimit || valid[i].isEmpty) continue;
        final oldest = valid[i].map((e) => e.createdAt).reduce(_older);
        if (horizon == null || oldest.isAfter(horizon)) horizon = oldest;
      }

      for (final event in valid.expand((events) => events)) {
        final inRange = horizon == null || !event.createdAt.isBefore(horizon);
        if (inRange && (includeReplies || replyParentId(event) == null)) {
          found[event.id] = event;
        }
      }
      if (horizon == null) {
        exhausted = true;
        break;
      }
      // A page that is all one second would otherwise never move on.
      cursor = cursor != null && !horizon.isBefore(cursor)
          ? cursor.subtract(const Duration(seconds: 1))
          : horizon;
    }

    final sorted = found.values.toList()..sort(compareNewestFirst);
    final kept = sorted.take(limit).toList();
    final truncated = sorted.length > limit;
    var next = truncated ? kept.last.createdAt : (exhausted ? null : cursor);
    if (next != null && until != null && !next.isBefore(until)) {
      next = until.subtract(const Duration(seconds: 1));
    }
    return PostPage(kept.map(nostrPostFromEvent).toList(), next);
  }
}

DateTime _older(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

class PostPage {
  const PostPage(this.posts, this.next);

  final List<NostrPost> posts;

  // Null once nothing older is left to fetch.
  final DateTime? next;
}
