import 'package:flutter/material.dart';

import '../main.dart';
import '../models/identity.dart';
import '../models/note.dart';
import '../nostr/nostr.dart';
import 'settings_store.dart';

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Fetches [note]'s signed event, confirms unless [alwaysConfirm] is false
/// and confirmation is off, then signs and publishes it via [publish].
Future<bool> _publishReaction(
  BuildContext context,
  Note note, {
  required RelayClient relayClient,
  required String dialogTitle,
  required String dialogBody,
  required bool alwaysConfirm,
  required Future<Map<String, RelayPublishResult>> Function({
    required String seckeyHex,
    required String myPubkeyHex,
    required NostrEvent target,
    required Set<String> relayUrls,
  })
  publish,
}) async {
  final myPubkeyHex = activeIdentityPubkeyNotifier.value;
  if (myPubkeyHex == null) return false;
  final identity = identityWithPubkey(identitiesNotifier.value, myPubkeyHex);
  if (identity == null) return false;

  final relayUrls = selectedRelaysNotifier.value;
  final messenger = ScaffoldMessenger.of(context);

  final target = await RelayPostRepository(
    relayUrls: relayUrls,
    client: relayClient,
  ).fetchEventById(note.id);
  if (!context.mounted) return false;
  if (target == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not load this note from relays')),
    );
    return false;
  }

  if (alwaysConfirm || confirmBeforeReactingNotifier.value) {
    if (!await _confirm(context, title: dialogTitle, body: dialogBody) ||
        !context.mounted) {
      return false;
    }
  }

  // Only touch secure storage once the user has actually confirmed.
  final privkeyHex = await SettingsStore.loadPrivateKey(myPubkeyHex);
  if (!context.mounted) return false;
  if (privkeyHex == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Could not find this identity's private key"),
      ),
    );
    return false;
  }

  final results = await publish(
    seckeyHex: privkeyHex,
    myPubkeyHex: myPubkeyHex,
    target: target,
    relayUrls: relayUrls,
  );
  final accepted = results.values
      .where((result) => result.outcome == RelayPublishOutcome.accepted)
      .length;
  if (accepted == 0) {
    String? reason;
    for (final result in results.values) {
      if (result.message != null && result.message!.isNotEmpty) {
        reason = result.message;
        break;
      }
    }
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(reason ?? 'Could not publish to any relay')),
      );
    }
    return false;
  }
  return true;
}

/// Publishes a NIP-25 like for [note].
Future<bool> likeNote(
  BuildContext context,
  Note note, {
  RelayClient relayClient = const RelayClient(),
}) {
  return _publishReaction(
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
  return _publishReaction(
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

/// Fetches the caller's own kind [kind] reaction/repost of [note], confirms
/// as in [_publishReaction], then publishes a NIP-09 deletion for it.
Future<bool> _retractReaction(
  BuildContext context,
  Note note, {
  required RelayClient relayClient,
  required int kind,
  required String dialogTitle,
  required String dialogBody,
  required bool alwaysConfirm,
}) async {
  final myPubkeyHex = activeIdentityPubkeyNotifier.value;
  if (myPubkeyHex == null) return false;
  final identity = identityWithPubkey(identitiesNotifier.value, myPubkeyHex);
  if (identity == null) return false;

  final relayUrls = selectedRelaysNotifier.value;
  final messenger = ScaffoldMessenger.of(context);
  final repository = RelayReactionsRepository(client: relayClient);

  final own = await repository.fetchOwnReaction(
    myPubkeyHex: myPubkeyHex,
    noteId: note.id,
    kind: kind,
    relayUrls: relayUrls,
  );
  if (!context.mounted) return false;
  if (own == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not find that on any of your relays'),
      ),
    );
    return false;
  }

  if (alwaysConfirm || confirmBeforeReactingNotifier.value) {
    if (!await _confirm(context, title: dialogTitle, body: dialogBody) ||
        !context.mounted) {
      return false;
    }
  }

  final privkeyHex = await SettingsStore.loadPrivateKey(myPubkeyHex);
  if (!context.mounted) return false;
  if (privkeyHex == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Could not find this identity's private key"),
      ),
    );
    return false;
  }

  final results = await repository.publishRetraction(
    seckeyHex: privkeyHex,
    myPubkeyHex: myPubkeyHex,
    target: own,
    relayUrls: relayUrls,
  );
  final accepted = results.values
      .where((result) => result.outcome == RelayPublishOutcome.accepted)
      .length;
  if (accepted == 0) {
    String? reason;
    for (final result in results.values) {
      if (result.message != null && result.message!.isNotEmpty) {
        reason = result.message;
        break;
      }
    }
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(reason ?? 'Could not publish to any relay')),
      );
    }
    return false;
  }
  return true;
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
        'guaranteed -- other relays or clients may still show it.',
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
        'guaranteed -- other relays or clients may still show it.',
  );
}
