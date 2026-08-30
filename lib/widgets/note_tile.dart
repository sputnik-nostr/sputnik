import 'package:flutter/material.dart';

import '../models/note.dart';
import '../screens/post_screen.dart';
import '../screens/profile_screen.dart';
import '../theme/app_text_styles.dart';
import 'bookmark_button.dart';
import 'fade_in_avatar.dart';
import 'linkified_text.dart';

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

    return InkWell(
      onTap: () => _openPost(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => openProfile(context, note.pubkey),
              child: FadeInAvatar(
                imageUrl: note.pictureUrl,
                backgroundColor: theme.colorScheme.primaryContainer,
                fallback: Text(
                  note.displayName[0].toUpperCase(),
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
                            overflow: TextOverflow.ellipsis,
                            style: theme.avatarName,
                          ),
                        ),
                      ),
                      Text(note.postedAt, style: theme.metadata),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinkifiedText(
                    note.content,
                    style: theme.textTheme.bodyMedium,
                  ),
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
                        BookmarkButton(note: note),
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
    final theme = Theme.of(context);
    final color = theme.colorScheme.outline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Text('$count', style: theme.metadata),
        ],
      ],
    );
  }
}
