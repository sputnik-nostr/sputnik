import 'package:flutter/material.dart';

import '../nostr/nostr.dart';
import '../screens/profile_screen.dart';
import '../theme/app_text_styles.dart';
import 'fade_in_avatar.dart';
import 'follow_button.dart';

const _avatarMinDecodeExtent = 128;

class ProfileResultTile extends StatelessWidget {
  const ProfileResultTile({
    super.key,
    required this.pubkeyHex,
    required this.metadata,
    this.showFollowButton = false,
    this.relayClient = const RelayClient(),
  });

  final String pubkeyHex;
  final NostrMetadata? metadata;

  /// False hides the follow button (no active identity, or this is you).
  final bool showFollowButton;
  final RelayClient relayClient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final npub = npubFromHex(pubkeyHex);
    final displayName = metadata?.resolvedName;
    final pictureUrl = metadata?.picture;
    final bio = metadata?.about?.replaceAll('\n', ' ').trim();

    final String subtitle;
    if (metadata == null) {
      subtitle = 'View profile';
    } else if (bio != null && bio.isNotEmpty) {
      subtitle = _truncateBio(bio);
    } else {
      subtitle = truncateNpub(npub);
    }

    return ListTile(
      leading: FadeInAvatar(
        minDecodeExtent: _avatarMinDecodeExtent,
        imageUrl: pictureUrl,
        backgroundColor: theme.colorScheme.primaryContainer,
        fallback: const Icon(Icons.person_outline),
      ),
      title: Text(
        displayName ?? truncateNpub(npub),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.avatarName,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: !showFollowButton
          ? null
          : FollowButton(
              targetPubkeyHex: pubkeyHex,
              relayClient: relayClient,
              dense: true,
            ),
      onTap: () => openProfile(context, pubkeyHex),
    );
  }
}

String _truncateBio(String bio) {
  const maxLength = 80;
  if (bio.length <= maxLength) return bio;
  return '${bio.substring(0, maxLength).trimRight()}...';
}
