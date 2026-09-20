import 'package:flutter/material.dart';

import '../main.dart';
import '../models/identity.dart';
import '../models/note.dart';
import '../nostr/nip10.dart';
import '../nostr/nostr.dart';
import '../services/settings_store.dart';
import '../theme/app_text_styles.dart';
import '../widgets/fade_in_avatar.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({
    super.key,
    this.relayClient = const RelayClient(),
    this.replyTo,
  });

  final RelayClient relayClient;

  /// The note being replied to, or null for a new top-level note.
  final Note? replyTo;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _controller = TextEditingController();

  bool _hasText = false;
  bool _posting = false;

  /// The parent's tags decide how a reply is threaded, so it is fetched early.
  Future<NostrEvent?>? _parentFuture;

  RelayPostRepository get _posts => RelayPostRepository(
    relayUrls: selectedRelaysNotifier.value,
    client: widget.relayClient,
  );

  @override
  void initState() {
    super.initState();
    final replyTo = widget.replyTo;
    if (replyTo != null) _parentFuture = _posts.fetchEventById(replyTo.id);
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
    final isReply = widget.replyTo != null;
    final noun = isReply ? 'reply' : 'note';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isReply ? 'Post reply to relays?' : 'Post to relays?'),
        content: Text(
          'This publishes your $noun to $relayCount relay(s). '
          '${isReply ? 'Replies' : 'Notes'} on Nostr are public and cannot '
          'be reliably deleted afterward.',
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

    setState(() => _posting = true);
    try {
      await _sign(identity, relayUrls);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _sign(Identity identity, Set<String> relayUrls) async {
    final messenger = ScaffoldMessenger.of(context);

    List<List<String>> tags = const [];
    if (widget.replyTo != null) {
      final parent =
          await _parentFuture ??
          await _posts.fetchEventById(widget.replyTo!.id);
      if (!mounted) return;
      if (parent == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not load the note you are replying to'),
          ),
        );
        return;
      }
      tags = replyTags(parent);
    }

    // Only touch secure storage once the user has actually confirmed.
    final privkeyHex = await SettingsStore.loadPrivateKey(identity.pubkeyHex);
    if (!mounted) return;
    if (privkeyHex == null) {
      messenger.showSnackBar(
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
        tags: tags,
        content: _controller.text.trim(),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not sign this note: $e')),
      );
      return;
    }

    final results = await widget.relayClient.publish(event, relayUrls);
    if (!mounted) return;

    final accepted = results.values
        .where((result) => result.outcome == RelayPublishOutcome.accepted)
        .length;

    if (accepted > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.replyTo != null
                ? 'Reply posted to $accepted/${results.length} relays'
                : 'Posted to $accepted/${results.length} relays',
          ),
        ),
      );
      Navigator.pop(context, event);
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
    final replyTo = widget.replyTo;
    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    final metadata = pubkeyHex == null
        ? null
        : profileCacheNotifier.value[pubkeyHex];
    final resolvedName = metadata?.resolvedName?.trim();
    final fallbackLabel = resolvedName?.isNotEmpty == true
        ? avatarInitial(resolvedName!)
        : pubkeyHex?.isNotEmpty == true
        ? avatarInitial(pubkeyHex!)
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
                    child: Text(replyTo == null ? 'Post' : 'Reply'),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (replyTo != null) _ReplyContext(note: replyTo),
          if (pubkeyHex == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Create or import an identity to post.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          Row(
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
                  cursorHeight:
                      (theme.textTheme.bodyLarge?.fontSize ?? 16) * 1.2,
                  decoration: InputDecoration.collapsed(
                    hintText: replyTo == null
                        ? 'Post a note'
                        : 'Post your reply',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReplyContext extends StatelessWidget {
  const _ReplyContext({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: 'Replying to ',
              children: [
                TextSpan(text: note.displayName, style: theme.avatarName),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.metadata,
          ),
          const SizedBox(height: 4),
          Text(
            note.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
