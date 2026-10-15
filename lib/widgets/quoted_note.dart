import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/note.dart';
import '../nostr/http_urls.dart';
import '../screens/post_screen.dart';
import '../services/bounded_cache.dart';
import '../services/note_hydration.dart';
import '../theme/app_text_styles.dart';
import 'linkified_text.dart';
import 'note_author_line.dart';

const _previewLines = 6;

/// A lookup that found nothing is retried after this.
const _missRetry = Duration(minutes: 2);

final _notes = BoundedMap<String, Note>(200);
final _misses = BoundedMap<String, DateTime>(200);
final _pending = <String, Future<Note?>>{};

/// Forgets every looked-up note.
void clearQuotedNoteCache() {
  _notes.clear();
  _misses.clear();
  _pending.clear();
}

Future<Note?> _fetch(String id) {
  final missedAt = _misses[id];
  if (missedAt != null && DateTime.now().difference(missedAt) < _missRetry) {
    return Future.value();
  }
  return _pending[id] ??= _load(id).whenComplete(() {
    // A block body: returning the removed future would make it await itself.
    _pending.remove(id);
  });
}

Future<Note?> _load(String id) async {
  try {
    final note = await loadNote(id, selectedRelaysNotifier.value);
    if (note != null) {
      return _notes[id] = note;
    }
  } catch (_) {
    // A failed lookup is a miss, so the reference stays a plain link.
  }
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
  });

  final String eventIdHex;
  final String reference;
  final bool selectable;

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
    final note = await _fetch(id);
    if (!mounted || id != widget.eventIdHex) return;
    setState(() {
      _note = note;
      _missed = note == null;
    });
  }

  void _open(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PostScreen(note: note)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_missed) {
      return LinkifiedText(widget.reference, selectable: widget.selectable);
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
              : _Preview(note: note),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.note});

  final Note note;

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
        NoteAuthorLine(note: note, showTime: true),
        if (text.isNotEmpty) ...[
          const SizedBox(height: 6),
          LinkifiedText(
            text,
            style: theme.textTheme.bodyMedium,
            selectable: false,
            maxLines: _previewLines,
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
