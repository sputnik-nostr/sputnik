import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/avatar_initial.dart';
import '../models/note.dart';
import '../models/time_format.dart';
import '../nostr/nostr.dart';
import '../screens/compose_screen.dart';
import '../screens/post_screen.dart';
import '../screens/profile_screen.dart';
import '../theme/app_text_styles.dart';
import 'bookmark_button.dart';
import 'delete_button.dart';
import 'fade_in_avatar.dart';
import 'note_action_button.dart';
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
                          Text(
                            relativeTime(note.createdAt),
                            style: theme.metadata,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      NoteContent(
                        note: note,
                        style: theme.textTheme.bodyMedium,
                        selectable: false,
                      ),
                      const SizedBox(height: 8),
                      _NoteActions(note: note),
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

/// Where in [notes] the row keyed [key] is now, for a list's
/// `findItemIndexCallback`.
///
/// Rows are keyed `ValueKey(note.id)`. With this, what a row remembers, such
/// as a like it just made, moves with its note when the list shifts instead of
/// being dropped. Two rows with one key would break that, so [notes] must hold
/// each note once, as a feed's cursor and the map of bookmarks make sure.
int? indexOfNoteRow(List<Note> notes, Key key) {
  if (key is! ValueKey<String>) return null;
  final index = notes.indexWhere((note) => note.id == key.value);
  return index < 0 ? null : index;
}

/// Reply, repost, like, bookmark and, on the active identity's own notes,
/// delete.
class _NoteActions extends StatelessWidget {
  const _NoteActions({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    // Tiles outlive an identity switch, so what they offer has to follow it.
    return ValueListenableBuilder<String?>(
      valueListenable: activeIdentityPubkeyNotifier,
      builder: (context, activePubkey, _) {
        final isOwnNote =
            note.pubkey.toLowerCase() == activePubkey?.toLowerCase();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              NoteActionButton(
                key: const Key('replyButton'),
                icon: Icons.chat_bubble_outline,
                count: note.replyCount,
                tooltip: 'Reply',
                onTap: () => openReplyComposer(context, note),
              ),
              const SizedBox(width: 20),
              RepostButton(note: note),
              const SizedBox(width: 20),
              LikeButton(note: note),
              const SizedBox(width: 20),
              BookmarkButton(note: note),
              if (isOwnNote) ...[
                const SizedBox(width: 20),
                DeleteButton(note: note),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Opens the composer for a reply and returns the published reply, if any.
Future<NostrEvent?> openReplyComposer(BuildContext context, Note note) {
  return Navigator.push<NostrEvent>(
    context,
    MaterialPageRoute(
      builder: (_) => ComposeScreen(replyTo: note),
      fullscreenDialog: true,
    ),
  );
}
