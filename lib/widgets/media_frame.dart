import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

/// Keeps a tall or wide file from taking over the feed.
const _minAspectRatio = 0.75;
const _maxAspectRatio = 2.4;
const _defaultAspectRatio = 16 / 9;
const _maxMediaHeight = 420.0;

/// The rounded, size-limited box a note's image or video sits in.
class MediaFrame extends StatelessWidget {
  const MediaFrame({super.key, this.aspectRatio, required this.child});

  /// Null when the note gave no size.
  final double? aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ratio = (aspectRatio ?? _defaultAspectRatio).clamp(
      _minAspectRatio,
      _maxAspectRatio,
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _maxMediaHeight),
        child: AspectRatio(
          aspectRatio: ratio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon, a message, and the host the file would come from.
class MediaTileMessage extends StatelessWidget {
  const MediaTileMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.url,
    this.indicator,
    this.action,
  });

  final IconData icon;
  final String title;
  final String url;

  /// Replaces [icon], e.g. a progress indicator.
  final Widget? indicator;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            indicator ?? Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
            Text(
              Uri.tryParse(url)?.host ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.metadata,
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
