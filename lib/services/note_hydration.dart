import '../app_state.dart';
import '../models/note.dart';
import '../models/note_mapper.dart';
import '../nostr/nostr.dart';
import 'profiles.dart';

/// The note [id] with its author's profile, or null if no relay returns it.
Future<Note?> loadNote(String id, Set<String> relayUrls) async {
  final post = await RelayPostRepository(relayUrls: relayUrls)
      .fetchPostById(id);
  if (post == null) return null;
  final metadata = await loadProfile(post.authorPubkey, relayUrls);
  return noteFromNostrPost(post, authorMetadata: metadata);
}

/// Fetches profiles and reaction counts for [posts], then maps them to
/// notes. [knownMetadata] skips the fetch for pubkeys it already covers.
Future<List<Note>> hydratePosts(
  List<NostrPost> posts,
  Set<String> relayUrls, {
  Map<String, NostrMetadata>? knownMetadata,
}) async {
  final known = knownMetadata ?? const <String, NostrMetadata>{};
  final needed = {
    for (final post in posts) post.authorPubkey,
    for (final post in posts)
      if (post.repostedByPubkey != null) post.repostedByPubkey!,
  }..removeAll(known.keys);

  final profilesFuture = needed.isEmpty
      ? Future.value(known)
      : loadProfiles(
          needed,
          relayUrls,
        ).then((fetched) => {...known, ...fetched});
  final reactionsFuture = RelayReactionsRepository().fetchReactions(
    posts.map((post) => post.id).toList(),
    relayUrls,
  );

  final notes = notesFromPosts(posts, await profilesFuture);
  return applyReactionCounts(
    notes,
    await reactionsFuture,
    myPubkeyHex: activeIdentityPubkeyNotifier.value,
  );
}
