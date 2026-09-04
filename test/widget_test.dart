import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/note.dart';

void main() {
  testWidgets('Profile avatar opens the settings drawer', (
    WidgetTester tester,
  ) async {
    notesNotifier.value = [
      Note(
        id: '1',
        pubkey:
            'npub1alice0000000000000000000000000000000000000000000000000000',
        displayName: 'Alice',
        handle: 'npub1alice...',
        content: 'hello',
        postedAt: '2m',
        createdAt: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(const MainApp());

    final profileButton = find.byKey(const Key('profileAvatarButton'));
    expect(profileButton, findsOneWidget);

    await tester.tap(profileButton);
    await tester.pumpAndSettle();

    expect(find.text('Anon'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settingsCard')));
    await tester.pumpAndSettle();

    expect(find.text('Theme'), findsOneWidget);
  });
}
