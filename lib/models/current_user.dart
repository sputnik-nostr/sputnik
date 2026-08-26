class CurrentUser {
  const CurrentUser._();

  // Placeholder hex pubkey for the current user. The NIP-19 `npub` is an encoding of this.
  static const pubkeyHex =
      'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
  static const displayName = 'Anon';
  static const bio = 'This is a test bio';
  static final lastActiveAt = DateTime.now().subtract(
    const Duration(days: 2, hours: 4),
  );
}
