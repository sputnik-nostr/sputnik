import 'models/nostr_event.dart';

const _nip10Markers = {'root', 'reply', 'mention'};

bool _hasNip10Marker(List<String> tag) =>
    tag.length >= 4 && _nip10Markers.contains(tag[3]);

// As per NIP-10, a marked "reply" tag should be preferred over "root" for
// top-level replies. Without markers (deprecated), the last "e" tag is the
// parent; earlier ones are just citations. Null means it's not a reply.
String? replyParentId(NostrEvent event) {
  final eTags = [
    for (final tag in event.tags)
      if (tag.length > 1 && tag[0] == 'e') tag,
  ];
  if (eTags.isEmpty) return null;

  final marked = eTags.where(_hasNip10Marker).toList();
  if (marked.isNotEmpty) {
    for (final tag in marked) {
      if (tag[3] == 'reply') return tag[1].toLowerCase();
    }
    for (final tag in marked) {
      if (tag[3] == 'root') return tag[1].toLowerCase();
    }
    return null;
  }

  return eTags.last[1].toLowerCase();
}
