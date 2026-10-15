import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/note.dart';
import '../nostr/nostr.dart';
import 'publishing.dart';

/// An event to act on, and a relay it was found on ('' if unknown).
typedef _Target = ({NostrEvent event, String relay});

typedef _FetchTarget = Future<_Target?> Function(
  String myPubkeyHex,
  Set<String> relayUrls,
);

typedef _Publish = Future<Map<String, RelayPublishResult>> Function(
  SecretKey secretKey,
  String myPubkeyHex,
  _Target target,
  Set<String> relayUrls,
);

/// [note]'s own signed event, and a relay that has it.
_FetchTarget _theNote(Note note) =>
    (_, relayUrls) =>
        RelayPostRepository(relayUrls: relayUrls).fetchEventWithRelay(note.id);

/// The active identity's own kind [kind] reaction to [note].
_FetchTarget _ownReaction(
  Note note,
  int kind,
  RelayReactionsRepository repository,
) => (myPubkeyHex, relayUrls) async {
  final own = await repository.fetchOwnReaction(
    myPubkeyHex: myPubkeyHex,
    noteId: note.id,
    kind: kind,
    relayUrls: relayUrls,
  );
  return own == null ? null : (event: own, relay: '');
};

/// NIP-09 deletions name only the event, so the relay hint is dropped.
_Publish _retraction(RelayReactionsRepository repository) =>
    (secretKey, myPubkeyHex, target, relayUrls) => repository.publishRetraction(
      secretKey: secretKey,
      myPubkeyHex: myPubkeyHex,
      target: target.event,
      relayUrls: relayUrls,
    );

/// Confirms first if [alwaysConfirm] or the confirmation setting is on.
Future<bool> _publishAgainst(
  BuildContext context, {
  required _FetchTarget fetchTarget,
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

  final published = await withSecretKey(
    identity,
    messenger,
    signFailure: 'Could not sign this event',
    use: (secretKey) async {
      if (!context.mounted) return false;
      final results = await publish(
        secretKey,
        identity.pubkeyHex,
        target,
        relayUrls,
      );
      return reportPublishResults(
        messenger,
        results,
        failure: 'Could not publish to any relay',
      );
    },
  );
  return published ?? false;
}

const _noteNotFound = 'Could not load this note from relays';
const _reactionNotFound = 'Could not find that on any of your relays';

/// Publishes a NIP-25 like for [note].
Future<bool> likeNote(BuildContext context, Note note) {
  final repository = RelayReactionsRepository();
  return _publishAgainst(
    context,
    fetchTarget: _theNote(note),
    notFoundMessage: _noteNotFound,
    alwaysConfirm: false,
    dialogTitle: 'Like this note?',
    dialogBody:
        'This publishes a public reaction to '
        '${selectedRelaysNotifier.value.length} relay(s). It can be '
        'removed later, but relays are not required to honor that.',
    publish: (secretKey, myPubkeyHex, target, relayUrls) =>
        repository.publishLike(
          secretKey: secretKey,
          myPubkeyHex: myPubkeyHex,
          target: target.event,
          relayHint: target.relay,
          relayUrls: relayUrls,
        ),
  );
}

/// Publishes a NIP-18 repost of [note]. Always confirms first.
Future<bool> repostNote(BuildContext context, Note note) {
  final repository = RelayReactionsRepository();
  return _publishAgainst(
    context,
    fetchTarget: _theNote(note),
    notFoundMessage: _noteNotFound,
    alwaysConfirm: true,
    dialogTitle: 'Repost this note?',
    dialogBody:
        "This publishes a public repost, including a copy of the note's "
        'content, to ${selectedRelaysNotifier.value.length} relay(s). It '
        'can be removed later, but relays are not required to honor that.',
    publish: (secretKey, myPubkeyHex, target, relayUrls) =>
        repository.publishRepost(
          secretKey: secretKey,
          myPubkeyHex: myPubkeyHex,
          target: target.event,
          relayHint: target.relay,
          relayUrls: relayUrls,
        ),
  );
}

/// Removes a previously-published like for [note] (NIP-09).
Future<bool> unlikeNote(BuildContext context, Note note) {
  final repository = RelayReactionsRepository();
  return _publishAgainst(
    context,
    fetchTarget: _ownReaction(note, 7, repository),
    notFoundMessage: _reactionNotFound,
    alwaysConfirm: false,
    dialogTitle: 'Remove your like?',
    dialogBody:
        'This asks your relays to delete your reaction. Removal is not '
        'guaranteed; other relays or clients may still show it.',
    publish: _retraction(repository),
  );
}

/// Removes a previously-published repost of [note] (NIP-09). Always
/// confirms first.
Future<bool> unrepostNote(BuildContext context, Note note) {
  final repository = RelayReactionsRepository();
  return _publishAgainst(
    context,
    fetchTarget: _ownReaction(note, 6, repository),
    notFoundMessage: _reactionNotFound,
    alwaysConfirm: true,
    dialogTitle: 'Remove your repost?',
    dialogBody:
        'This asks your relays to delete your repost. Removal is not '
        'guaranteed; other relays or clients may still show it.',
    publish: _retraction(repository),
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
Future<bool> deleteNote(BuildContext context, Note note) async {
  final succeeded = await _publishAgainst(
    context,
    fetchTarget: _theNote(note),
    notFoundMessage: _noteNotFound,
    alwaysConfirm: true,
    dialogTitle: 'Delete this note?',
    dialogBody:
        'This asks your relays to delete the note. Removal is not '
        'guaranteed; other relays or clients may still show it.',
    publish: _retraction(RelayReactionsRepository()),
  );
  if (succeeded) _removeNoteFromFeeds(note.id);
  return succeeded;
}
