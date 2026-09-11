import '../main.dart';
import '../models/note_mapper.dart';
import '../nostr/nostr.dart';

int _loadGeneration = 0;

Future<void> loadFeed() async {
  final generation = ++_loadGeneration;
  final relayUrls = selectedRelaysNotifier.value;
  final PostRepository postRepository = RelayPostRepository(
    relayUrls: relayUrls,
  );
  final posts = await postRepository.fetchPosts();
  if (generation != _loadGeneration) return;

  // Show posts right away, using already-cached profile metadata where
  // available, instead of blocking the whole feed on the profile and
  // reaction round trips below.
  notesNotifier.value = notesFromPosts(posts, profileCacheNotifier.value);

  final hydrated = await hydratePosts(posts, relayUrls);
  if (generation != _loadGeneration) return;
  notesNotifier.value = hydrated;
}
