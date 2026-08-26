import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/current_user.dart';
import '../models/note.dart';
import '../widgets/note_tile.dart';
import '../widgets/placeholder_tab.dart';

const _bannerHeight = 140.0 * 0.8;
const _avatarRadius = 40.0;
const _avatarOverlap = _avatarRadius * 2 * 0.25;

String _truncateNpub(String npub) {
  const totalLength = 20;
  const suffixLength = 5;
  if (npub.length <= totalLength) return npub;
  final prefixLength = totalLength - suffixLength - 3;
  final prefix = npub.substring(0, prefixLength);
  final suffix = npub.substring(npub.length - suffixLength);
  return '$prefix...$suffix';
}

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

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.npub = CurrentUser.npub});

  final String npub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: ValueListenableBuilder<List<Note>?>(
        valueListenable: notesNotifier,
        builder: (context, notes, _) {
          final ownNotes = (notes ?? const [])
              .where((note) => note.pubkey == npub)
              .toList();
          final isCurrentUser = npub == CurrentUser.npub;
          final displayName = isCurrentUser
              ? CurrentUser.displayName
              : (ownNotes.isNotEmpty
                    ? ownNotes.first.displayName
                    : _shortPubkey(npub));

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: _bannerHeight + _avatarRadius * 2 - _avatarOverlap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: _bannerHeight,
                      width: double.infinity,
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
                        child: CircleAvatar(
                          radius: _avatarRadius,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            displayName[0].toUpperCase(),
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 28,
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
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _truncateNpub(npub),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
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
                    if (isCurrentUser) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatLastActive(CurrentUser.lastActiveAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(CurrentUser.bio, style: theme.textTheme.bodyMedium),
                    ] else if (ownNotes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatLastActiveFromPostedAt(ownNotes.first.postedAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
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
