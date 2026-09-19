import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/widgets/fade_in_avatar.dart';

void main() {
  Future<void> pumpAvatar(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FadeInAvatar(
          imageUrl: 'https://example.com/pic.png',
          backgroundColor: Colors.blue,
          fallback: Text('A'),
        ),
      ),
    );
  }

  testWidgets('does not build an Image when media loading is off', (
    tester,
  ) async {
    loadMediaNotifier.value = false;
    await pumpAvatar(tester);
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('no image URL means no Image regardless of the setting', (
    tester,
  ) async {
    loadMediaNotifier.value = true;
    await tester.pumpWidget(
      const MaterialApp(
        home: FadeInAvatar(
          imageUrl: null,
          backgroundColor: Colors.blue,
          fallback: Text('A'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
  });
}
