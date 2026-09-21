import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../nostr/http_urls.dart';
import '../nostr/models/nostr_media.dart';
import '../screens/image_viewer_screen.dart';
import '../services/blossom_servers.dart';
import 'linkified_text.dart';
import 'media_frame.dart';
import 'note_video.dart';
import 'open_url.dart';

/// URLs tapped this session, so a tile scrolled back into view stays loaded.
final _approved = <String>{};
const _maxApproved = 500;

/// How tall each tile is when a note has several and they scroll sideways.
const _rowHeight = 200.0;

/// Each tile takes at most this much of the row, so the next one peeks in.
const _rowTileShare = 0.8;

/// A note's text and its images and videos, per [loadNoteImagesNotifier].
class NoteContent extends StatelessWidget {
  const NoteContent({
    super.key,
    required this.note,
    this.style,
    this.selectable = true,
  });

  final Note note;
  final TextStyle? style;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (note.media.isEmpty) {
      return LinkifiedText(note.content, style: style, selectable: selectable);
    }

    return ValueListenableBuilder<bool>(
      valueListenable: loadNoteImagesNotifier,
      builder: (context, autoLoad, _) {
        final text = withoutUrls(note.content, {
          for (final media in note.media) media.url,
        });
        final images = [
          for (final media in note.media)
            if (media.type == MediaType.image) media,
        ];

        Widget tile(NostrMedia media, {double? height, double? maxWidth}) {
          return switch (media.type) {
            MediaType.image => _ImageTile(
              key: ValueKey(media.url),
              media: media,
              gallery: images,
              authorPubkey: note.pubkey,
              autoLoad: autoLoad,
              frameHeight: height,
              frameMaxWidth: maxWidth,
            ),
            // Videos wait for a tap even when images load on their own.
            MediaType.video => NoteVideoTile(
              key: ValueKey(media.url),
              media: media,
              authorPubkey: note.pubkey,
              frameHeight: height,
              frameMaxWidth: maxWidth,
            ),
          };
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (text.isNotEmpty)
              LinkifiedText(text, style: style, selectable: selectable),
            Padding(
              padding: EdgeInsets.only(top: text.isEmpty ? 0 : 8),
              child: note.media.length == 1
                  ? tile(note.media.single)
                  : _ScrollingRow(
                      count: note.media.length,
                      itemBuilder: (index, maxWidth) => tile(
                        note.media[index],
                        height: _rowHeight,
                        maxWidth: maxWidth,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Tiles side by side that scroll sideways, like a profile's payment chips.
class _ScrollingRow extends StatefulWidget {
  const _ScrollingRow({required this.count, required this.itemBuilder});

  final int count;

  /// Builds tile [index], which may be at most the given width.
  final Widget Function(int index, double maxWidth) itemBuilder;

  @override
  State<_ScrollingRow> createState() => _ScrollingRowState();
}

class _ScrollingRowState extends State<_ScrollingRow> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mouse dragging is off by default on desktop, where it is the only way.
    final behavior = ScrollConfiguration.of(context).copyWith(
      dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      },
    );

    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      _ => false,
    };

    return ScrollConfiguration(
      behavior: behavior,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth * _rowTileShare;
          return Scrollbar(
            controller: _controller,
            // A mouse has no touch cue that the row scrolls, so show the bar.
            thumbVisibility: desktop,
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  for (var i = 0; i < widget.count; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    widget.itemBuilder(i, maxWidth),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ImageTile extends StatefulWidget {
  const _ImageTile({
    super.key,
    required this.media,
    required this.gallery,
    required this.authorPubkey,
    required this.autoLoad,
    this.frameHeight,
    this.frameMaxWidth,
  });

  final NostrMedia media;

  /// Every image in the note, so the viewer can swipe between them.
  final List<NostrMedia> gallery;
  final String authorPubkey;
  final bool autoLoad;
  final double? frameHeight;
  final double? frameMaxWidth;

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile> {
  late bool _tapped = _approved.contains(widget.media.url);

  void _load() {
    if (_approved.length >= _maxApproved) _approved.clear();
    _approved.add(widget.media.url);
    setState(() => _tapped = true);
  }

  void _open() {
    final index = widget.gallery.indexOf(widget.media);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          sources: [
            for (final media in widget.gallery)
              mediaSourceFor(media, widget.authorPubkey),
          ],
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final blurhash = media.blurhash;
    final loading = _tapped || widget.autoLoad;

    return MediaFrame(
      aspectRatio: media.aspectRatio,
      height: widget.frameHeight,
      maxWidth: widget.frameMaxWidth,
      child: Semantics(
        image: true,
        button: true,
        label: media.alt ?? 'Image',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: loading ? _open : _load,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (blurhash != null) MediaBlurhash(hash: blurhash),
              if (loading)
                NetworkMediaImage(
                  source: mediaSourceFor(media, widget.authorPubkey),
                  errorBuilder: (context, error, stackTrace) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => openExternalUrl(context, media.url),
                    child: MediaTileMessage(
                      icon: Icons.broken_image_outlined,
                      title: 'Could not load image. Tap to open the link.',
                      url: media.url,
                      overImage: blurhash != null,
                    ),
                  ),
                )
              else
                MediaTileMessage(
                  icon: Icons.image_outlined,
                  title: 'Tap to load',
                  url: media.url,
                  overImage: blurhash != null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
