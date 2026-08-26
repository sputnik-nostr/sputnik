import 'dart:convert';

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
    String? string(String key) => json[key] as String?;
    return NostrMetadata(
      name: string('name'),
      displayName: string('display_name') ?? string('displayName'),
      about: string('about'),
      picture: string('picture'),
      banner: string('banner'),
      nip05: string('nip05'),
      website: string('website'),
    );
  }

  factory NostrMetadata.fromJson(Map<String, dynamic> json) {
    return NostrMetadata(
      name: json['name'] as String?,
      displayName: json['displayName'] as String?,
      about: json['about'] as String?,
      picture: json['picture'] as String?,
      banner: json['banner'] as String?,
      nip05: json['nip05'] as String?,
      website: json['website'] as String?,
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
