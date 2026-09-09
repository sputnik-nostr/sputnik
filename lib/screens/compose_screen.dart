import 'package:flutter/material.dart';

import '../main.dart';
import '../models/current_user.dart';
import '../theme/app_text_styles.dart';
import '../widgets/fade_in_avatar.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _controller = TextEditingController();

  bool _hasText = false;

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

  void _post() {
    // Publishing isn't wired up yet: no event signing or relay write path
    // exists (RelayClient/RelayConnectionPool are read-only so far).
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Posting to relays is not implemented yet')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    final metadata = pubkeyHex == null
        ? null
        : profileCacheNotifier.value[pubkeyHex];
    final isCurrentUser =
        pubkeyHex == null || pubkeyHex == CurrentUser.pubkeyHex;
    final resolvedName = metadata?.resolvedName?.trim();
    final fallbackLabel = resolvedName?.isNotEmpty == true
        ? resolvedName![0].toUpperCase()
        : isCurrentUser
        ? CurrentUser.displayName[0].toUpperCase()
        : pubkeyHex[0].toUpperCase();

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
            child: FilledButton(
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
