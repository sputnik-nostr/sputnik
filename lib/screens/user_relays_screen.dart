import 'package:flutter/material.dart';

import '../main.dart';
import '../models/relay.dart';
import '../nostr/nostr.dart';
import '../services/relay_settings.dart';
import '../widgets/placeholder_tab.dart';

/// The relays published in a user's NIP-65 relay list.
class UserRelaysScreen extends StatefulWidget {
  const UserRelaysScreen({
    super.key,
    required this.pubkeyHex,
    this.relayClient = const RelayClient(),
  });

  final String pubkeyHex;
  final RelayClient relayClient;

  @override
  State<UserRelaysScreen> createState() => _UserRelaysScreenState();
}

class _UserRelaysScreenState extends State<UserRelaysScreen> {
  late final Future<List<RelayListEntry>> _entries = _load();

  Future<List<RelayListEntry>> _load() async {
    final own = await RelayListRepository(client: widget.relayClient)
        .fetch(widget.pubkeyHex, selectedRelaysNotifier.value);
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
                    trailing: selectedRelaysNotifier.value.contains(entry.url)
                        ? IconButton(
                            icon: const Icon(Icons.check),
                            tooltip: 'Already added',
                            onPressed: null,
                            style: IconButton.styleFrom(
                              disabledForegroundColor: Theme.of(context)
                                  .colorScheme
                                  .onSurface,
                            ),
                          )
                        : IconButton(
                            key: Key('addRelay-${entry.url}'),
                            icon: const Icon(Icons.add),
                            tooltip: 'Add relay',
                            onPressed: () => _add(entry.url),
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
