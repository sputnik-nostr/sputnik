import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/nostr_post.dart';
import 'relay_client.dart';

class ThreadData {
  const ThreadData({
    required this.replies,
    required this.likeCount,
    required this.repostCount,
  });

  final List<NostrPost> replies;
  final int likeCount;
  final int repostCount;
}

class RelayThreadRepository {
  const RelayThreadRepository({this.client = const RelayClient()});

  final RelayClient client;

  Future<ThreadData> fetchThread(String postId, Set<String> relayUrls) async {
    final results = await Future.wait([
      client.query(
        relayUrls,
        NostrFilter(
          kinds: const [1],
          tags: {
            'e': [postId],
          },
        ),
      ),
      client.query(
        relayUrls,
        NostrFilter(
          kinds: const [7],
          tags: {
            'e': [postId],
          },
        ),
      ),
      client.query(
        relayUrls,
        NostrFilter(
          kinds: const [6],
          tags: {
            'e': [postId],
          },
        ),
      ),
    ]);

    final replyEvents = results[0]..sort(compareNewestFirst);

    return ThreadData(
      replies: replyEvents.map(nostrPostFromEvent).toList(),
      likeCount: results[1].length,
      repostCount: results[2].length,
    );
  }
}
