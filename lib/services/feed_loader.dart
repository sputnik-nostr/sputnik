import 'package:flutter/foundation.dart';

import '../main.dart';
import '../models/note.dart';
import '../models/note_mapper.dart';
import '../nostr/nostr.dart';
import 'post_cursor.dart';

/// Tests swap this to feed the loaders without a network.
RelayClient feedRelayClient = const RelayClient();

/// Bumped by each load, so a slower, older load can't overwrite a newer one.
int _globalGeneration = 0;

/// As [_globalGeneration], for the following feed.
int _followingGeneration = 0;

/// Runs [load] unawaited; errors are reported to Flutter as [description].
void runFeedLoad(Future<void> Function() load, String description) {
  load().catchError((Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'sputnik',
        context: ErrorDescription(description),
      ),
    );
  });
}

final _globalCursor = PostCursor(
  (until) => RelayPostRepository(
    relayUrls: selectedRelaysNotifier.value,
    client: feedRelayClient,
  ).fetchPage(includeReplies: false, until: until),
);

final _followingCursor = PostCursor(
  (until) => RelayPostRepository(
    relayUrls: selectedRelaysNotifier.value,
    client: feedRelayClient,
  ).fetchPage(authors: _followingAuthors, includeReplies: false, until: until),
);

List<String> _followingAuthors = const [];

ValueListenable<bool> get globalFeedHasMore => _globalCursor.hasMore;
ValueListenable<bool> get followingFeedHasMore => _followingCursor.hasMore;

/// Loads the newest notes from the selected relays into [notesNotifier].
Future<void> loadGlobalFeed() async {
  final generation = ++_globalGeneration;
  final relayUrls = selectedRelaysNotifier.value;
  final posts = await _globalCursor.first();
  if (generation != _globalGeneration) return;

  await _showPosts(
    posts,
    relayUrls,
    notesNotifier,
    () => generation == _globalGeneration,
  );
}

/// Appends the next older page to [notesNotifier].
Future<void> loadMoreGlobalFeed() => _appendPosts(_globalCursor, notesNotifier);

/// Posts by the active identity and everyone it follows.
Future<void> loadFollowingFeed() async {
  final generation = ++_followingGeneration;
  final relayUrls = selectedRelaysNotifier.value;
  final myPubkeyHex = activeIdentityPubkeyNotifier.value;
  if (myPubkeyHex == null) {
    followingNotesNotifier.value = const [];
    _followingCursor.hasMore.value = false;
    return;
  }

  await const RelayContactsRepository().ensureMyFollowingLoaded(relayUrls);
  if (generation != _followingGeneration) return;

  _followingAuthors = {...?myFollowingNotifier.value, myPubkeyHex}.toList();
  final posts = await _followingCursor.first();
  if (generation != _followingGeneration) return;

  await _showPosts(
    posts,
    relayUrls,
    followingNotesNotifier,
    () => generation == _followingGeneration,
  );
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

  final relayUrls = selectedRelaysNotifier.value;
  target.value = [
    ...?target.value,
    ...notesFromPosts(posts, profileCacheNotifier.value),
  ];

  final hydrated = {
    for (final note in await hydratePosts(posts, relayUrls)) note.id: note,
  };
  target.value = [
    for (final note in target.value ?? const <Note>[])
      hydrated[note.id] ?? note,
  ];
}

Future<void> _showPosts(
  List<NostrPost> posts,
  Set<String> relayUrls,
  ValueNotifier<List<Note>?> target,
  bool Function() isCurrent,
) async {
  // Show posts immediately, using cached profile data when available, instead
  // of blocking the entire feed on the profile and reaction round trips below.
  target.value = notesFromPosts(posts, profileCacheNotifier.value);

  final hydrated = {
    for (final note in await hydratePosts(posts, relayUrls)) note.id: note,
  };
  if (!isCurrent()) return;
  // Older pages may have been appended while this was hydrating.
  target.value = [
    for (final note in target.value ?? const <Note>[])
      hydrated[note.id] ?? note,
  ];
}
