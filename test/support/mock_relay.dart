import 'dart:convert';
import 'dart:io';

import 'package:sputnik/nostr/nostr.dart';

import 'relay_states.dart';

void _send(WebSocket socket, Object message) {
  try {
    socket.add(jsonEncode(message));
  } catch (_) {
    // The client is gone.
  }
}

var _serial = 0;

/// A local relay in one of the [RelayState]s, speaking just enough of NIP-01.
class MockRelay {
  MockRelay._(this.server, this.state, this.held, {required this.refusing});

  final HttpServer server;
  final RelayState state;
  final List<NostrEvent> held;

  /// Refuses the WebSocket upgrade, like a relay that cannot be reached.
  bool refusing;

  /// Events sent to it.
  final received = <Map<String, dynamic>>[];

  /// How many times it was asked for events.
  int requests = 0;

  // The pool keys connections and cooldowns by URL, and the kernel reuses
  // ports, so each relay gets a path of its own.
  late final String url = 'ws://127.0.0.1:${server.port}/relay${_serial++}';

  static Future<MockRelay> start(
    RelayState state,
    List<NostrEvent> held,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = MockRelay._(
      server,
      state,
      held,
      // A cooling relay is unreachable until it has failed once.
      refusing: state == RelayState.down || state == RelayState.cooling,
    );
    server.listen((request) async {
      try {
        if (relay.refusing) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as List<dynamic>;
          switch (message.first) {
            case 'REQ':
              relay.requests++;
              // Never finishes its answer. The socket is dropped on the REQ
              // so that a test need not wait out the pool's timeout.
              if (state == RelayState.slow) {
                socket.close();
                return;
              }
              for (final event in held) {
                _send(socket, ['EVENT', message[1], event.toJson()]);
              }
              _send(socket, ['EOSE', message[1]]);
            case 'EVENT':
              final event = message[1] as Map<String, dynamic>;
              relay.received.add(event);
              _send(socket, ['OK', event['id'], true, '']);
          }
        }, onError: (_) {});
      } catch (_) {
        // The request went away mid-handshake.
      }
    }, onError: (_) {});
    return relay;
  }
}
