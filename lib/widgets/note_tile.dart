import 'package:flutter/material.dart';

import '../models/note.dart';

class NoteTile extends StatefulWidget {
  const NoteTile({super.key, required this.note});

  final Note note;

  @override
  State<NoteTile> createState() => _NoteTileState();
}

class _NoteTileState extends State<NoteTile> {
  bool _bookmarked = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = widget.note;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              note.displayName[0],
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
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
                      child: Text(
                        note.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
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
                Row(
                  children: [
                    _StatButton(
                      icon: Icons.chat_bubble_outline,
                      count: note.replyCount,
                    ),
                    const SizedBox(width: 20),
                    _StatButton(icon: Icons.repeat, count: note.repostCount),
                    const SizedBox(width: 20),
                    _StatButton(
                      icon: Icons.favorite_border,
                      count: note.likeCount,
                    ),
                    const Spacer(),
                    _BookmarkButton(
                      bookmarked: _bookmarked,
                      onTap: () => setState(() => _bookmarked = !_bookmarked),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
  const _BookmarkButton({required this.bookmarked, required this.onTap});

  final bool bookmarked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
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
  }
}
