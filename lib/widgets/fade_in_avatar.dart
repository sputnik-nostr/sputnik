import 'package:flutter/material.dart';

// A circular avatar whose image fades in once loaded instead of abruptly
// replacing the fallback (e.g. initials), which stays visible underneath if
// there's no image, it's still loading, or it fails to load.
class FadeInAvatar extends StatelessWidget {
  const FadeInAvatar({
    super.key,
    required this.imageUrl,
    required this.backgroundColor,
    required this.fallback,
    this.radius = 20,
  });

  final String? imageUrl;
  final Color backgroundColor;
  final Widget fallback;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final diameter = radius * 2;

    return ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: backgroundColor,
              child: Center(child: fallback),
            ),
            if (url != null)
              Image.network(
                url,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    child: child,
                  );
                },
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}
