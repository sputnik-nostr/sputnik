import 'package:sputnik/nostr/models/nostr_event.dart';
import 'package:sputnik/nostr/models/post_reactions.dart';
import 'package:sputnik/nostr/relay_thread_repository.dart';

/// A thread with no replies, found without asking any relay.
class NoReplies extends RelayThreadRepository {
  const NoReplies();

  @override
  Future<ThreadData> fetchThread(
    String postId,
    Set<String> relayUrls, {
    List<NostrEvent> extraEvents = const [],
  }) async {
    return const ThreadData(replies: [], reactions: PostReactions());
  }
}
