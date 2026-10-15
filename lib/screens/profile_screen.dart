import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models/avatar_initial.dart';
import '../models/note.dart';
import '../models/time_format.dart';
import '../nostr/nip05.dart';
import '../nostr/nostr.dart';
import '../services/follow_sync.dart';
import '../services/follows.dart';
import '../services/media_loader.dart';
import '../services/nip05_verification.dart';
import '../services/note_hydration.dart';
import '../services/payment_targets.dart';
import '../services/post_cursor.dart';
import '../services/profiles.dart';
import '../theme/app_text_styles.dart';
import '../widgets/compact_tab_bar.dart';
import '../widgets/count_label.dart';
import '../widgets/fade_in_avatar.dart';
import '../widgets/follow_button.dart';
import '../widgets/linkified_text.dart';
import '../widgets/load_more_footer.dart';
import '../widgets/media_frame.dart';
import '../widgets/nip05_badge.dart';
import '../widgets/note_tile.dart';
import '../widgets/payment_target_chip.dart';
import '../widgets/placeholder_tab.dart';
import 'edit_profile_screen.dart';
import 'identities_screen.dart';
import 'image_viewer_screen.dart';
import 'user_relays_screen.dart';
import 'users_list_screen.dart';

const _bannerHeight = 112.0;
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

  /// Reposts this profile has made, paged separately since they're a
  /// different kind of relay query.
  late final PostCursor _repostCursor = PostCursor((until) async {
    final relayUrls = selectedRelaysNotifier.value;
    final reposts = await RelayPostRepository(
      relayUrls: relayUrls,
      client: widget.relayClient,
      limit: _profileEventLimit,
    ).fetchReposts([_resolvedPubkeyHex!], relayUrls, until: until);
    final next = reposts.length >= _profileEventLimit
        ? reposts
              .map((post) => post.repostedAt!)
              .reduce((a, b) => a.isBefore(b) ? a : b)
        : null;
    return PostPage(reposts, next);
  });
  List<String>? _following;
  List<String>? _followers;
  List<NostrPaymentTarget>? _paymentTargets;
  String? _checkedNip05Identifier;
  Nip05Status? _nip05Status;

  bool get _isCurrentUser =>
      _resolvedPubkeyHex != null &&
      _resolvedPubkeyHex == activeIdentityPubkeyNotifier.value;

  String? get _nip05Identifier {
    final trimmed = profileCacheNotifier.value[_resolvedPubkeyHex]?.nip05
        ?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// The check contacts the identifier's domain, so it is opt-in.
  void _verifyNip05() {
    final identifier = _nip05Identifier;
    if (identifier == null || identifier == _checkedNip05Identifier) return;

    setState(() {
      _checkedNip05Identifier = identifier;
      _nip05Status = null;
    });
    verifyNip05(identifier: identifier, pubkeyHex: _resolvedPubkeyHex!).then((
      status,
    ) {
      if (!mounted || _checkedNip05Identifier != identifier) return;
      setState(() => _nip05Status = status);
    });
  }

  void _maybeAutoVerifyNip05() {
    if (autoVerifyNip05Notifier.value) _verifyNip05();
  }

  @override
  void dispose() {
    profileCacheNotifier.removeListener(_maybeAutoVerifyNip05);
    autoVerifyNip05Notifier.removeListener(_maybeAutoVerifyNip05);
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

    profileCacheNotifier.addListener(_maybeAutoVerifyNip05);
    autoVerifyNip05Notifier.addListener(_maybeAutoVerifyNip05);
    _maybeAutoVerifyNip05();
    loadProfile(
      pubkeyHex,
      selectedRelaysNotifier.value,
      client: widget.relayClient,
    );
    _loadAuthorPosts(pubkeyHex);
    _loadContacts(pubkeyHex);
    _loadPaymentTargets(pubkeyHex);
    ensureMyFollowingLoaded(
      selectedRelaysNotifier.value,
      relayClient: widget.relayClient,
    );
  }

  Future<void> _loadAuthorPosts(String pubkeyHex) async {
    final relayUrls = selectedRelaysNotifier.value;
    final fetched = await Future.wait([_cursor.first(), _repostCursor.first()]);
    if (!mounted) return;

    final notes = await _hydrate(
      [...fetched[0], ...fetched[1]],
      pubkeyHex,
      relayUrls,
    );
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
    final fetched = await Future.wait([_cursor.more(), _repostCursor.more()]);
    final posts = [...fetched[0], ...fetched[1]];
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
      client: widget.relayClient,
    );
  }

  Future<void> _loadContacts(String pubkeyHex, {bool force = false}) async {
    final relayUrls = selectedRelaysNotifier.value;
    final followingFuture = loadFollowing(
      pubkeyHex,
      relayUrls,
      force: force,
      client: widget.relayClient,
    );
    final followersFuture = loadFollowers(
      pubkeyHex,
      relayUrls,
      force: force,
      client: widget.relayClient,
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
    final targets = await loadPaymentTargets(
      pubkeyHex,
      selectedRelaysNotifier.value,
      force: force,
      client: widget.relayClient,
    );
    if (mounted) setState(() => _paymentTargets = targets);
  }

  Future<void> _refresh() async {
    final pubkeyHex = _resolvedPubkeyHex;
    if (pubkeyHex == null) return;

    await Future.wait([
      loadProfile(
        pubkeyHex,
        selectedRelaysNotifier.value,
        force: true,
        client: widget.relayClient,
      ),
      _loadAuthorPosts(pubkeyHex),
      _loadContacts(pubkeyHex, force: true),
      _loadPaymentTargets(pubkeyHex, force: true),
    ]);
  }

  /// Published targets, the legacy Monero field as fallback, minus hidden types.
  List<NostrPaymentTarget> _visiblePaymentTargets(NostrMetadata? metadata) {
    final targets = _paymentTargets ?? const <NostrPaymentTarget>[];
    final legacyMonero = metadata?.legacyMoneroAddress;
    final hidden = hiddenPaymentTargetTypesNotifier.value;
    return [
      ...targets,
      if (legacyMonero != null && targets.every((t) => t.type != 'monero'))
        NostrPaymentTarget(type: 'monero', address: legacyMonero),
    ].where((target) => !hidden.contains(target.type)).toList();
  }

  /// This profile's notes and reposts, newest activity first.
  List<Note> _ownNotes(String pubkeyHex, NostrMetadata? metadata) {
    final byId = <String, Note>{
      for (final note in notesNotifier.value ?? const <Note>[])
        if (note.pubkey == pubkeyHex) note.id: note,
      for (final note in _fetchedNotes ?? const <Note>[]) note.id: note,
    };
    // Re-apply fresh metadata; a repost keeps its original author's data.
    return byId.values
        .map(
          (note) => metadata == null || note.pubkey != pubkeyHex
              ? note
              : note.copyWith(
                  displayName: metadata.resolvedName,
                  pictureUrl: metadata.picture,
                ),
        )
        .toList()
      ..sort((a, b) => _activityTime(b).compareTo(_activityTime(a)));
  }

  static DateTime _activityTime(Note note) => note.repostedAt ?? note.createdAt;

  Future<void> _editProfile(String pubkeyHex) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(relayClient: widget.relayClient),
      ),
    );
    if (mounted) unawaited(_loadPaymentTargets(pubkeyHex));
  }

  @override
  Widget build(BuildContext context) {
    final pubkeyHex = _resolvedPubkeyHex;
    if (pubkeyHex == null) return const _NoIdentity();

    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([
          profileCacheNotifier,
          notesNotifier,
          activeIdentityPubkeyNotifier,
          loadMediaNotifier,
          hiddenPaymentTargetTypesNotifier,
        ]),
        builder: (context, _) {
          final metadata = profileCacheNotifier.value[pubkeyHex];
          final ownNotes = _ownNotes(pubkeyHex, metadata);
          final displayName =
              metadata?.resolvedName ??
              (ownNotes.isNotEmpty
                  ? ownNotes.first.displayName
                  : shortPubkey(pubkeyHex));

          return RefreshIndicator(
            onRefresh: _refresh,
            // The notes lists sit deeper than the default depth of 0.
            notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
            child: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _ProfileHeader(
                        bannerUrl: fetchableUrlOrNull(metadata?.banner),
                        pictureUrl: fetchableUrlOrNull(metadata?.picture),
                        displayName: displayName,
                        action: _isCurrentUser
                            ? _EditProfileButton(
                                onPressed: () => _editProfile(pubkeyHex),
                              )
                            : activeIdentityPubkeyNotifier.value == null
                            ? null
                            : FollowButton(
                                targetPubkeyHex: pubkeyHex,
                                relayClient: widget.relayClient,
                              ),
                      ),
                      _ProfileDetails(
                        pubkeyHex: pubkeyHex,
                        displayName: displayName,
                        metadata: metadata,
                        nip05Status: _nip05Status,
                        onVerifyNip05:
                            _nip05Identifier == _checkedNip05Identifier
                            ? null
                            : _verifyNip05,
                        lastActive: ownNotes.isEmpty
                            ? null
                            : _activityTime(ownNotes.first),
                        following: _following,
                        followers: _followers,
                        paymentTargets: _visiblePaymentTargets(metadata),
                        relayClient: widget.relayClient,
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
                  _notesTab('posts', [
                    for (final note in ownNotes)
                      if (!note.isReply) note,
                  ], 'No posts yet'),
                  _notesTab('replies', [
                    for (final note in ownNotes)
                      if (note.isReply) note,
                  ], 'No replies yet'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _notesTab(String storageKey, List<Note> notes, String emptyLabel) {
    return AnimatedBuilder(
      animation: Listenable.merge([_cursor.hasMore, _repostCursor.hasMore]),
      builder: (context, _) {
        final hasMore = _cursor.hasMore.value || _repostCursor.hasMore.value;
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

class _NoIdentity extends StatelessWidget {
  const _NoIdentity();

  @override
  Widget build(BuildContext context) {
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
}

void _openImage(BuildContext context, String imageUrl) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          ImageViewerScreen(sources: [profileImageSource(imageUrl)]),
    ),
  );
}

/// Banner and overlapping avatar, with back and [action] buttons over it.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.bannerUrl,
    required this.pictureUrl,
    required this.displayName,
    required this.action,
  });

  final String? bannerUrl;
  final String? pictureUrl;
  final String displayName;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bannerUrl = this.bannerUrl;
    final pictureUrl = this.pictureUrl;
    final action = this.action;

    return SizedBox(
      height: _bannerHeight + _avatarRadius * 2 - _avatarOverlap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: bannerUrl == null
                ? null
                : () => _openImage(context, bannerUrl),
            child: _Banner(url: bannerUrl),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              bottom: false,
              child: _FloatingBackButton(onTap: () => Navigator.pop(context)),
            ),
          ),
          if (action != null) Positioned(bottom: 8, right: 16, child: action),
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
                onTap: pictureUrl == null
                    ? null
                    : () => _openImage(context, pictureUrl),
                child: FadeInAvatar(
                  radius: _avatarRadius,
                  minDecodeExtent: _avatarMinDecodeExtent,
                  imageUrl: pictureUrl,
                  backgroundColor: theme.colorScheme.primaryContainer,
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
    );
  }
}

/// A theme gradient, with the banner faded in over it if media loads.
class _Banner extends StatelessWidget {
  const _Banner({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final url = this.url;

    return ClipRect(
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
                  colors: [colorScheme.primary, colorScheme.tertiary],
                ),
              ),
            ),
            if (url != null && loadMediaNotifier.value)
              Image(
                image: ResizeImage(
                  BoundedNetworkImage(profileImageSource(url)),
                  width: _bannerMaxDecodeExtent,
                  height: _bannerMaxDecodeExtent,
                  policy: ResizeImagePolicy.fit,
                ),
                fit: BoxFit.cover,
                frameBuilder: fadeInFrame,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}

class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton.filled(
      key: const Key('editProfileButton'),
      tooltip: 'Edit profile',
      onPressed: onPressed,
      icon: const Icon(Icons.edit_outlined, size: 16),
      style: IconButton.styleFrom(
        backgroundColor: colorScheme.inverseSurface,
        foregroundColor: colorScheme.onInverseSurface,
        shape: const StadiumBorder(),
        minimumSize: const Size(44, 30),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Name, npub, NIP-05, activity, bio, follow counts, and payment targets.
class _ProfileDetails extends StatelessWidget {
  const _ProfileDetails({
    required this.pubkeyHex,
    required this.displayName,
    required this.metadata,
    required this.nip05Status,
    required this.onVerifyNip05,
    required this.lastActive,
    required this.following,
    required this.followers,
    required this.paymentTargets,
    required this.relayClient,
  });

  final String pubkeyHex;
  final String displayName;
  final NostrMetadata? metadata;
  final Nip05Status? nip05Status;
  final VoidCallback? onVerifyNip05;
  final DateTime? lastActive;
  final List<String>? following;
  final List<String>? followers;
  final List<NostrPaymentTarget> paymentTargets;
  final RelayClient relayClient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nip05 = metadata?.nip05?.trim();
    final bio = metadata?.about;
    final lastActive = this.lastActive;

    return Padding(
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
          _NpubRow(npub: npubFromHex(pubkeyHex)),
          if (nip05 != null && nip05.isNotEmpty) ...[
            const SizedBox(height: 2),
            Nip05Badge(
              identifier: nip05,
              status: nip05Status,
              onVerify: onVerifyNip05,
            ),
          ],
          if (lastActive != null) ...[
            const SizedBox(height: 4),
            Text(formatLastActive(lastActive), style: theme.metadata),
          ],
          if (bio != null && bio.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            LinkifiedText(bio, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _ContactsCount(
                pubkeys: following,
                label: 'following',
                title: 'Following',
              ),
              const SizedBox(width: 16),
              _ContactsCount(
                pubkeys: followers,
                label: 'followers',
                title: 'Followers',
              ),
              const Spacer(),
              _RelaysButton(pubkeyHex: pubkeyHex, relayClient: relayClient),
            ],
          ),
          if (paymentTargets.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  for (final target in paymentTargets)
                    PaymentTargetChip(target: target),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NpubRow extends StatelessWidget {
  const _NpubRow({required this.npub});

  final String npub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(truncateNpub(npub), style: theme.metadata),
        const SizedBox(width: 4),
        InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          onTap: () {
            Clipboard.setData(ClipboardData(text: npub));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied npub to clipboard')),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.copy, size: 14, color: theme.colorScheme.outline),
          ),
        ),
      ],
    );
  }
}

/// A following/followers count that opens the list once it has loaded.
class _ContactsCount extends StatelessWidget {
  const _ContactsCount({
    required this.pubkeys,
    required this.label,
    required this.title,
  });

  final List<String>? pubkeys;
  final String label;
  final String title;

  @override
  Widget build(BuildContext context) {
    final pubkeys = this.pubkeys;
    return CountLabel(
      count: pubkeys?.length,
      label: label,
      onTap: pubkeys == null
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UsersListScreen(title: title, pubkeys: pubkeys),
              ),
            ),
    );
  }
}

class _RelaysButton extends StatelessWidget {
  const _RelaysButton({required this.pubkeyHex, required this.relayClient});

  final String pubkeyHex;
  final RelayClient relayClient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('profileRelaysButton'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserRelaysScreen(
              pubkeyHex: pubkeyHex,
              relayClient: relayClient,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns_outlined, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                'Relays',
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
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
