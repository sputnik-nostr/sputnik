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
}
