import '../main.dart';
import '../models/note_mapper.dart';
import '../nostr/nostr.dart';

Future<void> loadFeed() async {
  final relayUrls = selectedRelaysNotifier.value;
  final PostRepository postRepository = RelayPostRepository(
    relayUrls: relayUrls,
  );
  final posts = await postRepository.fetchPosts();

  // Show posts right away, using already-cached profile metadata where
  // available, instead of blocking the whole feed on the profile and
  // reaction round trips below.
  notesNotifier.value = notesFromPosts(posts, profileCacheNotifier.value);

  notesNotifier.value = await hydratePosts(posts, relayUrls);
}
