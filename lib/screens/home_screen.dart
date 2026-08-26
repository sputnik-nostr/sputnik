import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../widgets/note_tile.dart';
import '../widgets/placeholder_tab.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Note>?>(
      valueListenable: notesNotifier,
      builder: (context, notes, _) {
        if (notes == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (notes.isEmpty) {
          return const PlaceholderTab(
            icon: Icons.rss_feed_outlined,
            label: 'No posts from your relays',
          );
        }
        return ListView.separated(
          itemCount: notes.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => NoteTile(note: notes[index]),
        );
      },
    );
  }
}
