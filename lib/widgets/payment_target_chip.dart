import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../nostr/models/nostr_payment_target.dart';
import '../nostr/nip19.dart';
import '../theme/app_text_styles.dart';

const _tickers = <String, String>{
  'bitcoin': 'BTC',
  'lightning': 'LN',
  'bip352': 'BTC',
  'bip353': 'BTC',
  'bitcoincash': 'BCH',
  'litecoin': 'LTC',
  'monero': 'XMR',
  'ethereum': 'ETH',
  'zcash': 'ZEC',
  'nano': 'NANO',
  'solana': 'SOL',
  'tron': 'TRX',
};

const _brandColors = <String, Color>{
  'bitcoin': Color(0xFFF7931A),
  'lightning': Color(0xFFF7931A),
  'bip352': Color(0xFFF7931A),
  'bip353': Color(0xFFF7931A),
  'bitcoincash': Color(0xFF0AC18E),
  'litecoin': Color(0xFF345D9D),
  'monero': Color(0xFFFF6600),
  'ethereum': Color(0xFF627EEA),
  'zcash': Color(0xFFF4B728),
  'nano': Color(0xFF209CE9),
  'solana': Color(0xFF9945FF),
  'tron': Color(0xFFFF060A),
  'paypal': Color(0xFF0070BA),
  'venmo': Color(0xFF3D95CE),
  'revolut': Color(0xFF191C1F),
  'cashme': Color(0xFF00D632),
};

const _displayNames = <String, String>{
  'bitcoin': 'Bitcoin',
  'lightning': 'Lightning',
  'bip352': 'BIP-352',
  'bip353': 'BIP-353',
  'bitcoincash': 'Bitcoin Cash',
  'litecoin': 'Litecoin',
  'monero': 'Monero',
  'ethereum': 'Ethereum',
  'zcash': 'Zcash',
  'nano': 'Nano',
  'solana': 'Solana',
  'tron': 'Tron',
  'paypal': 'PayPal',
  'venmo': 'Venmo',
  'revolut': 'Revolut',
  'cashme': 'CashMe',
};

String _ticker(String type) => _tickers[type] ?? type.toUpperCase();

// Proper-noun currency names stay capitalized even mid-sentence.
String _displayName(String type) =>
    _displayNames[type] ??
    (type.isEmpty ? type : type[0].toUpperCase() + type.substring(1));

class PaymentTargetChip extends StatelessWidget {
  const PaymentTargetChip({super.key, required this.target});

  final NostrPaymentTarget target;

  Future<void> _open(BuildContext context) async {
    bool opened;
    try {
      opened = await launchUrl(
        target.launchUri,
        mode: LaunchMode.externalApplication,
      );
    } on PlatformException {
      opened = false;
    } on MissingPluginException {
      opened = false;
    } on FormatException {
      // The event tag data behind this target didn't form a valid URI.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'This ${_displayName(target.type)} address looks malformed',
            ),
          ),
        );
      }
      return;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No app found to open ${_displayName(target.type)} addresses',
          ),
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
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: target.address));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Copied ${_displayName(target.type)} address to clipboard',
              ),
            ),
          );
        },
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
              Text(
                truncateMiddle(
                  target.address,
                  totalLength: 16,
                  suffixLength: 4,
                ),
                style: theme.metadata,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
