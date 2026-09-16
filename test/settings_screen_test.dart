import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/screens/settings_screen.dart';

void main() {
  setUp(() {
    loadMediaNotifier.value = false;
  });

  testWidgets('the media switch reflects and updates loadMediaNotifier', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const Key('loadMediaSwitch'));
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(loadMediaNotifier.value, isTrue);
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
  });
}
