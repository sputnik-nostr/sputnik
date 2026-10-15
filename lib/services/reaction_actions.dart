import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/note.dart';
import '../nostr/nostr.dart';
import 'publishing.dart';

typedef _Publish = Future<Map<String, RelayPublishResult>> Function({
  required SecretKey secretKey,
  required String myPubkeyHex,
  required NostrEvent target,
  required Set<String> relayUrls,
});

/// Confirms first if [alwaysConfirm] or the confirmation setting is on.
Future<bool> _publishAgainst(
  BuildContext context, {
  required Future<NostrEvent?> Function(String myPubkeyHex, Set<String> relays)
  fetchTarget,
  required String notFoundMessage,
  required String dialogTitle,
  required String dialogBody,
  required bool alwaysConfirm,
  required _Publish publish,
}) async {
  final identity = activeIdentity();
  if (identity == null) return false;

  final relayUrls = selectedRelaysNotifier.value;
  final messenger = ScaffoldMessenger.of(context);

  final target = await fetchTarget(identity.pubkeyHex, relayUrls);
  if (!context.mounted) return false;
  if (target == null) {
    messenger.showSnackBar(SnackBar(content: Text(notFoundMessage)));
    return false;
  }

  if (alwaysConfirm || confirmBeforeReactingNotifier.value) {
    final confirmed = await confirmAction(
      context,
      title: dialogTitle,
      message: dialogBody,
      action: 'Continue',
    );
    if (!confirmed || !context.mounted) return false;
  }

  final secretKey = await loadSecretKeyOrReport(identity, messenger);
  if (secretKey == null) return false;

  try {
    if (!context.mounted) return false;
    final results = await publish(
      secretKey: secretKey,
      myPubkeyHex: identity.pubkeyHex,
      target: target,
      relayUrls: relayUrls,
    );
    return reportPublishResults(
      messenger,
      results,
      failure: 'Could not publish to any relay',
    );
  } finally {
    secretKey.wipe();
  }
}

/// [_publishAgainst] with [note]'s own signed event as the target.
Future<bool> _publishOnNote(
  BuildContext context,
  Note note, {
  required RelayClient relayClient,
  required String dialogTitle,
  required String dialogBody,
  required bool alwaysConfirm,
  required _Publish publish,
}) {
  return _publishAgainst(
    context,
    fetchTarget: (_, relayUrls) => RelayPostRepository(
      relayUrls: relayUrls,
      client: relayClient,
    ).fetchEventById(note.id),
    notFoundMessage: 'Could not load this note from relays',
    dialogTitle: dialogTitle,
    dialogBody: dialogBody,
    alwaysConfirm: alwaysConfirm,
    publish: publish,
  );
}

/// [_publishAgainst] with the caller's own kind [kind] reaction/repost of
/// [note] as the target of a NIP-09 deletion.
Future<bool> _retractReaction(
  BuildContext context,
  Note note, {
  required RelayClient relayClient,
  required int kind,
  required String dialogTitle,
  required String dialogBody,
  required bool alwaysConfirm,
}) {
  final repository = RelayReactionsRepository(client: relayClient);
  return _publishAgainst(
    context,
    fetchTarget: (myPubkeyHex, relayUrls) => repository.fetchOwnReaction(
      myPubkeyHex: myPubkeyHex,
      noteId: note.id,
      kind: kind,
      relayUrls: relayUrls,
    ),
    notFoundMessage: 'Could not find that on any of your relays',
    dialogTitle: dialogTitle,
    dialogBody: dialogBody,
    alwaysConfirm: alwaysConfirm,
    publish: repository.publishRetraction,
  );
}

/// Publishes a NIP-25 like for [note].
Future<bool> likeNote(
  BuildContext context,
  Note note, {
  RelayClient relayClient = const RelayClient(),
}) {
  return _publishOnNote(
    context,
    note,
    relayClient: relayClient,
    alwaysConfirm: false,
    dialogTitle: 'Like this note?',
    dialogBody:
        'This publishes a public reaction to '
        '${selectedRelaysNotifier.value.length} relay(s). It can be '
        'removed later, but relays are not required to honor that.',
    publish: RelayReactionsRepository(client: relayClient).publishLike,
  );
}

/// Publishes a NIP-18 repost of [note]. Always confirms first.
Future<bool> repostNote(
  BuildContext context,
  Note note, {
  RelayClient relayClient = const RelayClient(),
}) {
  return _publishOnNote(
    context,
    note,
    relayClient: relayClient,
    alwaysConfirm: true,
    dialogTitle: 'Repost this note?',
    dialogBody:
        "This publishes a public repost, including a copy of the note's "
        'content, to ${selectedRelaysNotifier.value.length} relay(s). It '
        'can be removed later, but relays are not required to honor that.',
    publish: RelayReactionsRepository(client: relayClient).publishRepost,
  );
}

/// Removes a previously-published like for [note] (NIP-09).
Future<bool> unlikeNote(
  BuildContext context,
  Note note, {
  RelayClient relayClient = const RelayClient(),
}) {
  return _retractReaction(
    context,
    note,
    relayClient: relayClient,
    kind: 7,
    alwaysConfirm: false,
    dialogTitle: 'Remove your like?',
    dialogBody:
        'This asks your relays to delete your reaction. Removal is not '
        'guaranteed; other relays or clients may still show it.',
  );
}

/// Removes a previously-published repost of [note] (NIP-09). Always
/// confirms first.
Future<bool> unrepostNote(
  BuildContext context,
  Note note, {
  RelayClient relayClient = const RelayClient(),
}) {
  return _retractReaction(
    context,
    note,
    relayClient: relayClient,
    kind: 6,
    alwaysConfirm: true,
    dialogTitle: 'Remove your repost?',
    dialogBody:
        'This asks your relays to delete your repost. Removal is not '
        'guaranteed; other relays or clients may still show it.',
  );
}

/// Drops [noteId] from the cached feeds, so a deleted note stops showing.
void _removeNoteFromFeeds(String noteId) {
  notesNotifier.value = notesNotifier.value
      ?.where((cached) => cached.id != noteId)
      .toList();
  followingNotesNotifier.value = followingNotesNotifier.value
      ?.where((cached) => cached.id != noteId)
      .toList();
}

/// Publishes a NIP-09 deletion request for [note] itself. Always confirms
/// first, since deleting your own note is not easily undone.
Future<bool> deleteNote(
  BuildContext context,
  Note note, {
  RelayClient relayClient = const RelayClient(),
}) async {
  final succeeded = await _publishOnNote(
    context,
    note,
    relayClient: relayClient,
    alwaysConfirm: true,
    dialogTitle: 'Delete this note?',
    dialogBody:
        'This asks your relays to delete the note. Removal is not '
        'guaranteed; other relays or clients may still show it.',
    publish: RelayReactionsRepository(client: relayClient).publishRetraction,
  );
  if (succeeded) _removeNoteFromFeeds(note.id);
  return succeeded;
}
