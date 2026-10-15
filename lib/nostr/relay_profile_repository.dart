import 'keys.dart';
import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'models/nostr_metadata.dart';
import 'profile_content.dart';
import 'relay_client.dart';
import 'replaceable_events.dart';

class RelayProfileRepository {
  const RelayProfileRepository({this.client = const RelayClient()});

  final RelayClient client;

  /// The newest metadata each of [pubkeys] has published, uncached.
  Future<Map<String, NostrMetadata>> fetchProfiles(
    Set<String> pubkeys,
    Set<String> relayUrls,
  ) async {
    if (pubkeys.isEmpty) return {};

    final eventsByChunk = await Future.wait(
      chunkedAuthors(pubkeys.toList()).map(
        (chunk) => client.query(
          relayUrls,
          NostrFilter(kinds: const [0], authors: chunk),
        ),
      ),
    );
    final events = eventsByChunk.expand((events) => events).toList()
      ..sort(compareNewestFirst);

    final requested = {for (final pubkey in pubkeys) pubkey.toLowerCase()};
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
    return metadataByPubkey;
  }

  /// Uncached, so an edit builds on what is really published.
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

  /// Publishes [fields] over [base]; its other fields and tags carry over.
  Future<({NostrEvent event, Map<String, RelayPublishResult> results})>
  publishProfile({
    required SecretKey secretKey,
    required String pubkeyHex,
    required NostrEvent? base,
    required Map<String, String> fields,
    required Set<String> relayUrls,
  }) async {
    final event = signEvent(
      secretKey: secretKey,
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
