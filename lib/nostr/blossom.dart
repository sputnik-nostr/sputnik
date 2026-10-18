import 'models/nostr_event.dart';

/// Bounds the servers tried for one blob, since each learns the viewer's IP.
const maxBlossomServers = 5;

final _blobName = RegExp(r'^([0-9a-fA-F]{64})(\.[A-Za-z0-9]+)?$');
final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

/// The extensions we pass on: short and plain, as for video temp files.
final _plainExtension = RegExp(r'^\.[A-Za-z0-9]{1,5}$');

/// The last path segment of [uri] as written, empty if there is none.
///
/// Not `Uri.pathSegments`, which decodes every segment and throws on escapes
/// that are not valid UTF-8, such as `%FF`, which a note's URL can contain.
/// Hashes and extensions are plain ASCII, so nothing here needs decoding.
String lastPathSegment(Uri uri) {
  final path = uri.path;
  return path.substring(path.lastIndexOf('/') + 1);
}

/// The SHA-256 that [uri] names in its last path segment, per NIP-B7.
String? blossomHash(Uri uri) {
  return _blobName.firstMatch(lastPathSegment(uri))?[1]?.toLowerCase();
}

/// The `.ext` after the name in [uri]'s last path segment: one to five ASCII
/// letters or digits, else empty, since the rest is the URL author's text.
String extensionOf(Uri uri) {
  final name = lastPathSegment(uri);
  final dot = name.lastIndexOf('.');
  final extension = dot <= 0 ? '' : name.substring(dot);
  return _plainExtension.hasMatch(extension) ? extension : '';
}

/// Whether [uri] is one we would fetch: HTTPS, with a host and no credentials.
bool isFetchableUrl(Uri? uri) {
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

/// The HTTPS origins in a kind:10063 server list, in the author's order.
List<String> blossomServersFromEvent(NostrEvent event) {
  final servers = <String>[];
  for (final tag in event.tags) {
    if (tag.length < 2 || tag[0] != 'server') continue;

    final uri = Uri.tryParse(tag[1].trim());
    if (!isFetchableUrl(uri)) continue;
    final origin = uri!.hasPort
        ? '${uri.scheme}://${uri.host}:${uri.port}'
        : '${uri.scheme}://${uri.host}';
    if (!servers.contains(origin)) servers.add(origin);
    if (servers.length >= maxBlossomServers) break;
  }
  return servers;
}

/// [server]'s scheme, host and port alone, or null if it is not an HTTPS one.
Uri? _originOf(String server) {
  final uri = Uri.tryParse(server);
  if (uri == null || !isFetchableUrl(uri)) return null;
  // The authority keeps the brackets of an IPv6 host, which `host` drops.
  return Uri.tryParse('${uri.scheme}://${uri.authority}');
}

/// Where each of [servers] would serve the blob, as NIP-B7 describes.
///
/// The URL is a single path segment: [sha256] and, if it is short and plain,
/// [extension]. So nothing a note's URL held can reshape the request, and a
/// server that is not an HTTPS origin is skipped rather than guessed at.
List<Uri> blossomUrls(List<String> servers, String sha256, String extension) {
  final hash = sha256.toLowerCase();
  if (!_sha256Hex.hasMatch(hash)) return const [];

  final name = _plainExtension.hasMatch(extension) ? '$hash$extension' : hash;
  return [
    for (final server in servers)
      if (_originOf(server) case final origin?)
        origin.replace(pathSegments: [name]),
  ];
}
