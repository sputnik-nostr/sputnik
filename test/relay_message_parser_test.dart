import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/keys.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';
import 'package:sputnik/nostr/models/text_sanitizer.dart';
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
    // The lone surrogate becomes U+FFFD, so the string is safe to render.
    expect(parsed!.message, 'broken�message');
  });

  test('cuts an OK message before sanitizing it', () async {
    // The cut falls between the halves of the emoji, which leaves a lone one.
    final raw = jsonEncode([
      'OK',
      'a' * 64,
      false,
      '${'x' * 299}\u{1F600}tail',
    ]);

    final parsed = await parser.parse(raw);

    expect(parsed!.message, '${'x' * 299}\u{FFFD}');
  });

  test('keeps a surrogate pair that ends exactly at the cut', () async {
    final raw = jsonEncode([
      'OK',
      'a' * 64,
      false,
      '${'x' * 298}\u{1F600}tail',
    ]);

    final parsed = await parser.parse(raw);

    expect(parsed!.message, '${'x' * 298}\u{1F600}');
  });

  test('an OK message is well-formed wherever it is cut', () async {
    for (var plain = 290; plain <= 300; plain++) {
      final raw = jsonEncode([
        'OK',
        'a' * 64,
        false,
        '${'x' * plain}${'\u{1F600}' * 8}',
      ]);

      final message = (await parser.parse(raw))!.message!;

      expect(message, hasLength(300), reason: '$plain units before the emoji');
      expect(
        sanitizeUtf16(message),
        message,
        reason: '$plain units before the emoji',
      );
    }
  });

  group('signed events', () {
    final key = generateNostrKeyPair();

    String eventMessage(String subId, {DateTime? at}) {
      final event = signEvent(
        secretKey: SecretKey.fromHex(key.privateKeyHex),
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

    test('without a subscription list every EVENT is parsed', () async {
      expect(await parser.parse(eventMessage('any')), isNotNull);
    });

    test('OK messages do not depend on the subscription list', () async {
      final raw = jsonEncode(['OK', 'a' * 64, true, '']);

      expect(await parser.parse(raw, subscriptionIds: {'live'}), isNotNull);
    });

    test('an event a little ahead of our clock is kept', () async {
      final near = DateTime.now().add(maxEventFutureSkew ~/ 4);

      expect(await parser.parse(eventMessage('s', at: near)), isNotNull);
    });
  });

  group('counting the openers of a message', () {
    test('counts every [ and { outside strings', () {
      const raw = r'["EVENT","s",{"tags":[["p","x"],["e","y"]],"a":{}}]';

      expect(countOpeners(raw), 6);
    });

    test('leaves out brackets inside strings, which are text', () {
      expect(countOpeners(r'["[[{{","}]"]'), 1);
      expect(countOpeners('["EVENT","s",{"content":"${'[{' * 1000}"}]'), 2);
    });

    test('knows an escaped quote from the end of a string', () {
      // The quote after the backslash is part of the string.
      expect(countOpeners(r'["a\"[{","b"]'), 1);
      // The backslash escapes the other backslash, so this quote ends it.
      expect(countOpeners(r'["a\\",[{]]'), 3);
    });

    test('stops past the limit, one over', () {
      expect(countOpeners('[' * 1000, limit: 10), 11);
      expect(countOpeners('[' * 10, limit: 10), 10);
      expect(
        countOpeners('{},' * maxMessageOpeners * 2),
        maxMessageOpeners + 1,
      );
    });

    test('has room for the fullest follow list that fits the length cap', () {
      final key = generateNostrKeyPair();
      final event = signEvent(
        secretKey: SecretKey.fromHex(key.privateKeyHex),
        pubkeyHex: key.publicKeyHex,
        kind: 3,
        content: '',
        tags: [
          for (var i = 0; i < 14358; i++)
            ['p', (i + 0x1000).toRadixString(16).padLeft(16, '0') * 4],
        ],
      );
      final raw = jsonEncode(['EVENT', 's', event.toJson()]);
      expect(raw.length, lessThanOrEqualTo(1 << 20));
      expect(raw.length, greaterThan(1000000));

      // One for each tag, and for the message, the event and its tags.
      expect(countOpeners(raw), 14358 + 3);
      expect(maxMessageOpeners, greaterThan(4 * (14358 + 3)));
    });
  });
}
