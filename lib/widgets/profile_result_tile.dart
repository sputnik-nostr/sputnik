import 'package:flutter/material.dart';

import '../nostr/nostr.dart';
import '../screens/profile_screen.dart';

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
      leading: CircleAvatar(
        backgroundImage: pictureUrl != null ? NetworkImage(pictureUrl) : null,
        onBackgroundImageError: pictureUrl != null ? (_, _) {} : null,
        child: pictureUrl == null ? const Icon(Icons.person_outline) : null,
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
