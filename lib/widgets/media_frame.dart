import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

import '../services/media_loader.dart';
import '../theme/app_text_styles.dart';

/// Keeps a tall or wide file from taking over the feed.
const _minAspectRatio = 0.75;
const _maxAspectRatio = 2.4;
const _defaultAspectRatio = 16 / 9;
const _maxMediaHeight = 420.0;

/// The rounded, size-limited box a note's image or video sits in.
class MediaFrame extends StatelessWidget {
  const MediaFrame({
    super.key,
    this.aspectRatio,
    this.height,
    this.maxWidth,
    required this.child,
  });

  /// Null when the note gave no size.
  final double? aspectRatio;

  /// A fixed height, so several frames can sit side by side in a scrolling row.
  final double? height;

  /// Caps the width of a fixed-height frame, so the next one can peek in.
  final double? maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ratio = (aspectRatio ?? _defaultAspectRatio).clamp(
      _minAspectRatio,
      _maxAspectRatio,
    );
    final frame = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: child,
      ),
    );

    final height = this.height;
    if (height != null) {
      final width = height * ratio;
      return SizedBox(
        width: maxWidth == null ? width : math.min(width, maxWidth!),
        height: height,
        child: frame,
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _maxMediaHeight),
        child: AspectRatio(aspectRatio: ratio, child: frame),
      ),
    );
  }
}

/// A blurred stand-in for a file that has not loaded; it fetches nothing.
class MediaBlurhash extends StatelessWidget {
  const MediaBlurhash({super.key, required this.hash});

  final String hash;

  @override
  Widget build(BuildContext context) {
    // No image argument: the package would download it outside our loader.
    return BlurHash(
      hash: hash,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
    this.overImage = false,
  });

  final IconData icon;
  final String title;
  final String url;

  /// Replaces [icon], e.g. a progress indicator.
  final Widget? indicator;
  final Widget? action;

  /// Adds a backdrop so the text stays readable on a blurred image.
  final bool overImage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    final message = Padding(
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
    );

    return Center(
      child: overImage
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
              ),
              child: message,
            )
          : message,
    );
  }
}

/// A network image sized to its box, fading in over whatever sits behind it.
class NetworkMediaImage extends StatelessWidget {
  const NetworkMediaImage({
    super.key,
    required this.source,
    required this.errorBuilder,
  });

  final MediaSource source;
  final ImageErrorWidgetBuilder errorBuilder;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Image(
          image: ResizeImage(
            BoundedNetworkImage(source),
            width: (constraints.maxWidth * pixelRatio).round(),
            policy: ResizeImagePolicy.fit,
          ),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: errorBuilder,
        );
      },
    );
  }
}
