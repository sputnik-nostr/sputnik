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

    return NostrMetadata(
      name: text('name'),
      displayName: text('display_name') ?? text('displayName'),
      about: text('about'),
      picture: string('picture'),
      banner: string('banner'),
      nip05: string('nip05'),
      website: string('website'),
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
    );
  }

  final String? name;
  final String? displayName;
  final String? about;
  final String? picture;
  final String? banner;
  final String? nip05;
  final String? website;

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
    };
  }
}
