import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../models/note_mapper.dart';
import '../models/time_format.dart';
import '../nostr/nostr.dart';
import '../theme/app_text_styles.dart';
import '../widgets/bookmark_button.dart';
import '../widgets/count_label.dart';
import '../widgets/fade_in_avatar.dart';
import '../widgets/note_content.dart';
import '../widgets/note_tile.dart';
import '../widgets/reaction_buttons.dart';
import 'profile_screen.dart';
import 'users_list_screen.dart';

class PostScreen extends StatefulWidget {
  const PostScreen({
    super.key,
    required this.note,
    this.threadRepository = const RelayThreadRepository(),
    this.relayClient = const RelayClient(),
  });

  final Note note;
  final RelayThreadRepository threadRepository;
  final RelayClient relayClient;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostThread {
  const _PostThread({
    required this.ancestors,
    required this.replyToId,
    required this.replies,
    required this.depths,
    required this.likerPubkeys,
    required this.reposterPubkeys,
  });

  final List<Note> ancestors;
  final String? replyToId;
  final List<Note> replies;
  final List<int> depths;
  final List<String> likerPubkeys;
  final List<String> reposterPubkeys;

  int get directReplyCount => depths.where((depth) => depth == 0).length;
}

/// Nesting past this only shifts replies off the screen.
const _maxIndentDepth = 4;

class _PostScreenState extends State<PostScreen> {
  static const _focusKey = ValueKey('focusedPost');

  final _scrollController = ScrollController();
  final _parentKey = GlobalKey();
  bool _revealedParent = false;

  _PostThread? _thread;
  bool _loading = true;
  int _loadGeneration = 0;

  /// Replies published from this screen, which relays may not return yet.
  final _publishedReplies = <NostrEvent>[];

  @override
  void initState() {
    super.initState();
    _refreshThread();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Slides the direct parent into view, unless the reader already scrolled.
  void _revealParent() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final height = _parentKey.currentContext?.size?.height;
    if (height == null || position.pixels != 0) return;

    position.animateTo(
      math.max(position.minScrollExtent, -height),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Keeps showing the previous thread while a newer one loads.
  Future<void> _refreshThread() async {
    final generation = ++_loadGeneration;
    _PostThread? thread;
    try {
      thread = await _loadThread();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'sputnik',
          context: ErrorDescription('loading a thread'),
        ),
      );
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _thread = thread ?? _thread;
      _loading = false;
    });

    if (!_revealedParent && (thread?.ancestors.isNotEmpty ?? false)) {
      _revealedParent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealParent());
    }
  }

  Future<_PostThread> _loadThread() async {
    final relayUrls = selectedRelaysNotifier.value;
    final thread = await widget.threadRepository.fetchThread(
      widget.note.id,
      relayUrls,
      extraEvents: _publishedReplies,
    );

    void applyCounts(ValueNotifier<List<Note>?> notifier) {
      notifier.value = notifier.value
          ?.map(
            (note) => note.id == widget.note.id
                ? note.copyWith(
                    likeCount: thread.likeCount,
                    repostCount: thread.repostCount,
                    replyCount: thread.directReplyCount,
                  )
                : note,
          )
          .toList();
    }

    applyCounts(notesNotifier);
    applyCounts(followingNotesNotifier);

    final posts = [
      ...thread.ancestors,
      for (final reply in thread.replies) reply.post,
    ];
    final notes = await hydratePosts(posts, relayUrls);
    final ancestorCount = thread.ancestors.length;

    return _PostThread(
      ancestors: notes.sublist(0, ancestorCount),
      replyToId: thread.replyToId,
      replies: notes.sublist(ancestorCount),
      depths: [for (final reply in thread.replies) reply.depth],
      likerPubkeys: thread.likerPubkeys,
      reposterPubkeys: thread.reposterPubkeys,
    );
  }

  Future<void> _reply(Note target) async {
    final published = await openReplyComposer(
      context,
      target,
      relayClient: widget.relayClient,
    );
    if (published == null || !mounted) return;
    _publishedReplies.add(published);
    _refreshThread();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Builder(
        builder: (context) {
          final thread = _thread;
          final loading = _loading;
          final ancestors = thread?.ancestors ?? const <Note>[];
          final replies = thread?.replies ?? const <Note>[];

          return CustomScrollView(
            controller: _scrollController,
            // Ancestors grow upward from the viewed note, so it stays in view.
            center: _focusKey,
            slivers: [
              SliverList.builder(
                itemCount: ancestors.length,
                itemBuilder: (context, index) => Column(
                  key: index == 0 ? _parentKey : null,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NoteTile(note: ancestors[ancestors.length - 1 - index]),
                    const Divider(height: 1),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                key: _focusKey,
                child: Column(
                  children: [
                    if (!loading &&
                        thread?.replyToId != null &&
                        ancestors.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'The note this replies to was not found on your '
                            'relays',
                            style: Theme.of(context).metadata,
                          ),
                        ),
                      ),
                    _PostHeader(
                      note: widget.note,
                      replyCount: thread?.directReplyCount,
                      likerPubkeys: thread?.likerPubkeys,
                      reposterPubkeys: thread?.reposterPubkeys,
                      onReply: () => _reply(widget.note),
                    ),
                    const Divider(height: 1),
                  ],
                ),
              ),
              if (replies.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: loading
                          ? const CircularProgressIndicator()
                          : const Text('No replies yet'),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: replies.length,
                  itemBuilder: (context, index) => _NestedReply(
                    note: replies[index],
                    depth: thread!.depths[index],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NestedReply extends StatelessWidget {
  const _NestedReply({required this.note, required this.depth});

  final Note note;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final indent = depth.clamp(0, _maxIndentDepth);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: indent * 16.0),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: indent == 0
                ? const BoxDecoration()
                : BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        width: 2,
                      ),
                    ),
                  ),
            child: NoteTile(note: note),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _PostHeader extends StatelessWidget {
  const _PostHeader({
    required this.note,
    required this.replyCount,
    required this.likerPubkeys,
    required this.reposterPubkeys,
    required this.onReply,
  });

  final Note note;
  final VoidCallback onReply;
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
    final myPubkeyHex = activeIdentityPubkeyNotifier.value?.toLowerCase();
    final reactionNote = note.copyWith(
      likedByMe: likerPubkeys?.contains(myPubkeyHex) ?? note.likedByMe,
      repostedByMe: reposterPubkeys?.contains(myPubkeyHex) ?? note.repostedByMe,
    );

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
                        avatarInitial(note.displayName),
                        style: theme.avatarFallback,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.avatarName,
                          ),
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
              NoteContent(note: note, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              Text(formatAbsoluteTime(note.createdAt), style: theme.metadata),
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
              IconButton(
                key: const Key('replyToPostButton'),
                icon: const Icon(Icons.chat_bubble_outline),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                tooltip: 'Reply',
                onPressed: onReply,
              ),
              RepostButton(note: reactionNote, showCount: false, size: 20),
              LikeButton(note: reactionNote, showCount: false, size: 20),
              BookmarkButton(note: note, size: 20),
            ],
          ),
        ),
      ],
    );
  }
}
