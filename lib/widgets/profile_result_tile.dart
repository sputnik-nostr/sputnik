import 'package:flutter/material.dart';

import '../nostr/nostr.dart';
import '../screens/profile_screen.dart';
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
    final npub = npubFromHex(pubkeyHex);
    final displayName = metadata?.resolvedName;
    final pictureUrl = metadata?.picture;

    return ListTile(
      leading: FadeInAvatar(
        imageUrl: pictureUrl,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        fallback: const Icon(Icons.person_outline),
      ),
      title: Text(displayName ?? truncateNpub(npub)),
      subtitle: Text(displayName != null ? truncateNpub(npub) : 'View profile'),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(pubkeyHex: pubkeyHex),
          ),
        );
      },
    );
  }
}
