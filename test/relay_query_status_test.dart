import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';

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
}
