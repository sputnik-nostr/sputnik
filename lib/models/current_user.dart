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
