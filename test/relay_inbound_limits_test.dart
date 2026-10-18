import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/nostr/relay_connection_pool.dart';
import 'package:sputnik/services/ssrf_guard.dart';

import 'support/loopback_connection.dart';
import 'support/raw_relay.dart';

void main() {
  const client = RelayClient(timeout: Duration(seconds: 2));
  const kind3 = NostrFilter(kinds: [3], limit: 1);
  const oneNote = NostrFilter(kinds: [1], limit: 1);
  final key = generateNostrKeyPair();

  NostrEvent sign({int kind = 1, String content = 'hi', int follows = 0}) {
    return signEvent(
      secretKey: SecretKey.fromHex(key.privateKeyHex),
      pubkeyHex: key.publicKeyHex,
      kind: kind,
      content: content,
      tags: [
        for (var i = 0; i < follows; i++)
          ['p', (i + 0x1000).toRadixString(16).padLeft(16, '0') * 4],
      ],
    );
  }

  String eventMessage(String sub, NostrEvent event) =>
      jsonEncode(['EVENT', sub, event.toJson()]);

  String eose(String sub) => jsonEncode(['EOSE', sub]);

  /// A relay that answers the first REQ with [reply] and then stays open.
  Future<RawRelay> relayReplying(
    FutureOr<void> Function(RawConnection connection, String sub) reply, {
    int port = 0,
  }) {
    return RawRelay.start((connection) async {
      final req = await connection.next('REQ');
      await reply(connection, req[1] as String);
      await connection.closed;
    }, port: port);
  }

  /// A relay that answers each of the first [rounds] REQs with [answer], and
  /// sends nothing in between: the next answer comes once the client has
  /// handled the last and asked again, whatever the time that takes.
  Future<RawRelay> relayAnswering(
    int rounds,
    void Function(RawConnection connection, String sub) answer,
  ) {
    return RawRelay.start((connection) async {
      for (var round = 0; round < rounds; round++) {
        final req = await connection.next('REQ', index: round);
        answer(connection, req[1] as String);
      }
      await connection.closed;
    });
  }

  /// Asks [relay] [times] in a row, each time after the last answer is in.
  Future<List<RelayQueryResult>> askedInTurn(RawRelay relay, int times) async {
    return [
      for (var i = 0; i < times; i++)
        await client.queryWithStatus({relay.url}, oneNote),
    ];
  }

  group('a message the app would have to drop fails its relay', () {
    // 15,000 follows make a kind 3 of about 1.1 MB, over the message cap.
    late NostrEvent tooBig;
    setUpAll(() => tooBig = sign(kind: 3, follows: 15000));

    test('an oversize message in fragments is not an answer', () async {
      final relay = await relayReplying((connection, sub) {
        connection.sendText(eventMessage(sub, tooBig), frames: 3);
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final first = await client.queryWithStatus({relay.url}, kind3);

      expect(first.events, isEmpty);
      expect(first.answeredRelays, 0);

      // The relay now cools down instead of being asked again.
      final second = await client.queryWithStatus({relay.url}, kind3);
      expect(second.answeredRelays, 0);
      expect(relay.connections.single.messagesOf('REQ'), hasLength(1));
    });

    test('so a follow list behind one stays unknown, not empty', () async {
      final relay = await relayReplying((connection, sub) {
        connection.sendText(eventMessage(sub, tooBig), frames: 3);
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final following = await RelayContactsRepository(client: client)
          .fetchFollowingOrNull(key.publicKeyHex, {relay.url});

      expect(following, isNull);
    });

    test('a binary message is not an answer either', () async {
      final relay = await relayReplying((connection, sub) {
        connection.send(
          webSocketFrame(2, utf8.encode(eventMessage(sub, sign()))),
        );
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final result = await client.queryWithStatus({relay.url}, kind3);

      expect(result.events, isEmpty);
      expect(result.answeredRelays, 0);
    });

    test(
      'an honest relay beside one that breaks the cap still answers',
      () async {
        final event = sign(kind: 3, follows: 10);
        final bad = await relayReplying((connection, sub) {
          connection.sendText(eventMessage(sub, tooBig), frames: 3);
          connection.sendText(eose(sub));
        });
        final good = await relayReplying((connection, sub) {
          connection.sendText(eventMessage(sub, event));
          connection.sendText(eose(sub));
        });
        addTearDown(bad.close);
        addTearDown(good.close);

        final result = await client.queryWithStatus({bad.url, good.url}, kind3);

        expect(result.events.map((e) => e.id), [event.id]);
        expect(result.answeredRelays, 1);
        expect(result.queriedRelays, 2);
      },
    );
  });

  group('a backlog of unparsed messages', () {
    late int messageCap;
    late int textCap;
    setUp(() {
      messageCap = maxPendingMessages;
      textCap = maxPendingParseLength;
    });
    tearDown(() {
      maxPendingMessages = messageCap;
      maxPendingParseLength = textCap;
    });

    /// A message the relay may send at any time, [chars] long plus 13.
    Uint8List notice(int chars) =>
        webSocketText(jsonEncode(['NOTICE', 'x' * chars]));

    test('beyond the count cap fails the relay', () async {
      maxPendingMessages = 100;
      final relay = await relayReplying((connection, sub) {
        connection.send(repeated(notice(80), 1000));
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final result = await client.queryWithStatus({relay.url}, kind3);

      expect(result.answeredRelays, 0);
      await relay.connections.single.closed.timeout(const Duration(seconds: 5));
    });

    test('is counted as it drains, not over the connection\'s life', () async {
      maxPendingMessages = 100;
      final event = sign();
      // 144 messages in all, but never more than twelve waiting at once.
      final relay = await relayAnswering(12, (connection, sub) {
        connection.send(repeated(notice(80), 10));
        connection.sendText(eventMessage(sub, event));
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final results = await askedInTurn(relay, 12);

      for (final (round, result) in results.indexed) {
        expect(result.events.map((e) => e.id), [event.id], reason: '$round');
        expect(result.answeredRelays, 1, reason: '$round');
      }
      // The counts are a connection's, so every query must have used the same.
      expect(relay.connections, hasLength(1));
    });

    test('within the count cap is an ordinary answer', () async {
      maxPendingMessages = 100;
      final event = sign();
      final relay = await relayReplying((connection, sub) {
        connection.send(repeated(notice(80), 50));
        connection.sendText(eventMessage(sub, event));
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final result = await client.queryWithStatus({relay.url}, oneNote);

      expect(result.events.map((e) => e.id), [event.id]);
      expect(result.answeredRelays, 1);
    });

    test('beyond the text cap fails the relay', () async {
      maxPendingParseLength = 20000;
      final relay = await relayReplying((connection, sub) {
        connection.send(repeated(notice(2000), 100));
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final result = await client.queryWithStatus({relay.url}, kind3);

      expect(result.answeredRelays, 0);
      await relay.connections.single.closed.timeout(const Duration(seconds: 5));
    });

    test(
      'text is counted as it drains, not over the connection\'s life',
      () async {
        maxPendingParseLength = 20000;
        final event = sign();
        // About 125 KB in all, but only about 10 KB waiting at once.
        final relay = await relayAnswering(12, (connection, sub) {
          connection.send(repeated(notice(2000), 5));
          connection.sendText(eventMessage(sub, event));
          connection.sendText(eose(sub));
        });
        addTearDown(relay.close);

        final results = await askedInTurn(relay, 12);

        for (final (round, result) in results.indexed) {
          expect(result.events.map((e) => e.id), [event.id], reason: '$round');
          expect(result.answeredRelays, 1, reason: '$round');
        }
        expect(relay.connections, hasLength(1));
      },
    );

    test('a relay that floods on a socket that answered before cools down', () async {
      maxPendingMessages = 100;
      final relay = await RawRelay.start((connection) async {
        final first = await connection.next('REQ');
        connection.sendText(eose(first[1] as String));
        final second = await connection.next('REQ', index: 1);
        connection.send(repeated(notice(80), 1000));
        connection.sendText(eose(second[1] as String));
        await connection.closed;
      });
      addTearDown(relay.close);

      final alive = await client.queryWithStatus({relay.url}, kind3);
      final flooding = await client.queryWithStatus({relay.url}, kind3);
      final cooling = await client.queryWithStatus({relay.url}, kind3);

      expect(alive.answeredRelays, 1);
      expect(flooding.answeredRelays, 0);
      expect(cooling.answeredRelays, 0);
      // Not retried on a fresh socket, and not asked again while cooling down.
      expect(relay.connections, hasLength(1));
      expect(relay.connections.single.messagesOf('REQ'), hasLength(2));
    });

    test('a publish that meets a flood is not accepted', () async {
      maxPendingMessages = 100;
      final relay = await RawRelay.start((connection) async {
        final published = await connection.next('EVENT');
        connection.send(repeated(notice(80), 1000));
        final id = (published[1] as Map<String, dynamic>)['id'];
        connection.sendText(jsonEncode(['OK', id, true, '']));
        await connection.closed;
      });
      addTearDown(relay.close);

      final results = await client.publish(sign(), {relay.url});
      final afterwards = await client.queryWithStatus({relay.url}, kind3);

      expect(results.acceptedCount, 0);
      expect(afterwards.answeredRelays, 0);
      // The relay cools down, so the query did not even dial it.
      expect(relay.connections, hasLength(1));
      expect(relay.connections.single.messagesOf('REQ'), isEmpty);
    });
  });

  group('a message too wide to decode safely', () {
    late int pendingCap;
    setUp(() => pendingCap = maxPendingOpeners);
    tearDown(() => maxPendingOpeners = pendingCap);

    /// Holds [openers] empty maps (and the two lists around them), so that
    /// decoding it takes far more heap than its text does.
    String wide(String sub, int openers) =>
        '["EVENT","$sub",[${'{},' * (openers - 2)}0]]';

    test('fails the relay, and its EOSE is no answer', () async {
      // 70,000 empty maps are 210 KB of text.
      final relay = await relayReplying((connection, sub) {
        connection.sendText(wide(sub, 70000));
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final first = await client.queryWithStatus({relay.url}, oneNote);

      expect(first.answeredRelays, 0);
      await relay.connections.single.closed.timeout(const Duration(seconds: 5));

      final second = await client.queryWithStatus({relay.url}, oneNote);
      expect(second.answeredRelays, 0);
      expect(relay.connections.single.messagesOf('REQ'), hasLength(1));
    });

    test('is not what a note full of brackets looks like', () async {
      final note = sign(content: '[{' * 50000);
      final relay = await relayReplying((connection, sub) {
        connection.sendText(eventMessage(sub, note));
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final result = await client.queryWithStatus({relay.url}, oneNote);

      expect(result.events.map((e) => e.id), [note.id]);
      expect(result.answeredRelays, 1);
    });

    test('many of them waiting at once fail the relay too', () async {
      // None is over the limit for one message, but together they hold more
      // than a connection may have waiting.
      maxPendingOpeners = 1000;
      final relay = await relayReplying((connection, sub) {
        connection.send(repeated(webSocketText(wide(sub, 600)), 10));
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final result = await client.queryWithStatus({relay.url}, oneNote);

      expect(result.answeredRelays, 0);
      await relay.connections.single.closed.timeout(const Duration(seconds: 5));
    });

    test(
      'are counted as they drain, not over the connection\'s life',
      () async {
        maxPendingOpeners = 1000;
        final event = sign();
        // About 1,250 openers in all, but only about a hundred waiting at once.
        final relay = await relayAnswering(12, (connection, sub) {
          connection.sendText(wide(sub, 100));
          connection.sendText(eventMessage(sub, event));
          connection.sendText(eose(sub));
        });
        addTearDown(relay.close);

        final results = await askedInTurn(relay, 12);

        for (final (round, result) in results.indexed) {
          expect(result.events.map((e) => e.id), [event.id], reason: '$round');
          expect(result.answeredRelays, 1, reason: '$round');
        }
        expect(relay.connections, hasLength(1));
      },
    );
  });

  group('frames are checked before dart:io has buffered them', () {
    test('a message in fragments is cut off while it is still being sent', () async {
      // 64 MiB as one message, in pieces of 64 KiB, unless the client hangs up.
      var sent = 0;
      final relay = await relayReplying((connection, sub) async {
        final piece = Uint8List(65536)..fillRange(0, 65536, 0x78);
        for (var i = 0; i < 1024 && !connection.isClosed; i++) {
          connection.send(webSocketFrame(i == 0 ? 1 : 0, piece, fin: false));
          await connection.flush();
          sent += piece.length;
        }
      });
      addTearDown(relay.close);

      final result = await client.queryWithStatus({relay.url}, kind3);

      expect(result.answeredRelays, 0);
      await relay.connections.single.closed.timeout(const Duration(seconds: 5));
      // About 1 MiB and what the sockets could hold, not the whole message.
      expect(sent, lessThan(24 << 20));
    });

    test(
      'a message of exactly the cap is delivered, one byte more is not',
      () async {
        Future<RelayQueryResult> afterNotice(int length) async {
          // ["NOTICE",""] is 13 bytes without what is in the string.
          final notice = '["NOTICE","${'x' * (length - 13)}"]';
          expect(utf8.encode(notice), hasLength(length));
          final relay = await relayReplying((connection, sub) {
            connection.sendText(notice, frames: 16);
            connection.sendText(eventMessage(sub, sign()));
            connection.sendText(eose(sub));
          });
          addTearDown(relay.close);
          return client.queryWithStatus({relay.url}, oneNote);
        }

        final atCap = await afterNotice(1 << 20);
        final overCap = await afterNotice((1 << 20) + 1);

        expect(atCap.events, hasLength(1));
        expect(atCap.answeredRelays, 1);
        expect(overCap.events, isEmpty);
        expect(overCap.answeredRelays, 0);
      },
    );

    test('a flood of empty frames is cut off', () async {
      // Far fewer than the pool would count as a backlog.
      final relay = await relayReplying((connection, sub) {
        connection.send(repeated(webSocketFrame(1, const []), 20000));
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final result = await client.queryWithStatus({relay.url}, kind3);

      expect(result.answeredRelays, 0);
      await relay.connections.single.closed.timeout(const Duration(seconds: 5));
    });

    test('a flood of pings is cut off, and only a few are answered', () async {
      final relay = await relayReplying((connection, sub) {
        connection.send(repeated(webSocketFrame(9, const []), 100000));
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final result = await client.queryWithStatus({relay.url}, kind3);

      expect(result.answeredRelays, 0);
      await relay.connections.single.closed.timeout(const Duration(seconds: 5));
      expect(relay.connections.single.pongs, lessThanOrEqualTo(256));
    });

    test('a relay that breaks a frame limit after answering is not retried', () async {
      final relay = await RawRelay.start((connection) async {
        final first = await connection.next('REQ');
        connection.sendText(eose(first[1] as String));
        final second = await connection.next('REQ', index: 1);
        connection.send(repeated(webSocketFrame(1, const []), 20000));
        connection.sendText(eose(second[1] as String));
        await connection.closed;
      });
      addTearDown(relay.close);

      final alive = await client.queryWithStatus({relay.url}, kind3);
      final flooding = await client.queryWithStatus({relay.url}, kind3);
      final cooling = await client.queryWithStatus({relay.url}, kind3);

      expect(alive.answeredRelays, 1);
      expect(flooding.answeredRelays, 0);
      expect(cooling.answeredRelays, 0);
      // Not retried on a fresh socket, and not asked again while cooling down.
      expect(relay.connections, hasLength(1));
      expect(relay.connections.single.messagesOf('REQ'), hasLength(2));
    });

    test('a ping now and then is answered', () async {
      final event = sign();
      final relay = await relayReplying((connection, sub) {
        connection.send(webSocketFrame(9, utf8.encode('hello')));
        connection.sendText(eventMessage(sub, event));
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final result = await client.queryWithStatus({relay.url}, oneNote);

      expect(result.events.map((e) => e.id), [event.id]);
      expect(result.answeredRelays, 1);
      final connection = relay.connections.single;
      for (var i = 0; i < 200 && connection.pongs < 1; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(connection.pongs, 1);
    });

    test('a relay that redirects is closed, not followed', () async {
      // dart:io would send the next request over the same connection, and read
      // the reply to that without anything watching it.
      var requests = 0;
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((socket) {
        // The client may be gone when the next write is tried.
        socket.done.ignore();
        socket.listen((_) {
          requests++;
          socket.add(
            ascii.encode(
              'HTTP/1.1 302 Found\r\n'
              'Location: /elsewhere\r\n'
              'Content-Length: 0\r\n\r\n',
            ),
          );
        }, onError: (_) {});
      });

      final result = await client.queryWithStatus({
        'ws://127.0.0.1:${server.port}',
      }, oneNote);

      expect(result.answeredRelays, 0);
      expect(requests, 1);
    });
  });

  group('the connection to a relay', () {
    test(
      'is not blamed for what the relay sends after it was let go',
      () async {
        var connections = 0;
        final flood = Completer<void>();
        final relay = await RawRelay.start((connection) async {
          final first = connections++ == 0;
          final req = await connection.next('REQ');
          connection.sendText(eose(req[1] as String));
          if (first) {
            await flood.future;
            connection.send(repeated(webSocketFrame(9, const []), 1000));
          }
          await connection.closed;
        });
        addTearDown(relay.close);

        final before = await client.queryWithStatus({relay.url}, kind3);
        await RelayConnectionPool.instance.retainOnly({});
        flood.complete();
        await relay.connections.first.closed.timeout(
          const Duration(seconds: 5),
        );
        final after = await client.queryWithStatus({relay.url}, kind3);

        expect(before.answeredRelays, 1);
        // Asked again at once: it is not on cooldown.
        expect(after.answeredRelays, 1);
        expect(relay.connections, hasLength(2));
      },
    );

    test('does not offer compression', () async {
      // A relay that is offered it could send a small frame that inflates
      // into a huge one.
      final relay = await relayReplying(
        (connection, sub) => connection.sendText(eose(sub)),
      );
      addTearDown(relay.close);

      await client.queryWithStatus({relay.url}, oneNote);

      final headers = relay.connections.single.requestHeaders;
      expect(headers.value('sec-websocket-extensions'), isNull);
    });

    test('goes through the SSRF guard unless a test replaces it', () async {
      expect(productionRelayConnectionFactory, same(guardedConnectionFactory));

      relayConnectionFactory = guardedConnectionFactory;
      addTearDown(() => relayConnectionFactory = loopbackConnectionFactory);
      final relay = await relayReplying(
        (connection, sub) => connection.sendText(eose(sub)),
      );
      addTearDown(relay.close);

      final result = await client.queryWithStatus({relay.url}, oneNote);

      expect(result.answeredRelays, 0);
      expect(relay.connections, isEmpty);
    });

    group('through a proxy', () {
      // The "proxy" is a relay that answers whatever it is asked for.
      Future<RelayQueryResult> asked(RawRelay proxy, Set<String> relays) {
        final port = Uri.parse(proxy.url).port;
        return HttpOverrides.runZoned(
          () => client.queryWithStatus(relays, kind3),
          findProxyFromEnvironment: (url, _) => 'PROXY 127.0.0.1:$port',
        );
      }

      test('a relay is reached', () async {
        final event = sign(kind: 3, follows: 10);
        final proxy = await relayReplying((connection, sub) {
          connection.sendText(eventMessage(sub, event));
          connection.sendText(eose(sub));
        });
        addTearDown(proxy.close);

        final result = await asked(proxy, {'ws://reached.example'});

        expect(result.events.map((e) => e.id), [event.id]);
        expect(result.answeredRelays, 1);
      });

      test('what the app can still tell is held to the limits', () async {
        final tooBig = sign(kind: 3, follows: 15000);
        final proxy = await relayReplying((connection, sub) {
          connection.sendText(eventMessage(sub, tooBig), frames: 3);
          connection.sendText(eose(sub));
        });
        addTearDown(proxy.close);

        final result = await asked(proxy, {'ws://limited.example'});

        expect(result.events, isEmpty);
        expect(result.answeredRelays, 0);
      });

      test('a binary message is not an answer there either', () async {
        final proxy = await relayReplying((connection, sub) {
          connection.send(
            webSocketFrame(2, utf8.encode(eventMessage(sub, sign()))),
          );
          connection.sendText(eose(sub));
        });
        addTearDown(proxy.close);

        final result = await asked(proxy, {'ws://binary.example'});

        expect(result.events, isEmpty);
        expect(result.answeredRelays, 0);
      });
    });
  });

  group('the relay pool', () {
    test('closes its connections when it is reset', () async {
      final relay = await relayReplying(
        (connection, sub) => connection.sendText(eose(sub)),
      );
      addTearDown(relay.close);
      await client.queryWithStatus({relay.url}, kind3);

      await RelayConnectionPool.instance.reset();

      await relay.connections.single.closed.timeout(const Duration(seconds: 5));
    });

    // The next two tests are to be run in this order: the relay of the second
    // is on the port of the first one's. The system hands a port out again
    // soon after it was freed, and the pool remembers a relay that failed by
    // its URL.
    int? failedPort;

    test('puts a relay that failed on cooldown', () async {
      final relay = await relayReplying((connection, sub) {
        connection.send(webSocketFrame(2, utf8.encode(eose(sub))));
      });
      addTearDown(relay.close);
      failedPort = Uri.parse(relay.url).port;

      final first = await client.queryWithStatus({relay.url}, kind3);
      final second = await client.queryWithStatus({relay.url}, kind3);

      expect(first.answeredRelays, 0);
      expect(second.answeredRelays, 0);
      expect(relay.connections.single.messagesOf('REQ'), hasLength(1));
    });

    test(
      'is reset after each test, so a relay on that port is asked',
      () async {
        final relay = await relayReplying(
          (connection, sub) => connection.sendText(eose(sub)),
          port: failedPort ?? 0,
        );
        addTearDown(relay.close);

        final result = await client.queryWithStatus({relay.url}, kind3);

        expect(result.answeredRelays, 1);
        expect(relay.connections, hasLength(1));
      },
    );
  });

  group('ordinary traffic is still delivered', () {
    test('a page of nearly 2000 events', () async {
      final events = [for (var i = 0; i < 1999; i++) sign(content: 'n$i')];
      final relay = await relayReplying((connection, sub) {
        final out = BytesBuilder(copy: false);
        for (final event in events) {
          out.add(webSocketText(eventMessage(sub, event)));
        }
        out.add(webSocketText(eose(sub)));
        connection.send(out.takeBytes());
      });
      addTearDown(relay.close);

      final result = await client.queryWithStatus({
        relay.url,
      }, const NostrFilter(kinds: [1], limit: 2000));

      expect(result.events, hasLength(1999));
      expect(result.answeredRelays, 1);
    });

    test('an 800 follow list', () async {
      final list = sign(kind: 3, follows: 800);
      final relay = await relayReplying((connection, sub) {
        connection.sendText(eventMessage(sub, list));
        connection.sendText(eose(sub));
      });
      addTearDown(relay.close);

      final result = await client.queryWithStatus({relay.url}, kind3);

      expect(result.events.single.tags, hasLength(800));
      expect(result.answeredRelays, 1);
    });

    test('a 900 KB event, whole or in pieces', () async {
      final big = sign(content: 'x' * 900000);
      for (final frames in [1, 7]) {
        final relay = await relayReplying((connection, sub) {
          connection.sendText(eventMessage(sub, big), frames: frames);
          connection.sendText(eose(sub));
        });
        addTearDown(relay.close);

        final result = await client.queryWithStatus({relay.url}, oneNote);

        expect(result.events.map((e) => e.id), [big.id], reason: '$frames');
        expect(result.answeredRelays, 1, reason: '$frames');
      }
    });
  });
}
