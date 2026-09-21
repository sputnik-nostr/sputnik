/// Matches an HTTP(S) URL, including any trailing punctuation.
final httpUrlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

const _urlTrailingPunctuation = '.,;:!?\'*';
const _urlClosers = {')': '(', ']': '[', '}': '{'};

/// Sentence punctuation and unmatched closers after a URL belong to the text.
String trimUrlEnd(String url) {
  var end = url.length;
  while (end > 0) {
    final last = url[end - 1];
    final opener = _urlClosers[last];
    final trailing =
        _urlTrailingPunctuation.contains(last) ||
        (opener != null && _count(url, end, last) > _count(url, end, opener));
    if (!trailing) break;
    end--;
  }
  return url.substring(0, end);
}

int _count(String text, int end, String char) {
  var count = 0;
  for (var i = 0; i < end; i++) {
    if (text[i] == char) count++;
  }
  return count;
}

/// [text] without the URLs in [urls], and without any line they empty out.
String withoutUrls(String text, Set<String> urls) {
  final lines = <String>[];
  for (final line in text.split('\n')) {
    var removed = false;
    final kept = line.replaceAllMapped(httpUrlPattern, (match) {
      final url = trimUrlEnd(match[0]!);
      if (!urls.contains(url)) return match[0]!;
      removed = true;
      return match[0]!.substring(url.length);
    });
    if (!removed) {
      lines.add(line);
    } else if (kept.trim().isNotEmpty) {
      lines.add(kept.trimRight());
    }
  }
  return lines.join('\n').trimRight();
}
