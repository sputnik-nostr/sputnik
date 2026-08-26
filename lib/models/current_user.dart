class CurrentUser {
  const CurrentUser._();

  static const npub =
      'npub1anon0000000000000000000000000000000000000000000000000000';
  static const displayName = 'Anon';
  static const bio = 'This is a test bio';
  static final lastActiveAt = DateTime.now().subtract(
    const Duration(days: 2, hours: 4),
  );
}
