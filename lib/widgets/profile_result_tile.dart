import 'package:flutter/material.dart';

import '../nostr/nostr.dart';
import '../screens/profile_screen.dart';
import '../theme/app_text_styles.dart';
import 'fade_in_avatar.dart';

class ProfileResultTile extends StatelessWidget {
  const ProfileResultTile({
    super.key,
    required this.pubkeyHex,
    required this.metadata,
  });

  final String pubkeyHex;
  final NostrMetadata? metadata;

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
        imageUrl: pictureUrl,
        backgroundColor: theme.colorScheme.primaryContainer,
        fallback: const Icon(Icons.person_outline),
      ),
      title: Text(displayName ?? truncateNpub(npub), style: theme.avatarName),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      onTap: () => openProfile(context, pubkeyHex),
    );
  }
}

String _truncateBio(String bio) {
  const maxLength = 80;
  if (bio.length <= maxLength) return bio;
  return '${bio.substring(0, maxLength).trimRight()}…';
}
