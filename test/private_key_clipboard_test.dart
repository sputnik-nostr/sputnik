import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/screens/identities_screen.dart';

void main() {
  late List<String> copied;
  late bool failCopy;
  late String? clipboardText;

  setUp(() {
    copied = [];
    failCopy = false;
    clipboardText = null;
    notesNotifier.value = const [];
    identitiesNotifier.value = const [];
    activeIdentityPubkeyNotifier.value = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            if (failCopy) {
              throw PlatformException(code: 'clipboard-unavailable');
            }
            final text = (call.arguments as Map)['text'] as String;
            copied.add(text);
            clipboardText = text;
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return {'text': clipboardText};
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

    // Let the pending clear timer run out within the test's fake clock.
    await tester.pump(nsecClipboardClearDelay);
    await tester.pumpAndSettle();
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

  testWidgets('the clipboard is cleared automatically after copying', (
    tester,
  ) async {
    await revealPrivateKey(tester);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(find.textContaining('cleared from the'), findsOneWidget);
    expect(clipboardText, startsWith('nsec1'));

    await tester.pump(nsecClipboardClearDelay);
    await tester.pumpAndSettle();

    expect(clipboardText, isEmpty);
  });

  testWidgets('a clipboard overwritten by something else is left alone', (
    tester,
  ) async {
    await revealPrivateKey(tester);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    clipboardText = 'something else the user copied';

    await tester.pump(nsecClipboardClearDelay);
    await tester.pumpAndSettle();

    expect(clipboardText, 'something else the user copied');
  });
}
