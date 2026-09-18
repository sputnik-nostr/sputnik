import 'package:flutter/material.dart';

import '../main.dart';
import '../models/identity.dart';
import '../theme/app_text_styles.dart';
import '../nostr/nostr.dart';
import '../services/cache_store.dart';
import '../services/settings_store.dart';
import '../widgets/payment_target_chip.dart';

const _maxPaymentTargets = 20;

String? _validateAddress(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return 'Enter an address';
  if (trimmed.contains(RegExp(r'\s'))) return 'An address has no spaces';
  return null;
}

class _Row {
  _Row({required this.type, String address = '', this.original})
    : address = TextEditingController(text: address);

  String type;
  final TextEditingController address;

  // The tag this row came from, so extra elements survive an unchanged row.
  final List<String>? original;
}

class EditPaymentTargetsScreen extends StatefulWidget {
  const EditPaymentTargetsScreen({
    super.key,
    this.relayClient = const RelayClient(),
  });

  final RelayClient relayClient;

  @override
  State<EditPaymentTargetsScreen> createState() =>
      _EditPaymentTargetsScreenState();
}

class _EditPaymentTargetsScreenState extends State<EditPaymentTargetsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rows = <_Row>[];

  NostrEvent? _base;
  bool _loading = true;
  bool _baseConclusive = true;
  bool _saving = false;

  RelayPaymentTargetsRepository get _repository =>
      RelayPaymentTargetsRepository(client: widget.relayClient);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.address.dispose();
    }
    super.dispose();
  }

  // A retry keeps what has been typed and only refreshes the base event.
  Future<void> _load({bool seedRows = true}) async {
    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    if (pubkeyHex == null) {
      setState(() => _loading = false);
      return;
    }
    if (seedRows) setState(() => _loading = true);

    final own = await _repository.fetchOwnPaymentTargetsEvent(
      pubkeyHex,
      selectedRelaysNotifier.value,
    );
    if (!mounted) return;

    setState(() {
      _base = own.event ?? _base;
      _baseConclusive = own.conclusive;
      _loading = false;
      if (!seedRows) return;
      for (final row in _rows) {
        row.address.dispose();
      }
      _rows
        ..clear()
        ..addAll([
          for (final tag in _base?.tags ?? const <List<String>>[])
            if (tag.length > 2 && tag[0] == 'payto')
              _Row(
                type: canonicalPaymentTargetType(tag[1]),
                address: tag[2],
                original: tag,
              ),
        ]);
    });
  }

  List<List<String>> _paytoTags() {
    return [
      for (final row in _rows)
        if (_isUnchanged(row))
          row.original!
        else
          ['payto', row.type, row.address.text.trim()],
    ];
  }

  bool _isUnchanged(_Row row) {
    final original = row.original;
    return original != null &&
        canonicalPaymentTargetType(original[1]) == row.type &&
        original[2] == row.address.text.trim();
  }

  Future<bool> _confirmSave(int relayCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update payment targets?'),
        content: Text(
          _baseConclusive
              ? 'This publishes your payment targets to $relayCount relay(s).'
              : 'This publishes your payment targets to $relayCount relay(s). '
                    'Some relays did not answer, so your current targets '
                    'could not be checked and may be overwritten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmSavePaymentTargetsButton'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _save() async {
    if (_loading || _saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    if (pubkeyHex == null) return;
    final identity = identityWithPubkey(identitiesNotifier.value, pubkeyHex);
    if (identity == null) return;

    final relayUrls = selectedRelaysNotifier.value;
    if (!await _confirmSave(relayUrls.length) || !mounted) return;

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

    setState(() => _saving = true);
    try {
      final published = await _repository.publishPaymentTargets(
        seckeyHex: privkeyHex,
        pubkeyHex: identity.pubkeyHex,
        base: _base,
        paytoTags: _paytoTags(),
        relayUrls: relayUrls,
      );
      if (!mounted) return;

      final results = published.results;
      final accepted = results.values
          .where((result) => result.outcome == RelayPublishOutcome.accepted)
          .length;
      if (accepted == 0) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not publish your payment targets to any relay',
            ),
          ),
        );
        return;
      }

      await CacheStore.putPaymentTargets(
        pubkeyHex,
        paymentTargetsFromEvent(published.event),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Updated payment targets on $accepted/${results.length} relays',
          ),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not sign your payment targets: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addRow() {
    setState(() => _rows.add(_Row(type: knownPaymentTargetTypes.first)));
  }

  void _removeRow(_Row row) {
    setState(() => _rows.remove(row));
    row.address.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment targets'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              key: const Key('savePaymentTargetsButton'),
              onPressed: _loading || _saving ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!_baseConclusive)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_outlined,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Some relays did not answer, so your published '
                              'targets could not be checked.',
                            ),
                          ),
                          TextButton(
                            key: const Key('retryLoadPaymentTargetsButton'),
                            onPressed: () => _load(seedRows: false),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    'Addresses others can use to pay you, shown on your '
                    'profile.',
                    style: theme.metadata,
                  ),
                  const SizedBox(height: 16),
                  for (final row in _rows)
                    Padding(
                      key: ObjectKey(row),
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 140,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: row.type,
                              decoration: const InputDecoration(
                                labelText: 'Type',
                              ),
                              items: [
                                for (final type in {
                                  ...knownPaymentTargetTypes,
                                  row.type,
                                })
                                  DropdownMenuItem(
                                    value: type,
                                    child: Text(
                                      paymentTargetTypeDisplayName(type),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (type) =>
                                  setState(() => row.type = type ?? row.type),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              key: const Key('paymentTargetAddressField'),
                              controller: row.address,
                              validator: _validateAddress,
                              maxLength: 500,
                              decoration: const InputDecoration(
                                labelText: 'Address',
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('removePaymentTargetButton'),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove payment target',
                            onPressed: () => _removeRow(row),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('addPaymentTargetButton'),
                      onPressed: _rows.length >= _maxPaymentTargets
                          ? null
                          : _addRow,
                      icon: const Icon(Icons.add),
                      label: const Text('Add payment target'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
