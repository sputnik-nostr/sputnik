import 'package:flutter/material.dart';

import '../nostr/nip05.dart';
import '../theme/app_text_styles.dart';

/// Shows a NIP-05 identifier alongside an icon reflecting its verification
/// state (still checking, verified, mismatched, or unreachable/malformed).
class Nip05Badge extends StatelessWidget {
  const Nip05Badge({super.key, required this.identifier, this.status});

  final String identifier;
  final Nip05Status? status;

  String get _displayIdentifier =>
      identifier.startsWith('_@') ? identifier.substring(2) : identifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        Tooltip(
          message: tooltip,
          child: Icon(icon, size: 14, color: color),
        ),
      ],
    );
  }
}
