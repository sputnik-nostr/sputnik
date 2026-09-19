import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/main.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/screens/home_screen.dart';
import 'package:sputnik/screens/identities_screen.dart';
import 'package:sputnik/widgets/compact_tab_bar.dart';

Note _note(String id, String content) => Note(
  id: id,
  pubkey: 'b' * 64,
  displayName: 'Bob',
  handle: 'bob',
  content: content,
  postedAt: '1m',
  createdAt: DateTime.now(),
);

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: HomeScreen())),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    activeIdentityPubkeyNotifier.value = 'a' * 64;
    myFollowingNotifier.value = {'b' * 64};
    followingNotesNotifier.value = [_note('1', 'from someone I follow')];
    notesNotifier.value = [_note('2', 'from the firehose')];
  });

  testWidgets('opens on the following feed', (tester) async {
    await _pumpHome(tester);

    expect(find.text('from someone I follow'), findsOneWidget);
    expect(find.text('from the firehose'), findsNothing);
  });

  testWidgets('the tab bar is shorter than the 48px default', (tester) async {
    await _pumpHome(tester);

    final height = tester.getSize(find.byType(TabBar)).height;
    expect(height, lessThan(48));
    expect(height, greaterThanOrEqualTo(compactTabHeight));
  });

  testWidgets('the global tab shows the global feed', (tester) async {
    await _pumpHome(tester);

    await tester.tap(find.text('Global'));
    await tester.pumpAndSettle();

    expect(find.text('from the firehose'), findsOneWidget);
    expect(find.text('from someone I follow'), findsNothing);
  });

  testWidgets('with no identity, following prompts to create one', (
    tester,
  ) async {
    activeIdentityPubkeyNotifier.value = null;
    await _pumpHome(tester);

    expect(find.text('No identity yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('createIdentityFromFeedButton')));
    await tester.pumpAndSettle();

    expect(find.byType(IdentitiesScreen), findsOneWidget);
  });

  testWidgets('following nobody explains how to fill the feed', (tester) async {
    myFollowingNotifier.value = const {};
    followingNotesNotifier.value = const [];
    await _pumpHome(tester);

    expect(find.text('Follow people to see their posts here'), findsOneWidget);
  });

  testWidgets('an empty following feed is not blamed on the follow list', (
    tester,
  ) async {
    followingNotesNotifier.value = const [];
    await _pumpHome(tester);

    expect(find.text('No posts from people you follow'), findsOneWidget);
  });

  testWidgets('a feed that has not loaded yet shows a spinner', (tester) async {
    followingNotesNotifier.value = null;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeScreen())),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
