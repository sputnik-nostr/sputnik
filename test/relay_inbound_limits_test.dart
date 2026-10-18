import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/nostr/relay_connection_pool.dart';

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
    FutureOr<void> Function(RawConnection connection, String sub) reply,
  ) {
    return RawRelay.start((connection) async {
      final req = await connection.next('REQ');
      await reply(connection, req[1] as String);
      await connection.closed;
    });
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
}
