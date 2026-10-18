import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';

import 'support/raw_relay.dart';

void main() {
  const client = RelayClient(timeout: Duration(seconds: 2));
  const kind3 = NostrFilter(kinds: [3], limit: 1);
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
}
