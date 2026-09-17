import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';

// A circular avatar whose image fades in once loaded instead of abruptly
// replacing the fallback (e.g. initials). The fallback stays visible
// underneath while there's no image, it's still loading, or it fails to
// load, and is hidden once the image loads so it can't show through a
// transparent picture. Loading is gated on loadMediaNotifier (reveals the
// viewer's IP to the image host).
class FadeInAvatar extends StatefulWidget {
  const FadeInAvatar({
    super.key,
    required this.imageUrl,
    required this.backgroundColor,
    required this.fallback,
    this.radius = 20,
    this.minDecodeExtent,
  });

  final String? imageUrl;
  final Color backgroundColor;
  final Widget fallback;
  final double radius;

  // Raises the decode resolution above what the widget's own on-screen size
  // would need, for placements (e.g. the profile page) that want a sharper
  // result than a low-DPI display's native pixels, short of full source
  // resolution.
  final int? minDecodeExtent;

  @override
  State<FadeInAvatar> createState() => _FadeInAvatarState();
}

class _FadeInAvatarState extends State<FadeInAvatar> {
  final _loaded = ValueNotifier(false);

  @override
  void didUpdateWidget(covariant FadeInAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _loaded.value = false;
  }

  @override
  void dispose() {
    _loaded.dispose();
    super.dispose();
  }

  void _markLoaded(bool loaded) {
    if (_loaded.value == loaded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loaded.value = loaded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;
    final sizeMatchedExtent =
        (diameter * MediaQuery.devicePixelRatioOf(context)).round();
    final decodeExtent = widget.minDecodeExtent == null
        ? sizeMatchedExtent
        : math.max(sizeMatchedExtent, widget.minDecodeExtent!);

    return ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: widget.backgroundColor,
              child: ValueListenableBuilder<bool>(
                valueListenable: _loaded,
                builder: (context, loaded, child) =>
                    loaded ? const SizedBox.shrink() : child!,
                child: Center(child: widget.fallback),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: loadMediaNotifier,
              builder: (context, loadMedia, _) {
                final url = widget.imageUrl;
                if (url == null || !loadMedia) {
                  _markLoaded(false);
                  return const SizedBox.shrink();
                }
                return Image(
                  image: ResizeImage(
                    NetworkImage(url),
                    width: decodeExtent,
                    height: decodeExtent,
                    policy: ResizeImagePolicy.fit,
                  ),
                  fit: BoxFit.cover,
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        _markLoaded(frame != null);
                        if (wasSynchronouslyLoaded) return child;
                        return AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          child: child,
                        );
                      },
                  errorBuilder: (_, _, _) {
                    _markLoaded(false);
                    return const SizedBox.shrink();
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
