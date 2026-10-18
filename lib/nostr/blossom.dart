import 'models/nostr_event.dart';

/// Bounds the servers tried for one blob, since each learns the viewer's IP.
const maxBlossomServers = 5;

final _blobName = RegExp(r'^([0-9a-fA-F]{64})(\.[A-Za-z0-9]+)?$');

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

/// The `.ext` after the name in [uri]'s last path segment, if any.
String extensionOf(Uri uri) {
  final name = lastPathSegment(uri);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot);
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

/// Where each of [servers] would serve the blob, as NIP-B7 describes.
List<Uri> blossomUrls(List<String> servers, String sha256, String extension) {
  return [for (final server in servers) Uri.parse('$server/$sha256$extension')];
}
