import 'package:flutter/material.dart';

import '../nostr/nip05.dart';
import '../theme/app_text_styles.dart';

/// Shows a NIP-05 identifier alongside an icon reflecting its verification
/// state (unchecked, checking, verified, mismatched, or unreachable).
class Nip05Badge extends StatelessWidget {
  const Nip05Badge({
    super.key,
    required this.identifier,
    this.status,
    this.onVerify,
  });

  final String identifier;
  final Nip05Status? status;

  /// Set while unchecked; tapping the icon starts the check.
  final VoidCallback? onVerify;

  String get _displayIdentifier =>
      identifier.startsWith('_@') ? identifier.substring(2) : identifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onVerify = this.onVerify;
    if (onVerify != null) {
      return _row(
        theme,
        Tooltip(
          message:
              'Tap to verify with ${parseNip05(identifier)?.domain ?? identifier}',
          child: InkWell(
            key: const Key('verifyNip05Button'),
            onTap: onVerify,
            customBorder: const CircleBorder(),
            child: Icon(
              Icons.travel_explore,
              size: 14,
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }

    final (icon, color, tooltip) = switch (status) {
      null => (Icons.hourglass_empty, theme.colorScheme.outline, 'Checking...'),
      Nip05Status.verified => (
        Icons.verified,
        theme.colorScheme.primary,
        'Verified by $_displayIdentifier',
      ),
      Nip05Status.mismatch => (
        Icons.error_outline,
        theme.colorScheme.error,
        "Doesn't match $_displayIdentifier",
      ),
      Nip05Status.unreachable => (
        Icons.help_outline,
        theme.colorScheme.outline,
        'Could not verify $_displayIdentifier',
      ),
    };

    return _row(
      theme,
      Tooltip(
        message: tooltip,
        triggerMode: TooltipTriggerMode.tap,
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }

  Widget _row(ThemeData theme, Widget statusIcon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            _displayIdentifier,
            overflow: TextOverflow.ellipsis,
            style: theme.metadata,
          ),
        ),
        const SizedBox(width: 4),
        statusIcon,
      ],
    );
  }
}
