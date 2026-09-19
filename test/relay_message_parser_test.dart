import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/keys.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';
import 'package:sputnik/nostr/relay_message_parser.dart';

void main() {
  final parser = RelayMessageParser.instance;

  test('parses an accepted OK message', () async {
    final raw = jsonEncode(['OK', 'a' * 64, true, '']);

    final parsed = await parser.parse(raw);

    expect(parsed, isNotNull);
    expect(parsed!.type, 'OK');
    expect(parsed.subscriptionId, 'a' * 64);
    expect(parsed.accepted, isTrue);
  });

  test('parses a rejected OK message with its reason', () async {
    final raw = jsonEncode(['OK', 'a' * 64, false, 'blocked: spam']);

    final parsed = await parser.parse(raw);

    expect(parsed, isNotNull);
    expect(parsed!.accepted, isFalse);
    expect(parsed.message, 'blocked: spam');
  });

  test('treats a missing accepted flag as not accepted', () async {
    final raw = jsonEncode(['OK', 'a' * 64]);

    final parsed = await parser.parse(raw);

    expect(parsed, isNotNull);
    expect(parsed!.accepted, isFalse);
    expect(parsed.message, isNull);
  });

  test('truncates an excessively long OK message', () async {
    final raw = jsonEncode(['OK', 'a' * 64, false, 'x' * 1000]);

    final parsed = await parser.parse(raw);

    expect(parsed, isNotNull);
    expect(parsed!.message, hasLength(300));
  });

  test('sanitizes a lone surrogate in an OK message', () async {
    // A lone high surrogate (\ud800) with no matching low surrogate.
    final raw = '["OK","${'a' * 64}",false,"broken\\ud800message"]';

    final parsed = await parser.parse(raw);

    expect(parsed, isNotNull);
    // The lone surrogate is replaced with U+FFFD rather than left dangling
    // (which would make the string unsafe to render).
    expect(parsed!.message, 'broken�message');
  });

  test('an EVENT message has no accepted/message fields', () async {
    final eventJson =
        '{"id":"${'a' * 64}","pubkey":"${'b' * 64}","created_at":0,'
        '"kind":1,"tags":[],"content":"","sig":"${'c' * 128}"}';
    final raw = '["EVENT","sub-id",$eventJson]';

    final parsed = await parser.parse(raw);

    // The event itself is unsigned garbage here (not a real signature), so
    // this either fails to parse (null) or parses without OK-only fields
    // set -- either way, accepted/message must not leak from an EVENT.
    if (parsed != null) {
      expect(parsed.accepted, isNull);
      expect(parsed.message, isNull);
    }
  });

  group('signed events', () {
    final key = generateNostrKeyPair();

    String eventMessage(String subId, {DateTime? at}) {
      final event = signEvent(
        seckeyHex: key.privateKeyHex,
        pubkeyHex: key.publicKeyHex,
        kind: 1,
        content: 'hello',
        createdAt: at,
      );
      return jsonEncode(['EVENT', subId, event.toJson()]);
    }

    test('an EVENT for a live subscription is parsed', () async {
      final parsed = await parser.parse(
        eventMessage('live'),
        subscriptionIds: {'live'},
      );

      expect(parsed?.event?.content, 'hello');
    });

    test('an EVENT for any other subscription is dropped', () async {
      final parsed = await parser.parse(
        eventMessage('stale'),
        subscriptionIds: {'live'},
      );

      expect(parsed, isNull);
    });

    test('without a subscription list every EVENT is parsed', () async {
      expect(await parser.parse(eventMessage('any')), isNotNull);
    });

    test('OK messages do not depend on the subscription list', () async {
      final raw = jsonEncode(['OK', 'a' * 64, true, '']);

      expect(await parser.parse(raw, subscriptionIds: {'live'}), isNotNull);
    });

    test('an event dated beyond the skew allowance is dropped', () async {
      final late = DateTime.now().add(maxEventFutureSkew * 2);

      expect(await parser.parse(eventMessage('s', at: late)), isNull);
    });

    test('an event a little ahead of our clock is kept', () async {
      final near = DateTime.now().add(maxEventFutureSkew ~/ 4);

      expect(await parser.parse(eventMessage('s', at: near)), isNotNull);
    });
  });
}
