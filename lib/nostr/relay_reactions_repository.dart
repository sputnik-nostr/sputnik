import 'dart:convert';

import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/post_reactions.dart';
import 'relay_client.dart';

/// Max events requested for each of likes and reposts.
const _reactionLimit = 500;

/// Per NIP-25/NIP-18: with more than one "e" tag, the last one is the
/// actual target; earlier ones are just citations.
String? _lastTaggedEventId(NostrEvent event) {
  String? found;
  for (final tag in event.tags) {
    if (tag.length > 1 && tag[0] == 'e') found = tag[1].toLowerCase();
  }
  return found;
}

/// Per NIP-25: "+" or empty content means like, "-" means dislike, and
/// anything else (emoji, custom-emoji shortcode) is neither.
bool _isLikeReaction(String content) => content.isEmpty || content == '+';

/// The pubkeys of authors of events (kind 6 reposts, kind 7 likes) that tag
/// one of the given post IDs, grouped by which post ID they tagged.
Map<String, List<String>> _authorsByTaggedPost(
  List<NostrEvent> events,
  Set<String> postIds,
  int kind,
) {
  final seenByPost = <String, Set<String>>{};
  for (final event in events) {
    if (event.kind != kind) continue;
    if (kind == 7 && !_isLikeReaction(event.content)) continue;

    final postId = _lastTaggedEventId(event);
    if (postId == null || !postIds.contains(postId)) continue;
    seenByPost.putIfAbsent(postId, () => {}).add(event.pubkey);
  }
  return {
    for (final entry in seenByPost.entries) entry.key: entry.value.toList(),
  };
}

class RelayReactionsRepository {
  const RelayReactionsRepository({this.client = const RelayClient()});

  final RelayClient client;

  /// Fetches likes and reposts for many posts in a single pair of relay
  /// queries (one for kind 7, one for kind 6), rather than one query per
  /// post. Every requested ID is present in the result, defaulting to no
  /// reactions when none were found.
  Future<Map<String, PostReactions>> fetchReactions(
    List<String> postIds,
    Set<String> relayUrls,
  ) async {
    if (postIds.isEmpty) return {};
    final postIdSet = {for (final id in postIds) id.toLowerCase()};

    final likesFuture = client.query(
      relayUrls,
      NostrFilter(
        kinds: const [7],
        tags: {'e': postIds},
        limit: _reactionLimit,
      ),
    );
    final repostsFuture = client.query(
      relayUrls,
      NostrFilter(
        kinds: const [6],
        tags: {'e': postIds},
        limit: _reactionLimit,
      ),
    );

    final likersByPost = _authorsByTaggedPost(await likesFuture, postIdSet, 7);
    final repostersByPost = _authorsByTaggedPost(
      await repostsFuture,
      postIdSet,
      6,
    );

    return {
      for (final postId in postIds)
        postId: PostReactions(
          likerPubkeys: likersByPost[postId.toLowerCase()] ?? const [],
          reposterPubkeys: repostersByPost[postId.toLowerCase()] ?? const [],
        ),
    };
  }

  /// Publishes a NIP-25 like (kind 7, content "+") for [target].
  Future<Map<String, RelayPublishResult>> publishLike({
    required String seckeyHex,
    required String myPubkeyHex,
    required NostrEvent target,
    required Set<String> relayUrls,
  }) {
    final event = signEvent(
      seckeyHex: seckeyHex,
      pubkeyHex: myPubkeyHex,
      kind: 7,
      tags: [
        ['e', target.id, ''],
        ['p', target.pubkey, ''],
        ['k', '${target.kind}'],
      ],
      content: '+',
    );
    return client.publish(event, relayUrls);
  }

  /// Publishes a NIP-18 repost (kind 6) of [target], content the reposted
  /// note's stringified JSON.
  Future<Map<String, RelayPublishResult>> publishRepost({
    required String seckeyHex,
    required String myPubkeyHex,
    required NostrEvent target,
    required Set<String> relayUrls,
  }) {
    final event = signEvent(
      seckeyHex: seckeyHex,
      pubkeyHex: myPubkeyHex,
      kind: 6,
      tags: [
        ['e', target.id, ''],
        ['p', target.pubkey, ''],
      ],
      content: jsonEncode(target.toJson()),
    );
    return client.publish(event, relayUrls);
  }

  /// The newest kind [kind] event by [myPubkeyHex] targeting [noteId], if
  /// any -- what [publishRetraction] would delete.
  Future<NostrEvent?> fetchOwnReaction({
    required String myPubkeyHex,
    required String noteId,
    required int kind,
    required Set<String> relayUrls,
  }) async {
    final events = await client.query(
      relayUrls,
      NostrFilter(
        kinds: [kind],
        authors: [myPubkeyHex],
        tags: {
          'e': [noteId],
        },
      ),
    );

    final wantedNote = noteId.toLowerCase();
    final wantedAuthor = myPubkeyHex.toLowerCase();
    final mine = events.where((event) {
      if (event.kind != kind || event.pubkey != wantedAuthor) return false;
      if (kind == 7 && !_isLikeReaction(event.content)) return false;
      return _lastTaggedEventId(event) == wantedNote;
    }).toList()..sort(compareNewestFirst);

    return mine.isEmpty ? null : mine.first;
  }

  /// Publishes a NIP-09 deletion request for [target]; removal is never
  /// guaranteed, since other relays or clients may already have a copy.
  Future<Map<String, RelayPublishResult>> publishRetraction({
    required String seckeyHex,
    required String myPubkeyHex,
    required NostrEvent target,
    required Set<String> relayUrls,
  }) {
    final event = signEvent(
      seckeyHex: seckeyHex,
      pubkeyHex: myPubkeyHex,
      kind: 5,
      tags: [
        ['e', target.id],
        ['k', '${target.kind}'],
      ],
      content: '',
    );
    return client.publish(event, relayUrls);
  }
}
