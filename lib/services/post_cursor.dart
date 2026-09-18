import 'package:flutter/foundation.dart';

import '../nostr/nostr.dart';

// Bounds memory, and how far a tab that filters most posts out keeps paging.
const maxCursorPosts = 1000;

// Pages through posts newest first, keeping track of what was already shown.
class PostCursor {
  PostCursor(this._fetchPage);

  final Future<PostPage> Function(DateTime? until) _fetchPage;

  // Whether older posts may be left to load.
  final hasMore = ValueNotifier<bool>(false);

  final _seen = <String>{};
  DateTime? _next;
  bool _loading = false;
  int _generation = 0;

  // Starts over from the newest post.
  Future<List<NostrPost>> first() async {
    final generation = ++_generation;
    _loading = true;
    try {
      final page = await _fetchPage(null);
      if (generation != _generation) return page.posts;
      _seen.clear();
      return _take(page);
    } finally {
      if (generation == _generation) _loading = false;
    }
  }

  // The next older posts that were not returned before.
  Future<List<NostrPost>> more() async {
    if (_loading || _next == null) return const [];
    final generation = _generation;
    _loading = true;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final page = await _fetchPage(_next);
        if (generation != _generation) return const [];
        final fresh = _take(page);
        if (fresh.isNotEmpty || _next == null) return fresh;
      }
      return const [];
    } finally {
      if (generation == _generation) _loading = false;
    }
  }

  List<NostrPost> _take(PostPage page) {
    final fresh = [
      for (final post in page.posts)
        if (_seen.add(post.id)) post,
    ];
    _next = _seen.length >= maxCursorPosts ? null : page.next;
    hasMore.value = _next != null;
    return fresh;
  }
}
