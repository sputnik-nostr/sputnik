import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../widgets/note_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Note>>(
      valueListenable: notesNotifier,
      builder: (context, notes, _) {
        if (notes.isEmpty) {
          return const Center(child: CircularProgressIndicator());
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
