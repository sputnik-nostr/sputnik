import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../nostr/nostr.dart';
import 'cache_store.dart';
import 'follow_confirmation.dart';
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

/// Asks whether to publish despite what [update] warns of; null when there is
/// nobody to ask. Tests replace it.
@visibleForTesting
Future<bool?> Function(FollowNeedsConfirmation update) confirmFollowUpdate =
    confirmFollowPublish;

/// Unpublished changes (pubkey -> follow?), sent on top of the relays' list.
final _pending = <String, bool>{};

/// What the user agreed to for exactly these [changes], so the publish after
/// the dialog, or a retry of it, does not ask again.
({String pubkeyHex, Map<String, bool> changes, Set<FollowRisk> risks})?
_consent;

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
  _consent = null;
  confirmFollowUpdate = confirmFollowPublish;
  _failedAttempts = 0;
  _myFollowingLoadedFor = null;
  _myFollowingLoading = null;
}

void _retryLater([String? failure]) {
  // The user is told once per streak of failures, not on every retry.
  if (_failedAttempts == 0) _reportSyncFailure(failure);

  final delays = followSyncRetryDelays;
  final delay = delays[min(_failedAttempts, delays.length - 1)];
  _failedAttempts++;
  _timer?.cancel();
  _timer = Timer(delay, _runSync);
}

Set<FollowRisk> _agreedRisks(String pubkeyHex, Map<String, bool> changes) {
  final consent = _consent;
  if (consent == null ||
      consent.pubkeyHex != pubkeyHex ||
      !mapEquals(consent.changes, changes)) {
    return const {};
  }
  return consent.risks;
}

/// Drops the queued [changes] the user turned down, and undoes them on screen.
void _discardChanges(String pubkeyHex, Map<String, bool> changes) {
  _consent = null;
  // A person tapped again meanwhile is a newer answer, which stays queued.
  final declined = {
    for (final change in changes.entries)
      if (_pending[change.key] == change.value) change.key: change.value,
  };
  for (final pubkey in declined.keys) {
    _pending.remove(pubkey);
  }

  final shown = myFollowingNotifier.value;
  if (activeIdentityPubkeyNotifier.value != pubkeyHex || shown == null) return;
  final reverted = {
    for (final pubkey in shown)
      if (declined[pubkey] != true) pubkey,
    for (final change in declined.entries)
      if (!change.value) change.key,
  };
  // A list that never loaded is unknown, not empty.
  myFollowingNotifier.value =
      reverted.isEmpty && _myFollowingLoadedFor != pubkeyHex ? null : reverted;
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

      final FollowUpdate update;
      try {
        update = await RelayContactsRepository().applyFollowChanges(
          secretKey: secretKey,
          myPubkeyHex: myPubkeyHex,
          changes: changes,
          relayUrls: selectedRelaysNotifier.value,
          agreedTo: _agreedRisks(myPubkeyHex, changes),
        );
      } finally {
        secretKey.wipe();
      }

      switch (update) {
        case FollowRefused():
          // The changes stay queued until the list can be loaded.
          _retryLater('Could not load your follow list');
          return;
        case FollowNeedsConfirmation():
          final agreed = await confirmFollowUpdate(update);
          if (agreed == null) {
            _retryLater();
            return;
          }
          // The relays answered and the user was asked, so whatever failed
          // before is over.
          _failedAttempts = 0;
          if (!agreed) {
            _discardChanges(myPubkeyHex, changes);
            continue;
          }
          // Applied again with the answer in hand, on what the relays say now.
          _consent = (
            pubkeyHex: myPubkeyHex,
            changes: changes,
            risks: {..._agreedRisks(myPubkeyHex, changes), ...update.risks},
          );
        case FollowPublished():
          if (update.results.acceptedCount == 0) {
            _retryLater();
            return;
          }
          _failedAttempts = 0;
          _consent = null;
          CacheStore.putFollowing(myPubkeyHex, update.following.toList());

          // Anything toggled again mid-publish stays queued for the next pass.
          for (final change in changes.entries) {
            if (_pending[change.key] == change.value) {
              _pending.remove(change.key);
            }
          }

          if (activeIdentityPubkeyNotifier.value == myPubkeyHex) {
            // What was just sent is the list, so it counts as loaded.
            _myFollowingLoadedFor = myPubkeyHex;
            myFollowingNotifier.value = _withPending(
              myPubkeyHex,
              update.following,
            );
          }
      }
    }
  } finally {
    _syncRunning = false;
  }
}

void _reportSyncFailure([String? failure]) {
  final context = navigatorKey.currentContext;
  if (context != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failure ?? 'Could not update your follow list')),
    );
  }
}
