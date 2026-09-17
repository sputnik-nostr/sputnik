import 'package:flutter/material.dart';

import '../main.dart';
import '../models/identity.dart';
import '../nostr/nostr.dart';
import '../services/settings_store.dart';

// Shared by the profile screen and user list rows to avoid duplicating the
// optimistic-flip/publish/revert logic between them.
class FollowButton extends StatefulWidget {
  const FollowButton({
    super.key,
    required this.targetPubkeyHex,
    required this.initialIsFollowing,
    this.relayClient = const RelayClient(),
    this.dense = false,
  });

  final String targetPubkeyHex;
  final bool initialIsFollowing;
  final RelayClient relayClient;

  // List-row-sized rendering instead of a full-size button.
  final bool dense;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  late bool _isFollowing = widget.initialIsFollowing;
  bool _pending = false;

  @override
  void didUpdateWidget(covariant FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Don't clobber an in-flight optimistic flip with a stale parent value.
    if (!_pending &&
        (oldWidget.targetPubkeyHex != widget.targetPubkeyHex ||
            oldWidget.initialIsFollowing != widget.initialIsFollowing)) {
      _isFollowing = widget.initialIsFollowing;
    }
  }

  Future<void> _toggle() async {
    final myPubkeyHex = activeIdentityPubkeyNotifier.value;
    if (myPubkeyHex == null || _pending) return;
    final identity = identityWithPubkey(identitiesNotifier.value, myPubkeyHex);
    if (identity == null) return;

    final wantsFollow = !_isFollowing;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isFollowing = wantsFollow;
      _pending = true;
    });

    final privkeyHex = await SettingsStore.loadPrivateKey(myPubkeyHex);
    if (!mounted) return;
    if (privkeyHex == null) {
      setState(() {
        _isFollowing = !wantsFollow;
        _pending = false;
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
          targetPubkeyHex: widget.targetPubkeyHex,
          follow: wantsFollow,
          relayUrls: selectedRelaysNotifier.value,
        );
    if (!mounted) return;

    final accepted = results.values.any(
      (result) => result.outcome == RelayPublishOutcome.accepted,
    );
    setState(() {
      _pending = false;
      if (!accepted) _isFollowing = !wantsFollow;
    });
    if (!accepted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update your follow list')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = _pending ? null : () => _toggle();
    final style = widget.dense
        ? TextButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            visualDensity: VisualDensity.compact,
          )
        : null;

    return _isFollowing
        ? OutlinedButton(
            key: const Key('followButton'),
            onPressed: onPressed,
            style: style,
            child: const Text('Following'),
          )
        : FilledButton(
            key: const Key('followButton'),
            onPressed: onPressed,
            style: style,
            child: const Text('Follow'),
          );
  }
}
