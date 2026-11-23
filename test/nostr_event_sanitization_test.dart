import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/keys.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';
import 'package:sputnik/nostr/models/text_sanitizer.dart';

bool _wellFormed(String text) => sanitizeUtf16(text) == text;

void main() {
  final keypair = generateNostrKeyPair();

  // UTF-8 can't carry a lone surrogate, so the ID of an event that holds one,
  // as earlier versions of this app signed them, was hashed over U+FFFD while
  // the JSON on the wire still holds the surrogate as an escape.
  Map<String, dynamic> wireEvent({
    required String content,
    List<List<String>> tags = const [],
  }) {
    String hashed(String text) => utf8.decode(utf8.encode(text));
    final signed = signEvent(
      secretKey: SecretKey.fromHex(keypair.privateKeyHex),
      pubkeyHex: keypair.publicKeyHex,
      kind: 1,
      tags: [
        for (final tag in tags) [for (final value in tag) hashed(value)],
      ],
      content: hashed(content),
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
    );
    final json = signed.toJson()
      ..['content'] = content
      ..['tags'] = tags;
    return jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
  }

  group('content', () {
    for (final (name, content, expected) in [
      ('a high surrogate in the middle', 'a\uD800b', 'a\u{FFFD}b'),
      ('a low surrogate in the middle', 'a\uDC00b', 'a\u{FFFD}b'),
      ('a high surrogate at the end', 'ab\uD83D', 'ab\u{FFFD}'),
      ('a low surrogate at the start', '\uDE00ab', '\u{FFFD}ab'),
      (
        'the halves of a pair in the wrong order',
        '\uDE00\uD83D',
        '\u{FFFD}\u{FFFD}',
      ),
      (
        'a high surrogate before a whole pair',
        '\uD83D\u{1F600}',
        '\u{FFFD}\u{1F600}',
      ),
    ]) {
      test('replaces $name', () {
        final json = wireEvent(content: content);
        // The control: what the relay sent is not valid text.
        expect(_wellFormed(json['content'] as String), isFalse);

        final event = NostrEvent.fromJson(json);

        expect(event.content, expected);
        expect(_wellFormed(event.content), isTrue);
      });
    }

    test('keeps valid surrogate pairs', () {
      const content =
          'ok \u{1F600} \u{1F468}\u{200D}\u{1F469} \u{1F1EB}\u{1F1F7}';

      final event = NostrEvent.fromJson(wireEvent(content: content));

      expect(event.content, content);
    });
  });

  group('tags', () {
    // One position at a time, so sanitizing only some of a tag's strings
    // can't pass.
    for (var position = 0; position < 3; position++) {
      test('replaces a lone surrogate in tag string $position', () {
        final tag = ['a', 'b', 'c']..[position] = 'x\uD800';
        final json = wireEvent(
          content: 'plain',
          tags: [
            ['e', 'before'],
            tag,
            ['p', 'after'],
          ],
        );

        final event = NostrEvent.fromJson(json);

        expect(event.tags, [
          ['e', 'before'],
          ['a', 'b', 'c']..[position] = 'x\u{FFFD}',
          ['p', 'after'],
        ]);
        expect(event.tags.expand((tag) => tag).every(_wellFormed), isTrue);
      });
    }

    test('replaces both kinds of lone surrogate and keeps valid pairs', () {
      final json = wireEvent(
        content: 'plain',
        tags: [
          ['t', 'high\uD83D', 'low\uDE00', 'pair\u{1F600}'],
        ],
      );

      final event = NostrEvent.fromJson(json);

      expect(event.tags, [
        ['t', 'high\u{FFFD}', 'low\u{FFFD}', 'pair\u{1F600}'],
      ]);
    });
  });

  group('sanitizeUtf16', () {
    test('agrees with UTF-8 on every unpaired surrogate', () {
      // Event IDs are hashed over UTF-8, which writes each unpaired surrogate
      // as U+FFFD, so sanitizing a text must not change the bytes its ID
      // covers: events that carry one stay readable.
      const pieces = [
        'a',
        '\u{E9}',
        '\u{1F600}',
        '\uD800',
        '\uDBFF',
        '\uDC00',
        '\uDFFF',
        '\uD83D',
        '\uDE00',
        '\u{FFFD}',
      ];
      final random = Random(1);
      var unpaired = 0;
      for (var i = 0; i < 2000; i++) {
        final text = [
          for (var n = random.nextInt(9); n > 0; n--)
            pieces[random.nextInt(pieces.length)],
        ].join();
        final sanitized = sanitizeUtf16(text);

        expect(
          sanitized,
          utf8.decode(utf8.encode(text)),
          reason: jsonEncode(text),
        );
        if (sanitized != text) unpaired++;
      }
      // The control: enough inputs had something to replace.
      expect(unpaired, greaterThan(500));
    });
  });
}
