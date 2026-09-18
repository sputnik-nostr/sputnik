import 'package:sputnik/nostr/nostr.dart';

import 'answering_relay_client.dart';

// A relay that answers filters from a list and stores what is published.
class InMemoryRelayClient extends RelayClient with AnsweringRelayClient {
  InMemoryRelayClient([List<NostrEvent> events = const []])
    : events = [...events];

  final List<NostrEvent> events;
  final published = <NostrEvent>[];
  final queries = <NostrFilter>[];

  // What publish() reports for every relay.
  RelayPublishOutcome publishOutcome = RelayPublishOutcome.accepted;

  // When false, queryWithStatus reports that no relay answered.
  bool relaysAnswer = true;

  @override
  Future<RelayQueryResult> queryWithStatus(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => RelayQueryResult(
    events: await query(relayUrls, filter),
    answeredRelays: relaysAnswer ? relayUrls.length : 0,
    queriedRelays: relayUrls.length,
  );

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    queries.add(filter);
    final matching = [
      for (final event in events)
        if (_matches(event, filter)) event,
    ]..sort(compareNewestFirst);
    final limit = filter.limit;
    return limit == null ? matching : matching.take(limit).toList();
  }

  @override
  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) async {
    published.add(event);
    if (publishOutcome == RelayPublishOutcome.accepted) {
      final replaceable =
          event.kind == 0 ||
          event.kind == 3 ||
          (event.kind >= 10000 && event.kind < 20000);
      if (replaceable) {
        events.removeWhere(
          (old) => old.pubkey == event.pubkey && old.kind == event.kind,
        );
      }
      events.add(event);
    }
    return {
      for (final url in relayUrls) url: RelayPublishResult(publishOutcome),
    };
  }

  bool _matches(NostrEvent event, NostrFilter filter) {
    if (filter.ids != null && !filter.ids!.contains(event.id)) return false;
    if (filter.authors != null && !filter.authors!.contains(event.pubkey)) {
      return false;
    }
    if (filter.kinds != null && !filter.kinds!.contains(event.kind)) {
      return false;
    }
    for (final entry in (filter.tags ?? const {}).entries) {
      final hit = event.tags.any(
        (tag) =>
            tag.length > 1 &&
            tag[0] == entry.key &&
            entry.value.contains(tag[1]),
      );
      if (!hit) return false;
    }
    return true;
  }
}

var _nextId = 0;

// A note with a made-up signature, for tests that never verify it.
NostrEvent fakeEvent({
  String? id,
  String pubkey = 'aa',
  int kind = 1,
  List<List<String>> tags = const [],
  String content = '',
  DateTime? createdAt,
}) {
  String hex64(String seed) => seed.padRight(64, '0').substring(0, 64);
  return NostrEvent(
    id: hex64(id ?? 'e${_nextId++}'),
    pubkey: hex64(pubkey),
    createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(1700000000000),
    kind: kind,
    tags: tags,
    content: content,
    sig: 'sig',
  );
}
