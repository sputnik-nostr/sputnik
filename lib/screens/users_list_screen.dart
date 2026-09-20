import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../nostr/nostr.dart';
import '../widgets/placeholder_tab.dart';
import '../widgets/profile_result_tile.dart';

/// A list of users, rendered as profile tiles. Used for followers/following
/// lists, as well as for who liked/reposted a post.
class UsersListScreen extends StatefulWidget {
  const UsersListScreen({
    super.key,
    required this.title,
    required this.pubkeys,
    this.relayClient = const RelayClient(),
  });

  final String title;
  final List<String> pubkeys;
  final RelayClient relayClient;

  @override
  State<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends State<UsersListScreen> {
  /// Only request profile data for rows that actually get built, rather than
  /// eagerly fetching the entire list up front.
  final _requested = <String>{};

  /// Awaiting the debounced fetch, so a fast scroll batches into one.
  final _pending = <String>{};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    RelayContactsRepository(client: widget.relayClient)
        .ensureMyFollowingLoaded(selectedRelaysNotifier.value);
  }

  void _ensureProfileRequested(String pubkeyHex) {
    if (!_requested.add(pubkeyHex)) return;
    _pending.add(pubkeyHex);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), _flushPending);
  }

  void _flushPending() {
    if (_pending.isEmpty) return;
    final toFetch = Set<String>.of(_pending);
    _pending.clear();
    RelayProfileRepository(client: widget.relayClient)
        .fetchProfiles(toFetch, selectedRelaysNotifier.value);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: widget.pubkeys.isEmpty
          ? PlaceholderTab(
              icon: Icons.people_outline,
              label: 'No ${widget.title.toLowerCase()} yet',
            )
          : ValueListenableBuilder<Map<String, NostrMetadata>>(
              valueListenable: profileCacheNotifier,
              builder: (context, profileCache, _) {
                return ListView.separated(
                  itemCount: widget.pubkeys.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final pubkeyHex = widget.pubkeys[index];
                    _ensureProfileRequested(pubkeyHex);
                    final myPubkeyHex = activeIdentityPubkeyNotifier.value;
                    final isSelf =
                        myPubkeyHex != null &&
                        pubkeyHex.toLowerCase() == myPubkeyHex.toLowerCase();
                    return ProfileResultTile(
                      pubkeyHex: pubkeyHex,
                      metadata: profileCache[pubkeyHex],
                      showFollowButton: !isSelf && myPubkeyHex != null,
                      relayClient: widget.relayClient,
                    );
                  },
                );
              },
            ),
    );
  }
}
