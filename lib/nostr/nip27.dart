import 'http_urls.dart';
import 'nip19.dart';

typedef NoteReference = ({int start, int end, String eventIdHex});

/// URLs are group 1, so an entity inside a URL is never group 2.
final linkPattern = RegExp(
  '(${httpUrlPattern.pattern})|($nostrEntityPattern)',
  caseSensitive: false,
);

/// The `note` and `nevent` references in [text], in order.
List<NoteReference> noteReferences(String text) {
  return [
    for (final match in linkPattern.allMatches(text))
      if (match.group(2) case final entity?)
        if (decodeNostrUri(entity)?.eventIdHex case final id?)
          (start: match.start, end: match.end, eventIdHex: id),
  ];
}
