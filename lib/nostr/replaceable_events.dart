import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_client.dart';

/// Only build an edit on [event] when [conclusive].
class OwnEvent {
  const OwnEvent({
    required this.event,
    required this.conclusive,
    this.answeredRelays = 0,
    this.queriedRelays = 0,
    bool? mostRelaysAnswered,
  }) : mostRelaysAnswered = mostRelaysAnswered ?? conclusive;

  final NostrEvent? event;

  /// Whether [event], or its absence, is safe to build on. A copy that was
  /// found needs most relays to have answered. Finding nothing needs every
  /// relay to have said so, since a silent one may hold the only copy.
  final bool conclusive;

  /// How many relays finished their answer, out of those asked.
  final int answeredRelays;
  final int queriedRelays;

  /// Every relay answered and none holds one, so starting a new one loses
  /// nothing.
  bool get confirmedAbsent => event == null && conclusive;

  /// Most of the relays asked finished their answer, as the pool counts them.
  final bool mostRelaysAnswered;
}

/// Queries [relayUrls] for the newest [kind] event by [pubkeyHex].
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
    // Lists are widely copied, so a silent minority rarely holds a newer one.
    // But when nothing was found, a silent relay may hold the only copy.
    conclusive: own.isEmpty
        ? result.allRelaysAnswered
        : result.mostRelaysAnswered,
    answeredRelays: result.answeredRelays,
    queriedRelays: result.queriedRelays,
    mostRelaysAnswered: result.mostRelaysAnswered,
  );
}

/// Relays keep the older of two same-second events, so an edit must be newer.
DateTime nextReplaceableTime(NostrEvent? previous) =>
    nextReplaceableTimeAfter(previous?.createdAt);

/// [nextReplaceableTime] for a newest event known only by its time.
DateTime nextReplaceableTimeAfter(DateTime? previous) {
  final now = DateTime.now();
  if (previous == null) return now;
  final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
  final previousSeconds = previous.millisecondsSinceEpoch ~/ 1000;
  return nowSeconds > previousSeconds
      ? now
      : DateTime.fromMillisecondsSinceEpoch((previousSeconds + 1) * 1000);
}
