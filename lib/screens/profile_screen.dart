import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/note.dart';
import '../models/note_mapper.dart';
import '../models/time_format.dart';
import '../nostr/nip05.dart';
import '../nostr/nostr.dart';
import '../theme/app_text_styles.dart';
import '../widgets/compact_tab_bar.dart';
import '../widgets/count_label.dart';
import '../widgets/fade_in_avatar.dart';
import '../widgets/follow_button.dart';
import '../services/media_loader.dart';
import '../services/post_cursor.dart';
import '../widgets/linkified_text.dart';
import '../widgets/load_more_footer.dart';
import '../widgets/nip05_badge.dart';
import '../widgets/note_tile.dart';
import '../widgets/payment_target_chip.dart';
import '../widgets/placeholder_tab.dart';
import 'edit_profile_screen.dart';
import 'identities_screen.dart';
import 'image_viewer_screen.dart';
import 'user_relays_screen.dart';
import 'users_list_screen.dart';

const _bannerHeight = 140.0 * 0.8;
const _bannerMaxDecodeExtent = 1600;
const _avatarMinDecodeExtent = 400;
const _avatarRadius = 40.0;
const _avatarOverlap = _avatarRadius * 2 * 0.25;
const _avatarInitialFontSize = _avatarRadius * 0.7;

/// Replies are fetched alongside posts, so a page needs headroom for both.
const _profileEventLimit = 100;

void openProfile(BuildContext context, String pubkeyHex) {
  // Otherwise a text field left focused offstage (e.g. search) can pop the
  // keyboard back up when this route is popped.
  FocusScope.of(context).unfocus();
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ProfileScreen(pubkeyHex: pubkeyHex)),
  );
}

class ProfileScreen extends StatefulWidget {
  /// [pubkeyHex] null means "my profile" (whichever identity is active).
  const ProfileScreen({
    super.key,
    this.pubkeyHex,
    this.relayClient = const RelayClient(),
  });

  final String? pubkeyHex;
  final RelayClient relayClient;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final String? _resolvedPubkeyHex =
      widget.pubkeyHex ?? activeIdentityPubkeyNotifier.value;

  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  List<Note>? _fetchedNotes;
  bool _loadingNotes = true;
  late final PostCursor _cursor = PostCursor(
    (until) => RelayPostRepository(
      relayUrls: selectedRelaysNotifier.value,
      client: widget.relayClient,
      limit: _profileEventLimit,
    ).fetchPage(authors: [_resolvedPubkeyHex!], until: until),
  );
  List<String>? _following;
  List<String>? _followers;
  List<NostrPaymentTarget>? _paymentTargets;
  String? _checkedNip05Identifier;
  Nip05Status? _nip05Status;

  bool get _isCurrentUser =>
      _resolvedPubkeyHex != null &&
      _resolvedPubkeyHex == activeIdentityPubkeyNotifier.value;

  void _maybeVerifyNip05(String? identifier, String pubkeyHex) {
    final trimmed = identifier?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    if (trimmed == _checkedNip05Identifier) return;

    _checkedNip05Identifier = trimmed;
    _nip05Status = null;
    verifyNip05(identifier: trimmed, pubkeyHex: pubkeyHex).then((status) {
      if (!mounted || _checkedNip05Identifier != trimmed) return;
      setState(() => _nip05Status = status);
    });
  }

  void _openImage(BuildContext context, String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ImageViewerScreen(sources: [MediaSource(url: imageUrl)]),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final pubkeyHex = _resolvedPubkeyHex;
    if (pubkeyHex == null) {
      // No identity to show a profile for at all.
      _loadingNotes = false;
      return;
    }

    RelayProfileRepository(client: widget.relayClient)
        .fetchProfile(pubkeyHex, selectedRelaysNotifier.value);
    _loadAuthorPosts(pubkeyHex);
    _loadContacts(pubkeyHex);
    _loadPaymentTargets(pubkeyHex);
    RelayContactsRepository(client: widget.relayClient)
        .ensureMyFollowingLoaded(selectedRelaysNotifier.value);
  }

  Future<void> _loadAuthorPosts(String pubkeyHex) async {
    final relayUrls = selectedRelaysNotifier.value;
    final posts = await _cursor.first();
    if (!mounted) return;

    final notes = await _hydrate(posts, pubkeyHex, relayUrls);
    if (!mounted) return;

    setState(() {
      _fetchedNotes = notes;
      _loadingNotes = false;
    });
  }

  Future<void> _loadMorePosts() async {
    final pubkeyHex = _resolvedPubkeyHex;
    if (pubkeyHex == null) return;
    final relayUrls = selectedRelaysNotifier.value;
    final posts = await _cursor.more();
    if (!mounted || posts.isEmpty) return;

    final notes = await _hydrate(posts, pubkeyHex, relayUrls);
    if (!mounted) return;

    setState(() => _fetchedNotes = [...?_fetchedNotes, ...notes]);
  }

  Future<List<Note>> _hydrate(
    List<NostrPost> posts,
    String pubkeyHex,
    Set<String> relayUrls,
  ) {
    final metadata = profileCacheNotifier.value[pubkeyHex];
    return hydratePosts(
      posts,
      relayUrls,
      knownMetadata: metadata == null ? const {} : {pubkeyHex: metadata},
    );
  }

  Future<void> _loadContacts(String pubkeyHex, {bool force = false}) async {
    final relayUrls = selectedRelaysNotifier.value;
    final repository = RelayContactsRepository(client: widget.relayClient);
    final followingFuture = repository.fetchFollowing(
      pubkeyHex,
      relayUrls,
      force: force,
    );
    final followersFuture = repository.fetchFollowers(
      pubkeyHex,
      relayUrls,
      force: force,
    );

    final following = await followingFuture;
    if (mounted) setState(() => _following = following);

    final followers = await followersFuture;
    if (mounted) setState(() => _followers = followers);
  }

  Future<void> _loadPaymentTargets(
    String pubkeyHex, {
    bool force = false,
  }) async {
    final targets =
        await RelayPaymentTargetsRepository(client: widget.relayClient)
            .fetchPaymentTargets(
              pubkeyHex,
              selectedRelaysNotifier.value,
              force: force,
            );
    if (mounted) setState(() => _paymentTargets = targets);
  }

  Future<void> _refresh() async {
    final pubkeyHex = _resolvedPubkeyHex;
    if (pubkeyHex == null) return;

    await Future.wait([
      RelayProfileRepository(client: widget.relayClient)
          .fetchProfile(pubkeyHex, selectedRelaysNotifier.value, force: true),
      _loadAuthorPosts(pubkeyHex),
      _loadContacts(pubkeyHex, force: true),
      _loadPaymentTargets(pubkeyHex, force: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pubkeyHex = _resolvedPubkeyHex;

    if (pubkeyHex == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PlaceholderTab(
                icon: Icons.person_outline,
                label: 'No identity yet',
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('createIdentityFromProfileButton'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const IdentitiesScreen()),
                ),
                child: const Text('Create or import an identity'),
              ),
            ],
          ),
        ),
      );
    }

    final npub = npubFromHex(pubkeyHex);

    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([
          profileCacheNotifier,
          notesNotifier,
          activeIdentityPubkeyNotifier,
          loadMediaNotifier,
          hiddenPaymentTargetTypesNotifier,
        ]),
        builder: (context, child) {
          final metadata = profileCacheNotifier.value[pubkeyHex];
          final notes = notesNotifier.value;
          final legacyMonero = metadata?.legacyMoneroAddress;
          final paymentTargets = [
            ...?_paymentTargets,
            if (legacyMonero != null &&
                (_paymentTargets ?? const []).every((t) => t.type != 'monero'))
              NostrPaymentTarget(type: 'monero', address: legacyMonero),
          ];
          final visiblePaymentTargets = paymentTargets
              .where(
                (target) => !hiddenPaymentTargetTypesNotifier.value.contains(
                  target.type,
                ),
              )
              .toList();
          final ownNotesById = <String, Note>{
            for (final note in (notes ?? const []))
              if (note.pubkey == pubkeyHex) note.id: note,
            for (final note in (_fetchedNotes ?? const [])) note.id: note,
          };
          // Notes fetched before this profile's metadata landed carry stale
          // author data, so re-apply whatever is cached now.
          final ownNotes =
              ownNotesById.values
                  .map(
                    (note) => metadata == null
                        ? note
                        : note.copyWith(
                            displayName: metadata.resolvedName,
                            pictureUrl: metadata.picture,
                          ),
                  )
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final posts = [
            for (final note in ownNotes)
              if (!note.isReply) note,
          ];
          final replies = [
            for (final note in ownNotes)
              if (note.isReply) note,
          ];
          final displayName =
              metadata?.resolvedName ??
              (ownNotes.isNotEmpty
                  ? ownNotes.first.displayName
                  : shortPubkey(pubkeyHex));
          final pictureUrl = metadata?.picture;
          final bannerUrl = metadata?.banner;
          final bio = metadata?.about;
          final hasBio = bio != null && bio.trim().isNotEmpty;
          final nip05 = metadata?.nip05;
          _maybeVerifyNip05(nip05, pubkeyHex);

          return RefreshIndicator(
            onRefresh: _refresh,
            // The notes lists sit deeper than the default depth of 0.
            notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
            child: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      SizedBox(
                        height:
                            _bannerHeight + _avatarRadius * 2 - _avatarOverlap,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GestureDetector(
                              onTap: bannerUrl != null
                                  ? () => _openImage(context, bannerUrl)
                                  : null,
                              child: ClipRect(
                                child: SizedBox(
                                  height: _bannerHeight,
                                  width: double.infinity,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              theme.colorScheme.primary,
                                              theme.colorScheme.tertiary,
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (bannerUrl != null &&
                                          loadMediaNotifier.value)
                                        Image(
                                          image: ResizeImage(
                                            NetworkImage(bannerUrl),
                                            width: _bannerMaxDecodeExtent,
                                            height: _bannerMaxDecodeExtent,
                                            policy: ResizeImagePolicy.fit,
                                          ),
                                          fit: BoxFit.cover,
                                          frameBuilder:
                                              (
                                                context,
                                                child,
                                                frame,
                                                wasSynchronouslyLoaded,
                                              ) {
                                                if (wasSynchronouslyLoaded) {
                                                  return child;
                                                }
                                                return AnimatedOpacity(
                                                  opacity: frame == null
                                                      ? 0
                                                      : 1,
                                                  duration: const Duration(
                                                    milliseconds: 300,
                                                  ),
                                                  curve: Curves.easeOut,
                                                  child: child,
                                                );
                                              },
                                          errorBuilder: (_, _, _) =>
                                              const SizedBox.shrink(),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: SafeArea(
                                bottom: false,
                                child: _FloatingBackButton(
                                  onTap: () => Navigator.pop(context),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              right: 16,
                              child: _isCurrentUser
                                  ? IconButton.filled(
                                      key: const Key('editProfileButton'),
                                      tooltip: 'Edit profile',
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => EditProfileScreen(
                                              relayClient: widget.relayClient,
                                            ),
                                          ),
                                        );
                                        if (mounted) {
                                          _loadPaymentTargets(pubkeyHex);
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                      ),
                                      style: IconButton.styleFrom(
                                        backgroundColor:
                                            theme.colorScheme.inverseSurface,
                                        foregroundColor:
                                            theme.colorScheme.onInverseSurface,
                                        shape: const StadiumBorder(),
                                        minimumSize: const Size(44, 30),
                                        padding: EdgeInsets.zero,
                                      ),
                                    )
                                  : activeIdentityPubkeyNotifier.value == null
                                  ? const SizedBox.shrink()
                                  : FollowButton(
                                      targetPubkeyHex: pubkeyHex,
                                      relayClient: widget.relayClient,
                                    ),
                            ),
                            Positioned(
                              top: _bannerHeight - _avatarOverlap,
                              left: 16,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: theme.colorScheme.surface,
                                ),
                                child: GestureDetector(
                                  onTap: pictureUrl != null
                                      ? () => _openImage(context, pictureUrl)
                                      : null,
                                  child: FadeInAvatar(
                                    radius: _avatarRadius,
                                    minDecodeExtent: _avatarMinDecodeExtent,
                                    imageUrl: pictureUrl,
                                    backgroundColor:
                                        theme.colorScheme.primaryContainer,
                                    fallback: Text(
                                      avatarInitial(displayName),
                                      style: theme.avatarFallback.copyWith(
                                        fontSize: _avatarInitialFontSize,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(truncateNpub(npub), style: theme.metadata),
                                const SizedBox(width: 4),
                                InkWell(
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                  onTap: () {
                                    Clipboard.setData(
                                      ClipboardData(text: npub),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Copied npub to clipboard',
                                        ),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.copy,
                                      size: 14,
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (nip05 != null && nip05.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Nip05Badge(
                                identifier: nip05.trim(),
                                status: _nip05Status,
                              ),
                            ],
                            if (ownNotes.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                formatLastActiveFromPostedAt(
                                  ownNotes.first.postedAt,
                                ),
                                style: theme.metadata,
                              ),
                            ],
                            if (hasBio) ...[
                              const SizedBox(height: 8),
                              LinkifiedText(
                                bio,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                CountLabel(
                                  count: _following?.length,
                                  label: 'following',
                                  onTap: _following == null
                                      ? null
                                      : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => UsersListScreen(
                                              title: 'Following',
                                              pubkeys: _following!,
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 16),
                                CountLabel(
                                  count: _followers?.length,
                                  label: 'followers',
                                  onTap: _followers == null
                                      ? null
                                      : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => UsersListScreen(
                                              title: 'Followers',
                                              pubkeys: _followers!,
                                            ),
                                          ),
                                        ),
                                ),
                                const Spacer(),
                                Material(
                                  color: Colors.transparent,
                                  shape: StadiumBorder(
                                    side: BorderSide(
                                      color: theme.colorScheme.outlineVariant,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    key: const Key('profileRelaysButton'),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => UserRelaysScreen(
                                          pubkeyHex: pubkeyHex,
                                          relayClient: widget.relayClient,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 5,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.dns_outlined,
                                            size: 14,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Relays',
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (visiblePaymentTargets.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (
                                      var i = 0;
                                      i < visiblePaymentTargets.length;
                                      i++
                                    ) ...[
                                      if (i > 0) const SizedBox(width: 8),
                                      PaymentTargetChip(
                                        target: visiblePaymentTargets[i],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      CompactTabBar(
                        controller: _tabController,
                        labels: const ['Posts', 'Replies'],
                      ),
                    ],
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  _notesTab('posts', posts, 'No posts yet'),
                  _notesTab('replies', replies, 'No replies yet'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _notesTab(String storageKey, List<Note> notes, String emptyLabel) {
    return ValueListenableBuilder<bool>(
      valueListenable: _cursor.hasMore,
      builder: (context, hasMore, _) {
        // A new key per page, so the next one is asked for if still in view.
        Widget footer() => LoadMoreFooter(
          key: ValueKey(_fetchedNotes?.length),
          onLoadMore: _loadMorePosts,
        );
        final showFooter = hasMore && !_loadingNotes;

        if (notes.isEmpty) {
          return ListView(
            key: PageStorageKey(storageKey),
            padding: EdgeInsets.zero,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_loadingNotes)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (!hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: PlaceholderTab(
                    icon: Icons.notes_outlined,
                    label: emptyLabel,
                  ),
                ),
              if (showFooter) footer(),
            ],
          );
        }

        return ListView.separated(
          key: PageStorageKey(storageKey),
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: notes.length + (showFooter ? 1 : 0),
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) =>
              index == notes.length ? footer() : NoteTile(note: notes[index]),
        );
      },
    );
  }
}

class _FloatingBackButton extends StatelessWidget {
  const _FloatingBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Material(
        color: Colors.black38,
        child: InkWell(
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}
