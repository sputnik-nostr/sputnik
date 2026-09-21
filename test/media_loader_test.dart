import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/services/media_loader.dart';

class _RealHttp extends HttpOverrides {}

// The test binding replaces every HttpClient with one that answers 400.
HttpClient _realClient() =>
    HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  late HttpServer server;
  late Uri base;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDown(() => server.close(force: true));

  void serve(void Function(HttpRequest request) handler) {
    server.listen((request) {
      handler(request);
    });
  }

  group('fetchImageBytes', () {
    test('returns the body of a 200 response', () async {
      serve((request) {
        request.response
          ..add([1, 2, 3])
          ..close();
      });

      final bytes = await fetchImageBytes(
        base.resolve('/a.png'),
        clientFactory: _realClient,
      );

      expect(bytes, [1, 2, 3]);
    });

    test('refuses a non-200 status', () async {
      serve((request) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      });

      expect(
        fetchImageBytes(base, clientFactory: _realClient),
        throwsA(isA<HttpException>()),
      );
    });

    test('refuses a declared length over the cap', () async {
      serve((request) {
        request.response
          ..contentLength = 100
          ..add(Uint8List(100))
          ..close();
      });

      expect(
        fetchImageBytes(base, maxBytes: 10, clientFactory: _realClient),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });

    test('refuses a streamed body that outgrows the cap', () async {
      serve((request) async {
        request.response.headers.chunkedTransferEncoding = true;
        try {
          for (var i = 0; i < 5; i++) {
            request.response.add(Uint8List(10));
            await request.response.flush();
          }
          await request.response.close();
        } catch (_) {
          // The client hangs up once it hits the cap.
        }
      });

      expect(
        fetchImageBytes(base, maxBytes: 25, clientFactory: _realClient),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });

    test('follows a redirect', () async {
      serve((request) {
        if (request.uri.path == '/start') {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, '/final')
            ..close();
        } else {
          request.response
            ..add([9])
            ..close();
        }
      });

      final bytes = await fetchImageBytes(
        base.resolve('/start'),
        clientFactory: _realClient,
      );

      expect(bytes, [9]);
    });

    test('gives up on a redirect loop', () async {
      var requests = 0;
      serve((request) {
        requests++;
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/again')
          ..close();
      });

      await expectLater(
        fetchImageBytes(base, clientFactory: _realClient),
        throwsA(isA<HttpException>()),
      );
      expect(requests, lessThanOrEqualTo(5));
    });
  });

  group('downloadMedia', () {
    String hashOf(List<int> bytes) => crypto.sha256.convert(bytes).toString();

    test('accepts bytes that match the expected hash', () async {
      final body = List.generate(300, (i) => i % 256);
      serve((request) {
        request.response
          ..add(body)
          ..close();
      });

      final bytes = await fetchImageBytes(
        base,
        sha256: hashOf(body),
        clientFactory: _realClient,
      );

      expect(bytes, body);
    });

    test('refuses bytes that do not match the expected hash', () async {
      serve((request) {
        request.response
          ..add([1, 2, 3])
          ..close();
      });

      await expectLater(
        fetchImageBytes(
          base,
          sha256: hashOf([9, 9, 9]),
          clientFactory: _realClient,
        ),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            contains('Hash mismatch'),
          ),
        ),
      );
    });

    test('hashes a body that arrives in several chunks', () async {
      final parts = [
        [1, 2, 3],
        [4, 5],
        [6, 7, 8, 9],
      ];
      serve((request) async {
        request.response.headers.chunkedTransferEncoding = true;
        for (final part in parts) {
          request.response.add(part);
          await request.response.flush();
        }
        await request.response.close();
      });

      final bytes = await fetchImageBytes(
        base,
        sha256: hashOf([for (final part in parts) ...part]),
        clientFactory: _realClient,
      );

      expect(bytes, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('reports progress against the declared length', () async {
      serve((request) {
        request.response
          ..contentLength = 6
          ..add([1, 2, 3, 4, 5, 6])
          ..close();
      });
      final seen = <(int, int?)>[];

      await downloadMedia(
        base,
        maxBytes: 100,
        onChunk: (_) {},
        onProgress: (received, total) => seen.add((received, total)),
        clientFactory: _realClient,
      );

      expect(seen.last, (6, 6));
    });

    test('can be cancelled while the host is silent', () async {
      serve((request) {
        // Headers and one byte, then nothing.
        request.response
          ..contentLength = 100
          ..add([0])
          ..flush();
      });
      final canceller = DownloadCanceller();
      final done = downloadMedia(
        base,
        maxBytes: 1000,
        onChunk: (_) {},
        canceller: canceller,
        clientFactory: _realClient,
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      canceller.cancel();

      await expectLater(done, throwsA(isA<DownloadCancelled>()));
    });
  });

  group('MediaSource.fetch', () {
    final hash = 'ab' * 32;
    final primary = 'https://one.example/$hash.png';

    // Fails for every URL in [failing]; otherwise returns the URL fetched.
    Future<String> Function(Uri) attempts(
      List<String> log, {
      Set<String> failing = const {},
    }) {
      return (uri) async {
        log.add(uri.toString());
        if (failing.contains(uri.toString())) throw HttpException('no $uri');
        return uri.toString();
      };
    }

    test('stops at the first URL that works', () async {
      final log = <String>[];
      var lookups = 0;
      final source = MediaSource(
        url: primary,
        sha256: hash,
        fallbackUrls: const ['https://two.example/a.png'],
        serverLookup: () async {
          lookups++;
          return const [];
        },
      );

      final got = await source.fetch(attempts(log));

      expect(got, primary);
      expect(log, [primary]);
      expect(lookups, 0);
    });

    test('tries the listed fallbacks in order after the URL fails', () async {
      final log = <String>[];
      final source = MediaSource(
        url: primary,
        fallbackUrls: const [
          'https://two.example/a.png',
          'https://three.example/a.png',
        ],
      );

      final got = await source.fetch(
        attempts(log, failing: {primary, 'https://two.example/a.png'}),
      );

      expect(got, 'https://three.example/a.png');
      expect(log, [primary, 'https://two.example/a.png', got]);
    });

    test('asks for Blossom servers only after everything else fails', () async {
      final log = <String>[];
      final source = MediaSource(
        url: primary,
        sha256: hash,
        fallbackUrls: const ['https://two.example/a.png'],
        serverLookup: () async => ['https://blossom.example'],
      );

      final got = await source.fetch(
        attempts(log, failing: {primary, 'https://two.example/a.png'}),
      );

      expect(got, 'https://blossom.example/$hash.png');
      expect(log, [
        primary,
        'https://two.example/a.png',
        'https://blossom.example/$hash.png',
      ]);
    });

    test('keeps the original file extension on the Blossom URL', () async {
      final log = <String>[];
      final source = MediaSource(
        url: 'https://one.example/$hash',
        sha256: hash,
        serverLookup: () async => ['https://blossom.example'],
      );

      await source.fetch(attempts(log, failing: {'https://one.example/$hash'}));

      expect(log.last, 'https://blossom.example/$hash');
    });

    test('never asks for servers when there is no hash to look up', () async {
      var lookups = 0;
      final source = MediaSource(
        url: 'https://one.example/a.png',
        serverLookup: () async {
          lookups++;
          return ['https://blossom.example'];
        },
      );

      await expectLater(
        source.fetch((uri) async => throw HttpException('down')),
        throwsA(isA<HttpException>()),
      );
      expect(lookups, 0);
    });

    test('does not retry a URL it has already tried', () async {
      final log = <String>[];
      final source = MediaSource(
        url: primary,
        sha256: hash,
        fallbackUrls: [primary],
        serverLookup: () async => ['https://one.example'],
      );

      await expectLater(
        source.fetch(attempts(log, failing: {primary})),
        throwsA(isA<HttpException>()),
      );

      expect(log, [primary]);
    });

    test('reports the first failure when every source fails', () async {
      final source = MediaSource(
        url: primary,
        sha256: hash,
        fallbackUrls: const ['https://two.example/a.png'],
        serverLookup: () async => ['https://blossom.example'],
      );

      await expectLater(
        source.fetch((uri) async => throw HttpException('no $uri')),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            'no $primary',
          ),
        ),
      );
    });

    test(
      'a failing server lookup still ends with the original error',
      () async {
        final source = MediaSource(
          url: primary,
          sha256: hash,
          serverLookup: () async => throw StateError('relays down'),
        );

        await expectLater(
          source.fetch((uri) async => throw HttpException('no $uri')),
          throwsA(isA<HttpException>()),
        );
      },
    );

    test('a cancelled download stops the search immediately', () async {
      final log = <String>[];
      final source = MediaSource(
        url: primary,
        fallbackUrls: const ['https://two.example/a.png'],
      );

      await expectLater(
        source.fetch((uri) async {
          log.add(uri.toString());
          throw const DownloadCancelled();
        }),
        throwsA(isA<DownloadCancelled>()),
      );

      expect(log, [primary]);
    });
  });

  group('redirectTarget', () {
    final https = Uri.parse('https://a.example/x/y.png');
    final http = Uri.parse('http://a.example/x/y.png');

    test('resolves a relative location against the current URL', () {
      expect(
        redirectTarget(https, '/z.png'),
        Uri.parse('https://a.example/z.png'),
      );
    });

    test('follows a move to another https host', () {
      expect(
        redirectTarget(https, 'https://b.example/y.png'),
        Uri.parse('https://b.example/y.png'),
      );
    });

    test('never downgrades https to http', () {
      expect(redirectTarget(https, 'http://b.example/y.png'), isNull);
    });

    test('allows http to upgrade to https', () {
      expect(redirectTarget(http, 'https://b.example/y.png'), isNotNull);
    });

    test('refuses other schemes, missing hosts, and credentials', () {
      expect(redirectTarget(https, null), isNull);
      expect(redirectTarget(https, 'ftp://b.example/y.png'), isNull);
      expect(redirectTarget(https, 'file:///etc/passwd'), isNull);
      expect(redirectTarget(https, 'https:///y.png'), isNull);
      expect(redirectTarget(https, 'https://u:p@b.example/y.png'), isNull);
    });
  });

  group('BoundedNetworkImage', () {
    test('is equal to another provider for the same URL', () {
      expect(
        BoundedNetworkImage(MediaSource(url: 'https://a.example/x.png')),
        BoundedNetworkImage(MediaSource(url: 'https://a.example/x.png')),
      );
      expect(
        BoundedNetworkImage(MediaSource(url: 'https://a.example/x.png')),
        isNot(BoundedNetworkImage(MediaSource(url: 'https://a.example/y.png'))),
      );
    });

    testWidgets('loads and decodes an image', (tester) async {
      await tester.runAsync(() async {
        serve((request) {
          request.response
            ..add(_onePixelPng)
            ..close();
        });

        final provider = BoundedNetworkImage(
          MediaSource(url: base.resolve('/a.png').toString()),
          clientFactory: _realClient,
        );
        final loaded = Completer<ImageInfo>();
        provider
            .resolve(ImageConfiguration.empty)
            .addListener(
              ImageStreamListener(
                (info, _) => loaded.complete(info),
                onError: (error, _) => loaded.completeError(error),
              ),
            );

        final info = await loaded.future.timeout(const Duration(seconds: 5));
        expect(info.image.width, 1);
        expect(info.image.height, 1);
      });
    });
    testWidgets('falls back to the next source when the first is down', (
      tester,
    ) async {
      await tester.runAsync(() async {
        serve((request) {
          if (request.uri.path == '/dead.png') {
            request.response
              ..statusCode = HttpStatus.notFound
              ..close();
          } else {
            request.response
              ..add(_onePixelPng)
              ..close();
          }
        });

        final provider = BoundedNetworkImage(
          MediaSource(
            url: base.resolve('/dead.png').toString(),
            fallbackUrls: [base.resolve('/alive.png').toString()],
          ),
          clientFactory: _realClient,
        );
        final loaded = Completer<ImageInfo>();
        provider
            .resolve(ImageConfiguration.empty)
            .addListener(
              ImageStreamListener(
                (info, _) => loaded.complete(info),
                onError: (error, _) => loaded.completeError(error),
              ),
            );

        final info = await loaded.future.timeout(const Duration(seconds: 5));
        expect(info.image.width, 1);
      });
    });

    testWidgets('refuses an image whose bytes do not match its hash', (
      tester,
    ) async {
      await tester.runAsync(() async {
        serve((request) {
          request.response
            ..add(_onePixelPng)
            ..close();
        });

        final provider = BoundedNetworkImage(
          MediaSource(
            url: base.resolve('/a.png').toString(),
            sha256: 'ab' * 32,
          ),
          clientFactory: _realClient,
        );
        final failed = Completer<Object>();
        provider
            .resolve(ImageConfiguration.empty)
            .addListener(
              ImageStreamListener(
                (info, _) => failed.completeError(StateError('loaded')),
                onError: (error, _) => failed.complete(error),
              ),
            );

        final error = await failed.future.timeout(const Duration(seconds: 5));
        expect(error, isA<HttpException>());
      });
    });
  });
}
