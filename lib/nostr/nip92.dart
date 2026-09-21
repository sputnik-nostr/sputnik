import 'blossom.dart';
import 'http_urls.dart';
import 'models/nostr_media.dart';

/// Bounds the fetches a single note can trigger; the rest stay links.
const maxNoteMedia = 4;

/// Bounds the alternate sources kept per file.
const maxFallbackUrls = 3;

/// Formats Flutter can decode without a plugin.
const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
const _imageMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
};
const _videoExtensions = {'mp4', 'm4v', 'mov', 'webm', 'mkv', 'ogv'};

final _dimPattern = RegExp(r'^(\d{1,5})x(\d{1,5})$');

/// The values of each field of each `imeta` tag in [tags], by its `url`.
Map<String, Map<String, List<String>>> _imetaByUrl(List<List<String>> tags) {
  final byUrl = <String, Map<String, List<String>>>{};
  for (final tag in tags) {
    if (tag.isEmpty || tag[0] != 'imeta') continue;

    final fields = <String, List<String>>{};
    for (final entry in tag.skip(1)) {
      final space = entry.indexOf(' ');
      if (space <= 0) continue;
      fields
          .putIfAbsent(entry.substring(0, space), () => [])
          .add(entry.substring(space + 1).trim());
    }
    final url = fields['url']?.first;
    if (url != null) byUrl.putIfAbsent(url, () => fields);
  }
  return byUrl;
}

MediaType? _typeOf(Uri uri, String? mimeType) {
  if (mimeType != null) {
    final mime = mimeType.split(';').first.toLowerCase();
    if (_imageMimeTypes.contains(mime)) return MediaType.image;
    return mime.startsWith('video/') ? MediaType.video : null;
  }
  final extension = extensionOf(uri).replaceFirst('.', '').toLowerCase();
  if (_imageExtensions.contains(extension)) return MediaType.image;
  return _videoExtensions.contains(extension) ? MediaType.video : null;
}

/// The HTTPS images and videos in [content], with NIP-92 imeta from [tags].
List<NostrMedia> noteMedia(String content, List<List<String>> tags) {
  final imeta = _imetaByUrl(tags);
  final media = <NostrMedia>[];
  final seen = <String>{};

  for (final match in httpUrlPattern.allMatches(content)) {
    if (media.length >= maxNoteMedia) break;

    final url = trimUrlEnd(match[0]!);
    final uri = Uri.tryParse(url);
    if (!isFetchableUrl(uri) || !seen.add(url)) continue;

    final fields = imeta[url];
    final type = _typeOf(uri!, fields?['m']?.first);
    if (type == null) continue;

    final dim = fields?['dim']?.first;
    final dimMatch = dim == null ? null : _dimPattern.firstMatch(dim);
    final width = int.tryParse(dimMatch?[1] ?? '');
    final height = int.tryParse(dimMatch?[2] ?? '');
    final sized = width != null && height != null && width > 0 && height > 0;
    final alt = fields?['alt']?.first;
    final declaredHash = fields?['x']?.first.toLowerCase();

    media.add(
      NostrMedia(
        url: url,
        type: type,
        width: sized ? width : null,
        height: sized ? height : null,
        alt: alt == null || alt.isEmpty ? null : alt,
        sha256:
            blossomHash(uri) ??
            (declaredHash != null && isSha256Hex(declaredHash)
                ? declaredHash
                : null),
        fallbackUrls: [
          for (final fallback in fields?['fallback'] ?? const <String>[])
            if (isFetchableUrl(Uri.tryParse(fallback)) && fallback != url)
              fallback,
        ].take(maxFallbackUrls).toList(),
      ),
    );
  }
  return media;
}
