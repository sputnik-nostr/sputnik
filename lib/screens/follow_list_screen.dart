import 'package:flutter/material.dart';

import '../main.dart';
import '../nostr/nostr.dart';
import '../widgets/placeholder_tab.dart';
import '../widgets/profile_result_tile.dart';

class FollowListScreen extends StatefulWidget {
  const FollowListScreen({
    super.key,
    required this.title,
    required this.pubkeys,
  });

  final String title;
  final List<String> pubkeys;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  @override
  void initState() {
    super.initState();
    const RelayProfileRepository().fetchProfiles(
      widget.pubkeys.toSet(),
      selectedRelaysNotifier.value,
    );
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
