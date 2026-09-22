import 'package:flutter/material.dart';

import '../models/note.dart';
import '../nostr/nostr.dart';
import '../services/reaction_actions.dart';
import '../theme/app_text_styles.dart';

/// A like button for [note]; toggles a like on tap.
class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.note,
    this.relayClient = const RelayClient(),
    this.showCount = true,
    this.size = 16,
  });

  final Note note;
  final RelayClient relayClient;
  final bool showCount;
  final double size;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  bool _pending = false;

  /// Set once this button has toggled a like itself; null defers to
  /// [Note.likedByMe].
  bool? _localOverride;

  Future<void> _tap() async {
    final liked = _localOverride ?? widget.note.likedByMe;
    setState(() => _pending = true);
    final succeeded = liked
        ? await unlikeNote(
            context,
            widget.note,
            relayClient: widget.relayClient,
          )
        : await likeNote(context, widget.note, relayClient: widget.relayClient);
    if (!mounted) return;
    setState(() {
      _pending = false;
      if (succeeded) _localOverride = !liked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liked = _localOverride ?? widget.note.likedByMe;
    final count =
        widget.note.likeCount +
        (liked == widget.note.likedByMe ? 0 : (liked ? 1 : -1));
    final color = liked ? theme.colorScheme.primary : theme.colorScheme.outline;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          liked ? Icons.favorite : Icons.favorite_border,
          size: widget.size,
          color: color,
        ),
        if (widget.showCount && count > 0) ...[
          const SizedBox(width: 4),
          Text('$count', style: theme.metadata),
        ],
      ],
    );

    return Tooltip(
      message: liked ? 'Liked' : 'Like',
      child: InkResponse(
        onTap: _pending ? null : _tap,
        radius: 20,
        child: Padding(padding: const EdgeInsets.all(4), child: content),
      ),
    );
  }
}

/// A repost button for [note]; toggles a repost on tap.
class RepostButton extends StatefulWidget {
  const RepostButton({
    super.key,
    required this.note,
    this.relayClient = const RelayClient(),
    this.showCount = true,
    this.size = 16,
  });

  final Note note;
  final RelayClient relayClient;
  final bool showCount;
  final double size;

  @override
  State<RepostButton> createState() => _RepostButtonState();
}

class _RepostButtonState extends State<RepostButton> {
  bool _pending = false;

  /// Set once this button has toggled a repost itself; null defers to
  /// [Note.repostedByMe].
  bool? _localOverride;

  Future<void> _tap() async {
    final reposted = _localOverride ?? widget.note.repostedByMe;
    setState(() => _pending = true);
    final succeeded = reposted
        ? await unrepostNote(
            context,
            widget.note,
            relayClient: widget.relayClient,
          )
        : await repostNote(
            context,
            widget.note,
            relayClient: widget.relayClient,
          );
    if (!mounted) return;
    setState(() {
      _pending = false;
      if (succeeded) _localOverride = !reposted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reposted = _localOverride ?? widget.note.repostedByMe;
    final count =
        widget.note.repostCount +
        (reposted == widget.note.repostedByMe ? 0 : (reposted ? 1 : -1));
    final color = reposted
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.repeat, size: widget.size, color: color),
        if (widget.showCount && count > 0) ...[
          const SizedBox(width: 4),
          Text('$count', style: theme.metadata),
        ],
      ],
    );

    return Tooltip(
      message: reposted ? 'Reposted' : 'Repost',
      child: InkResponse(
        onTap: _pending ? null : _tap,
        radius: 20,
        child: Padding(padding: const EdgeInsets.all(4), child: content),
      ),
    );
  }
}
