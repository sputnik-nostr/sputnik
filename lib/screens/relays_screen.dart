import 'package:flutter/material.dart';

import '../main.dart';
import '../models/identity.dart';
import '../models/relay.dart';
import '../nostr/nostr.dart';
import '../services/relay_settings.dart';
import '../services/settings_store.dart';

bool _isPlaintext(String relay) => Uri.tryParse(relay)?.scheme == 'ws';

Widget _plaintextWarningIcon(BuildContext context) {
  return Tooltip(
    message:
        'Unencrypted relay (ws://). Traffic to and from it can be read '
        'or tampered with on the network. Prefer a wss:// relay.',
    child: Icon(
      Icons.no_encryption_outlined,
      size: 20,
      color: Theme.of(context).colorScheme.error,
    ),
  );
}

Future<void> _addRelay(BuildContext context) async {
  if (customRelaysNotifier.value.length >= maxCustomRelays) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('You can only add up to $maxCustomRelays relays')),
    );
    return;
  }

  final controller = TextEditingController();
  String? error;

  final url = await showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final input = canonicalRelayUrl(controller.text);
            if (!isRelayUrl(input)) {
              setState(() => error = 'Enter a valid ws:// or wss:// URL');
              return;
            }
            Navigator.pop(context, input);
          }

          return AlertDialog(
            title: const Text('Add relay'),
            content: TextField(
              key: const Key('addRelayField'),
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'wss://relay.example.com',
                errorText: error,
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const Key('confirmAddRelayButton'),
                onPressed: submit,
                child: const Text('Add'),
              ),
            ],
          );
        },
      );
    },
  );
  if (url == null) return;

  final relay = canonicalRelayUrl(url);
  addCustomRelay(relay);
}

class RelaysScreen extends StatelessWidget {
  const RelaysScreen({super.key, this.relayClient = const RelayClient()});

  final RelayClient relayClient;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relays'),
        actions: [
          SizedBox(
            width: kToolbarHeight,
            child: Center(
              child: IconButton(
                key: const Key('addRelayButton'),
                icon: const Icon(Icons.add),
                tooltip: 'Add relay',
                onPressed: () => _addRelay(context),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          selectedRelaysNotifier,
          customRelaysNotifier,
          activeIdentityPubkeyNotifier,
        ]),
        builder: (context, _) {
          final selected = selectedRelaysNotifier.value;
          final customRelays = customRelaysNotifier.value.toList()..sort();

          return ListView(
            children: [
              if (activeIdentityPubkeyNotifier.value != null) ...[
                _MyRelayList(
                  key: ValueKey(activeIdentityPubkeyNotifier.value),
                  relayClient: relayClient,
                ),
                const Divider(height: 1),
              ],
              for (final relay in defaultRelays)
                CheckboxListTile(
                  title: Text(relay),
                  value: selected.contains(relay),
                  onChanged: (checked) =>
                      setRelaySelected(relay, checked ?? false),
                  secondary: _isPlaintext(relay)
                      ? _plaintextWarningIcon(context)
                      : null,
                ),
              if (customRelays.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Custom relays',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                for (final relay in customRelays)
                  CheckboxListTile(
                    title: Text(relay),
                    value: selected.contains(relay),
                    onChanged: (checked) =>
                        setRelaySelected(relay, checked ?? false),
                    secondary: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isPlaintext(relay)) ...[
                          _plaintextWarningIcon(context),
                          const SizedBox(width: 4),
                        ],
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove relay',
                          onPressed: () => removeCustomRelay(relay),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The active identity's published relay list (NIP-65).
class _MyRelayList extends StatefulWidget {
  const _MyRelayList({super.key, required this.relayClient});

  final RelayClient relayClient;

  @override
  State<_MyRelayList> createState() => _MyRelayListState();
}

class _MyRelayListState extends State<_MyRelayList> {
  OwnEvent? _own;
  List<RelayListEntry> _entries = const [];
  bool _loading = true;
  bool _publishing = false;

  RelayListRepository get _repository =>
      RelayListRepository(client: widget.relayClient);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    if (pubkeyHex == null) return;
    setState(() => _loading = true);

    final own = await _repository.fetch(
      pubkeyHex,
      selectedRelaysNotifier.value,
    );
    if (!mounted) return;

    final event = own.event;
    setState(() {
      _own = own;
      _entries = event == null ? const [] : relayListFromEvent(event);
      _loading = false;
    });
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    required Key actionKey,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: actionKey,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _useList() async {
    final urls = [for (final entry in _entries) entry.url];
    final hasPlaintext = urls.any(_isPlaintext);
    if (!await _confirm(
          title: 'Use your relay list?',
          message:
              'This replaces your selected relays with the ${urls.length} '
              'relay(s) in your published list.'
              '${hasPlaintext ? ' It includes unencrypted (ws://) relays.' : ''}',
          action: 'Use list',
          actionKey: const Key('confirmUseRelayListButton'),
        ) ||
        !mounted) {
      return;
    }

    final skipped = useRelays(urls);
    if (skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$skipped relay(s) were skipped because you can only add up to '
            '$maxCustomRelays custom relays',
          ),
        ),
      );
    }
  }

  Future<void> _publishSelection() async {
    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    if (pubkeyHex == null) return;
    final identity = identityWithPubkey(identitiesNotifier.value, pubkeyHex);
    if (identity == null) return;

    final selected = selectedRelaysNotifier.value;
    if (selected.isEmpty) return;
    final existing = {for (final entry in _entries) entry.url: entry};
    final removed = existing.keys.where((url) => !selected.contains(url));

    final notes = [
      if (_own?.conclusive == false)
        'Some relays did not respond, so your current list could not be '
            'checked.',
      if (removed.isNotEmpty)
        '${removed.length} relay(s) in your published list will be removed.',
      if (selected.length > 4) 'Keeping the list to 2-4 relays is recommended.',
    ];
    if (!await _confirm(
          title: 'Publish your relay list?',
          message:
              'This publishes your ${selected.length} selected relay(s) as '
              'your relay list, to those same relays. ${notes.join(' ')}',
          action: 'Publish',
          actionKey: const Key('confirmPublishRelayListButton'),
        ) ||
        !mounted) {
      return;
    }

    // Only touch secure storage once the user has actually confirmed.
    final privkeyHex = await SettingsStore.loadPrivateKey(identity.pubkeyHex);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (privkeyHex == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Could not find this identity's private key"),
        ),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      final published = await _repository.publish(
        seckeyHex: privkeyHex,
        pubkeyHex: identity.pubkeyHex,
        base: _own?.event,
        entries: [
          for (final url in selected.toList()..sort())
            RelayListEntry(
              url: url,
              read: existing[url]?.read ?? true,
              write: existing[url]?.write ?? true,
            ),
        ],
        relayUrls: selected,
      );
      if (!mounted) return;

      final accepted = published.results.values
          .where((result) => result.outcome == RelayPublishOutcome.accepted)
          .length;
      if (accepted == 0) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not publish your relay list to any relay'),
          ),
        );
        return;
      }

      setState(() {
        _own = OwnEvent(event: published.event, conclusive: true);
        _entries = relayListFromEvent(published.event);
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Published relay list to $accepted/${published.results.length} '
            'relays',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not sign your relay list: $e')),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unchecked = _own != null && !_own!.conclusive && _entries.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Your relay list',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          )
        else if (unchecked)
          ListTile(
            leading: Icon(
              Icons.warning_amber_outlined,
              color: theme.colorScheme.error,
            ),
            title: const Text(
              'Some relays did not respond, so your published list could not '
              'be checked',
            ),
            trailing: TextButton(
              key: const Key('retryLoadRelayListButton'),
              onPressed: _load,
              child: const Text('Retry'),
            ),
          )
        else if (_entries.isEmpty)
          const ListTile(title: Text('You have not published a relay list yet'))
        else
          for (final entry in _entries)
            ListTile(
              dense: true,
              title: Text(entry.url),
              subtitle: Text(entry.accessLabel),
              trailing: _isPlaintext(entry.url)
                  ? _plaintextWarningIcon(context)
                  : null,
            ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                key: const Key('useRelayListButton'),
                onPressed: _loading || _entries.isEmpty ? null : _useList,
                child: const Text('Use this list'),
              ),
              FilledButton.tonal(
                key: const Key('publishRelayListButton'),
                onPressed:
                    _loading ||
                        _publishing ||
                        selectedRelaysNotifier.value.isEmpty
                    ? null
                    : _publishSelection,
                child: const Text('Publish selection'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
