import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/screens/compose_screen.dart';

void main() {
  setUp(() {
    // Avoid HomeScreen's indefinite loading spinner, which would keep
    // pumpAndSettle spinning forever.
    notesNotifier.value = const [];
    activeIdentityPubkeyNotifier.value =
        'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
  });

  Future<void> openComposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.byKey(const Key('composeFab')));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping the compose FAB opens the compose screen', (
    tester,
  ) async {
    await openComposeScreen(tester);

    expect(find.byType(ComposeScreen), findsOneWidget);

    final textField = tester.widget<TextField>(
      find.byKey(const Key('composeTextField')),
    );
    expect(textField.autofocus, isTrue);
  });

  testWidgets('the post button is disabled until text is entered', (
    tester,
  ) async {
    await openComposeScreen(tester);

    FilledButton postButton() =>
        tester.widget<FilledButton>(find.byKey(const Key('composePostButton')));

    expect(postButton().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('composeTextField')),
      'gm nostr',
    );
    await tester.pump();

    expect(postButton().onPressed, isNotNull);
  });

  testWidgets('closing the compose screen returns to the root screen', (
    tester,
  ) async {
    await openComposeScreen(tester);

    await tester.tap(find.byKey(const Key('composeCloseButton')));
    await tester.pumpAndSettle();

    expect(find.byType(ComposeScreen), findsNothing);
    expect(find.byKey(const Key('composeFab')), findsOneWidget);
  });
}
