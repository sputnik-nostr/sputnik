import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/app_state.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/profiles.dart';

import 'support/in_memory_relay_client.dart';

// Answers every query with all its events, as a relay that ignores filters.
class _IgnoresFilters extends InMemoryRelayClient {
  _IgnoresFilters(super.events);

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async => events;
}

void main() {
  final alice = generateNostrKeyPair();
  final mallory = generateNostrKeyPair();
  const relays = {'wss://relay.example.com'};

  NostrEvent event(
    NostrKeyPair by, {
    required int kind,
    required String content,
    required Duration age,
  }) => signEvent(
    seckeyHex: by.privateKeyHex,
    pubkeyHex: by.publicKeyHex,
    kind: kind,
    content: content,
    createdAt: DateTime.now().subtract(age),
  );

  setUp(() => profileCacheNotifier.value = {});

  test('a newer event of another kind cannot replace the profile', () async {
    final real = event(
      alice,
      kind: 0,
      content: '{"name":"alice"}',
      age: const Duration(days: 30),
    );
    // Legacy contact lists carry a relay map as JSON content.
    final replayed = event(
      alice,
      kind: 3,
      content: '{"wss://relay.damus.io":{"read":true}}',
      age: const Duration(days: 1),
    );

    final profiles = await RelayProfileRepository(
      client: _IgnoresFilters([real, replayed]),
    ).fetchProfiles({alice.publicKeyHex}, relays);

    expect(profiles[alice.publicKeyHex]?.name, 'alice');
  });

  test('profiles nobody asked for are neither returned nor cached', () async {
    final asked = event(
      alice,
      kind: 0,
      content: '{"name":"alice"}',
      age: Duration.zero,
    );
    final unasked = event(
      mallory,
      kind: 0,
      content: '{"name":"mallory"}',
      age: Duration.zero,
    );

    final profiles = await loadProfiles(
      {alice.publicKeyHex},
      relays,
      force: true,
      client: _IgnoresFilters([asked, unasked]),
    );

    expect(profiles.keys, [alice.publicKeyHex]);
    expect(profileCacheNotifier.value.keys, [alice.publicKeyHex]);
  });

  test('the newest kind 0 event wins', () async {
    final older = event(
      alice,
      kind: 0,
      content: '{"name":"old"}',
      age: const Duration(days: 2),
    );
    final newer = event(
      alice,
      kind: 0,
      content: '{"name":"new"}',
      age: const Duration(days: 1),
    );

    final profiles = await RelayProfileRepository(
      client: _IgnoresFilters([older, newer]),
    ).fetchProfiles({alice.publicKeyHex}, relays);

    expect(profiles[alice.publicKeyHex]?.name, 'new');
  });
}
