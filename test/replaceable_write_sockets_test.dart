import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/nostr/relay_connection_pool.dart';

import 'support/mock_relay.dart';
import 'support/relay_states.dart';

// The matrix of replaceable_write_matrix_test.dart rests on how the pool counts
// relays as answered. This runs the same decisions over the real pool and real
// WebSockets, against relays on 127.0.0.1 that are in each of those states.

/// A user, with the real list and the stale copy of it that relays can hold.
typedef _User = ({NostrKeyPair me, NostrEvent real, NostrEvent stale});

/// What one cell came to.
typedef _Outcome = ({
  String decision,
  bool sent,

  /// The list shown, as text, when it was asked for.
  String? shown,
  String? counts,
});

void main() {
  const client = RelayClient();
  final newcomer = 'ee' * 32;

  setUp(resetKnownContactLists);
  tearDown(() => RelayConnectionPool.instance.retainOnly(const {}));

  _User newUser() {
    final me = generateNostrKeyPair();
    NostrEvent list(List<String> people, Duration age) => signEvent(
      secretKey: SecretKey.fromHex(me.privateKeyHex),
      pubkeyHex: me.publicKeyHex,
      kind: 3,
      tags: [
        for (final person in people) ['p', person * 32],
      ],
      content: '',
      createdAt: DateTime.now().subtract(age),
    );
    return (
      me: me,
      real: list(realFollows, const Duration(days: 1)),
      stale: list(staleFollows, const Duration(days: 60)),
    );
  }

  /// Relays in the states of [cells]; those that cooled down have failed once
  /// and are reachable again.
  Future<List<MockRelay>> startRelays(Composition cells, _User user) async {
    final relays = [
      for (final state in RelayState.values)
        for (var i = 0; i < cells[state]!; i++)
          await MockRelay.start(state, switch (state) {
            RelayState.stale => [user.stale],
            RelayState.empty => const [],
            _ => [user.real],
          }),
    ];
    final cooling = [
      for (final relay in relays)
        if (relay.state == RelayState.cooling) relay,
    ];
    await Future.wait([
      for (final relay in cooling)
        client.queryWithStatus({relay.url}, const NostrFilter(kinds: [3])),
    ]);
    for (final relay in cooling) {
      relay.refusing = false;
    }
    return relays;
  }

  /// One cell: a change of the list, and optionally the list shown, against
  /// relays in [cells], after seeing the real list if [seen].
  Future<_Outcome> run(
    Composition cells, {
    required bool seen,
    required bool unfollow,
    required bool shown,
  }) async {
    final user = newUser();
    if (seen) {
      noteOwnContactList(
        user.me.publicKeyHex,
        user.real.createdAt,
        realFollows.length,
      );
    }
    final writeOn = await startRelays(cells, user);
    final shownOn = shown ? await startRelays(cells, user) : <MockRelay>[];
    try {
      final repository = RelayContactsRepository(client: client);
      final list = shown
          ? await repository.fetchFollowingOrNull(user.me.publicKeyHex, {
              for (final relay in shownOn) relay.url,
            })
          : null;
      final update = await repository.applyFollowChanges(
        secretKey: SecretKey.fromHex(user.me.privateKeyHex),
        myPubkeyHex: user.me.publicKeyHex,
        changes: unfollow ? {realFollows.first * 32: false} : {newcomer: true},
        relayUrls: {for (final relay in writeOn) relay.url},
      );
      return (
        decision: describeUpdate(update),
        sent: writeOn.any((relay) => relay.received.isNotEmpty),
        shown: shown ? '$list' : null,
        counts: switch (update) {
          FollowNeedsConfirmation(
            :final answeredRelays,
            :final queriedRelays,
          ) ||
          FollowRefused(
            :final answeredRelays,
            :final queriedRelays,
          ) => '$answeredRelays/$queriedRelays',
          FollowPublished() => null,
        },
      );
    } finally {
      await Future.wait([
        for (final relay in [...shownOn, ...writeOn])
          relay.server.close(force: true),
      ]);
    }
  }

  /// What a cell should come to, as `describeUpdate`, and the list shown.
  void check(
    Composition cells,
    _Outcome got,
    List<String> wrong, {
    required bool seen,
    required bool unfollow,
  }) {
    final want = expectedDecision(cells, seen: seen, unfollow: unfollow);
    final answered = answeredIn(cells);
    final relays = relaysIn(cells);
    final wantShown = switch (want.base) {
      Base.real => [for (final person in realFollows) person * 32],
      Base.stale => [for (final person in staleFollows) person * 32],
      Base.none => answered == relays ? <String>[] : null,
    };
    final wantCounts = want.decision == Decision.publish
        ? null
        : '$answered/$relays';
    if (got.decision != want.text ||
        got.sent != (want.decision == Decision.publish) ||
        got.counts != wantCounts ||
        // The list shown does not depend on what was seen, or on the change.
        (got.shown != null && got.shown != '$wantShown')) {
      wrong.add(
        '${nameOf(cells)}: ${got.decision} (sent ${got.sent}, counts '
        '${got.counts}, shown ${got.shown}), expected ${want.text}',
      );
    }
  }

  for (final seen in [false, true]) {
    for (final unfollow in [false, true]) {
      final label =
          '${unfollow ? 'an unfollow' : 'a follow'}, '
          '${seen ? 'after' : 'without'} seeing the real list';

      test('$label: the real pool counts relays as the decision table '
          'assumes', () async {
        final cases = [
          for (final relays in [1, 2, 3]) ...compositions(relays),
        ];
        final wrong = <String>[];
        // A few cells at a time, so that no answer waits on a busy machine.
        for (var from = 0; from < cases.length; from += 8) {
          final batch = cases.sublist(from, (from + 8).clamp(0, cases.length));
          final results = await Future.wait(
            batch.map(
              (cells) => run(
                cells,
                seen: seen,
                unfollow: unfollow,
                // The list shown is asked once, with the first change.
                shown: !seen && !unfollow,
              ),
            ),
          );
          for (var i = 0; i < batch.length; i++) {
            check(batch[i], results[i], wrong, seen: seen, unfollow: unfollow);
          }
          // The relays of this batch are gone, and so should the sockets be.
          await RelayConnectionPool.instance.retainOnly(const {});
        }
        expect(wrong, isEmpty);
      });
    }
  }

  test('a relay that stays silent is counted as asked but not as '
      'answered', () async {
    // Silent for real: the socket stays open and the REQ is never answered, so
    // the pool gives up on it when its own timer runs out.
    final mute = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mute.listen((request) async {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((_) {}, onError: (_) {});
      } catch (_) {
        // The request went away mid-handshake.
      }
    });
    final silentUrl = 'ws://127.0.0.1:${mute.port}/mute';
    final holding = newUser();
    final nothing = newUser();
    final listed = [
      await MockRelay.start(RelayState.list, [holding.real]),
      await MockRelay.start(RelayState.list, [holding.real]),
    ];
    final empty = [
      await MockRelay.start(RelayState.empty, const []),
      await MockRelay.start(RelayState.empty, const []),
    ];
    addTearDown(
      () => Future.wait([
        mute.close(force: true),
        for (final relay in [...listed, ...empty])
          relay.server.close(force: true),
      ]),
    );

    Future<FollowUpdate> follow(_User user, List<MockRelay> others) {
      return const RelayContactsRepository(
        client: RelayClient(timeout: Duration(seconds: 2)),
      ).applyFollowChanges(
        secretKey: SecretKey.fromHex(user.me.privateKeyHex),
        myPubkeyHex: user.me.publicKeyHex,
        changes: {newcomer: true},
        relayUrls: {silentUrl, for (final relay in others) relay.url},
      );
    }

    final updates = await Future.wait([
      // The real list may be on the silent relay: the two others answer, which
      // is a majority, but all they say is that they hold none.
      follow(nothing, empty),
      // A list that was found is built on, whatever the silent relay holds.
      follow(holding, listed),
    ]);

    final asked = updates.first;
    expect(asked, isA<FollowNeedsConfirmation>());
    asked as FollowNeedsConfirmation;
    expect((asked.answeredRelays, asked.queriedRelays), (2, 3));
    expect(asked.found, isNull);
    expect(empty.every((relay) => relay.received.isEmpty), isTrue);

    expect(updates.last, isA<FollowPublished>());
    final sent = NostrEvent.fromJson(listed.first.received.single);
    expect(
      {for (final tag in sent.tags) tag[1]},
      {for (final person in realFollows) person * 32, newcomer},
    );
  });
}
