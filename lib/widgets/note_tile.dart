import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../screens/post_screen.dart';
import '../screens/profile_screen.dart';

class NoteTile extends StatelessWidget {
  const NoteTile({super.key, required this.note});

  final Note note;

  void _openProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(pubkeyHex: note.pubkey)),
    );
  }

  void _openPost(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PostScreen(note: note)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => _openPost(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _openProfile(context),
              child: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: note.pictureUrl != null
                    ? NetworkImage(note.pictureUrl!)
                    : null,
                onBackgroundImageError: note.pictureUrl != null
                    ? (_, _) {}
                    : null,
                child: note.pictureUrl == null
                    ? Text(
                        note.displayName[0].toUpperCase(),
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      )
                    : null,
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
                          onTap: () => _openProfile(context),
                          child: Text(
                            note.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        note.postedAt,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(note.content, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _StatButton(
                          icon: Icons.chat_bubble_outline,
                          count: note.replyCount,
                        ),
                        const SizedBox(width: 20),
                        _StatButton(
                          icon: Icons.repeat,
                          count: note.repostCount,
                        ),
                        const SizedBox(width: 20),
                        _StatButton(
                          icon: Icons.favorite_border,
                          count: note.likeCount,
                        ),
                        const SizedBox(width: 20),
                        _BookmarkButton(note: note),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatButton extends StatelessWidget {
  const _StatButton({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Text(
            '$count',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color),
          ),
        ],
      ],
    );
  }
}

class _BookmarkButton extends StatelessWidget {
  const _BookmarkButton({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<Map<String, Note>>(
      valueListenable: bookmarkedNotesNotifier,
      builder: (context, bookmarkedNotes, _) {
        final bookmarked = bookmarkedNotes.containsKey(note.id);

        return InkWell(
          onTap: () {
            final updated = Map<String, Note>.from(bookmarkedNotes);
            if (bookmarked) {
              updated.remove(note.id);
            } else {
              updated[note.id] = note;
            }
            bookmarkedNotesNotifier.value = updated;
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              bookmarked ? Icons.bookmark : Icons.bookmark_border,
              size: 18,
              color: bookmarked
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ),
        );
      },
    );
  }
}
