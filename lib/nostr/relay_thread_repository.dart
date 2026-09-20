import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/nostr_post.dart';
import 'models/post_reactions.dart';
import 'nip10.dart';
import 'relay_client.dart';
import 'relay_reactions_repository.dart';

/// A reply in a thread, and how deeply it is nested.
class ThreadReply {
  const ThreadReply({required this.post, required this.depth});

  final NostrPost post;

  /// 0 for a direct reply to the viewed note.
  final int depth;
}

/// Everything shown around a viewed note: ancestors, replies and reactions.
class ThreadData {
  const ThreadData({
    required this.replies,
    required this.likerPubkeys,
    required this.reposterPubkeys,
    this.ancestors = const [],
    this.replyToId,
  });

  /// The notes above the viewed one, root first.
  final List<NostrPost> ancestors;

  /// What the viewed note replies to, even when that note could not be found.
  final String? replyToId;

  /// Everything below the viewed note, depth-first and oldest first.
  final List<ThreadReply> replies;
  final List<String> likerPubkeys;
  final List<String> reposterPubkeys;

  int get directReplyCount => replies.where((reply) => reply.depth == 0).length;
  int get likeCount => likerPubkeys.length;
  int get repostCount => reposterPubkeys.length;
}

/// Most replies kept for one thread.
const _replyLimit = 200;

/// Most events requested per query for one thread.
const _threadEventLimit = 500;

/// How far up the reply chain to walk from the viewed note.
const _maxAncestors = 8;

class RelayThreadRepository {
  const RelayThreadRepository({
    this.client = const RelayClient(),
    this.reactionsRepository = const RelayReactionsRepository(),
  });

  final RelayClient client;
  final RelayReactionsRepository reactionsRepository;

  /// Fetches the thread around [postId]: its ancestors, replies and reactions.
  ///
  /// [extraEvents] are notes just published that relays may not return yet.
  Future<ThreadData> fetchThread(
    String postId,
    Set<String> relayUrls, {
    List<NostrEvent> extraEvents = const [],
  }) async {
    final wantedId = postId.toLowerCase();
    final focusFuture = _fetchByIds([wantedId], relayUrls);
    final citingFuture = _fetchCiting(wantedId, relayUrls);
    final reactionsFuture = reactionsRepository.fetchReactions([
      postId,
    ], relayUrls);

    final pool = <String, NostrEvent>{};
    void add(Iterable<NostrEvent> events) {
      for (final event in events) {
        if (event.kind == 1) pool.putIfAbsent(event.id, () => event);
      }
    }

    add(extraEvents);
    add(await focusFuture);
    add(await citingFuture);

    // Replies deeper than the viewed note cite the root, not the note itself.
    final focus = pool[wantedId];
    final rootId = focus == null ? null : threadRootId(focus);
    if (focus != null && rootId != null && rootId != wantedId) {
      final parentId = replyParentId(focus);
      final results = await Future.wait([
        _fetchCiting(rootId, relayUrls),
        _fetchByIds([
          rootId,
          if (parentId != null && parentId != rootId) parentId,
        ], relayUrls),
      ]);
      results.forEach(add);
    }

    final ancestors = <NostrEvent>[];
    var current = focus;
    while (current != null && ancestors.length < _maxAncestors) {
      final parentId = replyParentId(current);
      if (parentId == null || parentId == wantedId) break;
      if (!pool.containsKey(parentId)) {
        add(await _fetchByIds([parentId], relayUrls));
      }
      final parent = pool[parentId];
      if (parent == null || ancestors.contains(parent)) break;
      ancestors.add(parent);
      current = parent;
    }

    final reactions = (await reactionsFuture)[postId] ?? const PostReactions();

    return ThreadData(
      ancestors: ancestors.reversed.map(nostrPostFromEvent).toList(),
      replyToId: focus == null ? null : replyParentId(focus),
      replies: _descendants(wantedId, pool.values),
      likerPubkeys: reactions.likerPubkeys,
      reposterPubkeys: reactions.reposterPubkeys,
    );
  }

  Future<List<NostrEvent>> _fetchCiting(String id, Set<String> relayUrls) {
    return client.query(
      relayUrls,
      NostrFilter(
        kinds: const [1],
        tags: {
          'e': [id],
        },
        limit: _threadEventLimit,
      ),
    );
  }

  Future<List<NostrEvent>> _fetchByIds(
    List<String> ids,
    Set<String> relayUrls,
  ) async {
    final wanted = ids.toSet();
    final events = await client.query(
      relayUrls,
      NostrFilter(ids: ids, kinds: const [1], limit: ids.length),
    );
    return [
      for (final event in events)
        if (wanted.contains(event.id)) event,
    ];
  }

  List<ThreadReply> _descendants(String rootId, Iterable<NostrEvent> events) {
    final children = <String, List<NostrEvent>>{};
    for (final event in events) {
      final parentId = replyParentId(event);
      if (parentId == null || event.id == rootId) continue;
      children.putIfAbsent(parentId, () => []).add(event);
    }
    for (final siblings in children.values) {
      siblings.sort((a, b) => compareNewestFirst(b, a));
    }

    final replies = <ThreadReply>[];
    final visited = {rootId};
    void walk(String parentId, int depth) {
      for (final child in children[parentId] ?? const <NostrEvent>[]) {
        if (replies.length >= _replyLimit) return;
        if (!visited.add(child.id)) continue;
        replies.add(ThreadReply(post: nostrPostFromEvent(child), depth: depth));
        walk(child.id, depth + 1);
      }
    }

    walk(rootId, 0);
    return replies;
  }
}
