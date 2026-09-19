import 'package:sputnik/nostr/nostr.dart';

// Skips the reactions lookup for tests that only care about the thread.
class NoReactions extends RelayReactionsRepository {
  const NoReactions();

  @override
  Future<Map<String, PostReactions>> fetchReactions(
    List<String> postIds,
    Set<String> relayUrls,
  ) async => const {};
}
