import 'http_urls.dart';
import 'nip19.dart';

typedef NoteReference = ({int start, int end, String eventIdHex});

/// Matches URLs too, so a note ID inside one is not taken for a reference.
final _referencePattern = RegExp(
  '(${httpUrlPattern.pattern})|($nostrEntityPattern)',
  caseSensitive: false,
);

/// The `note` and `nevent` references in [text], in order.
List<NoteReference> noteReferences(String text) {
  return [
    for (final match in _referencePattern.allMatches(text))
      if (match.group(2) case final entity?)
        if (decodeNostrUri(entity)?.eventIdHex case final id?)
          (start: match.start, end: match.end, eventIdHex: id),
  ];
}
