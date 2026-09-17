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
    this.highQuality = false,
  });

  final String? imageUrl;
  final Color backgroundColor;
  final Widget fallback;
  final double radius;

  final bool highQuality;

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
    final decodeExtent = (diameter * MediaQuery.devicePixelRatioOf(context))
        .round();

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
                  image: widget.highQuality
                      ? NetworkImage(url)
                      : ResizeImage(
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
