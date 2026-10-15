import '../app_state.dart';
import '../nostr/nostr.dart';
import 'cache_store.dart';

/// Cached while fresh; fetched ones also go to [profileCacheNotifier].
Future<Map<String, NostrMetadata>> loadProfiles(
  Set<String> pubkeys,
  Set<String> relayUrls, {
  bool force = false,
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

  final fetched = await RelayProfileRepository().fetchProfiles(
    toFetch,
    relayUrls,
  );
  if (fetched.isNotEmpty) {
    profileCacheNotifier.value = {...profileCacheNotifier.value, ...fetched};
    await CacheStore.putProfiles(fetched);
  }
  return {...cached, ...fetched};
}

/// The active identity's profile name or short pubkey, or null with none.
String? activeIdentityName() {
  final pubkeyHex = activeIdentityPubkeyNotifier.value;
  if (pubkeyHex == null) return null;
  return profileCacheNotifier.value[pubkeyHex]?.resolvedName ??
      shortPubkey(pubkeyHex);
}

/// [loadProfiles] for a single [pubkey].
Future<NostrMetadata?> loadProfile(
  String pubkey,
  Set<String> relayUrls, {
  bool force = false,
}) async {
  final profiles = await loadProfiles({pubkey}, relayUrls, force: force);
  return profiles[pubkey];
}
