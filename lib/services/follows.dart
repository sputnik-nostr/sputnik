import '../nostr/nostr.dart';
import 'cache_store.dart';

/// Who [pubkeyHex] follows, from the cache while fresh and from relays
/// otherwise. Null when nothing was found and some relay may still hold a list.
Future<List<String>?> loadFollowingOrNull(
  String pubkeyHex,
  Set<String> relayUrls, {
  bool force = false,
  RelayClient client = const RelayClient(),
}) async {
  if (!force && CacheStore.isFollowingFresh(pubkeyHex)) {
    final cached = CacheStore.getFollowing(pubkeyHex);
    if (cached != null) return cached;
  }

  final following = await RelayContactsRepository(client: client)
      .fetchFollowingOrNull(pubkeyHex, relayUrls);
  if (following != null) {
    await CacheStore.putFollowing(pubkeyHex, following);
  }
  return following;
}

/// [loadFollowingOrNull], with an unknown list shown as empty.
Future<List<String>> loadFollowing(
  String pubkeyHex,
  Set<String> relayUrls, {
  bool force = false,
  RelayClient client = const RelayClient(),
}) async =>
    await loadFollowingOrNull(
      pubkeyHex,
      relayUrls,
      force: force,
      client: client,
    ) ??
    const <String>[];

/// Who follows [pubkeyHex], from the cache while fresh and from relays
/// otherwise.
Future<List<String>> loadFollowers(
  String pubkeyHex,
  Set<String> relayUrls, {
  bool force = false,
  RelayClient client = const RelayClient(),
}) async {
  if (!force && CacheStore.isFollowersFresh(pubkeyHex)) {
    final cached = CacheStore.getFollowers(pubkeyHex);
    if (cached != null) return cached;
  }

  final followers = await RelayContactsRepository(client: client)
      .fetchFollowers(pubkeyHex, relayUrls);
  // Empty may just mean the relays failed, so it is not worth keeping.
  if (followers.isNotEmpty) {
    await CacheStore.putFollowers(pubkeyHex, followers);
  }
  return followers;
}
