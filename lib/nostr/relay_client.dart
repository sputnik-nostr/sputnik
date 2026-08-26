import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';

class RelayClient {
  const RelayClient({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    final eventsByRelay = await Future.wait(
      relayUrls.map((relayUrl) => _queryRelay(relayUrl, filter)),
    );

    final eventsById = <String, NostrEvent>{};
    for (final events in eventsByRelay) {
      for (final event in events) {
        eventsById[event.id] = event;
      }
    }
    return eventsById.values.toList();
  }

  Future<List<NostrEvent>> _queryRelay(
    String relayUrl,
    NostrFilter filter,
  ) async {
    final events = <NostrEvent>[];
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      await channel.ready.timeout(timeout);

      final subscriptionId = 'sputnik-${DateTime.now().microsecondsSinceEpoch}';
      channel.sink.add(jsonEncode(['REQ', subscriptionId, filter.toJson()]));

      await for (final raw in channel.stream.timeout(timeout)) {
        final message = jsonDecode(raw as String);
        if (message is! List || message.isEmpty) continue;
        switch (message[0]) {
          case 'EVENT':
            events.add(NostrEvent.fromJson(message[2] as Map<String, dynamic>));
          case 'EOSE':
          case 'CLOSED':
            return events;
        }
      }
    } catch (_) {
      // Relay is unreachable for some reason; fall back to whatever events were
      // loaded before the failure.
    } finally {
      unawaited(channel?.sink.close());
    }
    return events;
  }
}
