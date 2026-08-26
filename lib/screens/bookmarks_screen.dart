import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../widgets/note_tile.dart';
import '../widgets/placeholder_tab.dart';

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, Note>>(
      valueListenable: bookmarkedNotesNotifier,
      builder: (context, bookmarkedNotes, _) {
        if (bookmarkedNotes.isEmpty) {
          return const PlaceholderTab(
            icon: Icons.bookmark_border,
            label: 'No bookmarks yet',
          );
        }

        final notes = bookmarkedNotes.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return ListView.separated(
          itemCount: notes.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => NoteTile(note: notes[index]),
        );
      },
    );
  }
}
