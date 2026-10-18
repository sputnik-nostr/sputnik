import '../nostr/nostr.dart';
import 'cache_store.dart';

/// Cached while fresh; null when some relay may still hold a list.
///
/// With [own], the list is the user's, and what is found is kept as the newest
/// seen, so that a change made later is not built on an older copy unasked.
Future<List<String>?> loadFollowingOrNull(
  String pubkeyHex,
  Set<String> relayUrls, {
  bool force = false,
  bool own = false,
}) async {
  final cached = force ? null : CacheStore.freshFollowing(pubkeyHex);
  if (cached != null) return cached;

  final following = await RelayContactsRepository().fetchFollowingOrNull(
    pubkeyHex,
    relayUrls,
    remember: own,
  );
  if (following != null) {
    CacheStore.putFollowing(pubkeyHex, following);
  }
  return following;
}

/// [loadFollowingOrNull], with an unknown list shown as empty.
Future<List<String>> loadFollowing(
  String pubkeyHex,
  Set<String> relayUrls, {
  bool force = false,
}) async =>
    await loadFollowingOrNull(pubkeyHex, relayUrls, force: force) ??
    const <String>[];

/// Who follows [pubkeyHex], from the cache while fresh.
Future<List<String>> loadFollowers(
  String pubkeyHex,
  Set<String> relayUrls, {
  bool force = false,
}) async {
  final cached = force ? null : CacheStore.freshFollowers(pubkeyHex);
  if (cached != null) return cached;

  final followers = await RelayContactsRepository().fetchFollowers(
    pubkeyHex,
    relayUrls,
  );
  // Empty may just mean the relays failed, so it is not worth keeping.
  if (followers.isNotEmpty) {
    CacheStore.putFollowers(pubkeyHex, followers);
  }
  return followers;
}
