import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';

import 'support/relay_states.dart';

// Every way 1, 2, 3 and 5 relays can be split into the states of
// support/relay_states.dart is run through the follow write and the list
// shown, and compared with the decision table written out there.

String _pubkey(String name) => name * 32;

final _newcomer = _pubkey('ee');

/// Relays in the states of [cells], as the pool would report them.
class _Relays extends RelayClient {
  _Relays(this.cells, {required this.real, required this.stale});

  final Composition cells;
  final NostrEvent real;
  final NostrEvent stale;
  final published = <NostrEvent>[];

  @override
  Future<RelayQueryResult> queryWithStatus(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => RelayQueryResult(
    events: [
      if (cells[RelayState.list]! > 0) real,
      if (cells[RelayState.stale]! > 0) stale,
    ],
    answeredRelays: answeredIn(cells),
    queriedRelays: relayUrls.length,
  );

  @override
  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) async {
    published.add(event);
    return {
      for (final url in relayUrls)
        url: const RelayPublishResult(RelayPublishOutcome.accepted),
    };
  }
}

void main() {
  final me = generateNostrKeyPair();
  final secretKey = SecretKey.fromHex(me.privateKeyHex);

  NostrEvent list(List<String> people, Duration age) => signEvent(
    secretKey: secretKey,
    pubkeyHex: me.publicKeyHex,
    kind: 3,
    tags: [
      for (final person in people) ['p', _pubkey(person)],
    ],
    content: '',
    createdAt: DateTime.now().subtract(age),
  );

  final real = list(realFollows, const Duration(days: 1));
  final stale = list(staleFollows, const Duration(days: 60));

  List<List<String>> baseTags(Base base) => switch (base) {
    Base.real => real.tags,
    Base.stale => stale.tags,
    Base.none => const [],
  };

  final cases = [
    for (final relays in [1, 2, 3, 5]) ...compositions(relays),
  ];
  Set<String> urlsFor(Composition cells) => {
    for (var i = 0; i < relaysIn(cells); i++) 'wss://relay$i.example',
  };

  setUp(resetKnownContactLists);

  test('covers every way the relays can be split', () {
    // 6 states: (n + 5) choose 5 splits of n relays.
    expect(cases, hasLength(6 + 21 + 56 + 252));
  });

  /// Writes [changes] in the cell, after seeing the real list if [seen].
  Future<({FollowUpdate update, _Relays relays})> write(
    Composition cells,
    Map<String, bool> changes, {
    required bool seen,
    Set<FollowRisk> agreedTo = const {},
  }) async {
    resetKnownContactLists();
    if (seen) {
      noteOwnContactList(me.publicKeyHex, real.createdAt, realFollows.length);
    }
    final relays = _Relays(cells, real: real, stale: stale);
    final update = await RelayContactsRepository(client: relays)
        .applyFollowChanges(
          secretKey: secretKey,
          myPubkeyHex: me.publicKeyHex,
          changes: changes,
          relayUrls: urlsFor(cells),
          agreedTo: agreedTo,
        );
    return (update: update, relays: relays);
  }

  for (final seen in [false, true]) {
    for (final unfollow in [false, true]) {
      final label =
          '${unfollow ? 'an unfollow' : 'a follow'}, '
          '${seen ? 'after' : 'without'} seeing the real list';
      final changes = unfollow
          ? {_pubkey(realFollows.first): false}
          : {_newcomer: true};
      Expected expected(Composition cells) =>
          expectedDecision(cells, seen: seen, unfollow: unfollow);

      test('$label: the decision follows the table in every state', () async {
        final wrong = <String>[];
        for (final cells in cases) {
          final run = await write(cells, changes, seen: seen);
          final want = expected(cells);
          final sent = run.relays.published.length;
          if (describeUpdate(run.update) != want.text ||
              sent != (want.decision == Decision.publish ? 1 : 0)) {
            wrong.add(
              '${nameOf(cells)}: ${describeUpdate(run.update)}, sent $sent, '
              'expected ${want.text}',
            );
          }
        }
        expect(wrong, isEmpty, reason: '${wrong.length} of ${cases.length}');
      });

      test('$label: what is sent builds on the list found', () async {
        final wrong = <String>[];
        for (final cells in cases) {
          final want = expected(cells);
          if (want.decision != Decision.publish) continue;
          final run = await write(cells, changes, seen: seen);
          final sent = run.relays.published.single.tags;
          final wanted = [
            for (final tag in baseTags(want.base))
              if (!(unfollow && tag[1] == _pubkey(realFollows.first))) tag,
            if (!unfollow) ['p', _newcomer],
          ];
          if ('$sent' != '$wanted') wrong.add('${nameOf(cells)}: $sent');
        }
        expect(wrong, isEmpty);
      });

      test('$label: a question names what was found', () async {
        final wrong = <String>[];
        for (final cells in cases) {
          final want = expected(cells);
          if (want.decision != Decision.confirm) continue;
          final run = await write(cells, changes, seen: seen);
          final update = run.update as FollowNeedsConfirmation;
          final found = switch (want.base) {
            Base.real => realFollows.length,
            Base.stale => staleFollows.length,
            Base.none => null,
          };
          if (update.answeredRelays != answeredIn(cells) ||
              update.queriedRelays != relaysIn(cells) ||
              update.found?.count != found ||
              update.lastSeen?.count != (seen ? realFollows.length : null) ||
              update.resultingCount !=
                  resultingPeople(want.base, unfollow: unfollow)) {
            wrong.add(nameOf(cells));
          }
        }
        expect(wrong, isEmpty);
      });

      test('$label: agreeing to the questions sends the list', () async {
        final wrong = <String>[];
        for (final cells in cases) {
          final want = expected(cells);
          if (want.decision != Decision.confirm) continue;
          final risks = {
            for (final name in want.risks) FollowRisk.values.byName(name),
          };
          final run = await write(cells, changes, seen: seen, agreedTo: risks);
          if (run.update is! FollowPublished ||
              run.relays.published.length != 1) {
            wrong.add('${nameOf(cells)}: ${describeUpdate(run.update)}');
          }
          // Agreeing to one question is not agreeing to another.
          if (risks.length < 2) continue;
          for (final risk in risks) {
            final partly = await write(
              cells,
              changes,
              seen: seen,
              agreedTo: {risk},
            );
            final update = partly.update;
            if (update is! FollowNeedsConfirmation ||
                update.risks.contains(risk) ||
                partly.relays.published.isNotEmpty) {
              wrong.add('${nameOf(cells)} agreeing to ${risk.name}');
            }
          }
        }
        expect(wrong, isEmpty);
      });
    }
  }

  test('an empty list is refused even when the user already agreed', () async {
    final wrong = <String>[];
    var tried = 0;
    for (final cells in cases) {
      final want = expectedDecision(cells, seen: true, unfollow: true);
      if (want.why != 'wouldEmptyList') continue;
      tried++;
      final run = await write(
        cells,
        {_pubkey(realFollows.first): false},
        seen: true,
        agreedTo: FollowRisk.values.toSet(),
      );
      if (describeUpdate(run.update) != 'refuse(wouldEmptyList)' ||
          run.relays.published.isNotEmpty) {
        wrong.add(nameOf(cells));
      }
    }
    expect(tried, greaterThan(0));
    expect(wrong, isEmpty);
  });

  test('the list shown is empty only when every relay said there is none, '
      'and unknown while one may still hold it', () async {
    final wrong = <String>[];
    for (final cells in cases) {
      final shown = await RelayContactsRepository(
        client: _Relays(cells, real: real, stale: stale),
      ).fetchFollowingOrNull(me.publicKeyHex, urlsFor(cells));
      final wanted = switch (baseOf(cells)) {
        Base.real => [for (final person in realFollows) _pubkey(person)],
        Base.stale => [for (final person in staleFollows) _pubkey(person)],
        Base.none => answeredIn(cells) == relaysIn(cells) ? <String>[] : null,
      };
      if ('$shown' != '$wanted') {
        wrong.add('${nameOf(cells)}: $shown, expected $wanted');
      }
    }
    expect(wrong, isEmpty);
  });

  test(
    'after seeing the real list, nothing else is ever built on silently, '
    'and without it only a stale copy found by most relays can still be',
    () async {
      // Cells where a list was sent although a relay holds the real one and
      // the list sent was not built on it, by whether the real list was seen.
      final lost = <String, Base>{};
      for (final seen in [false, true]) {
        for (final unfollow in [false, true]) {
          for (final cells in cases) {
            final run = await write(
              cells,
              unfollow
                  ? {_pubkey(realFollows.first): false}
                  : {_newcomer: true},
              seen: seen,
            );
            final holdsReal =
                cells[RelayState.list]! +
                    cells[RelayState.slow]! +
                    cells[RelayState.down]! +
                    cells[RelayState.cooling]! >
                0;
            if (run.update is FollowPublished &&
                holdsReal &&
                baseOf(cells) != Base.real) {
              lost['${seen ? 'seen' : 'unseen'} ${nameOf(cells)}'] = baseOf(
                cells,
              );
            }
          }
        }
      }
      expect(lost.keys.where((cell) => cell.startsWith('seen')), isEmpty);
      // The one gap left on purpose: a found list is trusted when most relays
      // answered, so a stale copy can win if the real list is on silent ones.
      expect(lost, isNotEmpty);
      expect(lost.values, everyElement(Base.stale));
    },
  );
}
