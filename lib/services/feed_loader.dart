import 'package:flutter/foundation.dart';

import '../main.dart';
import '../models/note.dart';
import '../models/note_mapper.dart';
import '../nostr/nostr.dart';

int _globalGeneration = 0;
int _followingGeneration = 0;

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

Future<void> loadGlobalFeed() async {
  final generation = ++_globalGeneration;
  final relayUrls = selectedRelaysNotifier.value;
  final posts = await RelayPostRepository(relayUrls: relayUrls)
      .fetchPosts(includeReplies: false);
  if (generation != _globalGeneration) return;

  await _showPosts(
    posts,
    relayUrls,
    notesNotifier,
    () => generation == _globalGeneration,
  );
}

// Posts by the active identity and everyone it follows.
Future<void> loadFollowingFeed() async {
  final generation = ++_followingGeneration;
  final relayUrls = selectedRelaysNotifier.value;
  final myPubkeyHex = activeIdentityPubkeyNotifier.value;
  if (myPubkeyHex == null) {
    followingNotesNotifier.value = const [];
    return;
  }

  await const RelayContactsRepository().ensureMyFollowingLoaded(relayUrls);
  if (generation != _followingGeneration) return;

  final authors = {...?myFollowingNotifier.value, myPubkeyHex}.toList();
  final posts = await RelayPostRepository(relayUrls: relayUrls)
      .fetchPostsByAuthors(authors, includeReplies: false);
  if (generation != _followingGeneration) return;

  await _showPosts(
    posts,
    relayUrls,
    followingNotesNotifier,
    () => generation == _followingGeneration,
  );
}

Future<void> _showPosts(
  List<NostrPost> posts,
  Set<String> relayUrls,
  ValueNotifier<List<Note>?> target,
  bool Function() isCurrent,
) async {
  // Show posts right away, using already-cached profile metadata where
  // available, instead of blocking the whole feed on the profile and
  // reaction round trips below.
  target.value = notesFromPosts(posts, profileCacheNotifier.value);

  final hydrated = await hydratePosts(posts, relayUrls);
  if (isCurrent()) target.value = hydrated;
}
