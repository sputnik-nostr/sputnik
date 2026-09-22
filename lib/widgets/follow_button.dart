import 'package:flutter/material.dart';

import '../main.dart';
import '../models/identity.dart';
import '../nostr/nostr.dart';
import '../services/follow_sync.dart';

Future<bool> _confirmFollowChange(
  BuildContext context, {
  required bool follow,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(follow ? 'Follow this person?' : 'Unfollow this person?'),
      content: Text(
        follow
            ? 'This publishes your updated follow list to your relays.'
            : 'This removes them from your follow list, published to your '
                  'relays.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(follow ? 'Follow' : 'Unfollow'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Follows or unfollows [targetPubkeyHex] as the active identity.
class FollowButton extends StatelessWidget {
  const FollowButton({
    super.key,
    required this.targetPubkeyHex,
    this.relayClient = const RelayClient(),
    this.dense = false,
  });

  final String targetPubkeyHex;
  final RelayClient relayClient;

  /// List-row-sized rendering instead of a full-size button.
  final bool dense;

  Future<void> _toggle(BuildContext context) async {
    final myPubkeyHex = activeIdentityPubkeyNotifier.value;
    if (myPubkeyHex == null) return;
    final identity = identityWithPubkey(identitiesNotifier.value, myPubkeyHex);
    if (identity == null) return;

    final target = targetPubkeyHex.toLowerCase();
    final currentlyFollowing =
        myFollowingNotifier.value?.contains(target) ?? false;
    final follow = !currentlyFollowing;

    if (confirmBeforeReactingNotifier.value) {
      final confirmed = await _confirmFollowChange(context, follow: follow);
      if (!confirmed || !context.mounted) return;
    }

    final updated = Set<String>.of(myFollowingNotifier.value ?? const {});
    if (follow) {
      updated.add(target);
    } else {
      updated.remove(target);
    }
    myFollowingNotifier.value = updated;

    scheduleFollowingSync(target, follow: follow, relayClient: relayClient);
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
                onPressed: () => _toggle(context),
                style: style,
                child: const Text('Following'),
              )
            : FilledButton(
                key: const Key('followButton'),
                onPressed: () => _toggle(context),
                style: style,
                child: const Text('Follow'),
              );
      },
    );
  }
}
