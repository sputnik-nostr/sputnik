import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';

void main() {
  late List<String> copied;
  late bool failCopy;

  setUp(() {
    copied = [];
    failCopy = false;
    notesNotifier.value = const [];
    identitiesNotifier.value = const [];
    activeIdentityPubkeyNotifier.value = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            if (failCopy) {
              throw PlatformException(code: 'clipboard-unavailable');
            }
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> revealPrivateKey(WidgetTester tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.byKey(const Key('profileAvatarButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settingsCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identitiesCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('generateIdentityButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View private key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reveal'));
    await tester.pumpAndSettle();
  }

  testWidgets('copying puts the key on the clipboard and says so', (
    tester,
  ) async {
    await revealPrivateKey(tester);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.single, startsWith('nsec1'));
    expect(find.textContaining('Copied private key'), findsOneWidget);
  });

  testWidgets('a failed copy is reported instead of claimed as success', (
    tester,
  ) async {
    await revealPrivateKey(tester);
    failCopy = true;

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copied, isEmpty);
    expect(find.text('Could not copy the private key'), findsOneWidget);
    expect(find.textContaining('Copied private key'), findsNothing);
  });

  testWidgets('the app does not promise to clear the clipboard', (
    tester,
  ) async {
    await revealPrivateKey(tester);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(find.textContaining('clears in'), findsNothing);
  });
}
