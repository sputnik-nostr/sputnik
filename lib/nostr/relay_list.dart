import '../models/relay.dart';
import 'models/nostr_event.dart';

// A published list this long is not a real preference, just bloat or abuse.
const maxRelayListEntries = 50;

class RelayListEntry {
  const RelayListEntry({
    required this.url,
    this.read = true,
    this.write = true,
  });

  final String url;

  // Relays where the author looks for mentions of themselves.
  final bool read;

  // Relays where the author publishes.
  final bool write;

  // The tag marker; none means both, as NIP-65 defines.
  String? get marker => read && write ? null : (read ? 'read' : 'write');

  String get accessLabel {
    if (read && write) return 'Read and write';
    return read ? 'Read only' : 'Write only';
  }

  List<String> toTag() => ['r', url, ?marker];
}

// Valid relays from a kind:10002 event, with repeats merged.
List<RelayListEntry> relayListFromEvent(NostrEvent event) {
  final byUrl = <String, RelayListEntry>{};
  for (final tag in event.tags) {
    if (tag.length < 2 || tag[0] != 'r') continue;
    final url = canonicalRelayUrl(tag[1]);
    if (!isRelayUrl(url)) continue;

    final marker = tag.length > 2 ? tag[2] : null;
    final entry = RelayListEntry(
      url: url,
      read: marker != 'write',
      write: marker != 'read',
    );
    final existing = byUrl[url];
    byUrl[url] = existing == null
        ? entry
        : RelayListEntry(
            url: url,
            read: existing.read || entry.read,
            write: existing.write || entry.write,
          );
    if (byUrl.length >= maxRelayListEntries) break;
  }
  return byUrl.values.toList();
}
