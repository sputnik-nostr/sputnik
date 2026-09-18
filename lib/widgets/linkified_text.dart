import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models/note_mapper.dart';
import '../nostr/models/nostr_metadata.dart';
import '../nostr/nip19.dart';
import '../nostr/relay_client.dart';
import '../nostr/relay_post_repository.dart';
import '../nostr/relay_profile_repository.dart';
import '../screens/post_screen.dart';
import '../screens/profile_screen.dart';

// A bare npub, nprofile, note or nevent is a citation too, not only nostr:.
final _linkPattern = RegExp(
  r'(https?://\S+)|(nostr:\w+)|(\bn(?:pub|profile|ote|event)1[02-9ac-hj-np-z]+)',
  caseSensitive: false,
);

// Bounds the profile lookups a single post can trigger.
const _maxMentionLookups = 20;
const _maxMentionNameLength = 40;

// Pubkeys already looked up this session, so a missing profile is not
// requested again each time its note scrolls into view.
final _lookedUp = <String>{};

class _Link {
  const _Link(this.match, this.httpUrl, this.target);

  final RegExpMatch match;
  final String? httpUrl;
  final NostrUriTarget? target;
}

class LinkifiedText extends StatefulWidget {
  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.selectable = true,
    this.relayClient = const RelayClient(),
  });

  final String text;
  final TextStyle? style;

  // Off inside tappable rows, where a selection area would swallow the taps.
  final bool selectable;

  final RelayClient relayClient;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final _recognizers = <String, TapGestureRecognizer>{};
  bool _opening = false;

  // Avoids re-scanning unchanged text on every rebuild.
  String? _parsedText;
  List<_Link>? _links;

  List<_Link> _linksFor(String text) {
    if (_parsedText == text) return _links!;
    _parsedText = text;
    return _links = [
      for (final match in _linkPattern.allMatches(text))
        _Link(
          match,
          match.group(1),
          match.group(1) != null
              ? null
              : decodeNostrUri(match.group(2) ?? match.group(3)!),
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _lookUpMentions();
  }

  @override
  void didUpdateWidget(LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _lookUpMentions();
  }

  // Names arrive through the profile cache, which the build listens to.
  void _lookUpMentions() {
    if (_lookedUp.length > 2000) _lookedUp.clear();
    final missing = <String>{
      for (final link in _linksFor(widget.text))
        if (link.target?.pubkeyHex case final pubkey?)
          if (!profileCacheNotifier.value.containsKey(pubkey) &&
              !_lookedUp.contains(pubkey))
            pubkey,
    }.take(_maxMentionLookups).toSet();
    if (missing.isEmpty) return;

    _lookedUp.addAll(missing);
    // A failed lookup just leaves the short npub in place.
    RelayProfileRepository(client: widget.relayClient)
        .fetchProfiles(missing, selectedRelaysNotifier.value)
        .ignore();
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  TapGestureRecognizer _recognizerFor(String key, VoidCallback onTap) {
    final existing = _recognizers[key];
    if (existing != null) return existing..onTap = onTap;
    return _recognizers[key] = TapGestureRecognizer()..onTap = onTap;
  }

  @override
  Widget build(BuildContext context) {
    final links = _linksFor(widget.text);
    if (links.every((link) => link.target?.pubkeyHex == null)) {
      return _buildText(context, links, const {});
    }
    return ValueListenableBuilder<Map<String, NostrMetadata>>(
      valueListenable: profileCacheNotifier,
      builder: (context, profiles, _) => _buildText(context, links, profiles),
    );
  }

  String _mentionLabel(String pubkeyHex, NostrMetadata? metadata) {
    final name = metadata?.resolvedName?.replaceAll(RegExp(r'\s+'), ' ');
    if (name == null || name.isEmpty) {
      return '@${truncateNpub(npubFromHex(pubkeyHex))}';
    }
    return name.length <= _maxMentionNameLength
        ? '@$name'
        : '@${name.substring(0, _maxMentionNameLength - 3)}...';
  }

  // A note id is long and unreadable; keep just enough to tell them apart.
  String _eventLabel(String matchedText) {
    final entity = matchedText.startsWith('nostr:')
        ? matchedText.substring('nostr:'.length)
        : matchedText;
    return truncateMiddle(entity, totalLength: 20, suffixLength: 5);
  }

  Widget _buildText(
    BuildContext context,
    List<_Link> links,
    Map<String, NostrMetadata> profiles,
  ) {
    final live = <String>{};

    final linkColor = Theme.of(context).colorScheme.primary;
    final spans = <InlineSpan>[];
    var start = 0;

    for (final link in links) {
      final match = link.match;
      if (match.start > start) {
        spans.add(TextSpan(text: widget.text.substring(start, match.start)));
      }

      final matchedText = match.group(0)!;
      final httpUrl = link.httpUrl;
      final nostrTarget = link.target;

      if (httpUrl == null && nostrTarget == null) {
        // An unrecognized `nostr:` entity (e.g. `nsec`, `naddr`); leave as
        // plain text rather than linkifying something we can't open.
        spans.add(TextSpan(text: matchedText));
        start = match.end;
        continue;
      }

      final key = '${match.start}:$matchedText';
      live.add(key);
      final recognizer = _recognizerFor(
        key,
        () => httpUrl != null
            ? _openHttpUrl(context, httpUrl)
            : _openNostrUri(context, nostrTarget!),
      );

      final pubkeyHex = nostrTarget?.pubkeyHex;
      spans.add(
        TextSpan(
          text: pubkeyHex != null
              ? _mentionLabel(pubkeyHex, profiles[pubkeyHex])
              : nostrTarget?.eventIdHex != null
              ? _eventLabel(matchedText)
              : matchedText,
          style: TextStyle(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
          ),
          recognizer: recognizer,
        ),
      );
      start = match.end;
    }

    if (start < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(start)));
    }

    for (final key in _recognizers.keys.toList()) {
      if (!live.contains(key)) _recognizers.remove(key)?.dispose();
    }

    final text = Text.rich(TextSpan(style: widget.style, children: spans));
    if (!widget.selectable) return text;

    // Plain taps still reach each link span's recognizer.
    return SelectionArea(child: text);
  }

  Future<void> _openHttpUrl(BuildContext context, String url) async {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } on FormatException {
      _reportUnopenable(context);
      return;
    }

    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      opened = false;
    } on MissingPluginException {
      opened = false;
    }
    if (!opened && context.mounted) _reportUnopenable(context);
  }

  void _reportUnopenable(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open this link')));
  }

  Future<void> _openNostrUri(
    BuildContext context,
    NostrUriTarget target,
  ) async {
    if (target.pubkeyHex != null) {
      openProfile(context, target.pubkeyHex!);
      return;
    }

    // A slow relay must not let repeated taps stack up several screens.
    if (_opening) return;
    _opening = true;
    try {
      await _openNote(context, target.eventIdHex!);
    } finally {
      _opening = false;
    }
  }

  Future<void> _openNote(BuildContext context, String eventIdHex) async {
    final relayUrls = selectedRelaysNotifier.value;
    final post = await RelayPostRepository(
      relayUrls: relayUrls,
      client: widget.relayClient,
    ).fetchPostById(eventIdHex);
    if (!context.mounted) return;

    if (post == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Note not found')));
      return;
    }

    final authorMetadata = await RelayProfileRepository(
      client: widget.relayClient,
    ).fetchProfile(post.author.pubkey, relayUrls);
    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostScreen(
          note: noteFromNostrPost(post, authorMetadata: authorMetadata),
          relayClient: widget.relayClient,
        ),
      ),
    );
  }
}
