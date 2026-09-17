import 'package:flutter/material.dart';

import '../main.dart';
import '../models/identity.dart';
import '../nostr/nostr.dart';
import '../services/follow_sync.dart';

// Shared by the profile screen and user list rows.
class FollowButton extends StatelessWidget {
  const FollowButton({
    super.key,
    required this.targetPubkeyHex,
    this.relayClient = const RelayClient(),
    this.dense = false,
  });

  final String targetPubkeyHex;
  final RelayClient relayClient;

  // List-row-sized rendering instead of a full-size button.
  final bool dense;

  void _toggle() {
    final myPubkeyHex = activeIdentityPubkeyNotifier.value;
    if (myPubkeyHex == null) return;
    final identity = identityWithPubkey(identitiesNotifier.value, myPubkeyHex);
    if (identity == null) return;

    final target = targetPubkeyHex.toLowerCase();
    final updated = Set<String>.of(myFollowingNotifier.value ?? const {});
    if (!updated.remove(target)) updated.add(target);
    myFollowingNotifier.value = updated;

    scheduleFollowingSync(relayClient: relayClient);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>?>(
      valueListenable: myFollowingNotifier,
      builder: (context, myFollowing, _) {
        final isFollowing =
            myFollowing?.contains(targetPubkeyHex.toLowerCase()) ?? false;
        final style = dense
            ? TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              )
            : null;

        return isFollowing
            ? OutlinedButton(
                key: const Key('followButton'),
                onPressed: _toggle,
                style: style,
                child: const Text('Following'),
              )
            : FilledButton(
                key: const Key('followButton'),
                onPressed: _toggle,
                style: style,
                child: const Text('Follow'),
              );
      },
    );
  }
}
