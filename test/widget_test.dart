import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/note.dart';

void main() {
  testWidgets('Profile avatar opens the settings drawer', (
    WidgetTester tester,
  ) async {
    notesNotifier.value = const [
      Note(
        displayName: 'Alice',
        handle: 'npub1alice...',
        content: 'hello',
        postedAt: '2m',
      ),
    ];

    await tester.pumpWidget(const MainApp());

    final profileButton = find.byKey(const Key('profileAvatarButton'));
    expect(profileButton, findsOneWidget);

    await tester.tap(profileButton);
    await tester.pumpAndSettle();

    expect(find.text('Anon'), findsOneWidget);
    expect(find.text('Dark mode'), findsOneWidget);
  });
}
