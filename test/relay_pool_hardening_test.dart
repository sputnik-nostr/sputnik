import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/nostr/relay_connection_pool.dart';

// A local relay that answers each REQ with whatever [script] builds.
Future<HttpServer> _serve(List<String> Function(String subId) script) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((message) {
      final decoded = jsonDecode(message as String) as List<dynamic>;
      if (decoded.first != 'REQ') return;
      script(decoded[1] as String).forEach(socket.add);
    });
  });
  return server;
}

String _eventMsg(String subId, NostrEvent event) =>
    jsonEncode(['EVENT', subId, event.toJson()]);

String _eose(String subId) => jsonEncode(['EOSE', subId]);

void main() {
  const client = RelayClient(timeout: Duration(seconds: 2));
  final key = generateNostrKeyPair();
  final otherKey = generateNostrKeyPair();

  NostrEvent sign({
    NostrKeyPair? by,
    int kind = 1,
    String content = 'hi',
    DateTime? at,
  }) {
    final signer = by ?? key;
    return signEvent(
      seckeyHex: signer.privateKeyHex,
      pubkeyHex: signer.publicKeyHex,
      kind: kind,
      content: content,
      createdAt: at,
    );
  }

  Future<RelayQueryResult> query(HttpServer server, NostrFilter filter) =>
      client.queryWithStatus({'ws://127.0.0.1:${server.port}'}, filter);

  group('what a relay returns is checked against the filter', () {
    test('drops events of another kind or author', () async {
      final wanted = sign(kind: 0, content: '{}');
      final wrongKind = sign(kind: 3, content: 'x');
      final wrongAuthor = sign(by: otherKey, kind: 0, content: '{}');
      final server = await _serve(
        (sub) => [
          _eventMsg(sub, wrongKind),
          _eventMsg(sub, wrongAuthor),
          _eventMsg(sub, wanted),
          _eose(sub),
        ],
      );
      addTearDown(() => server.close(force: true));

      final result = await query(
        server,
        NostrFilter(kinds: const [0], authors: [key.publicKeyHex]),
      );

      expect(result.events.map((e) => e.id), [wanted.id]);
      expect(result.allRelaysAnswered, isTrue);
    });

    test('drops events outside since and until', () async {
      final now = DateTime.now();
      final old = sign(
        content: 'old',
        at: now.subtract(const Duration(days: 3)),
      );
      final fresh = sign(
        content: 'fresh',
        at: now.subtract(const Duration(hours: 1)),
      );
      final server = await _serve(
        (sub) => [_eventMsg(sub, old), _eventMsg(sub, fresh), _eose(sub)],
      );
      addTearDown(() => server.close(force: true));

      final result = await query(
        server,
        NostrFilter(since: now.subtract(const Duration(days: 1))),
      );

      expect(result.events.map((e) => e.id), [fresh.id]);
    });

    test('keeps only events carrying a requested tag', () async {
      final tagged = signEvent(
        seckeyHex: key.privateKeyHex,
        pubkeyHex: key.publicKeyHex,
        kind: 1,
        tags: [
          ['e', 'a' * 64],
        ],
        content: 'tagged',
      );
      final plain = sign(content: 'plain');
      final server = await _serve(
        (sub) => [_eventMsg(sub, plain), _eventMsg(sub, tagged), _eose(sub)],
      );
      addTearDown(() => server.close(force: true));

      final result = await query(
        server,
        NostrFilter(
          tags: {
            'e': ['a' * 64],
          },
        ),
      );

      expect(result.events.map((e) => e.id), [tagged.id]);
    });

    test('an event repeated by the relay counts once', () async {
      final event = sign();
      final server = await _serve(
        (sub) => [
          for (var i = 0; i < 5; i++) _eventMsg(sub, event),
          _eose(sub),
        ],
      );
      addTearDown(() => server.close(force: true));

      final result = await query(server, const NostrFilter(kinds: [1]));

      expect(result.events, hasLength(1));
    });

    test('events beyond the limit are dropped but EOSE still counts', () async {
      final events = [for (var i = 0; i < 5; i++) sign(content: 'n$i')];
      final server = await _serve(
        (sub) => [for (final e in events) _eventMsg(sub, e), _eose(sub)],
      );
      addTearDown(() => server.close(force: true));

      final result = await query(server, const NostrFilter(limit: 2));

      expect(result.events, hasLength(2));
      expect(result.allRelaysAnswered, isTrue);
    });

    test('an event for another subscription is ignored', () async {
      final stray = sign(content: 'stray');
      final mine = sign(content: 'mine');
      final server = await _serve(
        (sub) => [
          _eventMsg('someone-elses-sub', stray),
          _eventMsg(sub, mine),
          _eose(sub),
        ],
      );
      addTearDown(() => server.close(force: true));

      final result = await query(server, const NostrFilter(kinds: [1]));

      expect(result.events.map((e) => e.id), [mine.id]);
    });

    test('an event dated far in the future is dropped', () async {
      final future = sign(
        content: 'future',
        at: DateTime.now().add(const Duration(days: 30)),
      );
      final mine = sign(content: 'mine');
      final server = await _serve(
        (sub) => [_eventMsg(sub, future), _eventMsg(sub, mine), _eose(sub)],
      );
      addTearDown(() => server.close(force: true));

      final result = await query(server, const NostrFilter(kinds: [1]));

      expect(result.events.map((e) => e.id), [mine.id]);
    });
  });

  group('removeIfCurrent', () {
    test('removes the connection it was given', () {
      final connection = Object();
      final connections = {'wss://a.example': connection};

      expect(
        removeIfCurrent(connections, 'wss://a.example', connection),
        isTrue,
      );
      expect(connections, isEmpty);
    });

    test('leaves a newer connection to the same relay alone', () {
      final stale = Object();
      final fresh = Object();
      final connections = {'wss://a.example': fresh};

      expect(removeIfCurrent(connections, 'wss://a.example', stale), isFalse);
      expect(connections['wss://a.example'], same(fresh));
    });

    test('does nothing when the relay has no connection', () {
      final connections = <String, Object>{};

      expect(
        removeIfCurrent(connections, 'wss://a.example', Object()),
        isFalse,
      );
    });
  });
}
