import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/app_seed_color.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/relay.dart';
import 'package:sputnik/screens/payment_target_types_screen.dart';
import 'package:sputnik/screens/settings_screen.dart';

SwitchListTile _switchIn(WidgetTester tester, Finder finder) =>
    tester.widget<SwitchListTile>(
      find.descendant(of: finder, matching: find.byType(SwitchListTile)),
    );

void main() {
  setUp(() {
    loadProfileImagesNotifier.value = false;
    loadNoteImagesNotifier.value = false;
    hiddenPaymentTargetTypesNotifier.value = const {};
    identitiesNotifier.value = const [];
    confirmBeforeReactingNotifier.value = false;
  });

  testWidgets('the profile images switch reflects and updates its notifier', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const Key('loadProfileImagesSwitch'));
    expect(_switchIn(tester, switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(loadProfileImagesNotifier.value, isTrue);
    expect(_switchIn(tester, switchFinder).value, isTrue);
  });

  testWidgets('the note images switch reflects and updates its notifier', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const Key('loadNoteImagesSwitch'));
    expect(_switchIn(tester, switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(loadNoteImagesNotifier.value, isTrue);
    expect(_switchIn(tester, switchFinder).value, isTrue);
  });

  testWidgets(
    'the confirm-before-reacting switch reflects and updates its notifier',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const Key('confirmBeforeReactingSwitch'));
      expect(_switchIn(tester, switchFinder).value, isFalse);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(confirmBeforeReactingNotifier.value, isTrue);
      expect(_switchIn(tester, switchFinder).value, isTrue);
    },
  );

  testWidgets('the payment addresses card shows how many types are hidden', (
    tester,
  ) async {
    hiddenPaymentTargetTypesNotifier.value = {'monero'};

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('paymentTargetTypesCard')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('1 type hidden'), findsOneWidget);
  });

  testWidgets('tapping the payment addresses card opens its screen', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('paymentTargetTypesCard')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.byKey(const Key('paymentTargetTypesCard')));
    await tester.pumpAndSettle();

    expect(find.byType(PaymentTargetTypesScreen), findsOneWidget);
  });

  testWidgets('resetting preferences also restores media loading, NIP-05 '
      'checks and payment target visibility, without touching identities', (
    tester,
  ) async {
    themeModeNotifier.value = ThemeMode.dark;
    seedColorNotifier.value = AppSeedColor.red;
    selectedRelaysNotifier.value = {'wss://custom.example'};
    loadProfileImagesNotifier.value = true;
    loadNoteImagesNotifier.value = true;
    autoVerifyNip05Notifier.value = true;
    hiddenPaymentTargetTypesNotifier.value = {'monero'};
    confirmBeforeReactingNotifier.value = true;
    identitiesNotifier.value = [
      Identity(pubkeyHex: 'a' * 64, createdAt: DateTime.now()),
    ];

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('resetPreferencesCard')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('resetPreferencesCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('resetPreferencesCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(themeModeNotifier.value, ThemeMode.system);
    expect(seedColorNotifier.value, AppSeedColor.blue);
    expect(selectedRelaysNotifier.value, defaultRelays.toSet());
    expect(loadProfileImagesNotifier.value, isFalse);
    expect(loadNoteImagesNotifier.value, isFalse);
    expect(autoVerifyNip05Notifier.value, isFalse);
    expect(hiddenPaymentTargetTypesNotifier.value, isEmpty);
    expect(confirmBeforeReactingNotifier.value, isFalse);
    expect(identitiesNotifier.value, hasLength(1));
  });
}
