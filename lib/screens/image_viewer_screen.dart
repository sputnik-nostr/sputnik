import 'package:flutter/material.dart';

import '../services/media_loader.dart';

/// Bounds the decoded size, so a huge image can't exhaust memory.
const _maxDecodeExtent = 4096;

/// Full-screen pinch-to-zoom view of a network image.
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.source});

  final MediaSource source;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: SizedBox.expand(
          child: Image(
            image: ResizeImage(
              BoundedNetworkImage(source),
              width: _maxDecodeExtent,
              height: _maxDecodeExtent,
              policy: ResizeImagePolicy.fit,
            ),
            fit: BoxFit.contain,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame != null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
