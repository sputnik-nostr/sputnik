import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../models/note_mapper.dart';
import '../nostr/nostr.dart';
import '../widgets/linkified_text.dart';
import '../widgets/note_tile.dart';
import 'profile_screen.dart';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatAbsoluteTime(DateTime time) {
  final local = time.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  final month = _monthNames[local.month - 1];
  return '$hour12:$minute $period · $month ${local.day}, ${local.year}';
}

class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.note});

  final Note note;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  late final Future<List<Note>> _repliesFuture;

  @override
  void initState() {
    super.initState();
    _repliesFuture = _loadReplies();
  }

  Future<List<Note>> _loadReplies() async {
    final relayUrls = selectedRelaysNotifier.value;
    final thread = await const RelayThreadRepository().fetchThread(
      widget.note.id,
      relayUrls,
    );

    notesNotifier.value = notesNotifier.value
        ?.map(
          (note) => note.id == widget.note.id
              ? note.copyWith(
                  likeCount: thread.likeCount,
                  repostCount: thread.repostCount,
                  replyCount: thread.replies.length,
                )
              : note,
        )
        .toList();

    final authorPubkeys = thread.replies
        .map((post) => post.author.pubkey)
        .toSet();
    final profilesByPubkey = await const RelayProfileRepository().fetchProfiles(
      authorPubkeys,
      relayUrls,
    );

    return thread.replies
        .map(
          (post) => noteFromNostrPost(
            post,
            authorMetadata: profilesByPubkey[post.author.pubkey],
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder<List<Note>>(
        future: _repliesFuture,
        builder: (context, snapshot) {
          final replies = snapshot.data;
          return ListView(
            children: [
              _PostHeader(note: widget.note, replyCount: replies?.length),
              const Divider(height: 1),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (replies == null || replies.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No replies yet')),
                )
              else
                for (final reply in replies) ...[
                  NoteTile(note: reply),
                  const Divider(height: 1),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _PostHeader extends StatelessWidget {
  const _PostHeader({required this.note, required this.replyCount});

  final Note note;
  final int? replyCount;

  void _openProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(pubkeyHex: note.pubkey)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final npub = npubFromHex(note.pubkey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openProfile(context),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      backgroundImage: note.pictureUrl != null
                          ? NetworkImage(note.pictureUrl!)
                          : null,
                      onBackgroundImageError: note.pictureUrl != null
                          ? (_, _) {}
                          : null,
                      child: note.pictureUrl == null
                          ? Text(
                              note.displayName[0].toUpperCase(),
                              style: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            truncateNpub(npub),
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LinkifiedText(note.content, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 16),
              Text(
                _formatAbsoluteTime(note.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              _StatCount(
                count: replyCount ?? note.replyCount,
                label: 'replies',
              ),
              const SizedBox(width: 20),
              _StatCount(count: note.repostCount, label: 'reposts'),
              const SizedBox(width: 20),
              _StatCount(count: note.likeCount, label: 'likes'),
              const Spacer(),
              _HeaderBookmarkButton(note: note),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCount extends StatelessWidget {
  const _StatCount({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodySmall,
        children: [
          TextSpan(
            text: '$count ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: label,
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _HeaderBookmarkButton extends StatelessWidget {
  const _HeaderBookmarkButton({required this.note});

  final Note note;

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
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              bookmarked ? Icons.bookmark : Icons.bookmark_border,
              size: 20,
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
