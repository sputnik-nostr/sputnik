import 'dart:convert';

import 'keys.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/post_reactions.dart';
import 'relay_client.dart';

/// Max events requested for each of likes and reposts, per chunk of posts.
const _reactionLimit = 500;

/// Small chunks, so one popular post only uses up its own chunk's limit.
const _postsPerReactionQuery = 10;

/// With several `e` tags, the last is the target; the rest are citations.
String? _lastTaggedEventId(NostrEvent event) {
  String? found;
  for (final tag in event.tags) {
    if (tag.length > 1 && tag[0] == 'e') found = tag[1].toLowerCase();
  }
  return found;
}

/// Per NIP-25, "+" or empty is a like; "-" and emoji are not.
bool _isLikeReaction(String content) => content.isEmpty || content == '+';

/// Authors of kind [kind] events tagging [postIds], by tagged post.
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
  const RelayReactionsRepository({this._client});

  final RelayClient? _client;

  RelayClient get client => _client ?? RelayClient.instance;

  /// Every requested ID is in the result, with no reactions if none found.
  Future<Map<String, PostReactions>> fetchReactions(
    List<String> postIds,
    Set<String> relayUrls,
  ) async {
    if (postIds.isEmpty) return {};
    final postIdSet = {for (final id in postIds) id.toLowerCase()};

    Future<List<NostrEvent>> fetchKind(int kind) async {
      final chunks = await Future.wait(
        chunked(postIds, _postsPerReactionQuery).map(
          (chunk) => client.query(
            relayUrls,
            NostrFilter(
              kinds: [kind],
              tags: {'e': chunk},
              limit: _reactionLimit,
            ),
          ),
        ),
      );
      return chunks.expand((events) => events).toList();
    }

    final likesFuture = fetchKind(7);
    final repostsFuture = fetchKind(6);

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

  /// A NIP-25 like (kind 7, "+") of [target], found on [relayHint].
  Future<Map<String, RelayPublishResult>> publishLike({
    required SecretKey secretKey,
    required String myPubkeyHex,
    required NostrEvent target,
    required String relayHint,
    required Set<String> relayUrls,
  }) {
    final event = signEvent(
      secretKey: secretKey,
      pubkeyHex: myPubkeyHex,
      kind: 7,
      tags: [
        ['e', target.id, relayHint, target.pubkey],
        ['p', target.pubkey, ''],
        ['k', '${target.kind}'],
      ],
      content: '+',
    );
    return client.publish(event, relayUrls);
  }

  /// A NIP-18 repost (kind 6) of [target]; NIP-18 requires [relayHint].
  Future<Map<String, RelayPublishResult>> publishRepost({
    required SecretKey secretKey,
    required String myPubkeyHex,
    required NostrEvent target,
    required String relayHint,
    required Set<String> relayUrls,
  }) {
    final event = signEvent(
      secretKey: secretKey,
      pubkeyHex: myPubkeyHex,
      kind: 6,
      tags: [
        ['e', target.id, relayHint],
        ['p', target.pubkey, ''],
      ],
      content: jsonEncode(target.toJson()),
    );
    return client.publish(event, relayUrls);
  }

  /// Your newest kind [kind] event on [noteId], for [publishRetraction].
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

  /// A NIP-09 deletion request; other relays or clients may keep a copy.
  Future<Map<String, RelayPublishResult>> publishRetraction({
    required SecretKey secretKey,
    required String myPubkeyHex,
    required NostrEvent target,
    required Set<String> relayUrls,
  }) {
    final event = signEvent(
      secretKey: secretKey,
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
