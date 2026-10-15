import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/relay.dart';
import '../nostr/nostr.dart';
import '../services/relay_settings.dart';
import '../services/ssrf_guard.dart';
import '../widgets/placeholder_tab.dart';
import 'relays_screen.dart';

/// The relays published in a user's NIP-65 relay list.
class UserRelaysScreen extends StatefulWidget {
  const UserRelaysScreen({super.key, required this.pubkeyHex});

  final String pubkeyHex;

  @override
  State<UserRelaysScreen> createState() => _UserRelaysScreenState();
}

class _UserRelaysScreenState extends State<UserRelaysScreen> {
  late final Future<List<RelayListEntry>> _entries = _load();

  Future<List<RelayListEntry>> _load() async {
    final own = await RelayListRepository().fetch(
      widget.pubkeyHex,
      selectedRelaysNotifier.value,
    );
    final event = own.event;
    return event == null ? const [] : relayListFromEvent(event);
  }

  void _add(String relay) {
    if (!addCustomRelay(relay)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only add up to $maxCustomRelays relays'),
        ),
      );
    }
  }

  Widget _addButton(BuildContext context, String relay) {
    if (selectedRelaysNotifier.value.contains(relay)) {
      return IconButton(
        icon: const Icon(Icons.check),
        tooltip: 'Already added',
        onPressed: null,
        style: IconButton.styleFrom(
          disabledForegroundColor: Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
    return IconButton(
      key: Key('addRelay-$relay'),
      icon: const Icon(Icons.add),
      tooltip: 'Add relay',
      onPressed: () => _add(relay),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relays')),
      body: FutureBuilder<List<RelayListEntry>>(
        future: _entries,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data ?? const <RelayListEntry>[];
          if (entries.isEmpty) {
            return const PlaceholderTab(
              icon: Icons.dns_outlined,
              label: 'No relay list found',
            );
          }

          return AnimatedBuilder(
            animation: selectedRelaysNotifier,
            builder: (context, _) => ListView(
              children: [
                for (final entry in entries)
                  ListTile(
                    title: Text(entry.url),
                    subtitle: Text(entry.accessLabel),
                    trailing: isLocalNetworkUrl(entry.url)
                        ? const IconButton(
                            icon: Icon(Icons.block),
                            tooltip: localNetworkRelayMessage,
                            onPressed: null,
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ?relayWarningIcon(context, entry.url),
                              _addButton(context, entry.url),
                            ],
                          ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
