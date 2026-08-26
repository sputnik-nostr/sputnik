import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../widgets/note_tile.dart';
import '../widgets/placeholder_tab.dart';

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: bookmarkedIdsNotifier,
      builder: (context, bookmarkedIds, _) {
        return ValueListenableBuilder<List<Note>>(
          valueListenable: notesNotifier,
          builder: (context, notes, _) {
            final bookmarkedNotes = notes
                .where((note) => bookmarkedIds.contains(note.id))
                .toList();

            if (bookmarkedNotes.isEmpty) {
              return const PlaceholderTab(
                icon: Icons.bookmark_border,
                label: 'No bookmarks yet',
              );
            }

            return ListView.separated(
              itemCount: bookmarkedNotes.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  NoteTile(note: bookmarkedNotes[index]),
            );
          },
        );
      },
    );
  }
}
