import 'package:sputnik/nostr/nostr.dart';

import 'in_memory_relay_client.dart';

// A relay pool where only some of the queried relays answer.
class PartlyAnsweringRelayClient extends InMemoryRelayClient {
  PartlyAnsweringRelayClient(super.events, {required this.answered});

  int answered;

  @override
  Future<RelayQueryResult> queryWithStatus(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => RelayQueryResult(
    events: await query(relayUrls, filter),
    answeredRelays: answered,
    queriedRelays: relayUrls.length,
  );
}
