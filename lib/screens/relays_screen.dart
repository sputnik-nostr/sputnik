import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/relay.dart';
import '../nostr/nostr.dart';
import '../services/publishing.dart';
import '../services/relay_settings.dart';
import '../services/ssrf_guard.dart';
import '../widgets/unchecked_warning.dart';

bool _isPlaintext(String relay) => Uri.tryParse(relay)?.scheme == 'ws';

const localNetworkRelayMessage =
    'Relays on local or private networks are not supported';

/// Why [relay] is unreachable or unsafe, if it is.
Widget? relayWarningIcon(BuildContext context, String relay) {
  final color = Theme.of(context).colorScheme.error;
  if (isLocalNetworkUrl(relay)) {
    return Tooltip(
      message: '$localNetworkRelayMessage, so this relay cannot be reached.',
      child: Icon(Icons.lan_outlined, size: 20, color: color),
    );
  }
  if (!_isPlaintext(relay)) return null;
  return Tooltip(
    message:
        'Unencrypted relay (ws://). Traffic to and from it can be read '
        'or tampered with on the network. Prefer a wss:// relay.',
    child: Icon(Icons.no_encryption_outlined, size: 20, color: color),
  );
}

Future<void> _addRelay(BuildContext context) async {
  if (customRelaysNotifier.value.length >= maxCustomRelays) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('You can only add up to $maxCustomRelays relays')),
    );
    return;
  }

  final url = await showDialog<String>(
    context: context,
    builder: (context) => const _AddRelayDialog(),
  );
  if (url != null) addCustomRelay(url);
}

/// Owns its controller, so it is disposed only after the closing animation.
class _AddRelayDialog extends StatefulWidget {
  const _AddRelayDialog();

  @override
  State<_AddRelayDialog> createState() => _AddRelayDialogState();
}

class _AddRelayDialogState extends State<_AddRelayDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final input = canonicalRelayUrl(_controller.text);
    if (!isRelayUrl(input)) {
      setState(() => _error = 'Enter a valid ws:// or wss:// URL');
      return;
    }
    if (isLocalNetworkUrl(input)) {
      setState(() => _error = localNetworkRelayMessage);
      return;
    }
    Navigator.pop(context, input);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add relay'),
      content: TextField(
        key: const Key('addRelayField'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          hintText: 'wss://relay.example.com',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('confirmAddRelayButton'),
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
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
                  secondary: relayWarningIcon(context, relay),
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
                        if (relayWarningIcon(context, relay)
                            case final warning?) ...[
                          warning,
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

  Future<void> _useList() async {
    final urls = [
      for (final entry in _entries)
        if (!isLocalNetworkUrl(entry.url)) entry.url,
    ];
    final localCount = _entries.length - urls.length;
    if (urls.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(localNetworkRelayMessage)));
      return;
    }
    final localNote = localCount > 0
        ? ' $localCount on a local or private network will be skipped.'
        : '';
    final plaintextNote = urls.any(_isPlaintext)
        ? ' It includes unencrypted (ws://) relays.'
        : '';
    if (!await confirmAction(
          context,
          title: 'Use your relay list?',
          message:
              'This replaces your selected relays with the ${urls.length} '
              'relay(s) in your published list.$localNote$plaintextNote',
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
    final identity = activeIdentity();
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
    if (!await confirmAction(
          context,
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

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _publishing = true);
    try {
      await withSecretKey<void>(
        identity,
        messenger,
        signFailure: 'Could not sign your relay list',
        use: (secretKey) async {
          if (!mounted) return;
          final published = await _repository.publish(
            secretKey: secretKey,
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

          final updated = reportPublishResults(
            messenger,
            published.results,
            failure: 'Could not publish your relay list to any relay',
            success: (counts) => 'Published relay list to $counts relays',
          );
          if (!updated) return;

          setState(() {
            _own = OwnEvent(event: published.event, conclusive: true);
            _entries = relayListFromEvent(published.event);
          });
        },
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: UncheckedWarning(
              message:
                  'Some relays did not respond, so your published list could '
                  'not be checked.',
              retryKey: const Key('retryLoadRelayListButton'),
              onRetry: _load,
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
              trailing: relayWarningIcon(context, entry.url),
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
