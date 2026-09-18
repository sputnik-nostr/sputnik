import 'models/nostr_event.dart';

const _nip10Markers = {'root', 'reply', 'mention'};

// Caps how many people a reply mentions when the parent lists hundreds.
const _maxReplyMentions = 50;

final _pubkeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

bool _hasNip10Marker(List<String> tag) =>
    tag.length >= 4 && _nip10Markers.contains(tag[3]);

List<List<String>> _eTags(NostrEvent event) => [
  for (final tag in event.tags)
    if (tag.length > 1 && tag[0] == 'e') tag,
];

// As per NIP-10, a marked "reply" tag should be preferred over "root" for
// top-level replies. Without markers (deprecated), the last "e" tag is the
// parent; earlier ones are just citations. Null means it's not a reply.
String? replyParentId(NostrEvent event) {
  final eTags = _eTags(event);
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

// The first note of the thread a reply belongs to. Null when it's not a reply.
String? threadRootId(NostrEvent event) {
  final parent = replyParentId(event);
  if (parent == null) return null;

  final eTags = _eTags(event);
  final marked = eTags.where(_hasNip10Marker).toList();
  if (marked.isEmpty) return eTags.first[1].toLowerCase();

  for (final tag in marked) {
    if (tag[3] == 'root') return tag[1].toLowerCase();
  }
  return parent;
}

// The e and p tags for a reply to [parent], per NIP-10.
List<List<String>> replyTags(NostrEvent parent) {
  final rootId = threadRootId(parent);
  final eTags = rootId == null || rootId == parent.id
      ? [
          ['e', parent.id, '', 'root', parent.pubkey],
        ]
      : [
          ['e', rootId, '', 'root'],
          ['e', parent.id, '', 'reply', parent.pubkey],
        ];

  final mentioned = <String>{
    parent.pubkey.toLowerCase(),
    for (final tag in parent.tags)
      if (tag.length > 1 && tag[0] == 'p' && _pubkeyPattern.hasMatch(tag[1]))
        tag[1].toLowerCase(),
  };

  return [
    ...eTags,
    for (final pubkey in mentioned.take(_maxReplyMentions)) ['p', pubkey],
  ];
}
