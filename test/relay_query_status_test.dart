import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/nostr/relay_connection_pool.dart';

// A local relay: answers every REQ with EOSE, or stays silent.
Future<HttpServer> _serve({required bool answer}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((message) {
      if (!answer) return;
      final decoded = jsonDecode(message as String) as List<dynamic>;
      if (decoded.first == 'REQ') socket.add(jsonEncode(['EOSE', decoded[1]]));
    });
  });
  return server;
}

void main() {
  const filter = NostrFilter(kinds: [3], limit: 1);
  const client = RelayClient(timeout: Duration(seconds: 1));

  test('a relay that never answers does not count', () async {
    final server = await _serve(answer: false);
    addTearDown(() => server.close(force: true));

    final result = await client.queryWithStatus({
      'ws://127.0.0.1:${server.port}',
    }, filter);

    expect(result.events, isEmpty);
    expect(result.answeredRelays, 0);
    expect(result.allRelaysAnswered, isFalse);
  });

  test(
    'an unreachable relay does not count, and does not hide a live one',
    () async {
      final live = await _serve(answer: true);
      final dead = await _serve(answer: true);
      final deadUrl = 'ws://127.0.0.1:${dead.port}';
      await dead.close(force: true);
      addTearDown(() => live.close(force: true));

      final result = await client.queryWithStatus({
        deadUrl,
        'ws://127.0.0.1:${live.port}',
      }, filter);

      expect(result.answeredRelays, 1);
      expect(result.queriedRelays, 2);
      expect(result.allRelaysAnswered, isFalse);
    },
  );

  test(
    'a query sharing a connection that never opens still times out',
    () async {
      // Accepts the TCP connection but never answers the WebSocket upgrade.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((_) {});
      addTearDown(() => server.close(force: true));
      final url = 'ws://127.0.0.1:${server.port}';

      final results = await Future.wait([
        client.queryWithStatus({url}, filter),
        client.queryWithStatus({url}, filter),
      ]).timeout(const Duration(seconds: 5));

      expect(results.map((result) => result.answeredRelays), [0, 0]);
    },
  );

  test('retainOnly closes connections to other relays', () async {
    final closed = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) {
        final decoded = jsonDecode(message as String) as List<dynamic>;
        if (decoded.first == 'REQ') {
          socket.add(jsonEncode(['EOSE', decoded[1]]));
        }
      }, onDone: closed.complete);
    });
    addTearDown(() => server.close(force: true));

    await client.queryWithStatus({'ws://127.0.0.1:${server.port}'}, filter);
    await RelayConnectionPool.instance.retainOnly(const {});

    await closed.future.timeout(const Duration(seconds: 5));
  });
}
