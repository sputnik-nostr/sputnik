import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';

import 'support/in_memory_relay_client.dart';

// A relay pool where only some of the queried relays answer.
class _PartlyAnswering extends InMemoryRelayClient {
  _PartlyAnswering(super.events, {required this.answered});

  int answered;

  @override
  Future<RelayQueryResult> queryWithStatus(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => RelayQueryResult(
    events: await query(relayUrls, filter),
    answeredRelays: answered,
    queriedRelays: relayUrls.length,
  );
}

void main() {
  final me = generateNostrKeyPair();
  final alice = 'aa' * 32;
  final bob = 'bb' * 32;
  final relays = {for (var i = 0; i < 4; i++) 'wss://r$i.example.com'};

  setUp(resetKnownContactLists);

  NostrEvent contactList(List<String> follows, {required Duration age}) {
    return signEvent(
      seckeyHex: me.privateKeyHex,
      pubkeyHex: me.publicKeyHex,
      kind: 3,
      tags: [
        for (final pubkey in follows) ['p', pubkey],
      ],
      content: '',
      createdAt: DateTime.now().subtract(age),
    );
  }

  Future<Map<String, RelayPublishResult>> follow(
    RelayClient client,
    String target,
  ) async {
    final outcome = await RelayContactsRepository(client: client)
        .applyFollowChanges(
          seckeyHex: me.privateKeyHex,
          myPubkeyHex: me.publicKeyHex,
          changes: {target: true},
          relayUrls: relays,
        );
    return outcome.results;
  }

  test('one relay of four answering is not enough to publish', () async {
    final client = _PartlyAnswering([
      contactList([alice], age: const Duration(days: 30)),
    ], answered: 1);

    final results = await follow(client, bob);

    expect(results, isEmpty);
    expect(client.published, isEmpty);
  });

  test('exactly half of the relays answering is not enough', () async {
    final client = _PartlyAnswering([
      contactList([alice], age: const Duration(days: 30)),
    ], answered: 2);

    await follow(client, bob);

    expect(client.published, isEmpty);
  });

  test('a majority answering with a list is enough', () async {
    final client = _PartlyAnswering([
      contactList([alice], age: const Duration(days: 30)),
    ], answered: 3);

    await follow(client, bob);

    expect(client.published.single.tags, [
      ['p', alice],
      ['p', bob],
    ]);
  });

  test('no relay answering never publishes a fresh list', () async {
    final client = _PartlyAnswering([], answered: 0);

    await follow(client, bob);

    expect(client.published, isEmpty);
  });

  test('every relay answering with nothing starts a fresh list', () async {
    final client = _PartlyAnswering([], answered: 4);

    await follow(client, bob);

    expect(client.published.single.tags, [
      ['p', bob],
    ]);
  });

  test('a lagging relay cannot roll back a list published earlier', () async {
    final older = contactList([alice], age: const Duration(days: 30));
    final client = _PartlyAnswering([older], answered: 4);

    await follow(client, bob);
    expect(client.published, hasLength(1));

    // The relays now answer with the pre-follow copy, as a laggard would.
    client.events
      ..clear()
      ..add(older);
    final results = await follow(client, 'cc' * 32);

    expect(results, isEmpty);
    expect(client.published, hasLength(1));
  });

  test(
    'a list published earlier that no relay returns is not dropped',
    () async {
      final client = _PartlyAnswering([
        contactList([alice], age: const Duration(days: 30)),
      ], answered: 4);

      await follow(client, bob);
      client.events.clear();
      final results = await follow(client, 'cc' * 32);

      expect(results, isEmpty);
      expect(client.published, hasLength(1));
    },
  );

  test('once the relays catch up the next change goes through', () async {
    final client = _PartlyAnswering([
      contactList([alice], age: const Duration(days: 30)),
    ], answered: 4);

    await follow(client, bob);
    await follow(client, 'cc' * 32);

    expect(client.published, hasLength(2));
    expect(client.published.last.tags.map((t) => t[1]), [
      alice,
      bob,
      'cc' * 32,
    ]);
  });
}
