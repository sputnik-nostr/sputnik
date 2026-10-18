import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/cache_store.dart';
import 'package:sputnik/services/follow_confirmation.dart';
import 'package:sputnik/services/follow_sync.dart';
import 'package:sputnik/services/settings_store.dart';
import 'package:sputnik/widgets/follow_button.dart';

import 'support/fake_secret_store.dart';
import 'support/follow_questions.dart';

/// Relays that answer as scripted, holding [current] when it is set.
class _ScriptedRelays extends RelayClient {
  _ScriptedRelays({required this.answered});

  int answered;
  final int queried = 5;
  NostrEvent? current;
  RelayPublishOutcome publishOutcome = RelayPublishOutcome.accepted;
  final published = <NostrEvent>[];

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => (await queryWithStatus(relayUrls, filter)).events;

  @override
  Future<RelayQueryResult> queryWithStatus(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => RelayQueryResult(
    events: [?current],
    answeredRelays: answered,
    queriedRelays: queried,
  );

  @override
  Future<Map<String, RelayPublishResult>> publish(
    NostrEvent event,
    Set<String> relayUrls,
  ) async {
    published.add(event);
    if (publishOutcome == RelayPublishOutcome.accepted) current = event;
    return {
      for (final url in relayUrls) url: RelayPublishResult(publishOutcome),
    };
  }
}

void main() {
  final alice = 'aa' * 32;
  final bob = 'bb' * 32;
  final carol = 'cc' * 32;
  final dave = 'dd' * 32;

  group('what confirming a tap says', () {
    test('a follow publishes the list and says how long it becomes', () {
      expect(
        followListChangeMessage(follow: true, listSize: 2),
        'This adds them to your follow list, which then has 3 people, and '
        'publishes it to your relays.',
      );
    });

    test('an unfollow says the same, one person fewer', () {
      expect(
        followListChangeMessage(follow: false, listSize: 3),
        'This removes them from your follow list, which then has 2 people, '
        'and publishes it to your relays.',
      );
      expect(
        followListChangeMessage(follow: false, listSize: 2),
        'This removes them from your follow list, which then has 1 person, '
        'and publishes it to your relays.',
      );
      expect(
        followListChangeMessage(follow: false, listSize: 1),
        'This removes them from your follow list, which then has 0 people, '
        'and publishes it to your relays.',
      );
    });

    test('does not make up a size while the list has not loaded', () {
      expect(
        followListChangeMessage(follow: true),
        'This adds them to your follow list and publishes it to your relays. '
        'The list has not loaded yet, so it is fetched first.',
      );
      expect(
        followListChangeMessage(follow: false),
        'This removes them from your follow list and publishes it to your '
        'relays. The list has not loaded yet, so it is fetched first.',
      );
    });
  });

  group('the question', () {
    FollowNeedsConfirmation update({
      Set<FollowRisk> risks = const {FollowRisk.noListFound},
      int answered = 4,
      int queried = 5,
      OwnListSize? found,
      OwnListSize? lastSeen,
      int resulting = 1,
    }) => FollowNeedsConfirmation(
      risks: risks,
      answeredRelays: answered,
      queriedRelays: queried,
      found: found,
      lastSeen: lastSeen,
      resultingCount: resulting,
    );
    final at = DateTime.utc(2026, 10, 1);

    test('names how many relays answered and what would be replaced', () {
      expect(
        followConfirmationMessage(update()),
        'No follow list was found on 4 of 5 relays and 1 did not answer. '
        'Publishing now would replace your list with only this person. '
        'Publish anyway?',
      );
      expect(
        followConfirmationMessage(
          update(answered: 3, queried: 5, resulting: 3),
        ),
        'No follow list was found on 3 of 5 relays and 2 did not answer. '
        'Publishing now would replace your list with only 3 people. '
        'Publish anyway?',
      );
    });

    test('adds the size of the list seen before', () {
      expect(
        followConfirmationMessage(
          update(
            risks: {FollowRisk.noListFound, FollowRisk.olderThanSeen},
            lastSeen: (createdAt: at, count: 120),
          ),
        ),
        'No follow list was found on 4 of 5 relays and 1 did not answer. '
        'This device last saw a list with 120 people. '
        'Publishing now would replace your list with only this person. '
        'Publish anyway?',
      );
    });

    test('says when the relays return an older list than the one seen', () {
      expect(
        followConfirmationMessage(
          update(
            risks: {FollowRisk.olderThanSeen},
            answered: 3,
            found: (createdAt: at, count: 1),
            lastSeen: (createdAt: at.add(const Duration(days: 9)), count: 4),
            resulting: 2,
          ),
        ),
        'The newest follow list on your relays has 1 person, but this device '
        'last saw a newer one with 4 people. '
        'Only 3 of 5 relays answered. '
        'Publishing now would replace the newer list with a list of '
        '2 people. Publish anyway?',
      );
      // Nothing to add about relays when every one of them answered.
      expect(
        followConfirmationMessage(
          update(
            risks: {FollowRisk.olderThanSeen},
            answered: 5,
            found: (createdAt: at, count: 30),
            lastSeen: (createdAt: at.add(const Duration(days: 9)), count: 120),
            resulting: 31,
          ),
        ),
        'The newest follow list on your relays has 30 people, but this device '
        'last saw a newer one with 120 people. '
        'Publishing now would replace the newer list with a list of '
        '31 people. Publish anyway?',
      );
    });

    test('says when every relay answered but none returned the list', () {
      final lastSeen = (createdAt: at, count: 4);
      expect(
        followConfirmationMessage(
          update(
            risks: {FollowRisk.olderThanSeen},
            answered: 5,
            lastSeen: lastSeen,
          ),
        ),
        'None of your 5 relays returned a follow list, but this device last '
        'saw one with 4 people. '
        'Publishing now would replace your list with only this person. '
        'Publish anyway?',
      );
      expect(
        followConfirmationMessage(
          update(
            risks: {FollowRisk.olderThanSeen},
            answered: 1,
            queried: 1,
            lastSeen: lastSeen,
          ),
        ),
        'Your relay returned no follow list, but this device last saw one '
        'with 4 people. '
        'Publishing now would replace your list with only this person. '
        'Publish anyway?',
      );
    });

    test('tells what happened, whichever question is still open', () {
      // The user already agreed that some relays were silent; the text must
      // not claim that every relay answered.
      expect(
        followConfirmationMessage(
          update(
            risks: {FollowRisk.olderThanSeen},
            lastSeen: (createdAt: at, count: 4),
          ),
        ),
        'No follow list was found on 4 of 5 relays and 1 did not answer. '
        'This device last saw a list with 4 people. '
        'Publishing now would replace your list with only this person. '
        'Publish anyway?',
      );
    });
  });

  group('when a follow needs the user to agree', () {
    late NostrKeyPair keypair;
    late String me;
    late _ScriptedRelays relays;
    late List<FollowNeedsConfirmation> asked;

    NostrEvent listOf(List<String> people) => signEvent(
      secretKey: SecretKey.fromHex(keypair.privateKeyHex),
      pubkeyHex: me,
      kind: 3,
      tags: [
        for (final person in people) ['p', person],
      ],
      content: '',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    );

    setUp(() async {
      resetFollowSync();
      resetKnownContactLists();
      await CacheStore.clearAll();
      followSyncRetryDelays = const [Duration(seconds: 10)];

      keypair = generateNostrKeyPair();
      me = keypair.publicKeyHex;
      SettingsStore.secretStore = FakeSecretStore();
      await SettingsStore.savePrivateKey(me, keypair.privateKeyHex);
      identitiesNotifier.value = [
        Identity(pubkeyHex: me, createdAt: DateTime.now()),
      ];
      activeIdentityPubkeyNotifier.value = me;
      selectedRelaysNotifier.value = {'wss://relay.example'};
      myFollowingNotifier.value = null;
      confirmBeforeReactingNotifier.value = false;

      asked = [];
      relays = _ScriptedRelays(answered: 4);
      RelayClient.instance = relays;
    });

    tearDown(resetFollowSync);

    /// The follow button taps, as far as the list and the queue are concerned.
    void tap(String person, {required bool follow}) {
      final shown = {...?myFollowingNotifier.value};
      myFollowingNotifier.value = follow
          ? (shown..add(person))
          : (shown..remove(person));
      scheduleFollowingSync(person, follow: follow);
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    }

    /// What each question was about, in the order they were asked.
    List<Set<FollowRisk>> risksAsked() => [
      for (final question in asked) question.risks,
    ];

    /// The list the user was looking at finishes loading while the first
    /// question is open, which makes the same tap doubtful in a second way.
    void listLoadsWhileAsked() {
      noteOwnContactList(
        me,
        DateTime.now().subtract(const Duration(days: 3)),
        5,
      );
    }

    testWidgets('publishes after the user agrees, and asks once', (
      tester,
    ) async {
      answerFollowQuestions((update) {
        asked.add(update);
        return true;
      });

      tap(carol, follow: true);
      await settle(tester);

      expect(asked.single.risks, {FollowRisk.noListFound});
      expect(relays.published.single.tags, [
        ['p', carol],
      ]);
      expect(myFollowingNotifier.value, {carol});
    });

    testWidgets('does not ask again when the publish has to be retried', (
      tester,
    ) async {
      relays.publishOutcome = RelayPublishOutcome.rejected;
      answerFollowQuestions((update) {
        asked.add(update);
        return true;
      });

      tap(carol, follow: true);
      await settle(tester);
      expect(relays.published, hasLength(1));

      relays.publishOutcome = RelayPublishOutcome.accepted;
      await tester.pump(const Duration(seconds: 11));

      expect(relays.published, hasLength(2));
      expect(asked, hasLength(1));
    });

    testWidgets(
      'asks again for the same tap once the list has been published',
      (tester) async {
        answerFollowQuestions((update) {
          asked.add(update);
          return true;
        });

        tap(carol, follow: true);
        await settle(tester);
        expect(relays.published, hasLength(1));

        // The relays that held the list are silent again. What the user agreed
        // to went with the publish it was for.
        relays.current = null;
        tap(carol, follow: true);
        await settle(tester);

        expect(risksAsked(), [
          {FollowRisk.noListFound},
          {FollowRisk.noListFound, FollowRisk.olderThanSeen},
        ]);
        expect(relays.published, hasLength(2));
      },
    );

    testWidgets('a question ends the streak of failures, so the back-off '
        'starts over', (tester) async {
      followSyncRetryDelays = const [
        Duration(seconds: 10),
        Duration(minutes: 5),
      ];
      relays.answered = 1;
      answerFollowQuestions((update) {
        asked.add(update);
        return true;
      });

      // Too few relays answer, so the change waits for a retry.
      tap(carol, follow: true);
      await settle(tester);
      expect(relays.published, isEmpty);

      // They answer now, with nothing; the user agrees, and the relays then
      // turn the list down.
      relays
        ..answered = 4
        ..publishOutcome = RelayPublishOutcome.rejected;
      await tester.pump(const Duration(seconds: 11));
      expect(asked, hasLength(1));
      expect(relays.published, hasLength(1));

      // That is a new streak: the next try is the first back-off again, not
      // the 5 minutes the earlier failure would have earned.
      await tester.pump(const Duration(seconds: 11));
      expect(relays.published, hasLength(2));
      // The publish is still being turned down; don't leave its retry running.
      resetFollowSync();
    });

    testWidgets(
      'asks again when the changes are no longer the ones agreed to',
      (tester) async {
        answerFollowQuestions((update) {
          asked.add(update);
          // Another person is tapped while the dialog is open.
          if (asked.length == 1) tap(dave, follow: true);
          return true;
        });

        tap(carol, follow: true);
        await settle(tester);

        expect(asked, hasLength(2));
        expect(asked.last.resultingCount, 2);
        expect(
          {for (final tag in relays.published.single.tags) tag[1]},
          {carol, dave},
        );
        // The debounce of the tap made meanwhile has nothing left to send.
        await tester.pump(const Duration(seconds: 1));
      },
    );

    testWidgets('asks again when another identity makes the same change', (
      tester,
    ) async {
      final other = generateNostrKeyPair();
      await SettingsStore.savePrivateKey(
        other.publicKeyHex,
        other.privateKeyHex,
      );
      identitiesNotifier.value = [
        ...identitiesNotifier.value,
        Identity(pubkeyHex: other.publicKeyHex, createdAt: DateTime.now()),
      ];
      answerFollowQuestions((update) {
        asked.add(update);
        return true;
      });

      // The user agrees, and the relays turn the list down.
      relays.publishOutcome = RelayPublishOutcome.rejected;
      tap(carol, follow: true);
      await settle(tester);
      expect(asked, hasLength(1));
      expect(relays.published.single.pubkey, me);

      // What was agreed to for one identity says nothing about another.
      relays.publishOutcome = RelayPublishOutcome.accepted;
      activeIdentityPubkeyNotifier.value = other.publicKeyHex;
      tap(carol, follow: true);
      await settle(tester);

      expect(asked, hasLength(2));
      expect(relays.published.last.pubkey, other.publicKeyHex);
    });

    testWidgets('keeps the first answer when a second question follows', (
      tester,
    ) async {
      answerFollowQuestions((update) {
        asked.add(update);
        if (asked.length == 1) listLoadsWhileAsked();
        return true;
      });

      tap(carol, follow: true);
      await settle(tester);

      // Agreeing to the second question does not forget the first answer, so
      // nothing is asked a third time.
      expect(risksAsked(), [
        {FollowRisk.noListFound},
        {FollowRisk.olderThanSeen},
      ]);
      expect(relays.published.single.tags, [
        ['p', carol],
      ]);
    });

    testWidgets('turning it down sends nothing and undoes the tap', (
      tester,
    ) async {
      myFollowingNotifier.value = {alice};
      answerFollowQuestions((update) {
        asked.add(update);
        return false;
      });

      tap(carol, follow: true);
      expect(myFollowingNotifier.value, {alice, carol});
      await settle(tester);

      expect(relays.published, isEmpty);
      expect(myFollowingNotifier.value, {alice});
      // The change is gone for good, not asked about again on a retry.
      await tester.pump(const Duration(seconds: 5));
      expect(asked, hasLength(1));
      expect(relays.published, isEmpty);
    });

    testWidgets('turning down a follow of a list that never loaded leaves it '
        'unknown', (tester) async {
      answerFollowQuestions((update) => false);

      tap(carol, follow: true);
      expect(myFollowingNotifier.value, {carol});
      await settle(tester);

      expect(myFollowingNotifier.value, isNull);
    });

    testWidgets('turning down an unfollow shows the person as followed again', (
      tester,
    ) async {
      relays.current = listOf([alice, bob]);
      relays.answered = 4;
      noteOwnContactList(me, DateTime.now(), 3);
      myFollowingNotifier.value = {alice, bob};
      answerFollowQuestions((update) {
        asked.add(update);
        return false;
      });

      tap(bob, follow: false);
      await settle(tester);

      // A list older than the last seen one, so the user is asked.
      expect(asked.single.risks, {FollowRisk.olderThanSeen});
      expect(myFollowingNotifier.value, {alice, bob});
      expect(relays.published, isEmpty);
    });

    testWidgets('only what was turned down is dropped', (tester) async {
      answerFollowQuestions((update) {
        asked.add(update);
        // Someone else is tapped while the dialog is open, then it is turned
        // down for the person it was about.
        if (asked.length == 1) tap(dave, follow: true);
        return asked.length > 1;
      });

      tap(carol, follow: true);
      await settle(tester);

      expect(asked, hasLength(2));
      expect(relays.published.single.tags, [
        ['p', dave],
      ]);
      expect(myFollowingNotifier.value, {dave});
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets(
      'turning a question down keeps the opposite tap made meanwhile',
      (tester) async {
        answerFollowQuestions((update) {
          asked.add(update);
          // The person is unfollowed again while the question about following
          // them is open, and the question is turned down.
          tap(carol, follow: false);
          return false;
        });

        tap(carol, follow: true);
        await settle(tester);
        expect(relays.published, isEmpty);

        // The unfollow is not what was turned down, so it waits for the list.
        relays
          ..current = listOf([alice, carol])
          ..answered = 5;
        await tester.pump(const Duration(seconds: 11));

        expect(relays.published.single.tags, [
          ['p', alice],
        ]);
      },
    );

    testWidgets('turning a question down forgets the answers given before it', (
      tester,
    ) async {
      // The user agrees to the first question and turns the second down.
      final replies = [true, false];
      answerFollowQuestions((update) {
        asked.add(update);
        if (asked.length == 1) listLoadsWhileAsked();
        return replies.removeAt(0);
      });

      tap(carol, follow: true);
      await settle(tester);

      expect(risksAsked(), [
        {FollowRisk.noListFound},
        {FollowRisk.olderThanSeen},
      ]);
      expect(relays.published, isEmpty);

      // The same tap again is a new decision: nothing of the earlier answer
      // is left, so both risks are asked about at once.
      asked.clear();
      answerFollowQuestions((update) {
        asked.add(update);
        return false;
      });
      tap(carol, follow: true);
      await settle(tester);

      expect(asked.single.risks, {
        FollowRisk.noListFound,
        FollowRisk.olderThanSeen,
      });
      expect(relays.published, isEmpty);
    });

    testWidgets('an unfollow on a list that could not be loaded waits for it', (
      tester,
    ) async {
      // The list is on the relays that stay silent now.
      relays.current = null;
      answerFollowQuestions((update) {
        asked.add(update);
        return true;
      });
      myFollowingNotifier.value = {alice, bob};

      tap(alice, follow: false);
      await settle(tester);

      expect(asked, isEmpty);
      expect(relays.published, isEmpty);
      // Not shown as followed again, and not forgotten.
      expect(myFollowingNotifier.value, {bob});

      relays
        ..current = listOf([alice, bob])
        ..answered = 5;
      await tester.pump(const Duration(seconds: 11));

      expect(relays.published.single.tags, [
        ['p', bob],
      ]);
    });

    testWidgets('with nobody to ask, the follow waits instead of publishing', (
      tester,
    ) async {
      answerFollowQuestions((update) => null);

      tap(carol, follow: true);
      await settle(tester);
      expect(relays.published, isEmpty);

      answerFollowQuestions((update) => true);
      await tester.pump(const Duration(seconds: 11));

      expect(relays.published.single.tags, [
        ['p', carol],
      ]);
    });

    testWidgets('with nobody to ask, the retries back off like any failure', (
      tester,
    ) async {
      followSyncRetryDelays = const [
        Duration(seconds: 10),
        Duration(minutes: 5),
      ];
      answerFollowQuestions((update) {
        asked.add(update);
        return null;
      });

      tap(carol, follow: true);
      await settle(tester);
      expect(asked, hasLength(1));

      await tester.pump(const Duration(seconds: 11));
      expect(asked, hasLength(2));

      // Nobody was asked, so this is still the same streak of failures: the
      // next try is the long back-off, not the short one again.
      await tester.pump(const Duration(seconds: 11));
      expect(asked, hasLength(2));
      await tester.pump(const Duration(minutes: 5));
      expect(asked, hasLength(3));
      expect(relays.published, isEmpty);
      // Still nobody to ask; don't leave the retry running.
      resetFollowSync();
    });

    testWidgets('asks nothing when every relay answered', (tester) async {
      relays.answered = 5;
      answerFollowQuestions((update) {
        asked.add(update);
        return true;
      });

      tap(carol, follow: true);
      await settle(tester);

      expect(asked, isEmpty);
      expect(relays.published, hasLength(1));
    });

    testWidgets('the real dialog says what is at stake and can be cancelled', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(body: FollowButton(targetPubkeyHex: carol)),
        ),
      );

      await tester.tap(find.byKey(const Key('followButton')));
      await settle(tester);

      expect(find.text('Publish your follow list?'), findsOneWidget);
      expect(
        find.text(
          'No follow list was found on 4 of 5 relays and 1 did not answer. '
          'Publishing now would replace your list with only this person. '
          'Publish anyway?',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(relays.published, isEmpty);
      expect(find.text('Follow'), findsOneWidget);
      expect(find.text('Following'), findsNothing);

      await tester.tap(find.byKey(const Key('followButton')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('confirmPublishFollowListButton')));
      await tester.pumpAndSettle();

      expect(relays.published.single.tags, [
        ['p', carol],
      ]);
      expect(find.text('Following'), findsOneWidget);
    });
  });
}
