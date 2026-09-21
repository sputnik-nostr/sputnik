import '../blossom.dart';
import '../blurhash.dart';

enum MediaType { image, video }

/// An image or video attached to a note, from its URL and any NIP-92 tag.
class NostrMedia {
  const NostrMedia({
    required this.url,
    this.type = MediaType.image,
    this.width,
    this.height,
    this.alt,
    this.sha256,
    this.fallbackUrls = const [],
    this.blurhash,
    this.posterUrl,
  });

  factory NostrMedia.fromJson(Map<String, dynamic> json) {
    int? dimension(String key) {
      final value = json[key];
      return value is int && value > 0 ? value : null;
    }

    final alt = json['alt'];
    final sha256 = json['sha256'];
    final fallbacks = json['fallbacks'];
    final blurhash = json['blurhash'];
    final poster = json['poster'];
    return NostrMedia(
      url: json['url'] as String,
      type: MediaType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => MediaType.image,
      ),
      width: dimension('width'),
      height: dimension('height'),
      alt: alt is String ? alt : null,
      sha256: sha256 is String && isSha256Hex(sha256) ? sha256 : null,
      fallbackUrls: [
        if (fallbacks is List)
          for (final url in fallbacks)
            if (url is String) url,
      ],
      blurhash: blurhash is String && isValidBlurhash(blurhash)
          ? blurhash
          : null,
      posterUrl: poster is String && isFetchableUrl(Uri.tryParse(poster))
          ? poster
          : null,
    );
  }

  final String url;
  final MediaType type;
  final int? width;
  final int? height;

  /// Alternative text, for screen readers.
  final String? alt;

  /// The lowercase hex hash the bytes must match, when the note names one.
  final String? sha256;

  /// Other places the same bytes are said to be, tried if [url] fails.
  final List<String> fallbackUrls;

  /// A tiny blurred stand-in that needs no download, when the note has one.
  final String? blurhash;

  /// A preview image for a video, shown once images are allowed to load.
  final String? posterUrl;

  /// Width over height, when both are known.
  double? get aspectRatio {
    final width = this.width;
    final height = this.height;
    return width == null || height == null ? null : width / height;
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    if (type != MediaType.image) 'type': type.name,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (alt != null) 'alt': alt,
    if (sha256 != null) 'sha256': sha256,
    if (fallbackUrls.isNotEmpty) 'fallbacks': fallbackUrls,
    if (blurhash != null) 'blurhash': blurhash,
    if (posterUrl != null) 'poster': posterUrl,
  };
}

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// Whether [value] is a lowercase hex SHA-256.
bool isSha256Hex(String value) => _sha256Pattern.hasMatch(value);
