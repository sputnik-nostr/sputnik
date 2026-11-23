// The relay states a follow-list write is checked against, and what it must do
// in each, written out apart from the code under test.

import 'package:sputnik/nostr/nostr.dart';

/// What one relay does when asked for the user's follow list.
enum RelayState {
  /// Answers with the user's real list, four people.
  list('L'),

  /// Answers with an older copy of it, one person.
  stale('S'),

  /// Answers that it has none.
  empty('E'),

  /// Holds the real list but does not answer in time.
  slow('W'),

  /// Holds the real list but cannot be reached.
  down('D'),

  /// Holds the real list and is reachable again, but failed a moment ago, so
  /// the pool skips it for a while. It still counts among the relays asked.
  cooling('C');

  const RelayState(this.letter);

  final String letter;

  bool get answers => this == list || this == stale || this == empty;
}

/// How many relays are in each state.
typedef Composition = Map<RelayState, int>;

/// Every way to spread [relays] relays over the states.
List<Composition> compositions(int relays) {
  final states = RelayState.values;
  final all = <Composition>[];
  void spread(int index, int left, List<int> counts) {
    if (index == states.length - 1) {
      all.add({
        for (var i = 0; i < states.length - 1; i++) states[i]: counts[i],
        states.last: left,
      });
      return;
    }
    for (var count = 0; count <= left; count++) {
      spread(index + 1, left - count, [...counts, count]);
    }
  }

  spread(0, relays, []);
  return all;
}

String nameOf(Composition composition) => [
  for (final state in RelayState.values) '${state.letter}${composition[state]}',
].join();

int relaysIn(Composition cells) => cells.values.fold(0, (sum, n) => sum + n);

int answeredIn(Composition cells) => [
  for (final state in RelayState.values)
    if (state.answers) cells[state]!,
].fold(0, (sum, n) => sum + n);

/// The lists the cells are about, by the byte their pubkeys repeat. The first
/// person is on both, and is the one an unfollow removes.
const realFollows = ['aa', 'bb', 'cc', 'dd'];
const staleFollows = ['aa'];

enum Decision { publish, confirm, refuse }

/// Which list a write would build on.
enum Base { real, stale, none }

/// The list a write finds: the real one if any relay that answered holds it,
/// else the stale one, else none.
Base baseOf(Composition cells) => cells[RelayState.list]! > 0
    ? Base.real
    : cells[RelayState.stale]! > 0
    ? Base.stale
    : Base.none;

class Expected {
  const Expected(this.decision, this.base, {this.risks = const {}, this.why});

  final Decision decision;
  final Base base;

  /// For [Decision.confirm]: what the user is asked about.
  final Set<String> risks;

  /// For [Decision.refuse]: why asking would not help.
  final String? why;

  /// How the outcome is written by [describe] in the matrix test.
  String get text => switch (decision) {
    Decision.publish => 'publish',
    Decision.confirm => 'confirm(${(risks.toList()..sort()).join(',')})',
    Decision.refuse => 'refuse($why)',
  };
}

/// What a follow of someone new, or an unfollow of the first person, must do.
/// [seen] says whether this device saw the real list before.
///
/// - Nothing is written unless most relays answered ("relaysSilent").
/// - A list found by most relays is built on. Nothing found is trusted only
///   when every relay said so; otherwise the user is asked ("noListFound").
/// - A list older than the one seen before, or none where one was seen, asks
///   too ("olderThanSeen").
/// - Where either doubt applies, a list left empty is refused outright
///   ("wouldEmptyList").
Expected expectedDecision(
  Composition cells, {
  required bool seen,
  required bool unfollow,
}) {
  final relays = relaysIn(cells);
  final answered = answeredIn(cells);
  final base = baseOf(cells);

  if (answered * 2 <= relays) {
    return Expected(Decision.refuse, base, why: 'relaysSilent');
  }

  final risks = {
    if (base == Base.none && answered < relays) 'noListFound',
    if (seen && base != Base.real) 'olderThanSeen',
  };
  if (risks.isEmpty) return Expected(Decision.publish, base);
  if (resultingPeople(base, unfollow: unfollow) == 0) {
    return Expected(Decision.refuse, base, why: 'wouldEmptyList');
  }
  return Expected(Decision.confirm, base, risks: risks);
}

/// How many people the written list holds.
int resultingPeople(Base base, {required bool unfollow}) {
  final before = switch (base) {
    Base.real => realFollows.length,
    Base.stale => staleFollows.length,
    Base.none => 0,
  };
  // The unfollowed person is on both lists.
  if (unfollow) return base == Base.none ? 0 : before - 1;
  return before + 1;
}

/// [Expected.text] for what a write really did.
String describeUpdate(FollowUpdate update) => switch (update) {
  FollowPublished() => 'publish',
  FollowRefused(:final reason) => 'refuse(${reason.name})',
  FollowNeedsConfirmation(:final risks) =>
    'confirm(${(risks.map((risk) => risk.name).toList()..sort()).join(',')})',
};
