import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../nostr/nostr.dart';
import 'cache_store.dart';
import 'follows.dart';
import 'settings_store.dart';

const _debounceDuration = Duration(milliseconds: 500);

/// Delay before each retry of a failed publish; the last one repeats.
@visibleForTesting
List<Duration> followSyncRetryDelays = const [
  Duration(seconds: 5),
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 10),
];

/// Unpublished changes (pubkey -> follow?), sent on top of the relays' list.
final _pending = <String, bool>{};

/// The identity [_pending] belongs to; switching identity discards the queue.
String? _pendingFor;

Timer? _timer;
bool _syncRunning = false;
int _failedAttempts = 0;

/// The identity [myFollowingNotifier] was last loaded for.
String? _myFollowingLoadedFor;

/// Shared by concurrent callers loading the same identity's list.
({String pubkeyHex, Future<void> future})? _myFollowingLoading;

/// Populates [myFollowingNotifier] for the active identity, once per identity.
Future<void> ensureMyFollowingLoaded(Set<String> relayUrls) {
  final myPubkeyHex = activeIdentityPubkeyNotifier.value;
  if (myPubkeyHex == null) {
    myFollowingNotifier.value = null;
    _myFollowingLoadedFor = null;
    return Future.value();
  }
  if (_myFollowingLoadedFor == myPubkeyHex &&
      myFollowingNotifier.value != null) {
    return Future.value();
  }
  if (_myFollowingLoadedFor != myPubkeyHex && !_hasPendingFor(myPubkeyHex)) {
    // Another identity's list must not stand in while this one loads.
    myFollowingNotifier.value = null;
    _myFollowingLoadedFor = null;
  }

  final inFlight = _myFollowingLoading;
  if (inFlight != null && inFlight.pubkeyHex == myPubkeyHex) {
    return inFlight.future;
  }

  late final Future<void> future;
  future = loadFollowingOrNull(myPubkeyHex, relayUrls)
      .then((following) {
        // Left unloaded on failure so the next call retries.
        if (following == null) return;
        // The active identity may have changed while this was in flight.
        if (activeIdentityPubkeyNotifier.value != myPubkeyHex) return;
        // A publish that landed meanwhile already set a newer list.
        if (_myFollowingLoadedFor == myPubkeyHex) return;
        myFollowingNotifier.value = _withPending(myPubkeyHex, following);
        _myFollowingLoadedFor = myPubkeyHex;
      })
      .whenComplete(() {
        if (identical(_myFollowingLoading?.future, future)) {
          _myFollowingLoading = null;
        }
      });
  _myFollowingLoading = (pubkeyHex: myPubkeyHex, future: future);
  return future;
}

bool _hasPendingFor(String pubkeyHex) =>
    _pendingFor == pubkeyHex && _pending.isNotEmpty;

/// [following] with [pubkeyHex]'s not-yet-published taps applied on top.
Set<String> _withPending(String pubkeyHex, Iterable<String> following) {
  if (_pendingFor != pubkeyHex) return following.toSet();
  return {
    for (final pubkey in following)
      if (_pending[pubkey] != false) pubkey,
    for (final change in _pending.entries)
      if (change.value) change.key,
  };
}

/// Queues a follow change, published in a batch after a short debounce.
void scheduleFollowingSync(String targetPubkeyHex, {required bool follow}) {
  final myPubkeyHex = activeIdentityPubkeyNotifier.value;
  if (myPubkeyHex == null) return;

  if (_pendingFor != myPubkeyHex) _pending.clear();
  _pendingFor = myPubkeyHex;
  _pending[targetPubkeyHex.toLowerCase()] = follow;

  _timer?.cancel();
  _timer = Timer(_debounceDuration, _runSync);
}

@visibleForTesting
void resetFollowSync() {
  _timer?.cancel();
  _pending.clear();
  _pendingFor = null;
  _failedAttempts = 0;
  _myFollowingLoadedFor = null;
  _myFollowingLoading = null;
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

/// Publishes queued changes until none are left, backing off on failure.
Future<void> _runSync() async {
  if (_syncRunning) return;
  _syncRunning = true;
  try {
    while (_pending.isNotEmpty) {
      final myPubkeyHex = _pendingFor!;
      final changes = Map<String, bool>.of(_pending);

      final secretKey = await SettingsStore.loadSecretKey(myPubkeyHex);
      if (secretKey == null) {
        _reportSyncFailure();
        return;
      }

      final ({Map<String, RelayPublishResult> results, Set<String> following})
      outcome;
      try {
        outcome = await RelayContactsRepository().applyFollowChanges(
          secretKey: secretKey,
          myPubkeyHex: myPubkeyHex,
          changes: changes,
          relayUrls: selectedRelaysNotifier.value,
        );
      } finally {
        secretKey.wipe();
      }
      if (outcome.results.acceptedCount == 0) {
        _retryLater();
        return;
      }
      _failedAttempts = 0;
      CacheStore.putFollowing(myPubkeyHex, outcome.following.toList());

      // Anything toggled again mid-publish stays queued for the next pass.
      for (final change in changes.entries) {
        if (_pending[change.key] == change.value) _pending.remove(change.key);
      }

      if (activeIdentityPubkeyNotifier.value == myPubkeyHex) {
        // Built on a conclusive fetch of the list, so it counts as loaded.
        _myFollowingLoadedFor = myPubkeyHex;
        myFollowingNotifier.value = _withPending(
          myPubkeyHex,
          outcome.following,
        );
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
