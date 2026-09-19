import 'nostr_event.dart';

class NostrFilter {
  const NostrFilter({
    this.ids,
    this.authors,
    this.kinds,
    this.tags,
    this.since,
    this.until,
    this.limit,
  });

  final List<String>? ids;
  final List<String>? authors;
  final List<int>? kinds;
  final Map<String, List<String>>? tags;
  final DateTime? since;
  final DateTime? until;
  final int? limit;

  Map<String, dynamic> toJson() {
    return {
      if (ids != null) 'ids': ids,
      if (authors != null) 'authors': authors,
      if (kinds != null) 'kinds': kinds,
      if (tags != null)
        for (final entry in tags!.entries) '#${entry.key}': entry.value,
      if (since != null) 'since': since!.millisecondsSinceEpoch ~/ 1000,
      if (until != null) 'until': until!.millisecondsSinceEpoch ~/ 1000,
      if (limit != null) 'limit': limit,
    };
  }

  NostrFilterMatcher matcher() => NostrFilterMatcher(this);
}

// Relays are untrusted, so what they return is checked against what was asked.
class NostrFilterMatcher {
  NostrFilterMatcher(NostrFilter filter)
    : _ids = filter.ids?.map((id) => id.toLowerCase()).toSet(),
      _authors = filter.authors?.map((a) => a.toLowerCase()).toSet(),
      _kinds = filter.kinds?.toSet(),
      _tags = filter.tags == null
          ? null
          : {
              for (final entry in filter.tags!.entries)
                entry.key: entry.value.toSet(),
            },
      _since = filter.since == null ? null : _seconds(filter.since!),
      _until = filter.until == null ? null : _seconds(filter.until!);

  final Set<String>? _ids;
  final Set<String>? _authors;
  final Set<int>? _kinds;
  final Map<String, Set<String>>? _tags;
  final int? _since;
  final int? _until;

  static int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

  bool matches(NostrEvent event) {
    if (_ids != null && !_ids.contains(event.id)) return false;
    if (_authors != null && !_authors.contains(event.pubkey)) return false;
    if (_kinds != null && !_kinds.contains(event.kind)) return false;

    final createdAt = _seconds(event.createdAt);
    if (_since != null && createdAt < _since) return false;
    if (_until != null && createdAt > _until) return false;

    for (final entry in (_tags ?? const <String, Set<String>>{}).entries) {
      final hit = event.tags.any(
        (tag) =>
            tag.length > 1 &&
            tag[0] == entry.key &&
            entry.value.contains(tag[1]),
      );
      if (!hit) return false;
    }
    return true;
  }
}
