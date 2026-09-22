import 'package:flutter/material.dart';

import '../models/note.dart';
import '../nostr/nostr.dart';
import '../screens/compose_screen.dart';
import '../screens/post_screen.dart';
import '../screens/profile_screen.dart';
import '../theme/app_text_styles.dart';
import 'bookmark_button.dart';
import 'fade_in_avatar.dart';
import 'note_content.dart';
import 'reaction_buttons.dart';

/// A feed row for [note]; tapping it opens the post.
class NoteTile extends StatelessWidget {
  const NoteTile({super.key, required this.note});

  final Note note;

  void _openPost(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PostScreen(note: note)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final repostedByPubkey = note.repostedByPubkey;

    return InkWell(
      onTap: () => _openPost(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (repostedByPubkey != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 44),
                child: GestureDetector(
                  onTap: () => openProfile(context, repostedByPubkey),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.repeat,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${note.repostedByDisplayName} reposted',
                        style: theme.metadata,
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => openProfile(context, note.pubkey),
                  child: FadeInAvatar(
                    imageUrl: note.pictureUrl,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    fallback: Text(
                      avatarInitial(note.displayName),
                      style: theme.avatarFallback,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => openProfile(context, note.pubkey),
                              child: Text(
                                note.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.avatarName,
                              ),
                            ),
                          ),
                          Text(note.postedAt, style: theme.metadata),
                        ],
                      ),
                      const SizedBox(height: 4),
                      NoteContent(
                        note: note,
                        style: theme.textTheme.bodyMedium,
                        selectable: false,
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _StatButton(
                              key: const Key('replyButton'),
                              icon: Icons.chat_bubble_outline,
                              count: note.replyCount,
                              tooltip: 'Reply',
                              onPressed: () => openReplyComposer(context, note),
                            ),
                            const SizedBox(width: 20),
                            RepostButton(note: note),
                            const SizedBox(width: 20),
                            LikeButton(note: note),
                            const SizedBox(width: 20),
                            BookmarkButton(note: note),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the composer for a reply and returns the published reply, if any.
Future<NostrEvent?> openReplyComposer(
  BuildContext context,
  Note note, {
  RelayClient relayClient = const RelayClient(),
}) {
  return Navigator.push<NostrEvent>(
    context,
    MaterialPageRoute(
      builder: (_) => ComposeScreen(replyTo: note, relayClient: relayClient),
      fullscreenDialog: true,
    ),
  );
}

class _StatButton extends StatelessWidget {
  const _StatButton({
    super.key,
    required this.icon,
    required this.count,
    this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final int count;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.outline;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Text('$count', style: theme.metadata),
        ],
      ],
    );
    if (onPressed == null) return content;

    return Tooltip(
      message: tooltip ?? '',
      child: InkResponse(
        onTap: onPressed,
        radius: 20,
        child: Padding(padding: const EdgeInsets.all(4), child: content),
      ),
    );
  }
}
