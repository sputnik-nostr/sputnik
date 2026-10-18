import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show mapEquals, setEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/identity_index.dart';
import 'package:sputnik/nostr/hex.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/identity_store.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/faulty_secret_store.dart';
import 'support/identity_storage.dart';
import 'support/reported_errors.dart';

/// A key pair drawn from [random], so that a run is the same every time.
HeldIdentity _drawIdentity(Random random) {
  final privkeyHex = hexEncode([
    for (var i = 0; i < 32; i++) random.nextInt(256),
  ]);
  final secretKey = SecretKey.fromHex(privkeyHex);
  try {
    return (
      identity: Identity(
        pubkeyHex: xonlyPubkeyHex(secretKey),
        createdAt: DateTime(1),
      ),
      privkeyHex: privkeyHex,
    );
  } finally {
    secretKey.wipe();
  }
}

/// What the device holds before the first start, and the keys in it.
typedef _Start = ({
  String name,
  Map<String, String> storage,
  Map<String, Object> preferences,
  List<HeldIdentity> kept,
});

/// Every shape older versions left behind, and the one this version leaves.
_Start _startingPoint(int shape, Random random) {
  final a = _drawIdentity(random);
  final b = _drawIdentity(random);
  final c = _drawIdentity(random);
  String inline(HeldIdentity held, [HeldIdentity? key]) => jsonEncode({
    ...held.identity.toJson(),
    'privkeyHex': (key ?? held).privkeyHex,
  });

  return switch (shape) {
    0 => (name: 'nothing', storage: {}, preferences: {}, kept: []),
    1 => (
      name: 'keys named after pubkeys',
      storage: legacyStorage([a, b]),
      preferences: {'active_identity_pubkey': b.pubkeyHex},
      kept: [a, b],
    ),
    2 => (
      name: 'keys inside the index',
      storage: inlineStorage([a, b]),
      preferences: {'active_identity_pubkey': a.pubkeyHex},
      kept: [a, b],
    ),
    3 => (
      name: 'keys in slots',
      storage: currentStorage([a, b], active: a.pubkeyHex),
      preferences: {},
      kept: [a, b],
    ),
    4 => (
      name: 'keys in preferences',
      storage: {},
      preferences: {
        'identities': plaintextIdentities([a, b]),
        'active_identity_pubkey': a.pubkeyHex,
      },
      kept: [a, b],
    ),
    5 => (
      name: 'a key with no index',
      storage: {'identity_secret_someslot': a.privkeyHex},
      preferences: {},
      kept: [a],
    ),
    6 => (
      name: 'one of each',
      storage: {
        'identities': jsonEncode([a.identity.toJson(), jsonDecode(inline(b))]),
        'identity_secret_${a.pubkeyHex}': a.privkeyHex,
      },
      preferences: {
        'identities': plaintextIdentities([c]),
      },
      kept: [a, b, c],
    ),
    7 => (
      name: 'damaged entries in preferences',
      storage: {},
      preferences: {
        'identities':
            '[{"pubkeyHex":"zz","createdAt":1},${inline(a)},${inline(b, c)}]',
      },
      kept: [a, c],
    ),
    8 => (
      name: 'the same identity in preferences and in the index',
      storage: legacyStorage([a]),
      preferences: {
        'identities': plaintextIdentities([a, b]),
        'active_identity_pubkey': a.pubkeyHex,
      },
      kept: [a, b],
    ),
    _ => (
      name: 'copies of keys and a key with no index',
      storage: {
        ...currentStorage([a]),
        'identity_secret_${a.pubkeyHex}': a.privkeyHex,
        'identity_secret_${b.pubkeyHex}': b.privkeyHex,
      },
      preferences: {},
      kept: [a, b],
    ),
  };
}

/// Starts the app again, as a new process would.
Future<void> _restart() async {
  IdentityStore.reset();
  identitiesNotifier.value = const [];
  activeIdentityPubkeyNotifier.value = null;
  await IdentityStore.load();
}

void main() {
  // Each test of identity_store_test.dart fails one storage call of one
  // change. This one lets whole sequences of changes and restarts run with up
  // to three failures anywhere in them, from every shape that storage has had.
  test('no key is lost, and none is hidden, whatever fails when', () async {
    captureReportedErrors();
    final random = Random(2026);
    final problems = <String>[];

    for (var run = 0; run < 1000; run++) {
      final start = _startingPoint(run % 10, random);
      SharedPreferences.setMockInitialValues({...start.preferences});
      final storage = FakeSecretStore(start.storage);
      final faults = {
        for (var i = random.nextInt(4); i > 0; i--)
          1 + random.nextInt(70):
              Fault.values[random.nextInt(Fault.values.length)],
      };
      SettingsStore.secretStore = FaultySecretStore(storage, faults: faults);

      // The keys the user has been told are saved, and the ones ever seen.
      final kept = {for (final held in start.kept) held.pubkeyHex: held};
      final seen = [...start.kept];
      // Identities whose removal failed may be left listed without a key.
      final maybeKeyless = <String>{};
      final steps = <String>[];

      await _restart();
      for (var step = random.nextInt(8) + 1; step > 0; step--) {
        final shown = identitiesNotifier.value;
        final onOffer = IdentityStore.unlisted.value;
        switch (random.nextInt(6)) {
          case 0:
            await _restart();
            steps.add('restart');
          case 1 || 2:
            final held = _drawIdentity(random);
            seen.add(held);
            try {
              await IdentityStore.add(held.pubkeyHex, held.privkeyHex);
              kept[held.pubkeyHex] = held;
              steps.add('add');
            } catch (_) {
              steps.add('add failed');
            }
          case 3 when shown.isNotEmpty:
            final identity = shown[random.nextInt(shown.length)];
            // Asking to delete a key ends the promise to keep it, whether or
            // not the call reports success.
            kept.remove(identity.pubkeyHex);
            try {
              await IdentityStore.remove(identity);
              steps.add('remove');
            } catch (_) {
              maybeKeyless.add(identity.pubkeyHex);
              steps.add('remove failed');
            }
          case 4 when onOffer.isNotEmpty:
            try {
              await IdentityStore.restore(
                onOffer[random.nextInt(onOffer.length)],
              );
              steps.add('list again');
            } catch (_) {
              steps.add('list again failed');
            }
          case 5 when shown.isNotEmpty:
            activeIdentityPubkeyNotifier.value =
                shown[random.nextInt(shown.length)].pubkeyHex;
            await IdentityStore.activeSaved;
            steps.add('select');
        }
      }

      // The next start finds storage working.
      SettingsStore.secretStore = storage;
      await _restart();
      final stored = storage.values;
      final preferences = await SharedPreferences.getInstance();
      final inPreferences = preferences.getString('identities') ?? '';
      final copyOfPreferences = stored['identities_from_preferences'] ?? '';
      final where =
          'run $run, ${start.name}, failing calls $faults, then $steps';

      if (IdentityStore.status.value != IdentityStatus.ready) {
        problems.add('the identities cannot be read: $where');
        continue;
      }

      final listed = {
        for (final identity in identitiesNotifier.value) identity.pubkeyHex,
      };
      final offered = {
        for (final key in IdentityStore.unlisted.value) key.pubkeyHex,
      };

      // A key the user has been told is saved can still be got at.
      for (final held in kept.values) {
        final pubkeyHex = held.pubkeyHex;
        if (listed.contains(pubkeyHex)) {
          if (await SettingsStore.loadPrivateKey(pubkeyHex) !=
              held.privkeyHex) {
            problems.add('${pubkeyHex.substring(0, 8)} lost its key: $where');
          }
        } else if (!offered.contains(pubkeyHex) &&
            !inPreferences.contains(held.privkeyHex) &&
            !copyOfPreferences.contains(held.privkeyHex)) {
          problems.add('${pubkeyHex.substring(0, 8)} is gone: $where');
        }
      }

      // An identity that is listed has a key to sign with, unless the user
      // asked to delete it and that stopped half way.
      for (final pubkeyHex in listed) {
        if (maybeKeyless.contains(pubkeyHex)) continue;
        if (await SettingsStore.loadSecretKey(pubkeyHex) == null) {
          problems.add('${pubkeyHex.substring(0, 8)} has no key: $where');
        }
      }

      // Every key that is stored is a listed identity's or on offer.
      final index = stored['identities'] == null
          ? IdentityIndex.empty
          : IdentityIndex.parse(stored['identities']!);
      for (final entry in stored.entries) {
        if (!entry.key.startsWith('identity_secret_')) continue;
        final name = entry.key.substring('identity_secret_'.length);
        final owner = seen.where((held) => held.privkeyHex == entry.value);
        if (owner.isEmpty || index.refersTo(name)) continue;
        final pubkeyHex = owner.first.pubkeyHex;
        if (offered.contains(pubkeyHex)) continue;
        // A copy beside the entry in use is not hidden: it is the same key.
        final copies = stored.values.where((value) => value == entry.value);
        if (listed.contains(pubkeyHex) && copies.length > 1) continue;
        problems.add(
          'the key of ${pubkeyHex.substring(0, 8)} is hidden '
          'in ${entry.key}: $where',
        );
      }

      // Another start with storage working has nothing left to change.
      await _restart();
      final settled = storage.values;
      final settledPreferences = (await SharedPreferences.getInstance())
          .getKeys();
      await _restart();
      if (!mapEquals(storage.values, settled) ||
          !setEquals(
            (await SharedPreferences.getInstance()).getKeys(),
            settledPreferences,
          )) {
        problems.add('a start still changes storage: $where');
      }
    }

    expect(problems.take(5), isEmpty, reason: '${problems.length} problems');
  });
}
