import 'package:flutter/material.dart';

import '../main.dart';
import '../models/note.dart';
import '../models/note_mapper.dart';
import '../nostr/http_urls.dart';
import '../nostr/nostr.dart';
import '../screens/post_screen.dart';
import '../theme/app_text_styles.dart';
import 'fade_in_avatar.dart';
import 'linkified_text.dart';

const _maxCached = 200;
const _previewLines = 6;

/// A lookup that found nothing is retried after this.
const _missRetry = Duration(minutes: 2);

final _notes = <String, Note>{};
final _misses = <String, DateTime>{};
final _pending = <String, Future<Note?>>{};

/// Forgets every looked-up note.
void clearQuotedNoteCache() {
  _notes.clear();
  _misses.clear();
  _pending.clear();
}

Future<Note?> _fetch(String id, RelayClient client) {
  final missedAt = _misses[id];
  if (missedAt != null && DateTime.now().difference(missedAt) < _missRetry) {
    return Future.value();
  }
  return _pending[id] ??= _load(id, client).whenComplete(() {
    // A block body: returning the removed future would make it await itself.
    _pending.remove(id);
  });
}

Future<Note?> _load(String id, RelayClient client) async {
  final relayUrls = selectedRelaysNotifier.value;
  try {
    final post = await RelayPostRepository(
      relayUrls: relayUrls,
      client: client,
    ).fetchPostById(id);
    if (post != null) {
      final metadata = await RelayProfileRepository(client: client)
          .fetchProfile(post.author.pubkey, relayUrls);
      if (_notes.length >= _maxCached) _notes.clear();
      return _notes[id] = noteFromNostrPost(post, authorMetadata: metadata);
    }
  } catch (_) {
    // A failed lookup is a miss, so the reference stays a plain link.
  }
  if (_misses.length >= _maxCached) _misses.clear();
  _misses[id] = DateTime.now();
  return null;
}

/// A tappable preview of the note [reference] cites, or its link if not found.
class QuotedNote extends StatefulWidget {
  const QuotedNote({
    super.key,
    required this.eventIdHex,
    required this.reference,
    this.selectable = true,
    this.relayClient = const RelayClient(),
  });

  final String eventIdHex;
  final String reference;
  final bool selectable;
  final RelayClient relayClient;

  @override
  State<QuotedNote> createState() => _QuotedNoteState();
}

class _QuotedNoteState extends State<QuotedNote> {
  Note? _note;
  bool _missed = false;

  @override
  void initState() {
    super.initState();
    _note = _notes[widget.eventIdHex];
    if (_note == null) _resolve();
  }

  @override
  void didUpdateWidget(QuotedNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventIdHex == widget.eventIdHex) return;
    _note = _notes[widget.eventIdHex];
    _missed = false;
    if (_note == null) _resolve();
  }

  Future<void> _resolve() async {
    final id = widget.eventIdHex;
    final note = await _fetch(id, widget.relayClient);
    if (!mounted || id != widget.eventIdHex) return;
    setState(() {
      _note = note;
      _missed = note == null;
    });
  }

  void _open(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostScreen(note: note, relayClient: widget.relayClient),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_missed) {
      return LinkifiedText(
        widget.reference,
        selectable: widget.selectable,
        relayClient: widget.relayClient,
      );
    }

    final note = _note;
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: note == null ? null : () => _open(note),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: note == null
              ? Text('Loading note...', style: Theme.of(context).metadata)
              : _Preview(note: note, relayClient: widget.relayClient),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.note, required this.relayClient});

  final Note note;
  final RelayClient relayClient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Media stays behind a tap on the full post.
    final text = withoutUrls(note.content, {
      for (final media in note.media) media.url,
    });

    return Column(
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
            const SizedBox(width: 8),
            Text(note.postedAt, style: theme.metadata),
          ],
        ),
        if (text.isNotEmpty) ...[
          const SizedBox(height: 6),
          LinkifiedText(
            text,
            style: theme.textTheme.bodyMedium,
            selectable: false,
            maxLines: _previewLines,
            relayClient: relayClient,
          ),
        ],
        if (note.media.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            note.media.length == 1
                ? 'Contains 1 attachment'
                : 'Contains ${note.media.length} attachments',
            style: theme.metadata,
          ),
        ],
      ],
    );
  }
}
