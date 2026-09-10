import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../services/feed_loader.dart';
import '../widgets/note_tile.dart';
import '../widgets/placeholder_tab.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Note>?>(
      valueListenable: notesNotifier,
      builder: (context, notes, _) {
        // RefreshIndicator needs a scrollable child to attach its drag
        // gesture to, so the loading/empty states use a scrollable ListView
        // too rather than a bare centered widget.
        Widget body;
        if (notes == null) {
          body = ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(
                height: 400,
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        } else if (notes.isEmpty) {
          body = ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(
                height: 400,
                child: PlaceholderTab(
                  icon: Icons.rss_feed_outlined,
                  label: 'No posts from your relays',
                ),
              ),
            ],
          );
        } else {
          body = ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => NoteTile(note: notes[index]),
          );
        }

        return RefreshIndicator(onRefresh: loadFeed, child: body);
      },
    );
  }
}
