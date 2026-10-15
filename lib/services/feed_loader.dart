import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../models/note.dart';
import '../models/note_mapper.dart';
import '../nostr/nostr.dart';
import 'error_reporting.dart';
import 'follow_sync.dart';
import 'note_hydration.dart';
import 'post_cursor.dart';

/// Runs [load] unawaited; errors are reported to Flutter as [description].
void runFeedLoad(Future<void> Function() load, String description) {
  load().catchError((Object error, StackTrace stack) {
    reportError(description, error, stack);
  });
}

final _globalCursor = PostCursor(
  (until) =>
      RelayPostRepository(relayUrls: selectedRelaysNotifier.value)
          .fetchPage(includeReplies: false, until: until),
);

final _followingCursor = PostCursor(
  (until) => RelayPostRepository(
    relayUrls: selectedRelaysNotifier.value,
  ).fetchPage(authors: _followingAuthors, includeReplies: false, until: until),
);

List<String> _followingAuthors = const [];

ValueListenable<bool> get globalFeedHasMore => _globalCursor.hasMore;
ValueListenable<bool> get followingFeedHasMore => _followingCursor.hasMore;

/// Loads the newest notes from the selected relays into [notesNotifier].
Future<void> loadGlobalFeed() =>
    _loadFirst(_globalCursor, selectedRelaysNotifier.value, notesNotifier);

/// Appends the next older page to [notesNotifier].
Future<void> loadMoreGlobalFeed() => _appendPosts(_globalCursor, notesNotifier);

/// Posts by the active identity and everyone it follows.
Future<void> loadFollowingFeed() async {
  final relayUrls = selectedRelaysNotifier.value;
  final myPubkeyHex = activeIdentityPubkeyNotifier.value;
  if (myPubkeyHex == null) {
    followingNotesNotifier.value = const [];
    _followingCursor.hasMore.value = false;
    return;
  }

  await ensureMyFollowingLoaded(relayUrls);
  // The identity may have changed while its follow list loaded.
  if (activeIdentityPubkeyNotifier.value != myPubkeyHex) return;

  _followingAuthors = {...?myFollowingNotifier.value, myPubkeyHex}.toList();
  await _loadFirst(_followingCursor, relayUrls, followingNotesNotifier);
}

/// Appends the next older page to [followingNotesNotifier].
Future<void> loadMoreFollowingFeed() =>
    _appendPosts(_followingCursor, followingNotesNotifier);

Future<void> _appendPosts(
  PostCursor cursor,
  ValueNotifier<List<Note>?> target,
) async {
  final posts = await cursor.more();
  if (posts.isEmpty) return;

  target.value = [
    ...?target.value,
    ...notesFromPosts(posts, profileCacheNotifier.value),
  ];
  await _hydrateInto(target, posts, selectedRelaysNotifier.value);
}

/// Shows the newest page at once, then again with profiles and counts.
Future<void> _loadFirst(
  PostCursor cursor,
  Set<String> relayUrls,
  ValueNotifier<List<Note>?> target,
) async {
  final posts = await cursor.first();
  if (posts == null) return;
  final generation = cursor.generation;

  target.value = notesFromPosts(posts, profileCacheNotifier.value);
  await _hydrateInto(
    target,
    posts,
    relayUrls,
    isCurrent: () => cursor.generation == generation,
  );
}

/// Replaces [posts]' notes in [target] with ones that have profiles and counts.
Future<void> _hydrateInto(
  ValueNotifier<List<Note>?> target,
  List<NostrPost> posts,
  Set<String> relayUrls, {
  bool Function()? isCurrent,
}) async {
  final hydrated = {
    for (final note in await hydratePosts(posts, relayUrls)) note.id: note,
  };
  if (isCurrent != null && !isCurrent()) return;
  // Other pages may have been added while this was hydrating.
  target.value = [
    for (final note in target.value ?? const <Note>[])
      hydrated[note.id] ?? note,
  ];
}
