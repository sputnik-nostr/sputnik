import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';

class BookmarkButton extends StatelessWidget {
  const BookmarkButton({super.key, required this.note, this.size = 18});

  final Note note;
  final double size;

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
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              bookmarked ? Icons.bookmark : Icons.bookmark_border,
              size: size,
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
