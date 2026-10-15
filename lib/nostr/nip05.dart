/// Result of checking a NIP-05 identifier against a pubkey.
enum Nip05Status {
  /// The domain confirmed this identifier maps to the pubkey.
  verified,

  /// The domain responded but does not map this identifier to the pubkey.
  mismatch,

  /// Could not be checked: malformed identifier, no response, or the
  /// target was refused as unsafe to fetch.
  unreachable,
}

/// A NIP-05 identifier split into local-part and domain.
typedef Nip05Identifier = ({String local, String domain});

final _localPartPattern = RegExp(r'^[a-z0-9-_.]+$');

/// Splits a NIP-05 identifier into local-part and domain. A bare domain
/// (no `@`) means the `_@domain` root identifier, per the spec.
Nip05Identifier? parseNip05(String identifier) {
  final trimmed = identifier.trim();
  if (trimmed.isEmpty) return null;

  final atIndex = trimmed.indexOf('@');
  final local = (atIndex == -1 ? '_' : trimmed.substring(0, atIndex))
      .toLowerCase();
  final domain = atIndex == -1 ? trimmed : trimmed.substring(atIndex + 1);
  if (domain.isEmpty || !_localPartPattern.hasMatch(local)) return null;

  return (local: local, domain: domain);
}
