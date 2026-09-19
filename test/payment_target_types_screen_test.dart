import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/screens/payment_target_types_screen.dart';
import 'package:sputnik/widgets/payment_target_chip.dart';

void main() {
  setUp(() {
    hiddenPaymentTargetTypesNotifier.value = const {};
  });

  testWidgets('every known type is checked on by default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PaymentTargetTypesScreen()),
    );
    await tester.pumpAndSettle();

    final checkbox = tester.widget<CheckboxListTile>(
      find.byKey(const Key('paymentTargetTypeCheckbox_monero')),
    );
    expect(checkbox.value, isTrue);
  });

  testWidgets('unchecking a type hides it via the shared notifier', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PaymentTargetTypesScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('paymentTargetTypeCheckbox_monero')));
    await tester.pumpAndSettle();

    expect(hiddenPaymentTargetTypesNotifier.value, {'monero'});
    final checkbox = tester.widget<CheckboxListTile>(
      find.byKey(const Key('paymentTargetTypeCheckbox_monero')),
    );
    expect(checkbox.value, isFalse);
  });

  testWidgets('re-checking a hidden type shows it again', (tester) async {
    hiddenPaymentTargetTypesNotifier.value = {'monero'};

    await tester.pumpWidget(
      const MaterialApp(home: PaymentTargetTypesScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('paymentTargetTypeCheckbox_monero')));
    await tester.pumpAndSettle();

    expect(hiddenPaymentTargetTypesNotifier.value, isEmpty);
  });

  testWidgets('a type with an ambiguous name shows a spec-derived subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PaymentTargetTypesScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Silent payments (BTC)'), findsOneWidget);
  });

  testWidgets('the "All types" checkbox is checked when nothing is hidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PaymentTargetTypesScreen()),
    );
    await tester.pumpAndSettle();

    final allCheckbox = tester.widget<CheckboxListTile>(
      find.byKey(const Key('paymentTargetTypeCheckboxAll')),
    );
    expect(allCheckbox.value, isTrue);
  });

  testWidgets(
    'the "All types" checkbox is indeterminate when some are hidden',
    (tester) async {
      hiddenPaymentTargetTypesNotifier.value = {'monero'};

      await tester.pumpWidget(
        const MaterialApp(home: PaymentTargetTypesScreen()),
      );
      await tester.pumpAndSettle();

      final allCheckbox = tester.widget<CheckboxListTile>(
        find.byKey(const Key('paymentTargetTypeCheckboxAll')),
      );
      expect(allCheckbox.value, isNull);
    },
  );

  testWidgets('tapping "All types" when fully shown hides every type', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PaymentTargetTypesScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('paymentTargetTypeCheckboxAll')));
    await tester.pumpAndSettle();

    expect(
      hiddenPaymentTargetTypesNotifier.value,
      knownPaymentTargetTypes.toSet(),
    );
  });

  testWidgets('tapping "All types" when some are hidden shows every type', (
    tester,
  ) async {
    hiddenPaymentTargetTypesNotifier.value = {'monero'};

    await tester.pumpWidget(
      const MaterialApp(home: PaymentTargetTypesScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('paymentTargetTypeCheckboxAll')));
    await tester.pumpAndSettle();

    expect(hiddenPaymentTargetTypesNotifier.value, isEmpty);
  });
}
