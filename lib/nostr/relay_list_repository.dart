import 'models/nostr_event.dart';
import 'relay_client.dart';
import 'relay_list.dart';
import 'replaceable_events.dart';

class RelayListRepository {
  const RelayListRepository({this.client = const RelayClient()});

  final RelayClient client;

  // Uncached: a relay list is only read when someone opens it.
  Future<OwnEvent> fetch(String pubkeyHex, Set<String> relayUrls) {
    return fetchOwnReplaceable(
      client,
      kind: 10002,
      pubkeyHex: pubkeyHex,
      relayUrls: relayUrls,
    );
  }

  // Publishes [entries] as the whole list; other tags carry over from [base].
  Future<({NostrEvent event, Map<String, RelayPublishResult> results})>
  publish({
    required String seckeyHex,
    required String pubkeyHex,
    required NostrEvent? base,
    required List<RelayListEntry> entries,
    required Set<String> relayUrls,
  }) async {
    final event = signEvent(
      seckeyHex: seckeyHex,
      pubkeyHex: pubkeyHex,
      kind: 10002,
      tags: [
        for (final tag in base?.tags ?? const <List<String>>[])
          if (tag.isEmpty || tag[0] != 'r') tag,
        for (final entry in entries) entry.toTag(),
      ],
      content: '',
      createdAt: nextReplaceableTime(base),
    );
    final results = await client.publish(event, relayUrls);
    return (event: event, results: results);
  }
}
