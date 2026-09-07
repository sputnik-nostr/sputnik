import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/nostr_payment_target.dart';
import 'package:sputnik/widgets/payment_target_chip.dart';

void main() {
  testWidgets('renders a wallet icon, the type, and a truncated address', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PaymentTargetChip(
            target: NostrPaymentTarget(
              type: 'bitcoin',
              address: 'bc1qxq66e0t8d7ugdecwnmv58e90tpry23nc84pg9k',
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
    expect(find.text('BTC'), findsOneWidget);
    expect(find.text('bc1qxq66e...pg9k'), findsOneWidget);
  });
}
