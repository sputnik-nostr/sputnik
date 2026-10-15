import 'package:sputnik/nostr/nostr.dart';

// For fakes that override only [RelayClient.query]: reports every relay as
// having answered, so status-aware callers behave as if the relays were up.
mixin AnsweringRelayClient on RelayClient {
  @override
  Future<RelayQueryResult> queryWithStatus(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    final events = await query(relayUrls, filter);
    return RelayQueryResult(
      events: events,
      answeredRelays: relayUrls.length,
      queriedRelays: relayUrls.length,
      sourceRelays: {
        if (relayUrls.isNotEmpty)
          for (final event in events) event.id: relayUrls.first,
      },
    );
  }
}
