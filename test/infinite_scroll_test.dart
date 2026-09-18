import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/main.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/home_screen.dart';
import 'package:sputnik/screens/profile_screen.dart';
import 'package:sputnik/services/feed_loader.dart';

import 'support/in_memory_relay_client.dart';

final _author = 'b' * 64;
final _base = DateTime.fromMillisecondsSinceEpoch(1700000000000);

// Newest first: note 0 is the newest.
List<NostrEvent> _notes(int count) => [
  for (var i = 0; i < count; i++)
    fakeEvent(
      id: i.toString().padLeft(64, '0'),
      pubkey: _author,
      content: 'note $i',
      createdAt: _base.subtract(Duration(minutes: i)),
    ),
];

Finder get _list => find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .hitTestable()
    .last;

// The loading footer animates forever, so pumpAndSettle would never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    // No relays, so profile and reaction lookups finish at once.
    selectedRelaysNotifier.value = const {};
    profileCacheNotifier.value = const {};
    activeIdentityPubkeyNotifier.value = 'a' * 64;
    myFollowingNotifier.value = {_author};
    notesNotifier.value = null;
    followingNotesNotifier.value = null;
  });

  tearDown(() => feedRelayClient = const RelayClient());

  testWidgets('the global feed loads older posts as it is scrolled', (
    tester,
  ) async {
    feedRelayClient = InMemoryRelayClient(_notes(100));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeScreen())),
    );
    await tester.tap(find.text('Global'));
    await tester.pump();
    await loadGlobalFeed();
    await _settle(tester);
    expect(find.text('note 0'), findsOneWidget);
    expect(find.text('note 45', skipOffstage: false), findsNothing);

    await tester.scrollUntilVisible(
      find.text('note 75'),
      600,
      scrollable: _list,
      maxScrolls: 200,
    );

    expect(find.text('note 75'), findsOneWidget);
    expect(notesNotifier.value!.length, greaterThan(60));
  });

  testWidgets('the feed stops asking once everything is loaded', (
    tester,
  ) async {
    feedRelayClient = InMemoryRelayClient(_notes(40));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeScreen())),
    );
    await tester.tap(find.text('Global'));
    await tester.pump();
    await loadGlobalFeed();
    await _settle(tester);

    await tester.scrollUntilVisible(
      find.text('note 39'),
      600,
      scrollable: _list,
      maxScrolls: 200,
    );
    await _settle(tester);

    expect(notesNotifier.value, hasLength(40));
    expect(globalFeedHasMore.value, isFalse);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a profile loads older posts as it is scrolled', (tester) async {
    final client = InMemoryRelayClient(_notes(260));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(pubkeyHex: _author, relayClient: client),
      ),
    );
    await _settle(tester);
    expect(find.text('note 250', skipOffstage: false), findsNothing);

    await tester.scrollUntilVisible(
      find.text('note 250'),
      800,
      scrollable: _list,
      maxScrolls: 400,
    );

    expect(find.text('note 250'), findsOneWidget);
  });
}
