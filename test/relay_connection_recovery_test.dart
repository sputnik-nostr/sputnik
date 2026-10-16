import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';

/// A local relay whose [respond] decides, per connection, what to answer.
Future<HttpServer> _serve(
  void Function(WebSocket socket, int connection, List<dynamic> message)
  respond,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var connections = 0;
  server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    final connection = connections++;
    socket.listen(
      (raw) => respond(
        socket,
        connection,
        jsonDecode(raw as String) as List<dynamic>,
      ),
    );
  });
  return server;
}

void main() {
  const filter = NostrFilter(kinds: [1], limit: 1);
  const client = RelayClient(timeout: Duration(seconds: 1));

  test('keeps open subscriptions per relay under common limits', () async {
    var open = 0;
    var mostOpen = 0;
    final server = await _serve((socket, _, message) {
      if (message.first == 'CLOSE') open--;
      if (message.first != 'REQ') return;
      open++;
      if (open > mostOpen) mostOpen = open;
      Timer(const Duration(milliseconds: 50), () {
        socket.add(jsonEncode(['EOSE', message[1]]));
      });
    });
    addTearDown(() => server.close(force: true));
    final url = 'ws://127.0.0.1:${server.port}';

    final results = await Future.wait([
      for (var i = 0; i < 30; i++) client.queryWithStatus({url}, filter),
    ]);

    expect(results.every((result) => result.allRelaysAnswered), isTrue);
    expect(mostOpen, lessThanOrEqualTo(10));
  });

  test('a query on a socket that went silent reconnects and retries', () async {
    var reqsOnFirst = 0;
    final server = await _serve((socket, connection, message) {
      if (message.first != 'REQ') return;
      // The first socket answers once, then acts like a dropped connection.
      if (connection == 0 && reqsOnFirst++ > 0) return;
      socket.add(jsonEncode(['EOSE', message[1]]));
    });
    addTearDown(() => server.close(force: true));
    final url = 'ws://127.0.0.1:${server.port}';

    expect(
      (await client.queryWithStatus({url}, filter)).allRelaysAnswered,
      isTrue,
    );
    expect(
      (await client.queryWithStatus({url}, filter)).allRelaysAnswered,
      isTrue,
    );
  });

  test('a relay that never answers is not retried', () async {
    var requests = 0;
    final server = await _serve((_, _, message) {
      if (message.first == 'REQ') requests++;
    });
    addTearDown(() => server.close(force: true));

    final result = await client.queryWithStatus({
      'ws://127.0.0.1:${server.port}',
    }, filter);

    expect(result.allRelaysAnswered, isFalse);
    expect(requests, 1);
  });

  test(
    'a publish on a socket that went silent reconnects and retries',
    () async {
      final event = NostrEvent(
        id: 'ab' * 32,
        pubkey: 'cd' * 32,
        createdAt: DateTime.now(),
        kind: 1,
        tags: const [],
        content: '',
        sig: 'ef' * 64,
      );
      final server = await _serve((socket, connection, message) {
        if (message.first == 'REQ') {
          socket.add(jsonEncode(['EOSE', message[1]]));
        } else if (message.first == 'EVENT' && connection > 0) {
          socket.add(jsonEncode(['OK', event.id, true, '']));
        }
      });
      addTearDown(() => server.close(force: true));
      final url = 'ws://127.0.0.1:${server.port}';
      await client.queryWithStatus({url}, filter);

      final results = await client.publish(event, {url});

      expect(results.acceptedCount, 1);
    },
  );
}
