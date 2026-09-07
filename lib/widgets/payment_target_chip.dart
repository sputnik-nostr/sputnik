import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../nostr/models/nostr_payment_target.dart';
import '../theme/app_text_styles.dart';

const _tickers = <String, String>{
  'bitcoin': 'BTC',
  'lightning': 'LN',
  'bip352': 'BTC',
  'bip353': 'BTC',
  'litecoin': 'LTC',
  'monero': 'XMR',
  'ethereum': 'ETH',
  'zcash': 'ZEC',
  'nano': 'NANO',
  'solana': 'SOL',
};

const _brandColors = <String, Color>{
  'bitcoin': Color(0xFFF7931A),
  'lightning': Color(0xFFF7931A),
  'bip352': Color(0xFFF7931A),
  'bip353': Color(0xFFF7931A),
  'litecoin': Color(0xFF345D9D),
  'monero': Color(0xFFFF6600),
  'ethereum': Color(0xFF627EEA),
  'zcash': Color(0xFFF4B728),
  'nano': Color(0xFF209CE9),
  'solana': Color(0xFF9945FF),
  'paypal': Color(0xFF0070BA),
  'venmo': Color(0xFF3D95CE),
  'revolut': Color(0xFF191C1F),
  'cashme': Color(0xFF00D632),
};

String _ticker(String type) => _tickers[type] ?? type.toUpperCase();

String _truncateAddress(String address) {
  const totalLength = 16;
  const suffixLength = 4;
  if (address.length <= totalLength) return address;
  final prefixLength = totalLength - suffixLength - 3;
  final prefix = address.substring(0, prefixLength);
  final suffix = address.substring(address.length - suffixLength);
  return '$prefix...$suffix';
}

class PaymentTargetChip extends StatelessWidget {
  const PaymentTargetChip({super.key, required this.target});

  final NostrPaymentTarget target;

  Future<void> _open(BuildContext context) async {
    final opened = await launchUrl(
      target.launchUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No app found to open ${target.type} addresses'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = _brandColors[target.type] ?? theme.colorScheme.outline;
    final background = Color.alphaBlend(
      tint.withValues(alpha: theme.brightness == Brightness.dark ? 0.24 : 0.14),
      theme.colorScheme.surface,
    );

    return Material(
      color: background,
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: InkWell(
        key: Key('paymentTarget_${target.type}_${target.address}'),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 14,
                color: tint,
              ),
              const SizedBox(width: 6),
              Text(
                _ticker(target.type),
                style: theme.metadata?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: tint,
                ),
              ),
              const SizedBox(width: 4),
              Text(_truncateAddress(target.address), style: theme.metadata),
            ],
          ),
        ),
      ),
    );
  }
}
