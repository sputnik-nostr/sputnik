import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/avatar_initial.dart';
import '../models/identity.dart';
import '../models/note.dart';
import '../nostr/nip10.dart';
import '../nostr/nostr.dart';
import '../services/profiles.dart';
import '../services/publishing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/fade_in_avatar.dart';
import '../widgets/note_author_line.dart';

enum _ComposeKind {
  note('note', 'Notes', 'Post to relays?', 'Posted', 'Post a note'),
  reply(
    'reply',
    'Replies',
    'Post reply to relays?',
    'Reply posted',
    'Post your reply',
  ),
  quote(
    'quote',
    'Quotes',
    'Post quote to relays?',
    'Quote posted',
    'Add a comment',
  );

  const _ComposeKind(
    this.noun,
    this.plural,
    this.confirmTitle,
    this.postedLabel,
    this.hint,
  );

  final String noun;
  final String plural;
  final String confirmTitle;
  final String postedLabel;
  final String hint;
}

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.replyTo, this.quoting});

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

  _ComposeKind get _kind => widget.replyTo != null
      ? _ComposeKind.reply
      : widget.quoting != null
      ? _ComposeKind.quote
      : _ComposeKind.note;

  RelayPostRepository get _posts =>
      RelayPostRepository(relayUrls: selectedRelaysNotifier.value);

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

  Future<void> _post() async {
    final identity = activeIdentity();
    if (identity == null) return;

    final kind = _kind;
    final relayUrls = selectedRelaysNotifier.value;
    final confirmed = await confirmAction(
      context,
      title: kind.confirmTitle,
      message:
          'This publishes your ${kind.noun} to ${relayUrls.length} relay(s). '
          '${kind.plural} on Nostr are public and cannot be reliably deleted '
          'afterward.',
      action: 'Post',
      actionKey: const Key('confirmPostButton'),
    );
    if (!confirmed || !mounted) return;

    setState(() => _posting = true);
    try {
      await _publish(identity, relayUrls);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _publish(Identity identity, Set<String> relayUrls) async {
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

    // Wiped before publishing, so the key is not held during network I/O.
    final event = await withSecretKey(
      identity,
      messenger,
      signFailure: 'Could not sign this note',
      use: (secretKey) async => signEvent(
        secretKey: secretKey,
        pubkeyHex: identity.pubkeyHex,
        kind: 1,
        tags: tags,
        content: content,
      ),
    );
    if (event == null || !mounted) return;

    final results = await RelayClient.instance.publish(event, relayUrls);
    if (!mounted) return;

    final posted = reportPublishResults(
      messenger,
      results,
      failure: 'Could not post this note to any relay',
      success: (counts) => '${_kind.postedLabel} to $counts relays',
    );
    if (posted) Navigator.pop(context, event);
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
    final name = activeIdentityName();
    final fallbackLabel = name == null ? '?' : avatarInitial(name);

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
                  decoration: InputDecoration.collapsed(hintText: _kind.hint),
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
Future<NostrEvent?> openQuoteComposer(BuildContext context, Note note) {
  return Navigator.push<NostrEvent>(
    context,
    MaterialPageRoute(
      builder: (_) => ComposeScreen(quoting: note),
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
              NoteAuthorLine(note: note),
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
