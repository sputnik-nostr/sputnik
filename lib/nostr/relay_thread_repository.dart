import 'models/nostr_filter.dart';
import 'models/nostr_event.dart';
import 'models/nostr_post.dart';
import 'models/post_reactions.dart';
import 'relay_client.dart';
import 'relay_reactions_repository.dart';

class ThreadData {
  const ThreadData({
    required this.replies,
    required this.likerPubkeys,
    required this.reposterPubkeys,
  });

  final List<NostrPost> replies;
  final List<String> likerPubkeys;
  final List<String> reposterPubkeys;

  int get likeCount => likerPubkeys.length;
  int get repostCount => reposterPubkeys.length;
}

class RelayThreadRepository {
  const RelayThreadRepository({
    this.client = const RelayClient(),
    this.reactionsRepository = const RelayReactionsRepository(),
  });

  final RelayClient client;
  final RelayReactionsRepository reactionsRepository;

  Future<ThreadData> fetchThread(String postId, Set<String> relayUrls) async {
    final repliesFuture = client.query(
      relayUrls,
      NostrFilter(
        kinds: const [1],
        tags: {
          'e': [postId],
        },
      ),
    );
    final reactionsFuture = reactionsRepository.fetchReactions([
      postId,
    ], relayUrls);

    final replyEvents = (await repliesFuture)..sort(compareNewestFirst);
    final reactions = (await reactionsFuture)[postId] ?? const PostReactions();

    return ThreadData(
      replies: replyEvents.map(nostrPostFromEvent).toList(),
      likerPubkeys: reactions.likerPubkeys,
      reposterPubkeys: reactions.reposterPubkeys,
    );
  }
}
