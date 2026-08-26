import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'models/nostr_event.dart';
import 'models/nostr_post.dart';
import 'post_repository.dart';

class RelayPostRepository implements PostRepository {
  const RelayPostRepository({
    required this.relayUrls,
    this.limit = 30,
    this.timeout = const Duration(seconds: 5),
  });

  final Set<String> relayUrls;
  final int limit;
  final Duration timeout;

  @override
  Future<List<NostrPost>> fetchPosts() async {
    final eventsByRelay = await Future.wait(relayUrls.map(_fetchFromRelay));

    final eventsById = <String, NostrEvent>{};
    for (final events in eventsByRelay) {
      for (final event in events) {
        eventsById[event.id] = event;
      }
    }

    final events = eventsById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return events.take(limit).map(_toPost).toList();
  }

  Future<List<NostrEvent>> _fetchFromRelay(String relayUrl) async {
    final events = <NostrEvent>[];
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      await channel.ready.timeout(timeout);

      final subscriptionId = 'sputnik-${DateTime.now().microsecondsSinceEpoch}';
      channel.sink.add(
        jsonEncode([
          'REQ',
          subscriptionId,
          {
            'kinds': [1],
            'limit': limit,
          },
        ]),
      );

      await for (final raw in channel.stream.timeout(timeout)) {
        final message = jsonDecode(raw as String);
        if (message is! List || message.isEmpty) continue;
        switch (message[0]) {
          case 'EVENT':
            events.add(NostrEvent.fromJson(message[2] as Map<String, dynamic>));
          case 'EOSE':
            return events;
        }
      }
    } catch (_) {
    } finally {
      unawaited(channel?.sink.close());
    }
    return events;
  }

  NostrPost _toPost(NostrEvent event) {
    final shortPubkey = event.pubkey.substring(0, 8);
    return NostrPost(
      id: event.id,
      author: NostrAuthor(
        pubkey: event.pubkey,
        displayName: shortPubkey,
        handle: shortPubkey,
      ),
      content: event.content,
      createdAt: event.createdAt,
    );
  }
}
