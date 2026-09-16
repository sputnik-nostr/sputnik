import 'package:flutter/material.dart';

import '../main.dart';
import '../models/identity.dart';
import '../nostr/nostr.dart';
import '../services/settings_store.dart';
import '../theme/app_text_styles.dart';
import '../widgets/fade_in_avatar.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.relayClient = const RelayClient()});

  final RelayClient relayClient;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _controller = TextEditingController();

  bool _hasText = false;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _confirmPost(int relayCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Post to relays?'),
        content: Text(
          'This publishes your note to $relayCount relay(s). Notes on '
          'Nostr are public and cannot be reliably deleted afterward.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmPostButton'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _post() async {
    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    if (pubkeyHex == null) return;
    final identity = identityWithPubkey(identitiesNotifier.value, pubkeyHex);
    if (identity == null) return;

    final relayUrls = selectedRelaysNotifier.value;
    if (!await _confirmPost(relayUrls.length) || !mounted) return;

    // Only touch secure storage once the user has actually confirmed.
    final privkeyHex = await SettingsStore.loadPrivateKey(identity.pubkeyHex);
    if (!mounted) return;
    if (privkeyHex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not find this identity's private key"),
        ),
      );
      return;
    }

    final NostrEvent event;
    try {
      event = signEvent(
        seckeyHex: privkeyHex,
        pubkeyHex: identity.pubkeyHex,
        kind: 1,
        content: _controller.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not sign this note: $e')));
      }
      return;
    }

    setState(() => _posting = true);
    final messenger = ScaffoldMessenger.of(context);
    final results = await widget.relayClient.publish(event, relayUrls);
    if (!mounted) return;
    setState(() => _posting = false);

    final accepted = results.values
        .where((result) => result.outcome == RelayPublishOutcome.accepted)
        .length;

    if (accepted > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('Posted to $accepted/${results.length} relays')),
      );
      Navigator.pop(context);
    } else {
      String? reason;
      for (final result in results.values) {
        if (result.message != null && result.message!.isNotEmpty) {
          reason = result.message;
          break;
        }
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(reason ?? 'Could not post this note to any relay'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    final metadata = pubkeyHex == null
        ? null
        : profileCacheNotifier.value[pubkeyHex];
    final resolvedName = metadata?.resolvedName?.trim();
    final fallbackLabel = resolvedName?.isNotEmpty == true
        ? resolvedName![0].toUpperCase()
        : pubkeyHex?.isNotEmpty == true
        ? pubkeyHex![0].toUpperCase()
        : '?';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('composeCloseButton'),
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _posting
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton(
                    key: const Key('composePostButton'),
                    onPressed: pubkeyHex != null && _hasText ? _post : null,
                    child: const Text('Post'),
                  ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FadeInAvatar(
              radius: 20,
              imageUrl: metadata?.picture,
              backgroundColor: theme.colorScheme.primaryContainer,
              fallback: Text(fallbackLabel, style: theme.avatarFallback),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('composeTextField'),
                controller: _controller,
                autofocus: true,
                maxLines: null,
                minLines: 6,
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.bodyLarge,
                cursorHeight: (theme.textTheme.bodyLarge?.fontSize ?? 16) * 1.2,
                decoration: const InputDecoration.collapsed(
                  hintText: "What's happening?",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
