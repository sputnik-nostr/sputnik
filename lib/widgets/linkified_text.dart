import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models/note_mapper.dart';
import '../nostr/nip19.dart';
import '../nostr/relay_post_repository.dart';
import '../nostr/relay_profile_repository.dart';
import '../screens/post_screen.dart';
import '../screens/profile_screen.dart';

final _linkPattern = RegExp(
  r'(https?://\S+)|(nostr:\w+)',
  caseSensitive: false,
);

class LinkifiedText extends StatefulWidget {
  const LinkifiedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final linkColor = Theme.of(context).colorScheme.primary;
    final spans = <InlineSpan>[];
    var start = 0;

    for (final match in _linkPattern.allMatches(widget.text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: widget.text.substring(start, match.start)));
      }

      final matchedText = match.group(0)!;
      final httpUrl = match.group(1);
      final nostrTarget = match.group(2) == null
          ? null
          : decodeNostrUri(match.group(2)!);

      if (httpUrl == null && nostrTarget == null) {
        // An unrecognized `nostr:` entity (e.g. `nsec`, `naddr`); leave as
        // plain text rather than linkifying something we can't open.
        spans.add(TextSpan(text: matchedText));
        start = match.end;
        continue;
      }

      final recognizer = TapGestureRecognizer()
        ..onTap = () => httpUrl != null
            ? launchUrl(
                Uri.parse(httpUrl),
                mode: LaunchMode.externalApplication,
              )
            : _openNostrUri(context, nostrTarget!);
      _recognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: matchedText,
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

    return Text.rich(TextSpan(style: widget.style, children: spans));
  }

  Future<void> _openNostrUri(
    BuildContext context,
    NostrUriTarget target,
  ) async {
    if (target.pubkeyHex != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileScreen(pubkeyHex: target.pubkeyHex!),
        ),
      );
      return;
    }

    final eventIdHex = target.eventIdHex!;
    final relayUrls = selectedRelaysNotifier.value;
    final post = await RelayPostRepository(relayUrls: relayUrls)
        .fetchPostById(eventIdHex);
    if (!context.mounted) return;

    if (post == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Note not found')));
      return;
    }

    final authorMetadata = await const RelayProfileRepository().fetchProfile(
      post.author.pubkey,
      relayUrls,
    );
    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostScreen(
          note: noteFromNostrPost(post, authorMetadata: authorMetadata),
        ),
      ),
    );
  }
}
