import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/blossom.dart';
import 'package:sputnik/nostr/relay_blossom_list_repository.dart';
import 'package:sputnik/nostr/relay_client.dart';
import 'package:sputnik/services/blossom_servers.dart';

import 'support/in_memory_relay_client.dart';

final _hash = 'ab' * 32;

void main() {
  group('blossomHash', () {
    test('reads the hash from the last path segment', () {
      for (final url in [
        'https://a.example/$_hash',
        'https://a.example/$_hash.png',
        'https://a.example/x/y/$_hash.webm',
        'https://a.example/${_hash.toUpperCase()}.jpg',
        'https://a.example/$_hash.jpg?w=1#x',
      ]) {
        expect(blossomHash(Uri.parse(url)), _hash, reason: url);
      }
    });

    test('is null unless the whole name is a hash', () {
      for (final url in [
        'https://a.example/photo.jpg',
        'https://a.example/x$_hash.jpg',
        'https://a.example/$_hash/photo.jpg',
        'https://a.example/${'a' * 63}',
        'https://a.example/${'a' * 65}',
        'https://a.example/${'g' * 64}',
        'https://a.example/',
        'https://a.example',
      ]) {
        expect(blossomHash(Uri.parse(url)), isNull, reason: url);
      }
    });

    test('reads the hash whatever the segments before it hold', () {
      expect(
        blossomHash(Uri.parse('https://a.example/%FF/x%80/$_hash.png')),
        _hash,
      );
    });

    test('is null, not an error, when the last segment is not UTF-8', () {
      for (final url in [
        'https://a.example/%FF',
        'https://a.example/$_hash%FF',
        'https://a.example/Caf%E9',
        'https://a.example/%E2%82',
      ]) {
        expect(blossomHash(Uri.parse(url)), isNull, reason: url);
      }
    });
  });

  test('extensionOf returns the extension with its dot, or nothing', () {
    expect(extensionOf(Uri.parse('https://a.example/$_hash.png')), '.png');
    expect(extensionOf(Uri.parse('https://a.example/$_hash')), '');
    expect(extensionOf(Uri.parse('https://a.example/.hidden')), '');
    expect(extensionOf(Uri.parse('https://a.example/')), '');
  });

  test('extensionOf returns only a short alphanumeric extension', () {
    for (final (url, expected) in [
      ('https://a.example/x.JPEG', '.JPEG'),
      ('https://a.example/x.tar.gz', '.gz'),
      ('https://a.example/x.torrent', ''),
      ('https://a.example/x.png%3Fa%3D1', ''),
      ('https://a.example/x.%2Fadmin', ''),
      ('https://a.example/x.%E2%82', ''),
      ('https://a.example/x.', ''),
    ]) {
      expect(extensionOf(Uri.parse(url)), expected, reason: url);
    }
  });

  test('extensionOf reads the last segment whatever precedes it', () {
    expect(extensionOf(Uri.parse('https://a.example/x/%80/y.jpg')), '.jpg');
    expect(extensionOf(Uri.parse('https://a.example/Caf%E9.jpg')), '.jpg');
    expect(
      () => extensionOf(Uri.parse('https://a.example/%FF')),
      returnsNormally,
    );
  });

  group('isFetchableUrl', () {
    test('takes an https URL with a host, no credentials and a real port', () {
      for (final url in [
        'https://a.example',
        'https://a.example/x.png',
        'https://a.example:8443/x.png',
        'https://a.example:65535',
        'https://[2001:db8::1]:8443/x.png',
      ]) {
        expect(isFetchableUrl(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('refuses other schemes, no host and credentials', () {
      for (final url in [
        'http://a.example/x.png',
        'file:///x.png',
        '//a.example/x.png',
        'https:///x.png',
        'https://u:p@a.example/x.png',
      ]) {
        expect(isFetchableUrl(Uri.parse(url)), isFalse, reason: url);
      }
      expect(isFetchableUrl(null), isFalse);
    });

    test('refuses a port no connection could use, without throwing', () {
      for (final port in [
        '65536',
        '99999999999',
        '9223372036854775807',
        // Too big for an int, so that reading the port throws.
        '9223372036854775808',
        '99999999999999999999999',
        '-1',
      ]) {
        final uri = Uri.tryParse('https://a.example:$port/x.png');

        expect(() => isFetchableUrl(uri), returnsNormally, reason: port);
        expect(isFetchableUrl(uri), isFalse, reason: port);
      }
    });
  });

  group('blossomServersFromEvent', () {
    test('lists the https servers in order, as origins', () {
      final event = fakeEvent(
        kind: 10063,
        tags: [
          ['server', 'https://one.example'],
          ['server', 'https://two.example/'],
          ['server', 'https://three.example:8443/some/path'],
        ],
      );

      expect(blossomServersFromEvent(event), [
        'https://one.example',
        'https://two.example',
        'https://three.example:8443',
      ]);
    });

    test('keeps the brackets of an IPv6 server, so its URLs can be built', () {
      final event = fakeEvent(
        kind: 10063,
        tags: [
          ['server', 'https://[2001:db8::1]:8443/blobs'],
          ['server', 'https://[2001:db8::2]'],
          ['server', 'HTTPS://One.Example:443'],
        ],
      );

      final servers = blossomServersFromEvent(event);

      expect(servers, [
        'https://[2001:db8::1]:8443',
        'https://[2001:db8::2]',
        'https://one.example',
      ]);
      expect(blossomUrls(servers, _hash, '.png'), [
        Uri.parse('https://[2001:db8::1]:8443/$_hash.png'),
        Uri.parse('https://[2001:db8::2]/$_hash.png'),
        Uri.parse('https://one.example/$_hash.png'),
      ]);
    });

    test('drops plain http, credentials, junk, and other tags', () {
      final event = fakeEvent(
        kind: 10063,
        tags: [
          ['server', 'http://plain.example'],
          ['server', 'https://user:pw@creds.example'],
          ['server', 'not a url'],
          ['server'],
          ['relay', 'https://wrongtag.example'],
          ['server', 'https://ok.example'],
        ],
      );

      expect(blossomServersFromEvent(event), ['https://ok.example']);
    });

    test('drops a server whose port nothing could connect to', () {
      final event = fakeEvent(
        kind: 10063,
        tags: [
          ['server', 'https://big.example:99999999999999999999999'],
          ['server', 'https://past.example:65536'],
          ['server', 'https://negative.example:-1'],
          ['server', 'https://ok.example:8443'],
        ],
      );

      expect(blossomServersFromEvent(event), ['https://ok.example:8443']);
    });

    test('lists a repeated server once and caps the list', () {
      final event = fakeEvent(
        kind: 10063,
        tags: [
          ['server', 'https://a.example'],
          ['server', 'https://a.example/'],
          for (var i = 0; i < 20; i++) ['server', 'https://s$i.example'],
        ],
      );

      final servers = blossomServersFromEvent(event);

      expect(servers.first, 'https://a.example');
      expect(servers, hasLength(maxBlossomServers));
      expect(servers.toSet(), hasLength(maxBlossomServers));
    });
  });

  test('blossomUrls builds each server URL from the hash and extension', () {
    expect(
      blossomUrls(
        ['https://a.example', 'https://b.example:8443'],
        _hash,
        '.png',
      ),
      [
        Uri.parse('https://a.example/$_hash.png'),
        Uri.parse('https://b.example:8443/$_hash.png'),
      ],
    );
    expect(blossomUrls(['https://a.example'], _hash, ''), [
      Uri.parse('https://a.example/$_hash'),
    ]);
  });

  group('blossomUrls from untrusted parts', () {
    const server = 'https://a.example';
    final bare = [Uri.parse('$server/$_hash')];

    test('keeps a short alphanumeric extension', () {
      for (final extension in ['.png', '.JPG', '.webm', '.m4v', '.a1b2c']) {
        expect(blossomUrls([server], _hash, extension), [
          Uri.parse('$server/$_hash$extension'),
        ], reason: extension);
      }
    });

    test('leaves off anything else, so it cannot reshape the request', () {
      for (final extension in [
        '.png?a=1',
        '.png#x',
        './admin',
        '.png/../x',
        '.png%3Fa',
        '.%2F',
        '.toolong',
        '.é',
        '. png',
        '.',
        '..',
        'png',
        '/x',
      ]) {
        expect(
          blossomUrls([server], _hash, extension),
          bare,
          reason: extension,
        );
      }
    });

    test('always asks for one path segment, with no query', () {
      for (final extension in ['.png?a=1', './../admin', '.png\r\nX: y', '#']) {
        for (final url in blossomUrls(
          [server, 'https://b.example:8443'],
          _hash,
          extension,
        )) {
          expect(url.pathSegments, hasLength(1), reason: extension);
          expect(url.pathSegments.single, startsWith(_hash));
          expect(url.hasQuery, isFalse, reason: extension);
          expect(url.hasFragment, isFalse, reason: extension);
        }
      }
    });

    test('asks for nothing unless the hash is 64 hex digits', () {
      for (final hash in [
        '',
        '../x',
        'ab' * 31,
        'ab' * 33,
        '${'ab' * 31}g1',
        '${'ab' * 31}a/',
        '${'ab' * 31}a?',
      ]) {
        expect(blossomUrls([server], hash, '.png'), isEmpty, reason: hash);
      }
      expect(blossomUrls([server], _hash.toUpperCase(), ''), bare);
    });

    test('skips a server with an unusable port, and still asks the rest', () {
      // Rebuilding a URL whose port is too big for an int throws.
      expect(
        blossomUrls(
          [
            'https://big.example:99999999999999999999999',
            'https://past.example:65536',
            'https://ok.example',
          ],
          _hash,
          '.png',
        ),
        [Uri.parse('https://ok.example/$_hash.png')],
      );
    });

    test('uses only the origin of a server, and skips what is not one', () {
      expect(
        blossomUrls(
          [
            'http://plain.example',
            'https://user:pw@creds.example',
            'not a url',
            '',
            'https://[bad',
            'https://a b:x',
            'https://ok.example/some/path?x=1#frag',
            'https://[2001:db8::1]:8443',
          ],
          _hash,
          '.png',
        ),
        [
          Uri.parse('https://ok.example/$_hash.png'),
          Uri.parse('https://[2001:db8::1]:8443/$_hash.png'),
        ],
      );
    });
  });

  group('RelayBlossomListRepository', () {
    test('reads the newest kind 10063 list by that author', () async {
      final client = InMemoryRelayClient([
        fakeEvent(
          pubkey: 'aa',
          kind: 10063,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000000),
          tags: [
            ['server', 'https://old.example'],
          ],
        ),
        fakeEvent(
          pubkey: 'aa',
          kind: 10063,
          createdAt: DateTime.fromMillisecondsSinceEpoch(2000000),
          tags: [
            ['server', 'https://new.example'],
          ],
        ),
        fakeEvent(
          pubkey: 'bb',
          kind: 10063,
          tags: [
            ['server', 'https://other-author.example'],
          ],
        ),
      ]);
      RelayClient.instance = client;

      final servers = await RelayBlossomListRepository(client: client)
          .fetchServers('aa'.padRight(64, '0'), {'wss://r.example'});

      expect(servers, ['https://new.example']);
    });
  });

  group('blossomServersFor', () {
    final author = 'aa'.padRight(64, '0');

    setUp(clearBlossomServerCache);

    test('remembers a found list instead of asking relays again', () async {
      final client = InMemoryRelayClient([
        fakeEvent(
          pubkey: 'aa',
          kind: 10063,
          tags: [
            ['server', 'https://one.example'],
          ],
        ),
      ]);
      RelayClient.instance = client;

      await blossomServersFor(author, {'wss://r'});
      final again = await blossomServersFor(author, {'wss://r'});

      expect(again, ['https://one.example']);
      expect(client.queries, hasLength(1));
    });

    test('does not remember an empty answer', () async {
      final client = InMemoryRelayClient();
      RelayClient.instance = client;

      await blossomServersFor(author, {'wss://r'});
      await blossomServersFor(author, {'wss://r'});

      expect(client.queries, hasLength(2));
    });

    test('shares one query between simultaneous lookups', () async {
      final client = InMemoryRelayClient();
      RelayClient.instance = client;

      await Future.wait([
        blossomServersFor(author, {'wss://r'}),
        blossomServersFor(author, {'wss://r'}),
      ]);

      expect(client.queries, hasLength(1));
    });
  });
}
