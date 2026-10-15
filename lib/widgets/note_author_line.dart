import 'package:flutter/material.dart';

import '../models/avatar_initial.dart';
import '../models/note.dart';
import '../models/time_format.dart';
import '../theme/app_text_styles.dart';
import 'fade_in_avatar.dart';

/// A small avatar and name heading a quoted or previewed note.
class NoteAuthorLine extends StatelessWidget {
  const NoteAuthorLine({super.key, required this.note, this.showTime = false});

  final Note note;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        FadeInAvatar(
          radius: 10,
          imageUrl: note.pictureUrl,
          backgroundColor: theme.colorScheme.primaryContainer,
          fallback: Text(
            avatarInitial(note.displayName),
            style: theme.avatarFallback.copyWith(fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            note.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.avatarName,
          ),
        ),
        if (showTime) ...[
          const SizedBox(width: 8),
          Text(relativeTime(note.createdAt), style: theme.metadata),
        ],
      ],
    );
  }
}
