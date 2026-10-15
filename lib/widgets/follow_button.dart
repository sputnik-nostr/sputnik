import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/follow_sync.dart';
import '../services/publishing.dart';

/// Follows or unfollows [targetPubkeyHex] as the active identity.
class FollowButton extends StatelessWidget {
  const FollowButton({
    super.key,
    required this.targetPubkeyHex,
    this.dense = false,
  });

  final String targetPubkeyHex;

  /// List-row-sized rendering instead of a full-size button.
  final bool dense;

  Future<void> _toggle(BuildContext context) async {
    if (activeIdentity() == null) return;

    final target = targetPubkeyHex.toLowerCase();
    final currentlyFollowing =
        myFollowingNotifier.value?.contains(target) ?? false;
    final follow = !currentlyFollowing;

    if (confirmBeforeReactingNotifier.value) {
      final confirmed = await confirmAction(
        context,
        title: follow ? 'Follow this person?' : 'Unfollow this person?',
        message: follow
            ? 'This publishes your updated follow list to your relays.'
            : 'This removes them from your follow list, published to your '
                  'relays.',
        action: follow ? 'Follow' : 'Unfollow',
      );
      if (!confirmed || !context.mounted) return;
    }

    final updated = Set<String>.of(myFollowingNotifier.value ?? const {});
    if (follow) {
      updated.add(target);
    } else {
      updated.remove(target);
    }
    myFollowingNotifier.value = updated;

    scheduleFollowingSync(target, follow: follow);
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
