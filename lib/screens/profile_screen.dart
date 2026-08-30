import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/current_user.dart';
import '../models/note.dart';
import '../models/note_mapper.dart';
import '../nostr/nostr.dart';
import '../theme/app_text_styles.dart';
import '../widgets/count_label.dart';
import '../widgets/fade_in_avatar.dart';
import '../widgets/linkified_text.dart';
import '../widgets/note_tile.dart';
import '../widgets/placeholder_tab.dart';
import 'image_viewer_screen.dart';
import 'users_list_screen.dart';

const _bannerHeight = 140.0 * 0.8;
const _avatarRadius = 40.0;
const _avatarOverlap = _avatarRadius * 2 * 0.25;
const _avatarInitialFontSize = _avatarRadius * 0.7;

String _formatLastActiveFromPostedAt(String postedAt) {
  return postedAt == 'now'
      ? 'Last active just now'
      : 'Last active $postedAt ago';
}

String _shortPubkey(String pubkey) {
  return pubkey.length <= 8 ? pubkey : pubkey.substring(0, 8);
}

String _formatLastActive(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Last active just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return 'Last active $m minute${m == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return 'Last active $h hour${h == 1 ? '' : 's'} ago';
  }
  if (diff.inDays < 7) {
    final d = diff.inDays;
    return 'Last active $d day${d == 1 ? '' : 's'} ago';
  }
  final w = diff.inDays ~/ 7;
  return 'Last active $w week${w == 1 ? '' : 's'} ago';
}

void openProfile(BuildContext context, String pubkeyHex) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ProfileScreen(pubkeyHex: pubkeyHex)),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.pubkeyHex = CurrentUser.pubkeyHex});

  final String pubkeyHex;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Note>? _fetchedNotes;
  bool _loadingNotes = true;
  List<String>? _following;
  List<String>? _followers;

  bool get _isCurrentUser => widget.pubkeyHex == CurrentUser.pubkeyHex;

  void _openImage(BuildContext context, String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ImageViewerScreen(imageUrl: imageUrl)),
    );
  }

  @override
  void initState() {
    super.initState();
    // The current user's pubkey is a local placeholder, not a real key any
    // relay has metadata for, so there's nothing to fetch. Otherwise, the
    // cached metadata (if any) renders instantly below while this refreshes
    // it in the background.
    if (_isCurrentUser) {
      _loadingNotes = false;
    } else {
      const RelayProfileRepository().fetchProfile(
        widget.pubkeyHex,
        selectedRelaysNotifier.value,
      );
      _loadAuthorPosts();
      _loadContacts();
    }
  }

  Future<void> _loadAuthorPosts() async {
    final relayUrls = selectedRelaysNotifier.value;
    final posts = await RelayPostRepository(relayUrls: relayUrls)
        .fetchPostsByAuthor(widget.pubkeyHex);
    if (!mounted) return;

    final metadata = profileCacheNotifier.value[widget.pubkeyHex];
    final notes = await hydratePosts(
      posts,
      relayUrls,
      knownMetadata: metadata == null ? const {} : {widget.pubkeyHex: metadata},
    );
    if (!mounted) return;

    setState(() {
      _fetchedNotes = notes;
      _loadingNotes = false;
    });
  }

  Future<void> _loadContacts() async {
    final relayUrls = selectedRelaysNotifier.value;
    const repository = RelayContactsRepository();
    final followingFuture = repository.fetchFollowing(
      widget.pubkeyHex,
      relayUrls,
    );
    final followersFuture = repository.fetchFollowers(
      widget.pubkeyHex,
      relayUrls,
    );

    final following = await followingFuture;
    if (mounted) setState(() => _following = following);

    final followers = await followersFuture;
    if (mounted) setState(() => _followers = followers);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pubkeyHex = widget.pubkeyHex;
    final npub = npubFromHex(pubkeyHex);

    return Scaffold(
      body: ValueListenableBuilder<Map<String, NostrMetadata>>(
        valueListenable: profileCacheNotifier,
        builder: (context, profileCache, _) {
          final metadata = _isCurrentUser ? null : profileCache[pubkeyHex];

          return ValueListenableBuilder<List<Note>?>(
            valueListenable: notesNotifier,
            builder: (context, notes, _) {
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
              final displayName = _isCurrentUser
                  ? CurrentUser.displayName
                  : (metadata?.resolvedName ??
                        (ownNotes.isNotEmpty
                            ? ownNotes.first.displayName
                            : _shortPubkey(pubkeyHex)));
              final pictureUrl = metadata?.picture;
              final bannerUrl = metadata?.banner;
              final bio = _isCurrentUser ? CurrentUser.bio : metadata?.about;
              final hasBio = bio != null && bio.trim().isNotEmpty;

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
                                  if (bannerUrl != null)
                                    Image.network(
                                      bannerUrl,
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
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
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
                        if (_isCurrentUser) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatLastActive(CurrentUser.lastActiveAt),
                            style: theme.metadata,
                          ),
                        ] else if (ownNotes.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatLastActiveFromPostedAt(
                              ownNotes.first.postedAt,
                            ),
                            style: theme.metadata,
                          ),
                        ],
                        if (hasBio) ...[
                          const SizedBox(height: 8),
                          LinkifiedText(bio, style: theme.textTheme.bodyMedium),
                        ],
                        if (!_isCurrentUser) ...[
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
