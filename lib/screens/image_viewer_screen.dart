import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/image_saver.dart';
import '../services/media_loader.dart';

/// Bounds the decoded size, so a huge image can't exhaust memory.
const _maxDecodeExtent = 4096;

const _pageDuration = Duration(milliseconds: 250);

/// Full-screen images to swipe between, zoom, save, or copy the link of.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.sources,
    this.initialIndex = 0,
    this.save = saveImage,
  });

  final List<MediaSource> sources;
  final int initialIndex;
  final Future<SaveResult> Function(MediaSource source) save;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late var _index = widget.initialIndex;
  var _zoomed = false;
  var _saving = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = _index + delta;
    if (_zoomed || target < 0 || target >= widget.sources.length) return;
    _pages.animateToPage(
      target,
      duration: _pageDuration,
      curve: Curves.easeOut,
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final result = await widget.save(widget.sources[_index]);
    if (!mounted) return;
    setState(() => _saving = false);
    final message = saveMessage(result);
    if (message != null) _say(message);
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.sources[_index].url));
    if (mounted) _say('Link copied');
  }

  bool get _desktop => switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final count = widget.sources.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: count > 1 ? Text('${_index + 1} / $count') : null,
        actions: [
          IconButton(
            key: const Key('copyImageLinkButton'),
            icon: const Icon(Icons.link),
            tooltip: 'Copy link',
            onPressed: _copyLink,
          ),
          IconButton(
            key: const Key('saveImageButton'),
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Save image',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              PageView.builder(
                controller: _pages,
                itemCount: count,
                // A zoomed image needs its own drags for panning.
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: (index) => setState(() {
                  _index = index;
                  _zoomed = false;
                }),
                itemBuilder: (context, index) => _ViewerPage(
                  key: ValueKey(index),
                  source: widget.sources[index],
                  onZoomChanged: (zoomed) {
                    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                  },
                ),
              ),
              // A mouse can't swipe, so desktop gets buttons as well as keys.
              if (count > 1 && _desktop) ...[
                _PageButton(
                  key: const Key('previousImageButton'),
                  alignment: Alignment.centerLeft,
                  icon: Icons.chevron_left,
                  tooltip: 'Previous image',
                  onPressed: _index > 0 && !_zoomed ? () => _go(-1) : null,
                ),
                _PageButton(
                  key: const Key('nextImageButton'),
                  alignment: Alignment.centerRight,
                  icon: Icons.chevron_right,
                  tooltip: 'Next image',
                  onPressed: _index < count - 1 && !_zoomed
                      ? () => _go(1)
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    super.key,
    required this.alignment,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Alignment alignment;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IconButton(
        icon: Icon(icon),
        iconSize: 36,
        color: Colors.white,
        disabledColor: Colors.white24,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

class _ViewerPage extends StatefulWidget {
  const _ViewerPage({
    super.key,
    required this.source,
    required this.onZoomChanged,
  });

  final MediaSource source;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  final _transform = TransformationController();

  @override
  void initState() {
    super.initState();
    _transform.addListener(
      () => widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01),
    );
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _transform,
      minScale: 1,
      maxScale: 4,
      child: SizedBox.expand(
        child: Image(
          image: ResizeImage(
            BoundedNetworkImage(widget.source),
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
    );
  }
}
