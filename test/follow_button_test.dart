import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/follow_sync.dart';
import 'package:sputnik/widgets/follow_button.dart';

import 'support/in_memory_relay_client.dart';

void main() {
  final target = 'bb' * 32;

  late String me;

  setUp(() {
    resetFollowSync();
    me = generateNostrKeyPair().publicKeyHex;
    identitiesNotifier.value = [
      Identity(pubkeyHex: me, createdAt: DateTime.now()),
    ];
    activeIdentityPubkeyNotifier.value = me;
    confirmBeforeReactingNotifier.value = true;
  });

  tearDown(() {
    resetFollowSync();
    confirmBeforeReactingNotifier.reset();
    myFollowingNotifier.value = null;
  });

  /// The active identity's list, loaded the way the app loads it.
  Future<void> loadList(List<String> people) async {
    RelayClient.instance = InMemoryRelayClient([
      fakeEvent(
        pubkey: me,
        kind: 3,
        tags: [
          for (final person in people) ['p', person],
        ],
      ),
    ]);
    await ensureMyFollowingLoaded({'wss://relay.example'});
    expect(myFollowingNotifier.value, people.toSet());
  }

  /// Shows the button and taps it, which opens the confirmation.
  Future<void> tapButton(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FollowButton(targetPubkeyHex: target)),
      ),
    );
    await tester.tap(find.byKey(const Key('followButton')));
    await tester.pumpAndSettle();
  }

  Future<void> cancel(WidgetTester tester) async {
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  }

  testWidgets('a follow says that the list is published and how long it '
      'becomes', (tester) async {
    await loadList(['aa' * 32, 'cc' * 32]);

    await tapButton(tester);

    expect(find.text('Follow this person?'), findsOneWidget);
    expect(
      find.text(
        'This adds them to your follow list, which then has 3 people, and '
        'publishes it to your relays.',
      ),
      findsOneWidget,
    );
    await cancel(tester);
    // Turned down, so nothing changed.
    expect(myFollowingNotifier.value, {'aa' * 32, 'cc' * 32});
  });

  testWidgets('an unfollow says the same, one person fewer', (tester) async {
    await loadList([target, 'cc' * 32]);

    await tapButton(tester);

    expect(find.text('Unfollow this person?'), findsOneWidget);
    expect(
      find.text(
        'This removes them from your follow list, which then has 1 person, '
        'and publishes it to your relays.',
      ),
      findsOneWidget,
    );
    await cancel(tester);
  });

  testWidgets('does not make up a size while the list has not loaded', (
    tester,
  ) async {
    myFollowingNotifier.value = null;

    await tapButton(tester);

    expect(
      find.text(
        'This adds them to your follow list and publishes it to your relays. '
        'The list has not loaded yet, so it is fetched first.',
      ),
      findsOneWidget,
    );
    await cancel(tester);
  });

  testWidgets('does not take the taps made so far for the whole list', (
    tester,
  ) async {
    // An earlier tap, while the list was still loading, left only itself.
    myFollowingNotifier.value = {'aa' * 32};

    await tapButton(tester);

    expect(
      find.text(
        'This adds them to your follow list and publishes it to your relays. '
        'The list has not loaded yet, so it is fetched first.',
      ),
      findsOneWidget,
    );
    await cancel(tester);
  });

  testWidgets('does not take the list of another identity for the one in use', (
    tester,
  ) async {
    await loadList(['aa' * 32, 'cc' * 32]);
    // Switched to an identity whose list has not loaded yet.
    final other = generateNostrKeyPair().publicKeyHex;
    identitiesNotifier.value = [
      ...identitiesNotifier.value,
      Identity(pubkeyHex: other, createdAt: DateTime.now()),
    ];
    activeIdentityPubkeyNotifier.value = other;

    await tapButton(tester);

    expect(
      find.text(
        'This adds them to your follow list and publishes it to your relays. '
        'The list has not loaded yet, so it is fetched first.',
      ),
      findsOneWidget,
    );
    await cancel(tester);
  });
}
