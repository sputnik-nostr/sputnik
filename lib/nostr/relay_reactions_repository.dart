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
}
