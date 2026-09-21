import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../nostr/http_urls.dart';
import '../nostr/models/nostr_media.dart';
import '../screens/image_viewer_screen.dart';
import '../services/blossom_servers.dart';
import '../services/media_loader.dart';
import 'linkified_text.dart';
import 'media_frame.dart';
import 'note_video.dart';
import 'open_url.dart';

/// URLs tapped this session, so a tile scrolled back into view stays loaded.
final _approved = <String>{};
const _maxApproved = 500;

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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (text.isNotEmpty)
              LinkifiedText(text, style: style, selectable: selectable),
            for (final media in note.media)
              Padding(
                padding: EdgeInsets.only(top: text.isEmpty ? 0 : 8),
                child: switch (media.type) {
                  MediaType.image => _ImageTile(
                    key: ValueKey(media.url),
                    media: media,
                    authorPubkey: note.pubkey,
                    autoLoad: autoLoad,
                  ),
                  // Videos wait for a tap even when images load on their own.
                  MediaType.video => NoteVideoTile(
                    key: ValueKey(media.url),
                    media: media,
                    authorPubkey: note.pubkey,
                  ),
                },
              ),
          ],
        );
      },
    );
  }
}

class _ImageTile extends StatefulWidget {
  const _ImageTile({
    super.key,
    required this.media,
    required this.authorPubkey,
    required this.autoLoad,
  });

  final NostrMedia media;
  final String authorPubkey;
  final bool autoLoad;

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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          source: mediaSourceFor(widget.media, widget.authorPubkey),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final loading = _tapped || widget.autoLoad;

    return MediaFrame(
      aspectRatio: media.aspectRatio,
      child: Semantics(
        image: true,
        button: true,
        label: media.alt ?? 'Image',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: loading ? _open : _load,
          child: loading
              ? _LoadedImage(media: media, authorPubkey: widget.authorPubkey)
              : MediaTileMessage(
                  icon: Icons.image_outlined,
                  title: 'Tap to load',
                  url: media.url,
                ),
        ),
      ),
    );
  }
}

class _LoadedImage extends StatelessWidget {
  const _LoadedImage({required this.media, required this.authorPubkey});

  final NostrMedia media;
  final String authorPubkey;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Image(
          image: ResizeImage(
            BoundedNetworkImage(mediaSourceFor(media, authorPubkey)),
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
          errorBuilder: (context, error, stackTrace) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openExternalUrl(context, media.url),
            child: MediaTileMessage(
              icon: Icons.broken_image_outlined,
              title: 'Could not load image. Tap to open the link.',
              url: media.url,
            ),
          ),
        );
      },
    );
  }
}
