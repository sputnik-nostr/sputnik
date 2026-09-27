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
    this.quoting,
  });

  final RelayClient relayClient;

  /// The note being replied to, or null for a new top-level note.
  final Note? replyTo;

  /// The note being quoted, or null. Mutually exclusive with [replyTo].
  final Note? quoting;

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
    final isQuote = widget.quoting != null;
    final noun = isReply
        ? 'reply'
        : isQuote
        ? 'quote'
        : 'note';
    final title = isReply
        ? 'Post reply to relays?'
        : isQuote
        ? 'Post quote to relays?'
        : 'Post to relays?';
    final plural = isReply
        ? 'Replies'
        : isQuote
        ? 'Quotes'
        : 'Notes';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(
          'This publishes your $noun to $relayCount relay(s). $plural on '
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
    var content = _controller.text.trim();

    final quoting = widget.quoting;
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
    } else if (quoting != null) {
      // NIP-18: mentions of quoted events must be converted into a q tag.
      tags = [
        ['q', quoting.id, '', quoting.pubkey],
      ];
      final reference =
          'nostr:${neventFromHex(quoting.id, authorPubkeyHex: quoting.pubkey)}';
      content = content.isEmpty ? reference : '$content\n\n$reference';
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
        content: content,
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
      final label = widget.replyTo != null
          ? 'Reply posted to $accepted/${results.length} relays'
          : quoting != null
          ? 'Quote posted to $accepted/${results.length} relays'
          : 'Posted to $accepted/${results.length} relays';
      messenger.showSnackBar(SnackBar(content: Text(label)));
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
    final quoting = widget.quoting;
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
                    onPressed:
                        pubkeyHex != null && (_hasText || quoting != null)
                        ? _post
                        : null,
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
                    hintText: replyTo != null
                        ? 'Post your reply'
                        : quoting != null
                        ? 'Add a comment'
                        : 'Post a note',
                  ),
                ),
              ),
            ],
          ),
          if (quoting != null) _QuoteContext(note: quoting),
        ],
      ),
    );
  }
}

/// Opens the composer to quote [note] and returns the published note, if any.
Future<NostrEvent?> openQuoteComposer(
  BuildContext context,
  Note note, {
  RelayClient relayClient = const RelayClient(),
}) {
  return Navigator.push<NostrEvent>(
    context,
    MaterialPageRoute(
      builder: (_) => ComposeScreen(quoting: note, relayClient: relayClient),
      fullscreenDialog: true,
    ),
  );
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

/// A preview of the note being quoted, shown as it will render once posted.
class _QuoteContext extends StatelessWidget {
  const _QuoteContext({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card.outlined(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FadeInAvatar(
                    radius: 10,
                    imageUrl: note.pictureUrl,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    fallback: Text(
                      avatarInitial(note.displayName),
                      style: theme.avatarFallback.copyWith(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      note.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.avatarName,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                note.content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
