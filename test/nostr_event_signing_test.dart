import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/keys.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';

void main() {
  final keypair = generateNostrKeyPair();

  test('toJson round-trips tags and created_at exactly', () {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(1700000042 * 1000);
    final event = signEvent(
      secretKey: SecretKey.fromHex(keypair.privateKeyHex),
      pubkeyHex: keypair.publicKeyHex,
      kind: 1,
      tags: [
        ['e', 'a' * 64],
        ['p', 'b' * 64],
      ],
      content: 'with tags',
      createdAt: createdAt,
    );

    final json = event.toJson();
    expect(json['created_at'], 1700000042);
    expect(json['tags'], [
      ['e', 'a' * 64],
      ['p', 'b' * 64],
    ]);

    final roundTripped = NostrEvent.fromJson(json);
    expect(roundTripped.tags, [
      ['e', 'a' * 64],
      ['p', 'b' * 64],
    ]);
  });

  test(
    'serializes only the NIP-01 escapes; other characters stay verbatim',
    () {
      final event = signEvent(
        secretKey: SecretKey.fromHex(keypair.privateKeyHex),
        pubkeyHex: keypair.publicKeyHex,
        kind: 1,
        tags: [
          ['t', 'x\ty'],
        ],
        content: 'a\bb\fc\rd\ne\tf\\"g\x7f\u{2028}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );

      // Written out by hand from the NIP-01 rules, not via jsonEncode.
      final expected =
          '[0,"${keypair.publicKeyHex}",1700000000,1,[["t","x'
          r'\t'
          'y"]],"a'
          r'\b'
          'b'
          r'\f'
          'c'
          r'\r'
          'd'
          r'\n'
          'e'
          r'\t'
          'f'
          r'\\'
          r'\"'
          'g\x7f\u{2028}"]';
      expect(event.id, sha256.convert(utf8.encode(expected)).toString());
      expect(NostrEvent.fromJson(event.toJson()).content, event.content);
    },
  );

  group('text that clients hash differently', () {
    // The IDs below are what nostr-tools 2.25.2 (getEventHash) computes for
    // this key, kind 1, created_at 1700000000 and the text that is expected
    // to be signed, so they check this app against another implementation.
    const secretKeyHex =
        '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';
    const pubkeyHex =
        '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e';

    NostrEvent sign({
      required String content,
      List<List<String>> tags = const [],
    }) => signEvent(
      secretKey: SecretKey.fromHex(secretKeyHex),
      pubkeyHex: pubkeyHex,
      kind: 1,
      tags: tags,
      content: content,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
    );

    // The C0 controls NIP-01 has no short escape for, from its table of
    // escapes (\b, \t, \n, \f and \r).
    final controls = [
      for (var code = 0; code < 0x20; code++)
        if (!const {0x08, 0x09, 0x0a, 0x0c, 0x0d}.contains(code)) code,
    ];

    test('there are 27 controls without a short escape', () {
      expect(controls, hasLength(27));
    });

    for (final code in controls) {
      final control = String.fromCharCode(code);
      final name = 'U+${code.toRadixString(16).toUpperCase().padLeft(4, '0')}';

      test('removes $name from content, from tags and from both', () {
        final inContent = sign(
          content: 'a${control}b',
          tags: [
            ['t', 'plain'],
          ],
        );
        expect(inContent.content, 'ab');
        expect(inContent.tags, [
          ['t', 'plain'],
        ]);
        expect(
          inContent.id,
          'cb96772d056f06c1e49b8e858f2a8bf55ba889d8131f32f19c7d5e7391f45b12',
        );

        final inTags = sign(
          content: 'plain',
          tags: [
            ['t$control', 'x${control}y'],
          ],
        );
        expect(inTags.content, 'plain');
        expect(inTags.tags, [
          ['t', 'xy'],
        ]);
        expect(
          inTags.id,
          '5b5e4f0817ea6deebe74cfab538af50da5d2ec9b97802b6cd2cd45a7dc3d2550',
        );

        final inBoth = sign(
          content: 'a${control}b',
          tags: [
            ['t$control', 'x${control}y'],
          ],
        );
        expect(inBoth.content, 'ab');
        expect(inBoth.tags, [
          ['t', 'xy'],
        ]);
        expect(
          inBoth.id,
          'de27e4e08cb2af0e19cb684612eca64038bd2756f0b2edeb4bcb9868eecb968c',
        );
      });
    }

    test('keeps the characters NIP-01 escapes', () {
      const content = 'a\bb\tc\nd\fe\rf"g\\h';

      final event = sign(
        content: content,
        tags: [
          ['t', 'x\ty', '\n'],
        ],
      );

      expect(event.content, content);
      expect(event.tags, [
        ['t', 'x\ty', '\n'],
      ]);
      expect(
        event.id,
        'c2f2283700d4110f6c837a4845c8a35922dad566e20f3df24ce63f237e04b88c',
      );
    });

    test('keeps DEL, U+2028 and emoji', () {
      const text = 'a\x7fb\u{2028}c\u{1F600}d';

      final event = sign(
        content: text,
        tags: [
          ['t', '\x7f\u{2028}\u{1F600}'],
        ],
      );

      expect(event.content, text);
      expect(event.tags, [
        ['t', '\x7f\u{2028}\u{1F600}'],
      ]);
      expect(
        event.id,
        '44ee2ec3a9f5b586b79ebf1d853b26b00672e8e2ce7be43283cea12f3019bf54',
      );
    });

    test('replaces lone surrogates, so none is sent as an escape', () {
      final event = sign(
        content: 'a\uD800b',
        tags: [
          ['t', 'x\uDC00y'],
        ],
      );

      expect(event.content, 'a\u{FFFD}b');
      expect(event.tags, [
        ['t', 'x\u{FFFD}y'],
      ]);
      expect(
        event.id,
        '9023c6dffab7ed5661dd515c851007dd0ae2d94ab1ac3c9d35f1df124041df5b',
      );
      expect(jsonEncode(event.toJson()).toLowerCase(), isNot(contains(r'\ud')));
    });

    test('cleans controls and surrogates in every string of every tag', () {
      final event = sign(
        content: 'line1\n\x0bline2\uD800\r\n"q"\\',
        tags: [
          ['t\x00\uD800', 'x\ty\uDC00\x1f'],
        ],
      );

      expect(event.content, 'line1\nline2\u{FFFD}\r\n"q"\\');
      expect(event.tags, [
        ['t\u{FFFD}', 'x\ty\u{FFFD}'],
      ]);
      expect(
        event.id,
        '2ff020c8dbbd62656ffc490d1497ad0186565efdb278a70535e5b29b5792b369',
      );
    });

    test('cleans every tag, not only the first', () {
      final event = sign(
        content: 'plain',
        tags: [
          ['p', 'ok'],
          ['t\x01', 'x\x02'],
          ['r', '\x0b', 'with\uD800\x1f'],
          [],
          ['e', 'a\ty'],
        ],
      );

      expect(event.tags, [
        ['p', 'ok'],
        ['t', 'x'],
        ['r', '', 'with\u{FFFD}'],
        [],
        ['e', 'a\ty'],
      ]);
      expect(
        event.id,
        'f3cd653578dbcc756061d535bc5e9c404b631d7a9f1c58a56aaa5a4ac8584b9c',
      );
    });

    test('replaces surrogates first, so removing a control joins nothing', () {
      final event = sign(content: '\uD83D\x01\uDE00');

      expect(event.content, '\u{FFFD}\u{FFFD}');
    });

    test(
      'signs what a standard JSON encoder writes, and it survives the wire',
      () {
        // Dart's jsonEncode writes every code unit as JSON.stringify does.
        final texts = [
          for (final code in controls) 'a${String.fromCharCode(code)}b',
          'a\bb\tc\nd\fe\rf"g\\h',
          'a\x7fb\u{2028}c\u{1F600}d',
          'a\uD800b',
          'a\uDC00b',
          '\uDE00\uD83D',
          'x\uD83D',
          '\uDE00y',
          'line1\n\x0bline2\uD800\r\n"q"\\',
          '',
        ];

        for (final text in texts) {
          final event = sign(
            content: text,
            tags: [
              ['t', text],
            ],
          );

          final standard = jsonEncode([
            0,
            event.pubkey,
            1700000000,
            event.kind,
            event.tags,
            event.content,
          ]);
          expect(
            event.id,
            sha256.convert(utf8.encode(standard)).toString(),
            reason: jsonEncode(text),
          );

          final received = NostrEvent.fromJson(
            jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>,
          );
          expect(received.id, event.id, reason: jsonEncode(text));
          expect(received.content, event.content, reason: jsonEncode(text));
          expect(received.tags, event.tags, reason: jsonEncode(text));
        }
      },
    );
  });
}
