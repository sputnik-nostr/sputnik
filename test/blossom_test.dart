import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/blossom.dart';
import 'package:sputnik/nostr/relay_blossom_list_repository.dart';
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
  });

  test('extensionOf returns the extension with its dot, or nothing', () {
    expect(extensionOf(Uri.parse('https://a.example/$_hash.png')), '.png');
    expect(extensionOf(Uri.parse('https://a.example/$_hash')), '');
    expect(extensionOf(Uri.parse('https://a.example/.hidden')), '');
    expect(extensionOf(Uri.parse('https://a.example/')), '');
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

      final servers = await RelayBlossomListRepository(client: client)
          .fetchServers('aa'.padRight(64, '0'), {'wss://r.example'});

      expect(servers, ['https://new.example']);
    });
  });

  group('blossomServersFor', () {
    final author = 'aa'.padRight(64, '0');

    setUp(resetBlossomServerCache);

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

      await blossomServersFor(author, {'wss://r'}, client: client);
      final again = await blossomServersFor(author, {
        'wss://r',
      }, client: client);

      expect(again, ['https://one.example']);
      expect(client.queries, hasLength(1));
    });

    test('does not remember an empty answer', () async {
      final client = InMemoryRelayClient();

      await blossomServersFor(author, {'wss://r'}, client: client);
      await blossomServersFor(author, {'wss://r'}, client: client);

      expect(client.queries, hasLength(2));
    });

    test('shares one query between simultaneous lookups', () async {
      final client = InMemoryRelayClient();

      await Future.wait([
        blossomServersFor(author, {'wss://r'}, client: client),
        blossomServersFor(author, {'wss://r'}, client: client),
      ]);

      expect(client.queries, hasLength(1));
    });
  });
}
