import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/hex.dart';
import 'package:sputnik/nostr/keys.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';
import 'package:sputnik/nostr/models/nostr_filter.dart';
import 'package:sputnik/nostr/relay_client.dart';
import 'package:sputnik/nostr/relay_message_parser.dart';

import 'support/nostr_tools_events.dart';

typedef _Events = ({String content, String tag, String both});

NostrEvent _read(String json) =>
    NostrEvent.fromJson(jsonDecode(json) as Map<String, dynamic>);

/// [json] after [edit] changed the decoded event.
Map<String, dynamic> _edited(
  String json,
  void Function(Map<String, dynamic> event) edit,
) {
  final event = jsonDecode(json) as Map<String, dynamic>;
  edit(event);
  return event;
}

String _name(int code) =>
    'U+${code.toRadixString(16).toUpperCase().padLeft(4, '0')}';

void main() {
  // The three events of one control; see support/nostr_tools_events.dart.
  void expectRead(int code, _Events events) {
    final control = String.fromCharCode(code);

    final inContent = _read(events.content);
    expect(inContent.content, 'a${control}b');
    expect(inContent.tags, [
      ['t', 'plain'],
    ]);

    final inTag = _read(events.tag);
    expect(inTag.content, 'plain');
    expect(inTag.tags, [
      ['t$control', 'x${control}y'],
    ]);

    final inBoth = _read(events.both);
    expect(inBoth.content, 'a${control}b');
    expect(inBoth.tags, [
      ['t$control', 'x${control}y'],
    ]);
  }

  group('events from clients that escape every control character', () {
    test('there is a vector for each of the 27 controls', () {
      expect(nostrToolsControlEvents.keys.toSet(), {
        for (var code = 0; code < 0x20; code++)
          if (!const {0x08, 0x09, 0x0a, 0x0c, 0x0d}.contains(code)) code,
      });
    });

    for (final MapEntry(key: code, value: events)
        in nostrToolsControlEvents.entries) {
      test('reads ${_name(code)} in content, in tags and in both', () {
        expectRead(code, events);
      });
    }

    test('reads controls mixed with the characters NIP-01 escapes', () {
      final event = _read(nostrToolsMixedEvent);

      expect(event.content, 'line1\nline2\x0b\t"q"\\ end\x1f');
      expect(event.tags, [
        ['t', 'a\x00b'],
        ['p', 'b' * 64],
        ['r', 'with\ttab\x1besc\n\x7f'],
      ]);
    });

    test('reads the characters every implementation hashes alike', () {
      for (final MapEntry(key: code, value: json)
          in nostrToolsOrdinaryEvents.entries) {
        final character = String.fromCharCode(code);

        final event = _read(json);

        expect(event.content, 'a${character}b', reason: _name(code));
        expect(event.tags, [
          ['t', 'x${character}y'],
        ], reason: _name(code));
      }
    });
  });

  group('events from clients that hash controls as they are', () {
    // This app did until it removed them before signing, and nostrdb does.
    for (final MapEntry(key: code, value: events)
        in earlierSputnikControlEvents.entries) {
      test('still reads ${_name(code)} in content, in tags and in both', () {
        expectRead(code, events);
      });
    }

    test('still reads controls mixed with the characters NIP-01 escapes', () {
      final event = _read(earlierSputnikMixedEvent);

      expect(event.content, 'line1\nline2\x0b\t"q"\\ end\x1f');
    });
  });

  group('altered events with a control character', () {
    // The signature is that of the original, so anything else must fail, for
    // either way of hashing the original.
    final originals = {
      for (final MapEntry(key: code, value: events)
          in nostrToolsControlEvents.entries)
        'nostr-tools ${_name(code)}': (code, events.both),
      for (final MapEntry(key: code, value: events)
          in earlierSputnikControlEvents.entries)
        'earlier ${_name(code)}': (code, events.both),
      'nostr-tools mixed': (0x0b, nostrToolsMixedEvent),
      'earlier mixed': (0x0b, earlierSputnikMixedEvent),
    };

    void expectRejected(
      String description,
      void Function(Map<String, dynamic> event, int code) edit,
    ) {
      test('are rejected when $description', () {
        for (final MapEntry(key: name, value: (code, json))
            in originals.entries) {
          final event = _edited(json, (event) => edit(event, code));

          expect(
            () => NostrEvent.fromJson(event),
            throwsFormatException,
            reason: name,
          );
        }
      });
    }

    test('are accepted as they are', () {
      for (final MapEntry(key: name, value: (_, json)) in originals.entries) {
        expect(_read(json).id, isNotEmpty, reason: name);
      }
    });

    expectRejected('the content is extended', (event, _) {
      event['content'] = '${event['content']}x';
    });

    expectRejected('a tag is extended', (event, _) {
      final tags = event['tags'] as List<dynamic>;
      (tags[0] as List<dynamic>)[1] = '${(tags[0] as List<dynamic>)[1]}x';
    });

    expectRejected('the control is replaced by another', (event, code) {
      final other = String.fromCharCode(code == 0x1f ? 0x1e : code + 1);
      event['content'] = (event['content'] as String).replaceAll(
        String.fromCharCode(code),
        other,
      );
    });

    expectRejected('the control is removed', (event, code) {
      event['content'] = (event['content'] as String).replaceAll(
        String.fromCharCode(code),
        '',
      );
    });

    expectRejected('the control is replaced by its escape as text', (
      event,
      code,
    ) {
      // A backslash and "u00xx": six characters that no encoding of the
      // original writes the way it wrote the control.
      final escape =
          r'\u'
          '00${code.toRadixString(16).padLeft(2, '0')}';
      event['content'] = (event['content'] as String).replaceAll(
        String.fromCharCode(code),
        escape,
      );
    });

    expectRejected('the signature is changed', (event, _) {
      final sig = event['sig'] as String;
      event['sig'] = '${sig.startsWith('0') ? '1' : '0'}${sig.substring(1)}';
    });

    expectRejected('the author is changed', (event, _) {
      event['pubkey'] = 'f' * 64;
    });

    expectRejected('the id is that of another event', (event, _) {
      for (final other in [
        nostrToolsControlEvents[0x01]!.both,
        nostrToolsControlEvents[0x02]!.both,
      ]) {
        final id = (jsonDecode(other) as Map<String, dynamic>)['id'];
        if (id != event['id']) {
          event['id'] = id;
          return;
        }
      }
    });
  });

  group('against a standard JSON encoder', () {
    // jsonEncode writes every control as \u00xx, as JSON.stringify does, so an
    // event hashed over its output is one from a client that escapes them.
    const secretKeyHex =
        '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';
    const pubkey =
        '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e';
    final controls = [
      for (var code = 0; code < 0x20; code++)
        if (!const {0x08, 0x09, 0x0a, 0x0c, 0x0d}.contains(code))
          String.fromCharCode(code),
    ];
    const others = [
      'a',
      ' ',
      '\u{E9}',
      '\u{1F600}',
      '"',
      '\\',
      '\n',
      '\t',
      '\r',
      '\b',
      '\f',
      '\x7f',
      '\u{2028}',
    ];
    final unpaired = [
      for (final unit in const [0xD800, 0xDBFF, 0xDC00, 0xDFFF])
        String.fromCharCode(unit),
    ];

    /// Up to a dozen of the characters above, a third of them controls, and
    /// with [unpairedSurrogates] some of those as well.
    String randomText(Random random, {bool unpairedSurrogates = false}) {
      final pieces = [...others, if (unpairedSurrogates) ...unpaired];
      return [
        for (var n = random.nextInt(12); n > 0; n--)
          random.nextInt(3) == 0
              ? controls[random.nextInt(controls.length)]
              : pieces[random.nextInt(pieces.length)],
      ].join();
    }

    /// Up to three tags of up to three strings each, so the first tag is not
    /// the only one with something in it.
    List<List<String>> randomTags(
      Random random, {
      bool unpairedSurrogates = false,
    }) => [
      for (var tags = random.nextInt(4); tags > 0; tags--)
        [
          for (var values = random.nextInt(4); values > 0; values--)
            randomText(random, unpairedSurrogates: unpairedSurrogates),
        ],
    ];

    /// [text] as a JSON string the way NIP-01 describes it: its seven escapes
    /// and every other character as it is.
    String nip01String(String text) {
      const escapes = {
        0x08: r'\b',
        0x09: r'\t',
        0x0a: r'\n',
        0x0c: r'\f',
        0x0d: r'\r',
        0x22: r'\"',
        0x5c: r'\\',
      };
      final body = StringBuffer();
      for (final unit in text.codeUnits) {
        body.write(escapes[unit] ?? String.fromCharCode(unit));
      }
      return '"$body"';
    }

    String asWritten(List<List<String>> tags, String content) {
      final written = [
        for (final tag in tags) '[${tag.map(nip01String).join(',')}]',
      ];
      return '[0,"$pubkey",1700000000,1,[${written.join(',')}],'
          '${nip01String(content)}]';
    }

    String standard(List<List<String>> tags, String content) =>
        jsonEncode([0, pubkey, 1700000000, 1, tags, content]);

    /// The event a relay would send whose ID is the hash of [serialization].
    Map<String, dynamic> signedOver(
      String serialization,
      List<List<String>> tags,
      String content,
    ) {
      final id = Uint8List.fromList(
        sha256.convert(utf8.encode(serialization)).bytes,
      );
      final sig = signSchnorrSignature(
        secretKey: SecretKey.fromHex(secretKeyHex),
        msg32: id,
      );
      return jsonDecode(
        jsonEncode({
          'id': hexEncode(id),
          'pubkey': pubkey,
          'created_at': 1700000000,
          'kind': 1,
          'tags': tags,
          'content': content,
          'sig': hexEncode(sig),
        }),
      ) as Map<String, dynamic>;
    }

    test('reads text hashed either way, whatever it mixes', () {
      final random = Random(20);
      var different = 0;
      for (var i = 0; i < 300; i++) {
        final tags = randomTags(random);
        final content = randomText(random);
        final literal = asWritten(tags, content);
        final escaped = standard(tags, content);
        if (literal != escaped) different++;

        for (final serialization in [literal, escaped]) {
          final event = NostrEvent.fromJson(
            signedOver(serialization, tags, content),
          );

          expect(event.content, content, reason: serialization);
          expect(event.tags, tags, reason: serialization);
        }
      }
      // The control: the two ways of hashing differed for most of them.
      expect(different, greaterThan(200));
    });

    test('does not read text with only some of its controls escaped', () {
      const content = 'a\x0bb\x01c';
      final tags = [
        ['t', 'v'],
      ];
      final escaped = standard(tags, content);
      final raw = asWritten(tags, content);
      final mixed = [
        escaped.replaceFirst(r'\u000b', '\x0b'),
        escaped.replaceFirst(r'\u0001', '\x01'),
      ];

      // The control: neither of the two ways is turned away.
      for (final serialization in [raw, escaped]) {
        expect(
          NostrEvent.fromJson(signedOver(serialization, tags, content)),
          isA<NostrEvent>(),
        );
      }
      for (final serialization in mixed) {
        expect(serialization, isNot(anyOf(raw, escaped)));
        expect(
          () => NostrEvent.fromJson(signedOver(serialization, tags, content)),
          throwsFormatException,
          reason: serialization,
        );
      }
    });

    test('signs events that are hashed the same either way', () {
      final random = Random(21);
      var cleaned = 0;
      for (var i = 0; i < 300; i++) {
        final tags = randomTags(random, unpairedSurrogates: true);
        final content = randomText(random, unpairedSurrogates: true);
        final event = signEvent(
          secretKey: SecretKey.fromHex(secretKeyHex),
          pubkeyHex: pubkey,
          kind: 1,
          tags: tags,
          content: content,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
        );
        if (event.content != content ||
            jsonEncode(event.tags) != jsonEncode(tags)) {
          cleaned++;
        }

        // Nothing is left that the two write differently.
        final literal = asWritten(event.tags, event.content);
        expect(literal, standard(event.tags, event.content));
        expect(
          event.id,
          sha256.convert(utf8.encode(literal)).toString(),
          reason: literal,
        );
      }
      // The control: most of the texts had something to remove or replace.
      expect(cleaned, greaterThan(150));
    });
  });

  group('through the parser', () {
    Future<NostrEvent?> parse(String json) async {
      final parsed = await RelayMessageParser.instance.parse(
        '["EVENT","s",$json]',
        subscriptionIds: {'s'},
      );
      return parsed?.event;
    }

    test('delivers events with controls from either kind of client', () async {
      for (final json in [
        nostrToolsControlEvents[0x0b]!.both,
        nostrToolsControlEvents[0x00]!.tag,
        nostrToolsMixedEvent,
        earlierSputnikControlEvents[0x0b]!.both,
        earlierSputnikMixedEvent,
      ]) {
        final event = await parse(json);

        expect(event, isNotNull, reason: json);
        expect(event!.id, _read(json).id);
      }
    });

    test('drops them once altered', () async {
      for (final json in [
        nostrToolsControlEvents[0x0b]!.both,
        earlierSputnikControlEvents[0x0b]!.both,
      ]) {
        final altered = jsonEncode(
          _edited(json, (e) => e['content'] = '${e['content']}x'),
        );

        expect(await parse(altered), isNull, reason: json);
      }
    });
  });

  group('through the relay pool', () {
    const pubkey =
        '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e';

    /// The kind 3 events a local relay holding only [eventJson] gives back,
    /// which it sends exactly as it was signed.
    Future<List<NostrEvent>> followLists(String eventJson) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as List<dynamic>;
          if (message.first != 'REQ') return;
          final subscription = jsonEncode(message[1]);
          socket.add('["EVENT",$subscription,$eventJson]');
          socket.add('["EOSE",$subscription]');
        });
      });

      return const RelayClient(timeout: Duration(seconds: 5)).query({
        'ws://127.0.0.1:${server.port}',
      }, const NostrFilter(kinds: [3], authors: [pubkey]));
    }

    test('delivers a follow list that holds no control character', () async {
      final lists = await followLists(nostrToolsFollowListWithoutControl);

      expect(lists.single.tags.map((tag) => tag[1]), [
        'a' * 64,
        'b' * 64,
        'c' * 64,
      ]);
    });

    test('delivers a follow list with a control in a petname', () async {
      final lists = await followLists(nostrToolsFollowListWithControl);

      expect(lists.single.tags.map((tag) => tag[1]), [
        'a' * 64,
        'b' * 64,
        'c' * 64,
      ]);
      expect(lists.single.tags[1][3], 'bob\x0b');
    });
  });
}
