import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/identity.dart';
import '../nostr/nostr.dart';
import 'settings_store.dart';

/// Shows a cancel/[action] dialog; true only if the user picked [action].
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  Key? actionKey,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: actionKey,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The active identity, if it is one we hold a key for.
Identity? activeIdentity() {
  final pubkeyHex = activeIdentityPubkeyNotifier.value;
  if (pubkeyHex == null) return null;
  return identityWithPubkey(identitiesNotifier.value, pubkeyHex);
}

/// Runs [use] with [identity]'s key and wipes it after. Null, with a
/// snackbar, if the key is missing or [signFailure] if signing throws.
Future<T?> withSecretKey<T>(
  Identity identity,
  ScaffoldMessengerState messenger, {
  required String signFailure,
  required Future<T> Function(SecretKey secretKey) use,
}) async {
  final secretKey = await SettingsStore.loadSecretKey(identity.pubkeyHex);
  if (secretKey == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Could not find this identity's private key"),
      ),
    );
    return null;
  }
  try {
    return await use(secretKey);
  } on ArgumentError {
    messenger.showSnackBar(SnackBar(content: Text(signFailure)));
    return null;
  } finally {
    secretKey.wipe();
  }
}

/// Runs [publish] with [identity]'s key and snackbars how it went; the
/// published event, or null if no relay accepted it.
Future<NostrEvent?> signAndPublish(
  Identity identity,
  ScaffoldMessengerState messenger, {
  required String signFailure,
  required String failure,
  required String Function(String counts) success,
  required Future<({NostrEvent event, Map<String, RelayPublishResult> results})>
  Function(SecretKey secretKey)
  publish,
}) async {
  final published = await withSecretKey(
    identity,
    messenger,
    signFailure: signFailure,
    use: publish,
  );
  if (published == null) return null;
  final accepted = reportPublishResults(
    messenger,
    published.results,
    failure: failure,
    success: success,
  );
  return accepted ? published.event : null;
}

/// Snackbars how [results] went and returns whether any relay accepted.
///
/// [success] gets an "accepted/total" count; null shows nothing on success.
bool reportPublishResults(
  ScaffoldMessengerState messenger,
  Map<String, RelayPublishResult> results, {
  required String failure,
  String Function(String counts)? success,
}) {
  final accepted = results.acceptedCount;
  if (accepted == 0) {
    final reason = results.firstReason;
    messenger.showSnackBar(
      SnackBar(content: Text(reason == null ? failure : '$failure: $reason')),
    );
    return false;
  }
  if (success != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(success('$accepted/${results.length}'))),
    );
  }
  return true;
}
