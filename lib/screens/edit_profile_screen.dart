import 'package:flutter/material.dart';

import '../app_state.dart';
import '../nostr/nip05.dart';
import '../nostr/nostr.dart';
import '../services/cache_store.dart';
import '../services/publishing.dart';
import '../widgets/unchecked_warning.dart';
import 'edit_payment_targets_screen.dart';

bool _isWebUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

String? _validateUrl(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty || _isWebUrl(trimmed)) return null;
  return 'Enter a valid http:// or https:// URL';
}

String? _validateNip05(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty || parseNip05(trimmed) != null) return null;
  return 'Enter an address, such as name@example.com';
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.relayClient = const RelayClient()});

  final RelayClient relayClient;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _pictureController = TextEditingController();
  final _bannerController = TextEditingController();
  final _nip05Controller = TextEditingController();
  final _websiteController = TextEditingController();

  /// The kind:0 event the edit is applied on top of, as read from the relays.
  NostrEvent? _base;
  bool _loading = true;
  bool _baseConclusive = true;
  bool _saving = false;

  RelayProfileRepository get _profiles =>
      RelayProfileRepository(client: widget.relayClient);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _nameController.dispose();
    _bioController.dispose();
    _pictureController.dispose();
    _bannerController.dispose();
    _nip05Controller.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  /// A retry keeps what has been typed and only refreshes the base event.
  Future<void> _load({bool seedFields = true}) async {
    final pubkeyHex = activeIdentityPubkeyNotifier.value;
    if (pubkeyHex == null) {
      setState(() => _loading = false);
      return;
    }
    if (seedFields) setState(() => _loading = true);

    final own = await _profiles.fetchOwnProfileEvent(
      pubkeyHex,
      selectedRelaysNotifier.value,
    );
    if (!mounted) return;

    NostrMetadata? metadata;
    final event = own.event;
    if (event != null) {
      try {
        metadata = NostrMetadata.fromContent(event.content);
      } catch (_) {
        // Unreadable content; the form starts from the cached profile.
      }
    }
    metadata ??= profileCacheNotifier.value[pubkeyHex];

    setState(() {
      _base = event ?? _base;
      _baseConclusive = own.conclusive;
      _loading = false;
    });
    if (!seedFields) return;

    setState(() {
      _displayNameController.text = metadata?.displayName ?? '';
      _nameController.text = metadata?.name ?? '';
      _bioController.text = metadata?.about ?? '';
      _pictureController.text = metadata?.picture ?? '';
      _bannerController.text = metadata?.banner ?? '';
      _nip05Controller.text = metadata?.nip05 ?? '';
      _websiteController.text = metadata?.website ?? '';
    });
  }

  Future<void> _save() async {
    if (_loading || _saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final identity = activeIdentity();
    if (identity == null) return;
    final pubkeyHex = identity.pubkeyHex;

    final relayUrls = selectedRelaysNotifier.value;
    final confirmed = await confirmAction(
      context,
      title: 'Update profile?',
      message: _baseConclusive
          ? 'This publishes your profile to ${relayUrls.length} relay(s).'
          : 'This publishes your profile to ${relayUrls.length} relay(s). '
                'Some relays did not respond, so your current profile could '
                'not be checked and fields you set elsewhere may be '
                'overwritten.',
      action: 'Save',
      actionKey: const Key('confirmSaveProfileButton'),
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await withSecretKey<void>(
        identity,
        messenger,
        signFailure: 'Could not sign this profile update',
        use: (secretKey) async {
          if (!mounted) return;
          final published = await _profiles.publishProfile(
            secretKey: secretKey,
            pubkeyHex: pubkeyHex,
            base: _base,
            fields: {
              'display_name': _displayNameController.text,
              'name': _nameController.text,
              'about': _bioController.text,
              'picture': _pictureController.text,
              'banner': _bannerController.text,
              'nip05': _nip05Controller.text,
              'website': _websiteController.text,
            },
            relayUrls: relayUrls,
          );
          if (!mounted) return;

          final updated = reportPublishResults(
            messenger,
            published.results,
            failure: 'Could not publish this profile update to any relay',
            success: (counts) => 'Updated profile on $counts relays',
          );
          if (!updated) return;

          final metadata = NostrMetadata.fromContent(published.event.content);
          profileCacheNotifier.value = {
            ...profileCacheNotifier.value,
            pubkeyHex: metadata,
          };
          await CacheStore.putProfiles({pubkeyHex: metadata});
          if (mounted) Navigator.pop(context);
        },
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              key: const Key('saveProfileButton'),
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
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        if (!_baseConclusive)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: UncheckedWarning(
                              message:
                                  'Some relays did not respond, so your published '
                                  'profile could not be checked.',
                              retryKey: const Key('retryLoadProfileButton'),
                              onRetry: () => _load(seedFields: false),
                            ),
                          ),
                        TextFormField(
                          key: const Key('editNameField'),
                          controller: _displayNameController,
                          maxLength: 50,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('editUsernameField'),
                          controller: _nameController,
                          maxLength: 50,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('editBioField'),
                          controller: _bioController,
                          maxLength: 500,
                          minLines: 1,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(labelText: 'Bio'),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('editPictureField'),
                          controller: _pictureController,
                          keyboardType: TextInputType.url,
                          validator: _validateUrl,
                          decoration: const InputDecoration(
                            labelText: 'Picture URL',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('editBannerField'),
                          controller: _bannerController,
                          keyboardType: TextInputType.url,
                          validator: _validateUrl,
                          decoration: const InputDecoration(
                            labelText: 'Banner URL',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('editNip05Field'),
                          controller: _nip05Controller,
                          keyboardType: TextInputType.emailAddress,
                          validator: _validateNip05,
                          decoration: const InputDecoration(
                            labelText: 'NIP-05 address',
                            hintText: 'name@example.com',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('editWebsiteField'),
                          controller: _websiteController,
                          keyboardType: TextInputType.url,
                          validator: _validateUrl,
                          decoration: const InputDecoration(
                            labelText: 'Website',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    key: const Key('editPaymentTargetsTile'),
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: const Text('Payment targets'),
                    subtitle: const Text('Addresses others can use to pay you'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditPaymentTargetsScreen(
                          relayClient: widget.relayClient,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
