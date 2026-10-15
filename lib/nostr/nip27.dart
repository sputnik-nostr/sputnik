import 'http_urls.dart';
import 'nip19.dart';

typedef NoteReference = ({int start, int end, String eventIdHex});

/// HTTP(S) URLs (group 1), and nostr: URIs or bare NIP-19 entities (group 2).
/// URLs are matched too, so an entity inside one is not taken for a reference.
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
