import '../app_state.dart';
import '../nostr/nostr.dart';
import 'cache_store.dart';

/// Profiles for [pubkeys], from the cache while fresh and from relays
/// otherwise. Fetched ones go into [profileCacheNotifier] and the disk cache.
Future<Map<String, NostrMetadata>> loadProfiles(
  Set<String> pubkeys,
  Set<String> relayUrls, {
  bool force = false,
  RelayClient client = const RelayClient(),
}) async {
  final cached = <String, NostrMetadata>{};
  final toFetch = <String>{};
  for (final pubkey in pubkeys) {
    final metadata = profileCacheNotifier.value[pubkey];
    if (!force && metadata != null && CacheStore.isProfileFresh(pubkey)) {
      cached[pubkey] = metadata;
    } else {
      toFetch.add(pubkey);
    }
  }
  if (toFetch.isEmpty) return cached;

  final fetched = await RelayProfileRepository(client: client)
      .fetchProfiles(toFetch, relayUrls);
  if (fetched.isNotEmpty) {
    profileCacheNotifier.value = {...profileCacheNotifier.value, ...fetched};
    await CacheStore.putProfiles(fetched);
  }
  return {...cached, ...fetched};
}

/// [loadProfiles] for a single [pubkey].
Future<NostrMetadata?> loadProfile(
  String pubkey,
  Set<String> relayUrls, {
  bool force = false,
  RelayClient client = const RelayClient(),
}) async {
  final profiles = await loadProfiles(
    {pubkey},
    relayUrls,
    force: force,
    client: client,
  );
  return profiles[pubkey];
}
