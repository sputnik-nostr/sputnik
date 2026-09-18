import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_client.dart';

// The newest replaceable event you own, and whether that answer is complete.
class OwnEvent {
  const OwnEvent({required this.event, required this.conclusive});

  final NostrEvent? event;

  // False when nothing was found but a relay never answered.
  final bool conclusive;
}

Future<OwnEvent> fetchOwnReplaceable(
  RelayClient client, {
  required int kind,
  required String pubkeyHex,
  required Set<String> relayUrls,
}) async {
  final result = await client.queryWithStatus(
    relayUrls,
    NostrFilter(kinds: [kind], authors: [pubkeyHex], limit: 1),
  );
  final author = pubkeyHex.toLowerCase();
  final own = [
    for (final event in result.events)
      if (event.kind == kind && event.pubkey == author) event,
  ]..sort(compareNewestFirst);

  return OwnEvent(
    event: own.isEmpty ? null : own.first,
    conclusive: own.isNotEmpty || result.allRelaysAnswered,
  );
}

// Relays keep the older of two same-second events, so an edit must be newer.
DateTime nextReplaceableTime(NostrEvent? previous) {
  final now = DateTime.now();
  if (previous == null) return now;
  final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
  final previousSeconds = previous.createdAt.millisecondsSinceEpoch ~/ 1000;
  return nowSeconds > previousSeconds
      ? now
      : DateTime.fromMillisecondsSinceEpoch((previousSeconds + 1) * 1000);
}
