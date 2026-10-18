import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/blossom.dart';
import 'package:sputnik/nostr/nip92.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/image_saver.dart';
import 'package:sputnik/services/media_loader.dart';
import 'package:sputnik/widgets/fade_in_avatar.dart';

import 'support/in_memory_relay_client.dart';
import 'support/no_reactions.dart';

final _hash = 'ab' * 32;

DateTime _at(int minutes) =>
    DateTime.fromMillisecondsSinceEpoch(1700000000000 + minutes * 60000);

class _RealHttp extends HttpOverrides {}

// The test binding replaces every HttpClient with one that answers 400.
HttpClient _realClient() =>
    HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());

/// Percent-escapes that are not valid UTF-8, which is what makes
/// Uri.pathSegments throw, plus escapes that are valid but steer a path.
final _badEscapes = [
  for (var byte = 0x80; byte <= 0xff; byte++)
    '%${byte.toRadixString(16).toUpperCase()}',
  // Overlong forms, surrogate halves, beyond U+10FFFF, cut-off sequences.
  '%C0%80', '%C0%AF', '%E0%80%AF', '%ED%A0%80', '%ED%BF%BF', '%F4%90%80%80',
  '%E2%82', '%F0%9F%98',
  // What older servers produce for non-ASCII names.
  'Caf%E9', 'Gr%F6%DFe', '%E4%F6%FC',
  // Not escapes at all, or escapes of characters that steer a path.
  '%', '%%', '%zz', '%2', '%2F', '%3F', '%23', '%00', '%25', '%2e%2e',
  '..%2F..%2F', '%E2%82%AC', '%F0%9F%98%80',
];

/// The places in a URL where such a name can appear.
Iterable<String> _shapes(String name) => [
  'https://a.example/$name',
  'https://a.example/$name.jpg',
  'https://a.example/x/$name/y.jpg',
  'https://a.example/$_hash.$name',
  'https://a.example/$_hash.png/$name',
  'https://a.example/$name/$_hash.png',
  'https://a.example/x.png?q=$name#$name',
];

/// Ports the parser lets through although no connection could use them. The
/// last ones are too big for an int, so reading the port throws.
const _badPorts = [
  '65536',
  '99999999999',
  '9223372036854775807',
  '9223372036854775808',
  '99999999999999999999999',
  '-1',
];

final _hostileUrls = [
  for (final name in _badEscapes) ..._shapes(name),
  for (final port in _badPorts) ...[
    'https://a.example:$port',
    'https://a.example:$port/x.png',
    'https://a.example:$port/$_hash.png',
  ],
];

final _png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);

/// Everything that reads a URL a note or profile author wrote.
final _consumers = <String, Object? Function(String url)>{
  'blossomHash': (url) => blossomHash(Uri.parse(url)),
  'extensionOf': (url) => extensionOf(Uri.parse(url)),
  'isFetchableUrl': (url) => isFetchableUrl(Uri.parse(url)),
  'blossomUrls': (url) =>
      blossomUrls(['https://b.example'], _hash, extensionOf(Uri.parse(url))),
  'blossomUrls with the URL as a server': (url) =>
      blossomUrls([url, 'https://b.example'], _hash, '.png'),
  'blossomServersFromEvent': (url) => blossomServersFromEvent(
    fakeEvent(
      kind: 10063,
      tags: [
        ['server', url],
      ],
    ),
  ),
  'noteMedia': (url) => noteMedia('look $url', const []),
  'noteMedia with imeta': (url) => noteMedia(url, [
    ['imeta', 'url $url', 'm image/jpeg', 'x $_hash', 'fallback $url'],
  ]),
  'nostrPostFromEvent': (url) =>
      nostrPostFromEvent(fakeEvent(content: 'look $url')),
  'profileImageSource': profileImageSource,
  'imageFileName': (url) => imageFileName(url, _png),
};

void main() {
  group('a URL with hostile percent-escapes', () {
    for (final entry in _consumers.entries) {
      test('does not make ${entry.key} throw', () {
        for (final url in _hostileUrls) {
          expect(() => entry.value(url), returnsNormally, reason: url);
        }
      });
    }

    test('does not make a source with a hash and servers throw', () async {
      for (final url in _hostileUrls) {
        final source = MediaSource(
          url: url,
          sha256: _hash,
          fallbackUrls: [url],
          serverLookup: () async => [url, 'https://blossom.example'],
        );

        await expectLater(
          source.fetch((uri) async => throw const HttpException('down')),
          throwsA(isA<HttpException>()),
          reason: url,
        );
      }
    });

    test('is sent as written, not decoded, when it is fetched', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      server.listen((request) {
        paths.add(request.uri.path);
        request.response
          ..add([1, 2, 3])
          ..close();
      });

      final bytes = await fetchImageBytes(
        Uri.parse('http://127.0.0.1:${server.port}/x/%80/Caf%E9.png'),
        clientFactory: _realClient,
      );

      expect(bytes, [1, 2, 3]);
      expect(paths, ['/x/%80/Caf%E9.png']);
    });
  });

  group('noteMedia', () {
    test('keeps an image whose name is not valid UTF-8, without a hash', () {
      final media = noteMedia('look https://a.example/Caf%E9.jpg', const []);

      expect(media.map((m) => m.url), ['https://a.example/Caf%E9.jpg']);
      expect(media.single.type, MediaType.image);
      expect(media.single.sha256, isNull);
    });

    test('reads the hash and type from the last segment alone', () {
      final media = noteMedia('https://a.example/x/%80/$_hash.png', const []);

      expect(media.single.type, MediaType.image);
      expect(media.single.sha256, _hash);
    });

    test('keeps looking after a link it cannot make sense of', () {
      final media = noteMedia(
        'https://a.example/%FF https://b.example/%ED%A0%80.png '
        'https://c.example/ok.jpg',
        const [],
      );

      expect(media.map((m) => m.url), [
        'https://b.example/%ED%A0%80.png',
        'https://c.example/ok.jpg',
      ]);
    });

    test('leaves a link with a port nothing could connect to as text', () {
      for (final port in _badPorts) {
        final content = 'look https://a.example:$port/x.png';

        expect(noteMedia(content, const []), isEmpty, reason: port);
        expect(nostrPostFromEvent(fakeEvent(content: content)).media, isEmpty);
      }
    });

    test('takes a type from imeta when the name says nothing', () {
      const url = 'https://a.example/%FF';

      final media = noteMedia(url, [
        ['imeta', 'url $url', 'm image/jpeg'],
      ]);

      expect(media.single.type, MediaType.image);
      expect(media.single.sha256, isNull);
    });
  });

  group('a note that links such a URL', () {
    test('still maps, with its text', () {
      final post = nostrPostFromEvent(
        fakeEvent(content: 'look https://a.example/%FF'),
      );

      expect(post.content, 'look https://a.example/%FF');
      expect(post.media, isEmpty);
    });

    test('does not cost the rest of its page', () async {
      // The ids are spelled out because the ones fakeEvent numbers by itself
      // are padded on the right: e1 and e10 come out as the same id, and
      // this page would lose posts to deduplication when it runs early.
      final repository = RelayPostRepository(
        relayUrls: {'wss://r'},
        client: InMemoryRelayClient([
          for (var i = 0; i < 29; i++)
            fakeEvent(
              id: 'a${i.toString().padLeft(2, '0')}',
              content: 'benign $i',
              createdAt: _at(i),
            ),
          fakeEvent(
            id: 'bff',
            content: 'look https://a.example/%FF',
            createdAt: _at(99),
          ),
        ]),
      );

      expect((await repository.fetchPage()).posts, hasLength(30));
    });

    test('does not hide the other replies in a thread', () async {
      final root = fakeEvent(id: '01', content: 'root', createdAt: _at(0));
      final tags = [
        ['e', root.id, '', 'root'],
      ];
      final repository = RelayThreadRepository(
        client: InMemoryRelayClient([
          root,
          fakeEvent(id: '02', content: 'nice', createdAt: _at(1), tags: tags),
          fakeEvent(
            id: '03',
            content: 'see https://a.example/%FF',
            createdAt: _at(2),
            tags: tags,
          ),
        ]),
        reactionsRepository: const NoReactions(),
      );

      final thread = await repository.fetchThread(root.id, {'wss://r'});

      expect(thread.replies, hasLength(2));
    });
  });

  group('a profile picture with such a URL', () {
    testWidgets('builds its avatar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FadeInAvatar(
            imageUrl: 'https://a.example/%FF',
            backgroundColor: Colors.blue,
            fallback: const Text('A'),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
