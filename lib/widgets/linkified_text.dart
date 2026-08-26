import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final _urlPattern = RegExp(r'https?://\S+');

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

    for (final match in _urlPattern.allMatches(widget.text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: widget.text.substring(start, match.start)));
      }

      final url = match.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _recognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            color: linkColor,
            decoration: TextDecoration.underline,
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
}
