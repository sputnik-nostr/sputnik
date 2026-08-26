import '../main.dart';
import '../services/cache_store.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/nostr_metadata.dart';
import 'relay_client.dart';

// Some relays cap how many authors a single filter may list, so large
// requests (e.g. profiles for a big follower list) are split into chunks
// small enough that no relay should reject or truncate them.
const _authorsChunkSize = 100;

List<List<String>> _chunked(List<String> items, int size) {
  return [
    for (var i = 0; i < items.length; i += size)
      items.sublist(i, i + size > items.length ? items.length : i + size),
  ];
}

class RelayProfileRepository {
  const RelayProfileRepository({this.client = const RelayClient()});

  final RelayClient client;

  Future<NostrMetadata?> fetchProfile(
    String pubkey,
    Set<String> relayUrls,
  ) async {
    final profiles = await fetchProfiles({pubkey}, relayUrls);
    return profiles[pubkey];
  }

  Future<Map<String, NostrMetadata>> fetchProfiles(
    Set<String> pubkeys,
    Set<String> relayUrls,
  ) async {
    if (pubkeys.isEmpty) return {};

    final cached = <String, NostrMetadata>{};
    final toFetch = <String>{};
    for (final pubkey in pubkeys) {
      final metadata = profileCacheNotifier.value[pubkey];
      if (metadata != null && CacheStore.isProfileFresh(pubkey)) {
        cached[pubkey] = metadata;
      } else {
        toFetch.add(pubkey);
      }
    }
    if (toFetch.isEmpty) return cached;

    final eventsByChunk = await Future.wait(
      _chunked(toFetch.toList(), _authorsChunkSize).map(
        (chunk) => client.query(
          relayUrls,
          NostrFilter(kinds: const [0], authors: chunk),
        ),
      ),
    );
    final events = eventsByChunk.expand((events) => events).toList()
      ..sort(compareNewestFirst);

    final metadataByPubkey = <String, NostrMetadata>{};
    for (final event in events) {
      if (metadataByPubkey.containsKey(event.pubkey)) continue;
      try {
        metadataByPubkey[event.pubkey] = NostrMetadata.fromContent(
          event.content,
        );
      } catch (_) {
        // Metadata content is malformed; skip event for this author.
      }
    }

    if (metadataByPubkey.isNotEmpty) {
      profileCacheNotifier.value = {
        ...profileCacheNotifier.value,
        ...metadataByPubkey,
      };
      await CacheStore.putProfiles(metadataByPubkey);
    }

    return {...cached, ...metadataByPubkey};
  }
}
