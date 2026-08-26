import '../main.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/nostr_metadata.dart';
import 'relay_client.dart';

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

    final events = await client.query(
      relayUrls,
      NostrFilter(kinds: const [0], authors: pubkeys.toList()),
    );
    events.sort(compareNewestFirst);

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
    }

    return metadataByPubkey;
  }
}
