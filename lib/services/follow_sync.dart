import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../nostr/nostr.dart';
import 'settings_store.dart';

// Debounced background publish of myFollowingNotifier to relays.
const _debounceDuration = Duration(milliseconds: 500);

Timer? _debounce;
bool _syncRunning = false;
RelayClient _syncClient = const RelayClient();

void scheduleFollowingSync({RelayClient relayClient = const RelayClient()}) {
  _syncClient = relayClient;
  _debounce?.cancel();
  _debounce = Timer(_debounceDuration, _runSync);
}

Future<void> _runSync() async {
  if (_syncRunning) return;
  _syncRunning = true;
  try {
    while (true) {
      final myPubkeyHex = activeIdentityPubkeyNotifier.value;
      final desired = myFollowingNotifier.value;
      if (myPubkeyHex == null || desired == null) return;

      final privkeyHex = await SettingsStore.loadPrivateKey(myPubkeyHex);
      if (privkeyHex == null) {
        _reportSyncFailure();
        return;
      }

      final results = await RelayContactsRepository(client: _syncClient)
          .syncFollowingTo(
            seckeyHex: privkeyHex,
            myPubkeyHex: myPubkeyHex,
            desiredFollowing: desired,
            relayUrls: selectedRelaysNotifier.value,
          );
      final accepted = results.values.any(
        (result) => result.outcome == RelayPublishOutcome.accepted,
      );
      if (!accepted) {
        _reportSyncFailure();
        return;
      }

      // Loop if state changed again mid-publish; otherwise done.
      if (setEquals(myFollowingNotifier.value, desired)) return;
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
