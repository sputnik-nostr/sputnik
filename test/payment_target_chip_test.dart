import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/nostr_payment_target.dart';
import 'package:sputnik/widgets/payment_target_chip.dart';

void main() {
  const target = NostrPaymentTarget(
    type: 'bitcoin',
    address: 'bc1qxq66e0t8d7ugdecwnmv58e90tpry23nc84pg9k',
  );

  testWidgets('renders a wallet icon, the type, and a truncated address', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PaymentTargetChip(target: target)),
      ),
    );

    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
    expect(find.text('BTC'), findsOneWidget);
    expect(find.text('bc1qxq66e...pg9k'), findsOneWidget);
  });

  testWidgets('long-pressing copies the full address to the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PaymentTargetChip(target: target)),
      ),
    );

    await tester.longPress(find.byType(PaymentTargetChip));
    await tester.pump();

    expect(copied, target.address);
    expect(find.text('Copied Bitcoin address to clipboard'), findsOneWidget);
  });
}
