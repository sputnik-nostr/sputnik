import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/identity.dart';
import '../models/note.dart';
import '../models/note_mapper.dart';
import '../models/time_format.dart';
import '../nostr/nip05.dart';
import '../nostr/nostr.dart';
import '../services/settings_store.dart';
import '../theme/app_text_styles.dart';
import '../widgets/count_label.dart';
import '../widgets/fade_in_avatar.dart';
import '../widgets/linkified_text.dart';
import '../widgets/nip05_badge.dart';
import '../widgets/note_tile.dart';
import '../widgets/payment_target_chip.dart';
import '../widgets/placeholder_tab.dart';
import 'edit_profile_screen.dart';
import 'identities_screen.dart';
import 'image_viewer_screen.dart';
import 'users_list_screen.dart';

const _bannerHeight = 140.0 * 0.8;
const _avatarRadius = 40.0;
const _avatarOverlap = _avatarRadius * 2 * 0.25;
const _avatarInitialFontSize = _avatarRadius * 0.7;

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
  /// [pubkeyHex] null means "my profile" -- whichever identity is active.
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

class _ProfileScreenState extends State<ProfileScreen> {
  late final String? _resolvedPubkeyHex =
      widget.pubkeyHex ?? activeIdentityPubkeyNotifier.value;

  List<Note>? _fetchedNotes;
  bool _loadingNotes = true;
  List<String>? _following;
  List<String>? _followers;
  List<NostrPaymentTarget>? _paymentTargets;
  bool _isFollowing = false;
  bool _followPending = false;
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
      MaterialPageRoute(builder: (_) => ImageViewerScreen(imageUrl: imageUrl)),
    );
  }

  Future<void> _toggleFollow() async {
    final myPubkeyHex = activeIdentityPubkeyNotifier.value;
    final targetPubkeyHex = _resolvedPubkeyHex;
    if (myPubkeyHex == null || targetPubkeyHex == null || _followPending) {
      return;
    }
    final identity = identityWithPubkey(identitiesNotifier.value, myPubkeyHex);
    if (identity == null) return;

    // Flip immediately; publish in the background, revert on failure.
    final wantsFollow = !_isFollowing;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isFollowing = wantsFollow;
      _followPending = true;
    });

    final privkeyHex = await SettingsStore.loadPrivateKey(myPubkeyHex);
    if (!mounted) return;
    if (privkeyHex == null) {
      setState(() {
        _isFollowing = !wantsFollow;
        _followPending = false;
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Could not find this identity's private key"),
        ),
      );
      return;
    }

    final results = await RelayContactsRepository(client: widget.relayClient)
        .setFollowing(
          seckeyHex: privkeyHex,
          myPubkeyHex: myPubkeyHex,
          targetPubkeyHex: targetPubkeyHex,
          follow: wantsFollow,
          relayUrls: selectedRelaysNotifier.value,
        );
    if (!mounted) return;

    final accepted = results.values.any(
      (result) => result.outcome == RelayPublishOutcome.accepted,
    );
    setState(() {
      _followPending = false;
      if (!accepted) _isFollowing = !wantsFollow;
    });
    if (!accepted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update your follow list')),
      );
    }
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
    _loadFollowState(pubkeyHex);
  }

  Future<void> _loadAuthorPosts(String pubkeyHex) async {
    final relayUrls = selectedRelaysNotifier.value;
    final posts = await RelayPostRepository(
      relayUrls: relayUrls,
      client: widget.relayClient,
    ).fetchPostsByAuthor(pubkeyHex);
    if (!mounted) return;

    final metadata = profileCacheNotifier.value[pubkeyHex];
    final notes = await hydratePosts(
      posts,
      relayUrls,
      knownMetadata: metadata == null ? const {} : {pubkeyHex: metadata},
    );
    if (!mounted) return;

    setState(() {
      _fetchedNotes = notes;
      _loadingNotes = false;
    });
  }

  Future<void> _loadContacts(String pubkeyHex) async {
    final relayUrls = selectedRelaysNotifier.value;
    final repository = RelayContactsRepository(client: widget.relayClient);
    final followingFuture = repository.fetchFollowing(pubkeyHex, relayUrls);
    final followersFuture = repository.fetchFollowers(pubkeyHex, relayUrls);

    final following = await followingFuture;
    if (mounted) setState(() => _following = following);

    final followers = await followersFuture;
    if (mounted) setState(() => _followers = followers);
  }

  Future<void> _loadPaymentTargets(String pubkeyHex) async {
    final targets = await RelayPaymentTargetsRepository(
      client: widget.relayClient,
    ).fetchPaymentTargets(pubkeyHex, selectedRelaysNotifier.value);
    if (mounted) setState(() => _paymentTargets = targets);
  }

  // Whether the active identity (not the viewed profile) follows them.
  Future<void> _loadFollowState(String pubkeyHex) async {
    final myPubkeyHex = activeIdentityPubkeyNotifier.value;
    if (myPubkeyHex == null || myPubkeyHex == pubkeyHex) return;
    final myFollowing = await RelayContactsRepository(
      client: widget.relayClient,
    ).fetchFollowing(myPubkeyHex, selectedRelaysNotifier.value);
    if (mounted) {
      setState(
        () => _isFollowing = myFollowing.contains(pubkeyHex.toLowerCase()),
      );
    }
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
        ]),
        builder: (context, child) {
          final metadata = profileCacheNotifier.value[pubkeyHex];
          final notes = notesNotifier.value;
          final ownNotesById = <String, Note>{
            for (final note in (notes ?? const []))
              if (note.pubkey == pubkeyHex) note.id: note,
            for (final note in (_fetchedNotes ?? const [])) note.id: note,
          };
          // Notes may have been fetched (and their author metadata
          // resolved) before this profile's own metadata query landed,
          // so always re-apply whatever is currently cached rather than
          // trusting what was baked in when each note was fetched.
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

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: _bannerHeight + _avatarRadius * 2 - _avatarOverlap,
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
                              if (bannerUrl != null && loadMediaNotifier.value)
                                Image(
                                  image: ResizeImage(
                                    NetworkImage(bannerUrl),
                                    width:
                                        (MediaQuery.sizeOf(context).width *
                                                MediaQuery.devicePixelRatioOf(
                                                  context,
                                                ))
                                            .round()
                                            .clamp(1, 4096),
                                    height:
                                        (_bannerHeight *
                                                MediaQuery.devicePixelRatioOf(
                                                  context,
                                                ))
                                            .round()
                                            .clamp(1, 4096),
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
                                          opacity: frame == null ? 0 : 1,
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
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const EditProfileScreen(),
                                ),
                              ),
                              icon: const Icon(Icons.edit_outlined, size: 16),
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
                          : _isFollowing
                          ? OutlinedButton(
                              key: const Key('followButton'),
                              onPressed: _followPending
                                  ? null
                                  : () => _toggleFollow(),
                              child: const Text('Following'),
                            )
                          : FilledButton(
                              key: const Key('followButton'),
                              onPressed: _followPending
                                  ? null
                                  : () => _toggleFollow(),
                              child: const Text('Follow'),
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
                            imageUrl: pictureUrl,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            fallback: Text(
                              displayName[0].toUpperCase(),
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
                            Clipboard.setData(ClipboardData(text: npub));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied npub to clipboard'),
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
                        formatLastActiveFromPostedAt(ownNotes.first.postedAt),
                        style: theme.metadata,
                      ),
                    ],
                    if (hasBio) ...[
                      const SizedBox(height: 8),
                      LinkifiedText(bio, style: theme.textTheme.bodyMedium),
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
                      ],
                    ),
                    if (_paymentTargets != null &&
                        _paymentTargets!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final target in _paymentTargets!)
                            PaymentTargetChip(target: target),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              if (ownNotes.isEmpty && _loadingNotes)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (ownNotes.isEmpty)
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
