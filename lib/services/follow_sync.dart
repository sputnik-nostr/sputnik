import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../main.dart';
import '../nostr/nostr.dart';
import 'settings_store.dart';

const _debounceDuration = Duration(milliseconds: 500);

// Delay before each retry of a failed publish; the last one repeats.
@visibleForTesting
List<Duration> followSyncRetryDelays = const [
  Duration(seconds: 5),
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 10),
];

// Unpublished changes (pubkey -> follow?), sent on top of the relays' list.
final _pending = <String, bool>{};
String? _pendingFor;

Timer? _timer;
bool _syncRunning = false;
int _failedAttempts = 0;
RelayClient _syncClient = const RelayClient();

void scheduleFollowingSync(
  String targetPubkeyHex, {
  required bool follow,
  RelayClient relayClient = const RelayClient(),
}) {
  final myPubkeyHex = activeIdentityPubkeyNotifier.value;
  if (myPubkeyHex == null) return;

  if (_pendingFor != myPubkeyHex) _pending.clear();
  _pendingFor = myPubkeyHex;
  _pending[targetPubkeyHex.toLowerCase()] = follow;

  _syncClient = relayClient;
  _timer?.cancel();
  _timer = Timer(_debounceDuration, _runSync);
}

@visibleForTesting
void resetFollowSync() {
  _timer?.cancel();
  _pending.clear();
  _pendingFor = null;
  _failedAttempts = 0;
}

void _retryLater() {
  // The user is told once per streak of failures, not on every retry.
  if (_failedAttempts == 0) _reportSyncFailure();

  final delays = followSyncRetryDelays;
  final delay = delays[min(_failedAttempts, delays.length - 1)];
  _failedAttempts++;
  _timer?.cancel();
  _timer = Timer(delay, _runSync);
}

Future<void> _runSync() async {
  if (_syncRunning) return;
  _syncRunning = true;
  try {
    while (_pending.isNotEmpty) {
      final myPubkeyHex = _pendingFor!;
      final changes = Map<String, bool>.of(_pending);

      final privkeyHex = await SettingsStore.loadPrivateKey(myPubkeyHex);
      if (privkeyHex == null) {
        _reportSyncFailure();
        return;
      }

      final outcome = await RelayContactsRepository(client: _syncClient)
          .applyFollowChanges(
            seckeyHex: privkeyHex,
            myPubkeyHex: myPubkeyHex,
            changes: changes,
            relayUrls: selectedRelaysNotifier.value,
          );
      final accepted = outcome.results.values.any(
        (result) => result.outcome == RelayPublishOutcome.accepted,
      );
      if (!accepted) {
        _retryLater();
        return;
      }
      _failedAttempts = 0;

      // Anything toggled again mid-publish stays queued for the next pass.
      for (final change in changes.entries) {
        if (_pending[change.key] == change.value) _pending.remove(change.key);
      }

      if (activeIdentityPubkeyNotifier.value == myPubkeyHex) {
        myFollowingNotifier.value = {
          for (final pubkey in outcome.following)
            if (_pending[pubkey] != false) pubkey,
          for (final change in _pending.entries)
            if (change.value) change.key,
        };
      }
    }
  } finally {
    _syncRunning = false;
  }
}

void _reportSyncFailure() {
  final context = navigatorKey.currentContext;
  if (context != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not update your follow list')),
    );
  }
}
