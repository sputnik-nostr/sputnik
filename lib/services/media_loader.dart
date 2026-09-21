import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../nostr/blossom.dart';
import 'ssrf_guard.dart';

/// Larger files are refused rather than downloaded.
const maxImageBytes = 10 * 1024 * 1024;
const maxVideoBytes = 100 * 1024 * 1024;

/// Covers a whole download, so a host that trickles bytes can't hold it open.
const imageTimeout = Duration(seconds: 30);
const videoTimeout = Duration(minutes: 10);

const _maxRedirects = 3;
const _connectTimeout = Duration(seconds: 10);
const _stallTimeout = Duration(seconds: 15);
const _maxRedirectBodyBytes = 64 * 1024;

typedef HttpClientFactory = HttpClient Function();

/// [url] if it is one we would fetch, else null.
String? fetchableUrlOrNull(String? url) =>
    url != null && isFetchableUrl(Uri.tryParse(url)) ? url : null;

/// A profile picture or banner, held to the hash a Blossom URL names.
MediaSource profileImageSource(String url) =>
    MediaSource(url: url, sha256: blossomHash(Uri.parse(url)));

/// An HttpClient that refuses non-public addresses.
HttpClient guardedHttpClient() =>
    HttpClient()..connectionFactory = guardedConnectionFactory;

/// Bounds the connections one host can hold open on the shared client.
const _maxConnectionsPerHost = 6;

HttpClient Function() _sharedClientBuilder = guardedHttpClient;
HttpClient? _sharedClient;

/// One guarded client for every image, so a feed reuses connections.
///
/// [downloadMedia] never closes it: a download only aborts its own request.
HttpClient sharedImageClient() {
  return _sharedClient ??= _sharedClientBuilder()
    ..connectionTimeout = _connectTimeout
    ..maxConnectionsPerHost = _maxConnectionsPerHost;
}

@visibleForTesting
void replaceSharedImageClient(HttpClient Function()? builder) {
  _sharedClient?.close(force: true);
  _sharedClient = null;
  _sharedClientBuilder = builder ?? guardedHttpClient;
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();

  @override
  String toString() => 'Download cancelled';
}

/// Aborts a download in progress.
class DownloadCanceller {
  bool _cancelled = false;
  void Function()? _abort;

  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _abort?.call();
  }
}

/// Where a redirect leads, or null if unsafe (e.g. HTTPS to HTTP).
Uri? redirectTarget(Uri from, String? location) {
  if (location == null) return null;
  final Uri target;
  try {
    target = from.resolve(location);
  } on FormatException {
    return null;
  }
  if (target.scheme != 'https' && target.scheme != 'http') return null;
  if (from.scheme == 'https' && target.scheme != 'https') return null;
  if (target.host.isEmpty || target.userInfo.isNotEmpty) return null;
  return target;
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? digest;

  @override
  void add(crypto.Digest data) => digest = data;

  @override
  void close() {}
}

/// Streams [uri] to [onChunk]; chunks arrive before [sha256] is checked.
Future<void> downloadMedia(
  Uri uri, {
  required int maxBytes,
  required void Function(List<int> chunk) onChunk,
  String? sha256,
  void Function(int received, int? total)? onProgress,
  Duration timeout = imageTimeout,
  DownloadCanceller? canceller,
  HttpClientFactory clientFactory = guardedHttpClient,
}) async {
  final client = clientFactory()..connectionTimeout = _connectTimeout;
  final ownsClient = !identical(client, _sharedClient);

  HttpClientRequest? request;
  StreamSubscription<List<int>>? body;
  Completer<void>? bodyDone;
  var aborted = false;

  // Aborts only this download, so a shared client keeps serving the others.
  void abort() {
    aborted = true;
    request?.abort();
    body?.cancel();
    final done = bodyDone;
    if (done != null && !done.isCompleted) {
      done.completeError(const HttpException('Download aborted'));
    }
    if (ownsClient) client.close(force: true);
  }

  Future<void> readBody(
    HttpClientResponse response,
    void Function(List<int> chunk) onData,
  ) {
    final done = bodyDone = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    subscription = body = response
        .timeout(_stallTimeout)
        .listen(
          (chunk) {
            try {
              onData(chunk);
            } catch (error, stack) {
              subscription.cancel();
              if (!done.isCompleted) done.completeError(error, stack);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!done.isCompleted) done.completeError(error, stack);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
    return done.future;
  }

  // An unread body would keep a shared connection busy.
  Future<Never> refuse(HttpClientResponse response, HttpException error) async {
    response.listen(null).cancel().ignore();
    throw error;
  }

  final deadline = Timer(timeout, abort);
  canceller?._abort = abort;
  try {
    var current = uri;
    for (var hops = 0; ; hops++) {
      if (canceller?.cancelled ?? false) throw const DownloadCancelled();
      final pending = await client.getUrl(current);
      request = pending;
      if (aborted) {
        pending.abort();
        throw HttpException('Download aborted', uri: current);
      }
      pending.followRedirects = false;
      final response = await pending.close();

      if (response.isRedirect) {
        final next = hops < _maxRedirects
            ? redirectTarget(
                current,
                response.headers.value(HttpHeaders.locationHeader),
              )
            : null;
        if (next == null) {
          await refuse(
            response,
            HttpException('Blocked redirect', uri: current),
          );
        }
        var redirectBytes = 0;
        await readBody(response, (chunk) {
          redirectBytes += chunk.length;
          if (redirectBytes > _maxRedirectBodyBytes) {
            throw HttpException('Redirect body too large', uri: current);
          }
        });
        current = next;
        continue;
      }

      if (response.statusCode != HttpStatus.ok) {
        await refuse(
          response,
          HttpException('HTTP ${response.statusCode}', uri: current),
        );
      }
      final total = response.contentLength >= 0 ? response.contentLength : null;
      if (total != null && total > maxBytes) {
        await refuse(response, HttpException('File too large', uri: current));
      }

      final digest = _DigestSink();
      final hasher = sha256 == null
          ? null
          : crypto.sha256.startChunkedConversion(digest);
      var received = 0;
      await readBody(response, (chunk) {
        received += chunk.length;
        if (received > maxBytes) {
          throw HttpException('File too large', uri: current);
        }
        hasher?.add(chunk);
        onChunk(chunk);
        onProgress?.call(received, total);
      });

      if (hasher != null) {
        hasher.close();
        if (digest.digest.toString() != sha256) {
          throw HttpException('Hash mismatch', uri: current);
        }
      }
      return;
    }
  } catch (_) {
    if (canceller?.cancelled ?? false) throw const DownloadCancelled();
    rethrow;
  } finally {
    deadline.cancel();
    // A body cut short must not leave a shared connection reading it.
    body?.cancel().ignore();
    if (ownsClient) client.close(force: true);
  }
}

/// Downloads [uri] into memory, checking [sha256] when given.
Future<Uint8List> fetchImageBytes(
  Uri uri, {
  int maxBytes = maxImageBytes,
  String? sha256,
  HttpClientFactory clientFactory = sharedImageClient,
}) async {
  final bytes = BytesBuilder(copy: false);
  await downloadMedia(
    uri,
    maxBytes: maxBytes,
    sha256: sha256,
    onChunk: bytes.add,
    clientFactory: clientFactory,
  );
  return bytes.takeBytes();
}

/// Where a file can be fetched, and what its bytes must hash to.
class MediaSource {
  const MediaSource({
    required this.url,
    this.sha256,
    this.fallbackUrls = const [],
    this.serverLookup,
  });

  final String url;
  final String? sha256;
  final List<String> fallbackUrls;

  /// The author's Blossom servers, asked for only once every URL has failed.
  final Future<List<String>> Function()? serverLookup;

  /// Tries [url], the fallbacks, then the author's servers.
  Future<T> fetch<T>(Future<T> Function(Uri uri) attempt) async {
    final tried = <String>{};
    Object? firstError;
    StackTrace? firstStack;

    Future<({T value})?> tryUri(Uri uri) async {
      if (!tried.add(uri.toString())) return null;
      try {
        return (value: await attempt(uri));
      } on DownloadCancelled {
        rethrow;
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
        return null;
      }
    }

    for (final candidate in [url, ...fallbackUrls]) {
      final uri = Uri.tryParse(candidate);
      final result = uri == null ? null : await tryUri(uri);
      if (result != null) return result.value;
    }

    final hash = sha256;
    final lookup = serverLookup;
    if (hash != null && lookup != null) {
      var servers = const <String>[];
      try {
        servers = await lookup();
      } catch (_) {
        // A failed lookup just leaves the earlier error to report.
      }
      final extension = extensionOf(Uri.parse(url));
      for (final uri in blossomUrls(servers, hash, extension)) {
        final result = await tryUri(uri);
        if (result != null) return result.value;
      }
    }

    Error.throwWithStackTrace(
      firstError ?? const HttpException('No source for this file'),
      firstStack ?? StackTrace.current,
    );
  }
}

/// A network image fetched through the SSRF guard, with a size cap.
class BoundedNetworkImage extends ImageProvider<BoundedNetworkImage> {
  const BoundedNetworkImage(
    this.source, {
    this.clientFactory = sharedImageClient,
  });

  final MediaSource source;
  final HttpClientFactory clientFactory;

  String get url => source.url;

  @override
  Future<BoundedNetworkImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    BoundedNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1.0,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await source.fetch(
      (uri) => fetchImageBytes(
        uri,
        sha256: source.sha256,
        clientFactory: clientFactory,
      ),
    );
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is BoundedNetworkImage &&
      other.url == url &&
      other.source.sha256 == source.sha256;

  @override
  int get hashCode => Object.hash(url, source.sha256);
}
