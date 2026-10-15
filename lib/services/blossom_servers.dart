import 'dart:async';

import '../app_state.dart';
import '../nostr/models/nostr_media.dart';
import '../nostr/relay_blossom_list_repository.dart';
import 'bounded_cache.dart';
import 'media_loader.dart';

final _known = BoundedMap<String, List<String>>(200);
final _inFlight = <String, Future<List<String>>>{};

/// [pubkeyHex]'s Blossom servers; only found lists are remembered.
Future<List<String>> blossomServersFor(
  String pubkeyHex,
  Set<String> relayUrls,
) {
  final known = _known[pubkeyHex];
  if (known != null) return Future.value(known);

  return _inFlight[pubkeyHex] ??= () async {
    try {
      final servers = await RelayBlossomListRepository().fetchServers(
        pubkeyHex,
        relayUrls,
      );
      if (servers.isNotEmpty) {
        _known[pubkeyHex] = servers;
      }
      return servers;
    } finally {
      unawaited(_inFlight.remove(pubkeyHex));
    }
  }();
}

void clearBlossomServerCache() {
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
