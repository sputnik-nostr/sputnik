import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets/payment_target_chip.dart';

class PaymentTargetTypesScreen extends StatelessWidget {
  const PaymentTargetTypesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment targets')),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: hiddenPaymentTargetTypesNotifier,
        builder: (context, hidden, _) {
          final shownCount = knownPaymentTargetTypes.length - hidden.length;
          final allShown = shownCount == knownPaymentTargetTypes.length;
          final noneShown = shownCount == 0;

          return ListView(
            children: [
              CheckboxListTile(
                key: const Key('paymentTargetTypeCheckboxAll'),
                title: const Text('All types'),
                value: allShown ? true : (noneShown ? false : null),
                tristate: true,
                onChanged: (value) {
                  hiddenPaymentTargetTypesNotifier.value = allShown
                      ? knownPaymentTargetTypes.toSet()
                      : const {};
                },
              ),
              const Divider(height: 1),
              for (final type in knownPaymentTargetTypes)
                CheckboxListTile(
                  key: Key('paymentTargetTypeCheckbox_$type'),
                  title: Text(paymentTargetTypeDisplayName(type)),
                  subtitle: switch (paymentTargetTypeSubtitle(type)) {
                    final subtitle? => Text(subtitle),
                    null => null,
                  },
                  value: !hidden.contains(type),
                  onChanged: (value) {
                    final updated = Set<String>.of(hidden);
                    if (value ?? true) {
                      updated.remove(type);
                    } else {
                      updated.add(type);
                    }
                    hiddenPaymentTargetTypesNotifier.value = updated;
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
