import 'package:flutter/material.dart';

import '../main.dart';
import '../models/current_user.dart';
import '../models/note.dart';
import '../widgets/note_tile.dart';
import '../widgets/placeholder_tab.dart';

String _truncateNpub(String npub) {
  const totalLength = 25;
  const suffixLength = 8;
  if (npub.length <= totalLength) return npub;
  final prefixLength = totalLength - suffixLength - 3;
  final prefix = npub.substring(0, prefixLength);
  final suffix = npub.substring(npub.length - suffixLength);
  return '$prefix...$suffix';
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.npub = CurrentUser.npub});

  final String npub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: ValueListenableBuilder<List<Note>>(
        valueListenable: notesNotifier,
        builder: (context, notes, _) {
          final ownNotes = notes.where((note) => note.pubkey == npub).toList();

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        CurrentUser.displayName[0],
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            CurrentUser.displayName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _truncateNpub(npub),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (ownNotes.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: PlaceholderTab(
                    icon: Icons.notes_outlined,
                    label: 'No posts yet',
                  ),
                )
              else
                for (final note in ownNotes) ...[
                  NoteTile(note: note),
                  const Divider(height: 1),
                ],
            ],
          );
        },
      ),
    );
  }
}
