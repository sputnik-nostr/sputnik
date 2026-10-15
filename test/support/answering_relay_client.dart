import 'package:sputnik/nostr/nostr.dart';

// Reports every relay as answered, so status-aware callers see them up.
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
