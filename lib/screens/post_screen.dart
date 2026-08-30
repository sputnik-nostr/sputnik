import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../models/note_mapper.dart';
import '../nostr/nostr.dart';
import '../theme/app_text_styles.dart';
import '../widgets/bookmark_button.dart';
import '../widgets/count_label.dart';
import '../widgets/fade_in_avatar.dart';
import '../widgets/linkified_text.dart';
import '../widgets/note_tile.dart';
import 'profile_screen.dart';
import 'users_list_screen.dart';

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

class _PostThread {
  const _PostThread({
    required this.replies,
    required this.likerPubkeys,
    required this.reposterPubkeys,
  });

  final List<Note> replies;
  final List<String> likerPubkeys;
  final List<String> reposterPubkeys;
}

class _PostScreenState extends State<PostScreen> {
  late final Future<_PostThread> _threadFuture;

  @override
  void initState() {
    super.initState();
    _threadFuture = _loadThread();
  }

  Future<_PostThread> _loadThread() async {
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
    final profilesFuture = const RelayProfileRepository().fetchProfiles(
      authorPubkeys,
      relayUrls,
    );
    final reactionsFuture = const RelayReactionsRepository().fetchReactions(
      thread.replies.map((post) => post.id).toList(),
      relayUrls,
    );

    final profilesByPubkey = await profilesFuture;
    final replyNotes = thread.replies
        .map(
          (post) => noteFromNostrPost(
            post,
            authorMetadata: profilesByPubkey[post.author.pubkey],
          ),
        )
        .toList();

    final reactionsByReplyId = await reactionsFuture;

    return _PostThread(
      replies: applyReactionCounts(replyNotes, reactionsByReplyId),
      likerPubkeys: thread.likerPubkeys,
      reposterPubkeys: thread.reposterPubkeys,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder<_PostThread>(
        future: _threadFuture,
        builder: (context, snapshot) {
          final thread = snapshot.data;
          final replies = thread?.replies;
          return ListView(
            children: [
              _PostHeader(
                note: widget.note,
                replyCount: replies?.length,
                likerPubkeys: thread?.likerPubkeys,
                reposterPubkeys: thread?.reposterPubkeys,
              ),
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
  const _PostHeader({
    required this.note,
    required this.replyCount,
    required this.likerPubkeys,
    required this.reposterPubkeys,
  });

  final Note note;
  final int? replyCount;
  final List<String>? likerPubkeys;
  final List<String>? reposterPubkeys;

  void _openUsersList(
    BuildContext context,
    String title,
    List<String> pubkeys,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UsersListScreen(title: title, pubkeys: pubkeys),
      ),
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
                onTap: () => openProfile(context, note.pubkey),
                child: Row(
                  children: [
                    FadeInAvatar(
                      radius: 22,
                      imageUrl: note.pictureUrl,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      fallback: Text(
                        note.displayName[0].toUpperCase(),
                        style: theme.avatarFallback,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(note.displayName, style: theme.avatarName),
                          Text(
                            truncateNpub(npub),
                            overflow: TextOverflow.ellipsis,
                            style: theme.metadata,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LinkifiedText(note.content, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              Text(_formatAbsoluteTime(note.createdAt), style: theme.metadata),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              CountLabel(
                count: replyCount ?? note.replyCount,
                label: 'replies',
              ),
              const SizedBox(width: 20),
              CountLabel(
                count: reposterPubkeys?.length ?? note.repostCount,
                label: 'reposts',
                onTap: reposterPubkeys == null
                    ? null
                    : () =>
                          _openUsersList(context, 'Reposts', reposterPubkeys!),
              ),
              const SizedBox(width: 20),
              CountLabel(
                count: likerPubkeys?.length ?? note.likeCount,
                label: 'likes',
                onTap: likerPubkeys == null
                    ? null
                    : () => _openUsersList(context, 'Likes', likerPubkeys!),
              ),
              const Spacer(),
              BookmarkButton(note: note, size: 20),
            ],
          ),
        ),
      ],
    );
  }
}
