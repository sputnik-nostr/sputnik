import 'package:flutter/foundation.dart';

import '../main.dart';
import '../nostr/models/nostr_media.dart';
import '../nostr/relay_blossom_list_repository.dart';
import '../nostr/relay_client.dart';
import 'media_loader.dart';

const _maxCached = 200;

final _known = <String, List<String>>{};
final _inFlight = <String, Future<List<String>>>{};

/// [pubkeyHex]'s Blossom servers; only found lists are remembered.
Future<List<String>> blossomServersFor(
  String pubkeyHex,
  Set<String> relayUrls, {
  RelayClient client = const RelayClient(),
}) {
  final known = _known[pubkeyHex];
  if (known != null) return Future.value(known);

  return _inFlight[pubkeyHex] ??= () async {
    try {
      final servers = await RelayBlossomListRepository(client: client)
          .fetchServers(pubkeyHex, relayUrls);
      if (servers.isNotEmpty) {
        if (_known.length >= _maxCached) _known.clear();
        _known[pubkeyHex] = servers;
      }
      return servers;
    } finally {
      _inFlight.remove(pubkeyHex);
    }
  }();
}

@visibleForTesting
void resetBlossomServerCache() {
  _known.clear();
  _inFlight.clear();
}

/// How to fetch [media] by [authorPubkey], falling back to their servers.
MediaSource mediaSourceFor(NostrMedia media, String authorPubkey) {
  return MediaSource(
    url: media.url,
    sha256: media.sha256,
    fallbackUrls: media.fallbackUrls,
    serverLookup: () =>
        blossomServersFor(authorPubkey, selectedRelaysNotifier.value),
  );
}
