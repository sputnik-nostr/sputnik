import 'dart:convert';

import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/nostr_post.dart';
import 'nip10.dart';
import 'relay_client.dart';

/// Replies are dropped after the query, so ask for more to still fill a page.
const _replyOverfetch = 3;

/// Bounds the queries one page can cost when most results are dropped.
const _maxPageRounds = 4;

class RelayPostRepository {
  const RelayPostRepository({
    required this.relayUrls,
    this.limit = 30,
    this.client = const RelayClient(),
  });

  final Set<String> relayUrls;

  /// Notes per page.
  final int limit;
  final RelayClient client;

  /// Like [fetchEventById], as a [NostrPost].
  Future<NostrPost?> fetchPostById(String id) async {
    final event = await fetchEventById(id);
    return event == null ? null : nostrPostFromEvent(event);
  }

  /// The kind 1 note with [id], or null if no relay returns it.
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

  /// Fetches up to [limit] kind 1 notes older than [until], optionally only by
  /// [authors] and without replies.
  ///
  /// Pass the previous page's [PostPage.next] as [until] for the next page.
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
      // A chunk that hit its limit may lack older events, so only trust events
      // at or newer than the newest such cutoff.
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

  /// Fetches up to [limit] reposts (kind 6) by [authors], resolving each to
  /// the kind 1 note it points at. Drops any whose note can't be resolved.
  Future<List<NostrPost>> fetchReposts(
    List<String> authors,
    Set<String> relayUrls, {
    DateTime? until,
  }) async {
    if (authors.isEmpty) return const [];
    final wanted = {for (final author in authors) author.toLowerCase()};

    final eventsByChunk = await Future.wait(
      chunkedAuthors(wanted.toList()).map(
        (chunk) => client.query(
          relayUrls,
          NostrFilter(
            kinds: const [6],
            authors: chunk,
            until: until,
            limit: limit,
          ),
        ),
      ),
    );
    final reposts =
        eventsByChunk
            .expand((events) => events)
            .where((event) => event.kind == 6 && wanted.contains(event.pubkey))
            .toList()
          ..sort(compareNewestFirst);

    final resolved = await Future.wait(
      reposts.take(limit).map((repost) async {
        final original = await _resolveRepostTarget(repost, relayUrls);
        if (original == null) return null;
        return NostrPost.repost(
          nostrPostFromEvent(original),
          byPubkey: repost.pubkey,
          at: repost.createdAt,
        );
      }),
    );
    return [for (final post in resolved) ?post];
  }

  /// The kind 1 note [repost] points at.
  Future<NostrEvent?> _resolveRepostTarget(
    NostrEvent repost,
    Set<String> relayUrls,
  ) async {
    if (repost.content.isNotEmpty) {
      try {
        final embedded = NostrEvent.fromJson(
          jsonDecode(repost.content) as Map<String, dynamic>,
        );
        if (embedded.kind == 1) return embedded;
      } catch (_) {
        // Not usable as embedded content; fall back to fetching it below.
      }
    }

    String? targetId;
    for (final tag in repost.tags) {
      if (tag.length > 1 && tag[0] == 'e') targetId = tag[1];
    }
    return targetId == null ? null : fetchEventById(targetId);
  }
}

DateTime _older(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

/// One page of notes, newest first.
class PostPage {
  const PostPage(this.posts, this.next);

  final List<NostrPost> posts;

  /// Null once nothing older is left to fetch.
  final DateTime? next;
}
