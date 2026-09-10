// Hardcoded placeholder data for the current user.
class CurrentUser {
  const CurrentUser._();

  static const pubkeyHex =
      'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
  static const displayName = 'Anon';
  static const bio = 'This is a test bio';
  static final lastActiveAt = DateTime.now().subtract(
    const Duration(days: 2, hours: 4),
  );
}

class CurrentUserProfile {
  const CurrentUserProfile({required this.displayName, required this.bio});

  factory CurrentUserProfile.fromJson(Map<String, dynamic> json) =>
      CurrentUserProfile(
        displayName: json['displayName'] as String? ?? CurrentUser.displayName,
        bio: json['bio'] as String? ?? CurrentUser.bio,
      );

  static const fallback = CurrentUserProfile(
    displayName: CurrentUser.displayName,
    bio: CurrentUser.bio,
  );

  final String displayName;
  final String bio;

  CurrentUserProfile copyWith({String? displayName, String? bio}) {
    return CurrentUserProfile(
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
    );
  }

  Map<String, dynamic> toJson() => {'displayName': displayName, 'bio': bio};
}
