import 'dart:io';

import 'package:flutter/material.dart';

import '../main.dart';
import '../nostr/models/nostr_media.dart';
import '../services/blossom_servers.dart';
import '../services/media_loader.dart';
import '../services/video_store.dart';
import 'media_frame.dart';
import 'media_kit_player.dart';
import 'open_url.dart';

typedef VideoPlayerBuilder = Widget Function(BuildContext context, File file);

Widget _defaultPlayer(BuildContext context, File file) {
  return MediaKitPlayer(file: file);
}

enum _Phase { idle, downloading, ready, failed }

/// The tile that most recently started a video; every other one stops.
final _activeVideo = ValueNotifier<Object?>(null);

/// A video that is downloaded only when tapped, then played from disk.
class NoteVideoTile extends StatefulWidget {
  const NoteVideoTile({
    super.key,
    required this.media,
    required this.authorPubkey,
    this.frameHeight,
    this.frameMaxWidth,
    this.store,
    this.playerBuilder = _defaultPlayer,
  });

  final NostrMedia media;
  final String authorPubkey;

  /// A fixed height, when the tile sits in a scrolling row.
  final double? frameHeight;
  final double? frameMaxWidth;
  final VideoStore? store;
  final VideoPlayerBuilder playerBuilder;

  @override
  State<NoteVideoTile> createState() => _NoteVideoTileState();
}

class _NoteVideoTileState extends State<NoteVideoTile> {
  var _phase = _Phase.idle;
  File? _file;
  int? _percent;
  DownloadCanceller? _canceller;

  @override
  void initState() {
    super.initState();
    _activeVideo.addListener(_yieldToOtherVideo);
  }

  void _yieldToOtherVideo() {
    if (_activeVideo.value == this) return;
    if (_phase == _Phase.downloading) _canceller?.cancel();
    if (_phase == _Phase.ready) setState(() => _phase = _Phase.idle);
  }

  Future<void> _start() async {
    _activeVideo.value = this;
    final canceller = _canceller = DownloadCanceller();
    setState(() {
      _phase = _Phase.downloading;
      _percent = null;
    });

    try {
      final file = await (widget.store ?? VideoStore.instance).fetch(
        mediaSourceFor(widget.media, widget.authorPubkey),
        canceller: canceller,
        onProgress: (received, total) {
          if (!mounted || total == null || total == 0) return;
          final percent = received * 100 ~/ total;
          if (percent != _percent) setState(() => _percent = percent);
        },
      );
      if (!mounted) return;
      setState(() {
        _file = file;
        _phase = _Phase.ready;
      });
    } on DownloadCancelled {
      if (mounted) setState(() => _phase = _Phase.idle);
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  @override
  void dispose() {
    _activeVideo.removeListener(_yieldToOtherVideo);
    _canceller?.cancel();
    super.dispose();
  }

  /// The blurred stand-in and, once images may load, the poster.
  Widget _backdrop() {
    final blurhash = widget.media.blurhash;
    final poster = widget.media.posterUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (blurhash != null) MediaBlurhash(hash: blurhash),
        if (poster != null)
          ValueListenableBuilder<bool>(
            valueListenable: loadNoteImagesNotifier,
            builder: (context, autoLoad, _) {
              if (!autoLoad) return const SizedBox.shrink();
              return NetworkMediaImage(
                source: MediaSource(url: poster),
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              );
            },
          ),
      ],
    );
  }

  Widget _message(BuildContext context) {
    final url = widget.media.url;
    final overImage =
        widget.media.blurhash != null || widget.media.posterUrl != null;
    switch (_phase) {
      case _Phase.idle:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _start,
          child: MediaTileMessage(
            icon: Icons.play_circle_outline,
            title: 'Tap to play',
            url: url,
            overImage: overImage,
          ),
        );
      case _Phase.downloading:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _canceller?.cancel(),
          child: MediaTileMessage(
            icon: Icons.downloading,
            title: _percent == null
                ? 'Downloading. Tap to cancel'
                : 'Downloading $_percent%. Tap to cancel',
            url: url,
            overImage: overImage,
            indicator: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                value: _percent == null ? null : _percent! / 100,
              ),
            ),
          ),
        );
      case _Phase.failed:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _start,
          child: MediaTileMessage(
            icon: Icons.error_outline,
            title: 'Could not load video. Tap to try again',
            url: url,
            overImage: overImage,
            action: TextButton(
              onPressed: () => openExternalUrl(context, url),
              child: const Text('Open link'),
            ),
          ),
        );
      case _Phase.ready:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MediaFrame(
      aspectRatio: widget.media.aspectRatio,
      height: widget.frameHeight,
      maxWidth: widget.frameMaxWidth,
      child: Semantics(
        label: widget.media.alt ?? 'Video',
        child: _phase == _Phase.ready
            ? widget.playerBuilder(context, _file!)
            : Stack(
                fit: StackFit.expand,
                children: [_backdrop(), _message(context)],
              ),
      ),
    );
  }
}
