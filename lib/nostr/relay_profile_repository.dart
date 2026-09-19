import '../main.dart';
import '../services/cache_store.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/nostr_metadata.dart';
import 'profile_content.dart';
import 'relay_client.dart';
import 'replaceable_events.dart';

class RelayProfileRepository {
  const RelayProfileRepository({this.client = const RelayClient()});

  final RelayClient client;

  Future<NostrMetadata?> fetchProfile(
    String pubkey,
    Set<String> relayUrls, {
    bool force = false,
  }) async {
    final profiles = await fetchProfiles({pubkey}, relayUrls, force: force);
    return profiles[pubkey];
  }

  Future<Map<String, NostrMetadata>> fetchProfiles(
    Set<String> pubkeys,
    Set<String> relayUrls, {
    bool force = false,
  }) async {
    if (pubkeys.isEmpty) return {};

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

    final eventsByChunk = await Future.wait(
      chunkedAuthors(toFetch.toList()).map(
        (chunk) => client.query(
          relayUrls,
          NostrFilter(kinds: const [0], authors: chunk),
        ),
      ),
    );
    final events = eventsByChunk.expand((events) => events).toList()
      ..sort(compareNewestFirst);

    final requested = {for (final pubkey in toFetch) pubkey.toLowerCase()};
    final metadataByPubkey = <String, NostrMetadata>{};
    for (final event in events) {
      // Any signed event from a relay is authentic, not necessarily asked for.
      if (event.kind != 0 || !requested.contains(event.pubkey)) continue;
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

  // Uncached, so an edit builds on what is really published.
  Future<OwnEvent> fetchOwnProfileEvent(
    String pubkeyHex,
    Set<String> relayUrls,
  ) {
    return fetchOwnReplaceable(
      client,
      kind: 0,
      pubkeyHex: pubkeyHex,
      relayUrls: relayUrls,
    );
  }

  // Publishes [fields] over [base]; its other fields and tags carry over.
  Future<({NostrEvent event, Map<String, RelayPublishResult> results})>
  publishProfile({
    required String seckeyHex,
    required String pubkeyHex,
    required NostrEvent? base,
    required Map<String, String> fields,
    required Set<String> relayUrls,
  }) async {
    final event = signEvent(
      seckeyHex: seckeyHex,
      pubkeyHex: pubkeyHex,
      kind: 0,
      tags: base?.tags ?? const [],
      content: editedProfileContent(base?.content, fields),
      createdAt: nextReplaceableTime(base),
    );
    final results = await client.publish(event, relayUrls);
    return (event: event, results: results);
  }
}
