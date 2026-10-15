import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

/// A small icon button under a note, with an optional count beside it.
class NoteActionButton extends StatelessWidget {
  const NoteActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
    this.count = 0,
    this.size = 16,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Hidden when zero.
  final int count;
  final double size;

  /// Defaults to the theme's outline color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        onLongPress: onLongPress,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: size, color: color ?? theme.colorScheme.outline),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Text('$count', style: theme.metadata),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
