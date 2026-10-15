import 'hex.dart';
import 'models/nostr_event.dart';

const _nip10Markers = {'root', 'reply', 'mention'};

/// Caps how many people a reply mentions when the parent lists hundreds.
const _maxReplyMentions = 50;

bool _hasNip10Marker(List<String> tag) =>
    tag.length >= 4 && _nip10Markers.contains(tag[3]);

/// The `e` tags that can make [event] a reply; a quoted unmarked one is not.
List<List<String>> _eTags(NostrEvent event) {
  final quoted = {
    for (final tag in event.tags)
      if (tag.length > 1 && tag[0] == 'q') tag[1].toLowerCase(),
  };
  return [
    for (final tag in event.tags)
      if (tag.length > 1 && tag[0] == 'e')
        if (_hasNip10Marker(tag) || !quoted.contains(tag[1].toLowerCase())) tag,
  ];
}

/// The parent's ID: marked `reply`, then `root`, else the last `e` tag.
String? replyParentId(NostrEvent event) => _parentId(_eTags(event));

String? _parentId(List<List<String>> eTags) {
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

/// The thread root's ID; unmarked, the first `e` tag.
String? threadRootId(NostrEvent event) {
  final eTags = _eTags(event);
  final parent = _parentId(eTags);
  if (parent == null) return null;

  final marked = eTags.where(_hasNip10Marker).toList();
  if (marked.isEmpty) return eTags.first[1].toLowerCase();

  for (final tag in marked) {
    if (tag[3] == 'root') return tag[1].toLowerCase();
  }
  return parent;
}

/// The e and p tags for a reply to [parent], per NIP-10.
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
      if (tag.length > 1 && tag[0] == 'p' && isHex(tag[1], 32))
        tag[1].toLowerCase(),
  };

  return [
    ...eTags,
    for (final pubkey in mentioned.take(_maxReplyMentions)) ['p', pubkey],
  ];
}
