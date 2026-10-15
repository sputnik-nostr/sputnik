import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../nostr/nostr.dart';
import '../services/follow_sync.dart';
import '../services/profiles.dart';
import '../widgets/placeholder_tab.dart';
import '../widgets/profile_result_tile.dart';

/// Profile tiles for [pubkeys], e.g. followers or who liked a post.
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
  /// Profiles are fetched as rows are built, not for the whole list up front.
  final _requested = <String>{};

  /// Awaiting the debounced fetch, so a fast scroll batches into one.
  final _pending = <String>{};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    ensureMyFollowingLoaded(selectedRelaysNotifier.value);
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
    loadProfiles(toFetch, selectedRelaysNotifier.value);
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
                    final myPubkeyHex = activeIdentityPubkeyNotifier.value;
                    final isSelf =
                        myPubkeyHex != null &&
                        pubkeyHex.toLowerCase() == myPubkeyHex.toLowerCase();
                    return _UserRow(
                      key: ValueKey(pubkeyHex),
                      onCreated: () => _ensureProfileRequested(pubkeyHex),
                      child: ProfileResultTile(
                        pubkeyHex: pubkeyHex,
                        metadata: profileCache[pubkeyHex],
                        showFollowButton: !isSelf && myPubkeyHex != null,
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

/// Asks for its profile once, when the list first builds the row.
class _UserRow extends StatefulWidget {
  const _UserRow({super.key, required this.onCreated, required this.child});

  final VoidCallback onCreated;
  final Widget child;

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  @override
  void initState() {
    super.initState();
    widget.onCreated();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
