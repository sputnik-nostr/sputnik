import 'dart:convert';

import 'text_sanitizer.dart';

class NostrMetadata {
  const NostrMetadata({
    this.name,
    this.displayName,
    this.about,
    this.picture,
    this.banner,
    this.nip05,
    this.website,
    this.legacyMoneroAddress,
  });

  factory NostrMetadata.fromContent(String content) {
    final json = jsonDecode(content) as Map<String, dynamic>;
    String? string(String key) {
      final value = json[key];
      return value is String ? value : null;
    }

    String? text(String key) {
      final value = string(key);
      return value == null ? null : sanitizeUtf16(value);
    }

    // Non-standard fields some clients use instead of a NIP-A3 payto tag.
    String? legacyMoneroAddress() {
      final direct = text('xmr') ?? text('monero_address');
      if (direct != null) return direct;
      final addresses = json['cryptocurrency_addresses'];
      final nested = addresses is Map ? addresses['monero'] : null;
      return nested is String ? sanitizeUtf16(nested) : null;
    }

    return NostrMetadata(
      name: text('name'),
      displayName: text('display_name') ?? text('displayName'),
      about: text('about'),
      picture: string('picture'),
      banner: string('banner'),
      nip05: string('nip05'),
      website: string('website'),
      legacyMoneroAddress: legacyMoneroAddress(),
    );
  }

  factory NostrMetadata.fromJson(Map<String, dynamic> json) {
    String? string(String key) {
      final value = json[key];
      return value is String ? value : null;
    }

    return NostrMetadata(
      name: string('name'),
      displayName: string('displayName'),
      about: string('about'),
      picture: string('picture'),
      banner: string('banner'),
      nip05: string('nip05'),
      website: string('website'),
      legacyMoneroAddress: string('legacyMoneroAddress'),
    );
  }

  final String? name;
  final String? displayName;
  final String? about;
  final String? picture;
  final String? banner;
  final String? nip05;
  final String? website;
  final String? legacyMoneroAddress;

  String? get resolvedName {
    final trimmedDisplayName = displayName?.trim();
    if (trimmedDisplayName != null && trimmedDisplayName.isNotEmpty) {
      return trimmedDisplayName;
    }
    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) return trimmedName;
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      if (name != null) 'name': name,
      if (displayName != null) 'displayName': displayName,
      if (about != null) 'about': about,
      if (picture != null) 'picture': picture,
      if (banner != null) 'banner': banner,
      if (nip05 != null) 'nip05': nip05,
      if (website != null) 'website': website,
      if (legacyMoneroAddress != null)
        'legacyMoneroAddress': legacyMoneroAddress,
    };
  }

  // The kind:0 wire format, per NIP-01: snake_case display_name, unlike the
  // camelCase used by toJson()'s internal cache shape.
  Map<String, dynamic> toEventContent() {
    return {
      if (name != null) 'name': name,
      if (displayName != null) 'display_name': displayName,
      if (about != null) 'about': about,
      if (picture != null) 'picture': picture,
      if (banner != null) 'banner': banner,
      if (nip05 != null) 'nip05': nip05,
      if (website != null) 'website': website,
    };
  }

  NostrMetadata copyWith({
    String? name,
    String? displayName,
    String? about,
    String? picture,
    String? banner,
    String? nip05,
    String? website,
  }) {
    return NostrMetadata(
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      about: about ?? this.about,
      picture: picture ?? this.picture,
      banner: banner ?? this.banner,
      nip05: nip05 ?? this.nip05,
      website: website ?? this.website,
      legacyMoneroAddress: legacyMoneroAddress,
    );
  }
}
