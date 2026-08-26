class NostrFilter {
  const NostrFilter({
    this.ids,
    this.authors,
    this.kinds,
    this.since,
    this.until,
    this.limit,
  });

  final List<String>? ids;
  final List<String>? authors;
  final List<int>? kinds;
  final DateTime? since;
  final DateTime? until;
  final int? limit;

  Map<String, dynamic> toJson() {
    return {
      if (ids != null) 'ids': ids,
      if (authors != null) 'authors': authors,
      if (kinds != null) 'kinds': kinds,
      if (since != null) 'since': since!.millisecondsSinceEpoch ~/ 1000,
      if (until != null) 'until': until!.millisecondsSinceEpoch ~/ 1000,
      if (limit != null) 'limit': limit,
    };
  }
}
