import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../nostr/models/nostr_payment_target.dart';
import '../nostr/models/payment_target_types.dart';
import '../nostr/nip19.dart';
import '../theme/app_text_styles.dart';

// Kept separate from PaymentTargetTypeInfo since Color is a UI concern and
// the model layer stays Flutter-free.
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
  'zano': Color(0xFF274CFF),
  'firo': Color(0xFFBA2A45),
  'nano': Color(0xFF209CE9),
  'solana': Color(0xFF9945FF),
  'tron': Color(0xFFFF060A),
  'paypal': Color(0xFF0070BA),
  'venmo': Color(0xFF3D95CE),
  'cashme': Color(0xFF00D632),
};

String _ticker(String type) =>
    paymentTargetTypes[type]?.ticker ?? type.toUpperCase();

// Proper-noun currency names stay capitalized even mid-sentence.
String _displayName(String type) =>
    paymentTargetTypes[type]?.displayName ??
    (type.isEmpty ? type : type[0].toUpperCase() + type.substring(1));

// All types the app recognizes, for the "hide address types" setting.
final knownPaymentTargetTypes = paymentTargetTypes.keys.toList();

String paymentTargetTypeDisplayName(String type) => _displayName(type);

// A hint under a type's display name: its ticker, or a short description.
String? paymentTargetTypeSubtitle(String type) {
  final info = paymentTargetTypes[type];
  final description = info?.description;
  final ticker = info?.ticker;
  if (description == null) return ticker;
  return ticker == null ? description : '$description ($ticker)';
}

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
    // Revolut's brand color is near-black, so follow the theme to stay legible.
    final tint = target.type == 'revolut'
        ? theme.colorScheme.onSurface
        : _brandColors[target.type] ?? theme.colorScheme.outline;
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
