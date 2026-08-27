import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../nostr/nostr.dart';
import '../widgets/placeholder_tab.dart';
import '../widgets/profile_result_tile.dart';

// A titled list of users, rendered as profile tiles. Used for
// followers/following as well as for who liked/reposted a post.
class UsersListScreen extends StatefulWidget {
  const UsersListScreen({
    super.key,
    required this.title,
    required this.pubkeys,
  });

  final String title;
  final List<String> pubkeys;

  @override
  State<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends State<UsersListScreen> {
  // Only rows that actually get built (i.e. are visible or near-visible)
  // request their profile, rather than eagerly fetching the whole list up
  // front. Requests are debounced so a fast scroll batches into one fetch
  // instead of firing per row.
  final _requested = <String>{};
  final _pending = <String>{};
  Timer? _debounce;

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
    const RelayProfileRepository().fetchProfiles(
      toFetch,
      selectedRelaysNotifier.value,
    );
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
                    return ProfileResultTile(
                      pubkeyHex: pubkeyHex,
                      metadata: profileCache[pubkeyHex],
                    );
                  },
                );
              },
            ),
    );
  }
}
