import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';

void main() {
  setUp(() {
    notesNotifier.value = const [];
    customRelaysNotifier.value = const {};
    selectedRelaysNotifier.value = const {};
  });

  Future<void> openAddRelayDialog(WidgetTester tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.byKey(const Key('profileAvatarButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settingsCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('relaysCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addRelayButton')));
    await tester.pumpAndSettle();
  }

  testWidgets('submitting an invalid URL from the keyboard is rejected', (
    tester,
  ) async {
    await openAddRelayDialog(tester);

    await tester.enterText(find.byKey(const Key('addRelayField')), 'not a url');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid ws:// or wss:// URL'), findsOneWidget);
    expect(customRelaysNotifier.value, isEmpty);
  });

  testWidgets('submitting a valid URL from the keyboard adds it', (
    tester,
  ) async {
    await openAddRelayDialog(tester);

    await tester.enterText(
      find.byKey(const Key('addRelayField')),
      'wss://relay.example.com',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(customRelaysNotifier.value, contains('wss://relay.example.com'));
  });

  testWidgets('the Add button rejects an invalid URL', (tester) async {
    await openAddRelayDialog(tester);

    await tester.enterText(
      find.byKey(const Key('addRelayField')),
      'wss://relay.damus.io@158.51.42.7',
    );
    await tester.tap(find.byKey(const Key('confirmAddRelayButton')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid ws:// or wss:// URL'), findsOneWidget);
    expect(customRelaysNotifier.value, isEmpty);
  });

  testWidgets('the Add button accepts a valid URL', (tester) async {
    await openAddRelayDialog(tester);

    await tester.enterText(
      find.byKey(const Key('addRelayField')),
      '  wss://relay.example.com  ',
    );
    await tester.tap(find.byKey(const Key('confirmAddRelayButton')));
    await tester.pumpAndSettle();

    expect(customRelaysNotifier.value, contains('wss://relay.example.com'));
  });
}
