import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/post_reactions.dart';
import 'relay_client.dart';

// The pubkeys of authors of events (kind 6 reposts, kind 7 likes) that tag
// one of the given post ids, grouped by which post id they tagged.
Map<String, List<String>> _authorsByTaggedPost(
  List<NostrEvent> events,
  Set<String> postIds,
) {
  final seenByPost = <String, Set<String>>{};
  for (final event in events) {
    for (final tag in event.tags) {
      if (tag.length < 2 || tag[0] != 'e') continue;
      final postId = tag[1];
      if (!postIds.contains(postId)) continue;
      seenByPost.putIfAbsent(postId, () => {}).add(event.pubkey);
    }
  }
  return {
    for (final entry in seenByPost.entries) entry.key: entry.value.toList(),
  };
}

class RelayReactionsRepository {
  const RelayReactionsRepository({this.client = const RelayClient()});

  final RelayClient client;

  // Fetches likes and reposts for many posts in a single pair of relay
  // queries (one for kind 7, one for kind 6), rather than one query per
  // post. Every requested id is present in the result, defaulting to no
  // reactions when none were found.
  Future<Map<String, PostReactions>> fetchReactions(
    List<String> postIds,
    Set<String> relayUrls,
  ) async {
    if (postIds.isEmpty) return {};
    final postIdSet = postIds.toSet();

    final likesFuture = client.query(
      relayUrls,
      NostrFilter(kinds: const [7], tags: {'e': postIds}),
    );
    final repostsFuture = client.query(
      relayUrls,
      NostrFilter(kinds: const [6], tags: {'e': postIds}),
    );

    final likersByPost = _authorsByTaggedPost(await likesFuture, postIdSet);
    final repostersByPost = _authorsByTaggedPost(
      await repostsFuture,
      postIdSet,
    );

    return {
      for (final postId in postIds)
        postId: PostReactions(
          likerPubkeys: likersByPost[postId] ?? const [],
          reposterPubkeys: repostersByPost[postId] ?? const [],
        ),
    };
  }
}
