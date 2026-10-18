import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sputnik/models/identity_index.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/faulty_secret_store.dart';
import 'support/identity_storage.dart';
import 'support/reported_errors.dart';

// Reports success for writes it does not keep, like a store that lost them.
class _ForgetfulSecretStore extends FakeSecretStore {
  _ForgetfulSecretStore(this.forgets, [super.initial]);

  final bool Function(String key) forgets;

  @override
  Future<void> write(String key, String value) async {
    if (!forgets(key)) await super.write(key, value);
  }
}

// Fails the writes that [fails] picks, with the error of a locked keyring.
class _LockedWritesSecretStore extends FakeSecretStore {
  _LockedWritesSecretStore(this.fails, [super.initial]);

  final bool Function(String key) fails;

  @override
  Future<void> write(String key, String value) {
    if (fails(key)) throw PlatformException(code: 'KeyringLocked');
    return super.write(key, value);
  }
}

// Fails every delete, like a keyring whose unlock prompt was dismissed.
class _UndeletableSecretStore extends FakeSecretStore {
  _UndeletableSecretStore([super.initial]);

  @override
  Future<void> delete(String key) =>
      throw PlatformException(code: 'KeyringLocked');
}

final _slotName = RegExp(r'^[0-9a-f]{32}$');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SettingsStore.secretStore = FakeSecretStore();
  });

  FakeSecretStore store() => SettingsStore.secretStore as FakeSecretStore;

  group('the entry of a key', () {
    test('is named after a random slot, not after the pubkey', () async {
      final held = newHeldIdentity();

      final index = await SettingsStore.addIdentity(
        held.identity,
        held.privkeyHex,
      );

      final slot = index.slotOf(held.pubkeyHex);
      expect(slot, matches(_slotName));
      expect(store().values['identity_secret_$slot'], held.privkeyHex);
      for (final name in store().values.keys) {
        expect(name, isNot(contains(held.pubkeyHex)));
      }
      expect(
        await SettingsStore.loadPrivateKey(held.pubkeyHex),
        held.privkeyHex,
      );
    });

    test('differs between identities and between additions', () async {
      final a = newHeldIdentity();
      final b = newHeldIdentity();
      await SettingsStore.addIdentity(a.identity, a.privkeyHex);
      final both = await SettingsStore.addIdentity(b.identity, b.privkeyHex);
      final first = both.slotOf(a.pubkeyHex);

      expect(both.slotOf(b.pubkeyHex), isNot(first));

      // Deleting an identity and adding it again does not bring its slot back.
      await SettingsStore.removeIdentity(a.pubkeyHex);
      final again = await SettingsStore.addIdentity(a.identity, a.privkeyHex);
      expect(again.slotOf(a.pubkeyHex), isNot(first));
    });

    test('is deleted with the identity, and so is an older copy', () async {
      final held = newHeldIdentity();
      final index = await SettingsStore.addIdentity(
        held.identity,
        held.privkeyHex,
      );
      final slot = index.slotOf(held.pubkeyHex);
      await SettingsStore.savePrivateKey(held.pubkeyHex, held.privkeyHex);

      await SettingsStore.removeIdentity(held.pubkeyHex);

      expect(store().values.keys, ['identities']);
      expect(store().values.containsKey('identity_secret_$slot'), isFalse);
    });
  });

  test('changes of every kind made at the same time all take effect', () async {
    final a = newHeldIdentity();
    final b = newHeldIdentity();
    final c = newHeldIdentity();
    SettingsStore.secretStore = FakeSecretStore(
      currentStorage([a, b], active: a.pubkeyHex),
    );

    await Future.wait([
      SettingsStore.addIdentity(c.identity, c.privkeyHex),
      SettingsStore.removeIdentity(a.pubkeyHex),
      SettingsStore.saveActiveIdentityPubkey(b.pubkeyHex),
      SettingsStore.loadIdentityIndex(),
    ]);

    final index = storedIndex(store().values);
    expect(index.identities.map((i) => i.pubkeyHex), [
      b.pubkeyHex,
      c.pubkeyHex,
    ]);
    expect(index.active, b.pubkeyHex);
    expect(await SettingsStore.loadPrivateKey(b.pubkeyHex), b.privkeyHex);
    expect(await SettingsStore.loadPrivateKey(c.pubkeyHex), c.privkeyHex);
    expect(isStored(store().values, a.privkeyHex), isFalse);
  });

  group('reading a key', () {
    test('finds it in its slot', () async {
      final held = newHeldIdentity();
      SettingsStore.secretStore = FakeSecretStore(currentStorage([held]));

      expect(
        await SettingsStore.loadPrivateKey(held.pubkeyHex),
        held.privkeyHex,
      );
    });

    test('finds it under the pubkey while the identity has no slot', () async {
      final held = newHeldIdentity();
      SettingsStore.secretStore = FakeSecretStore(legacyStorage([held]));

      expect(
        await SettingsStore.loadPrivateKey(held.pubkeyHex),
        held.privkeyHex,
      );
    });

    test('finds it under the pubkey when its slot is empty', () async {
      final held = newHeldIdentity();
      SettingsStore.secretStore = FakeSecretStore({
        'identities': currentStorage([held])['identities']!,
        'identity_secret_${held.pubkeyHex}': held.privkeyHex,
      });

      expect(
        await SettingsStore.loadPrivateKey(held.pubkeyHex),
        held.privkeyHex,
      );
    });

    test('prefers its slot when the pubkey has an entry too', () async {
      final held = newHeldIdentity();
      SettingsStore.secretStore = FakeSecretStore({
        ...currentStorage([held]),
        'identity_secret_${held.pubkeyHex}': 'an older copy',
      });

      expect(
        await SettingsStore.loadPrivateKey(held.pubkeyHex),
        held.privkeyHex,
      );
    });

    test('finds nothing for an identity that has no entry', () async {
      final held = newHeldIdentity();
      SettingsStore.secretStore = FakeSecretStore(currentStorage([held]));

      expect(await SettingsStore.loadPrivateKey('f' * 64), isNull);
    });

    test(
      'lends only a key that is the identity\'s, from either entry',
      () async {
        final held = newHeldIdentity();
        final other = newHeldIdentity();

        for (final storage in [
          {
            'identities': currentStorage([held])['identities']!,
            'identity_secret_slot0': other.privkeyHex,
          },
          {'identity_secret_${held.pubkeyHex}': other.privkeyHex},
        ]) {
          SettingsStore.secretStore = FakeSecretStore(storage);

          expect(await SettingsStore.loadSecretKey(held.pubkeyHex), isNull);
        }
      },
    );
  });

  group('moving a key named after its pubkey into a slot', () {
    late HeldIdentity held;
    late FakeSecretStore inner;

    setUp(() {
      held = newHeldIdentity();
      inner = FakeSecretStore(legacyStorage([held]));
      SettingsStore.secretStore = inner;
    });

    test('gives it a slot and leaves nothing under its pubkey', () async {
      final index = await SettingsStore.loadIdentityIndex();

      final slot = index.slotOf(held.pubkeyHex);
      expect(slot, matches(_slotName));
      expect(inner.values['identity_secret_$slot'], held.privkeyHex);
      expect(storedIndex(inner.values).slotOf(held.pubkeyHex), slot);
      for (final name in inner.values.keys) {
        expect(name, isNot(contains(held.pubkeyHex)));
      }
      expect(
        await SettingsStore.loadPrivateKey(held.pubkeyHex),
        held.privkeyHex,
      );
    });

    test(
      'copies it, saves the index and only then deletes the old entry',
      () async {
        final watched = FaultySecretStore(inner);
        SettingsStore.secretStore = watched;

        await SettingsStore.loadIdentityIndex();

        // Every write is read back before the next step.
        expect(watched.calls, [
          'read identities',
          'read identity_secret_${held.pubkeyHex}',
          matches(RegExp(r'^write identity_secret_[0-9a-f]{32}$')),
          matches(RegExp(r'^read identity_secret_[0-9a-f]{32}$')),
          'write identities',
          'read identities',
          'delete identity_secret_${held.pubkeyHex}',
          'read identities',
        ]);
      },
    );

    test('keeps the old entry while the index cannot be saved', () async {
      final locked = _LockedWritesSecretStore(
        (key) => key == 'identities',
        legacyStorage([held]),
      );
      SettingsStore.secretStore = locked;
      final reported = captureReportedErrors();

      final index = await SettingsStore.loadIdentityIndex();

      expect(reported, hasLength(1));
      expect(index.slotOf(held.pubkeyHex), isNull);
      expect(locked.values['identity_secret_${held.pubkeyHex}'], isNotNull);
      expect(
        await SettingsStore.loadPrivateKey(held.pubkeyHex),
        held.privkeyHex,
      );

      // The next start, with storage working, finishes the move.
      SettingsStore.secretStore = FakeSecretStore(locked.values);
      final again = await SettingsStore.loadIdentityIndex();
      expect(again.slotOf(held.pubkeyHex), matches(_slotName));
      expect(
        await SettingsStore.loadPrivateKey(held.pubkeyHex),
        held.privkeyHex,
      );
    });

    test('keeps the old entry when the slot did not keep the key', () async {
      final forgetful = _ForgetfulSecretStore(
        (key) => key.startsWith('identity_secret_') && key.length == 48,
        legacyStorage([held]),
      );
      SettingsStore.secretStore = forgetful;
      final reported = captureReportedErrors();

      await SettingsStore.loadIdentityIndex();

      expect(reported, hasLength(1));
      expect(storedIndex(forgetful.values).slotOf(held.pubkeyHex), isNull);
      expect(
        await SettingsStore.loadPrivateKey(held.pubkeyHex),
        held.privkeyHex,
      );
    });

    test('keeps the key when the old entry cannot be deleted', () async {
      final undeletable = _UndeletableSecretStore(legacyStorage([held]));
      SettingsStore.secretStore = undeletable;
      final reported = captureReportedErrors();

      final index = await SettingsStore.loadIdentityIndex();

      expect(reported, hasLength(1));
      expect(index.slotOf(held.pubkeyHex), matches(_slotName));
      expect(
        await SettingsStore.loadPrivateKey(held.pubkeyHex),
        held.privkeyHex,
      );
    });

    test('leaves a key that is not the identity\'s where it is', () async {
      final other = newHeldIdentity();
      inner = FakeSecretStore({
        ...legacyStorage([held]),
        'identity_secret_${held.pubkeyHex}': other.privkeyHex,
      });
      SettingsStore.secretStore = inner;
      final before = inner.values;
      final reported = captureReportedErrors();

      await SettingsStore.loadIdentityIndex();

      expect(reported, hasLength(1));
      expect(inner.values, before);
    });

    test('leaves two different keys of one identity where they are', () async {
      inner = FakeSecretStore({
        'identities': jsonEncode([
          {...held.identity.toJson(), 'privkeyHex': 'another key'},
        ]),
        'identity_secret_${held.pubkeyHex}': held.privkeyHex,
      });
      SettingsStore.secretStore = inner;
      final before = inner.values;
      final reported = captureReportedErrors();

      await SettingsStore.loadIdentityIndex();

      expect(reported, hasLength(1));
      expect(inner.values, before);
    });

    test('leaves an identity without a key alone', () async {
      inner = FakeSecretStore({
        'identities': legacyStorage([held])['identities']!,
      });
      SettingsStore.secretStore = inner;
      final before = inner.values;
      final reported = captureReportedErrors();

      await SettingsStore.loadIdentityIndex();

      expect(reported, isEmpty);
      expect(inner.values, before);
    });

    test('does nothing at the next start', () async {
      await SettingsStore.loadIdentityIndex();
      final watched = FaultySecretStore(inner);
      SettingsStore.secretStore = watched;

      await SettingsStore.loadIdentityIndex();

      // Only the index is read: no key is touched once it is in a slot.
      expect(watched.calls, ['read identities', 'read identities']);
    });
  });

  group('moving a key stored inline into a slot', () {
    test('gives it a slot and takes it out of the index', () async {
      final held = newHeldIdentity();
      SettingsStore.secretStore = FakeSecretStore(inlineStorage([held]));

      final index = await SettingsStore.loadIdentityIndex();

      final slot = index.slotOf(held.pubkeyHex);
      expect(slot, matches(_slotName));
      expect(store().values['identity_secret_$slot'], held.privkeyHex);
      expect(store().values['identities'], isNot(contains(held.privkeyHex)));
    });

    test('drops the inline copy of a key that is stored already', () async {
      final held = newHeldIdentity();
      SettingsStore.secretStore = FakeSecretStore({
        'identities': inlineStorage([held])['identities']!,
        'identity_secret_${held.pubkeyHex}': held.privkeyHex,
      });

      final index = await SettingsStore.loadIdentityIndex();

      expect(index.keysToMove, isEmpty);
      expect(store().values['identities'], isNot(contains(held.privkeyHex)));
      expect(
        await SettingsStore.loadPrivateKey(held.pubkeyHex),
        held.privkeyHex,
      );
    });

    test('leaves a key that is not the identity\'s inline', () async {
      final held = newHeldIdentity();
      final other = newHeldIdentity();
      SettingsStore.secretStore = FakeSecretStore({
        'identities': jsonEncode([
          {...held.identity.toJson(), 'privkeyHex': other.privkeyHex},
        ]),
      });
      final reported = captureReportedErrors();

      final index = await SettingsStore.loadIdentityIndex();

      expect(reported, hasLength(1));
      expect(index.keysToMove.single.inlineKey, other.privkeyHex);
      expect(store().values['identities'], contains(other.privkeyHex));
    });
  });

  test(
    'whichever storage call fails, no key is lost on the way to a slot',
    () async {
      final named = newHeldIdentity();
      final inline = newHeldIdentity();
      final done = newHeldIdentity();
      final seed = {
        'identities': jsonEncode([
          named.identity.toJson(),
          {...inline.identity.toJson(), 'privkeyHex': inline.privkeyHex},
          {...done.identity.toJson(), 'slot': 'slot0'},
        ]),
        'identity_secret_${named.pubkeyHex}': named.privkeyHex,
        'identity_secret_slot0': done.privkeyHex,
      };
      captureReportedErrors();

      await forEveryFault(
        seed: seed,
        scenario: SettingsStore.loadIdentityIndex,
        check: (fault, after, error) async {
          final held = [named, inline, done];

          // Right after the failure, before any restart: nothing is gone, and
          // each key is either found by the app or still inline in the index.
          final index = storedIndex(after.values);
          expect(
            index.identities.map((i) => i.pubkeyHex),
            held.map((h) => h.pubkeyHex),
            reason: fault,
          );
          for (final h in held) {
            expect(isStored(after.values, h.privkeyHex), isTrue, reason: fault);
            final inIndex = index.keysToMove.any(
              (k) => k.pubkeyHex == h.pubkeyHex && k.inlineKey == h.privkeyHex,
            );
            expect(
              inIndex ||
                  await SettingsStore.loadPrivateKey(h.pubkeyHex) != null,
              isTrue,
              reason: '$fault: a key is neither found nor inline',
            );
          }

          // A start that works finishes the job.
          final restarted = await SettingsStore.loadIdentityIndex();
          expect(restarted.keysToMove, isEmpty, reason: fault);
          for (final h in held) {
            expect(
              await SettingsStore.loadPrivateKey(h.pubkeyHex),
              h.privkeyHex,
              reason: fault,
            );
          }
          expect(
            after.values['identities'],
            isNot(contains(inline.privkeyHex)),
            reason: fault,
          );
        },
      );
    },
  );

  group('the active identity', () {
    late HeldIdentity a;
    late HeldIdentity b;

    setUp(() {
      a = newHeldIdentity();
      b = newHeldIdentity();
    });

    Future<void> withPointerInPreferences(
      String? pointer, {
      String? inIndex,
    }) async {
      SharedPreferences.setMockInitialValues({
        'active_identity_pubkey': ?pointer,
        'theme_mode': 'dark',
      });
      SettingsStore.secretStore = FakeSecretStore(
        currentStorage([a, b], active: inIndex),
      );
    }

    Future<String?> pointerInPreferences() async =>
        (await SharedPreferences.getInstance()).getString(
          'active_identity_pubkey',
        );

    test('moves from preferences into the index', () async {
      await withPointerInPreferences(b.pubkeyHex);

      final index = await SettingsStore.loadIdentityIndex();

      expect(index.active, b.pubkeyHex);
      expect(storedIndex(store().values).active, b.pubkeyHex);
      expect(await pointerInPreferences(), isNull);
      // Nothing else in preferences is touched.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'theme_mode'});
    });

    test('is the one in the index when preferences name another', () async {
      await withPointerInPreferences(b.pubkeyHex, inIndex: a.pubkeyHex);

      final index = await SettingsStore.loadIdentityIndex();

      expect(index.active, a.pubkeyHex);
      expect(await pointerInPreferences(), isNull);
    });

    test('is not taken from preferences if that identity is gone', () async {
      await withPointerInPreferences('f' * 64);

      final index = await SettingsStore.loadIdentityIndex();

      expect(index.active, isNull);
      expect(index.activePubkey, a.pubkeyHex);
      expect(await pointerInPreferences(), isNull);
    });

    test('stays in preferences while the index cannot be written', () async {
      await withPointerInPreferences(b.pubkeyHex);
      final inner = store();
      SettingsStore.secretStore = _LockedWritesSecretStore(
        (key) => key == 'identities',
        inner.values,
      );
      final reported = captureReportedErrors();

      final index = await SettingsStore.loadIdentityIndex();

      expect(reported, hasLength(1));
      expect(index.active, isNull);
      expect(await pointerInPreferences(), b.pubkeyHex);

      // The next start, with storage working, moves it.
      SettingsStore.secretStore = FakeSecretStore(inner.values);
      expect((await SettingsStore.loadIdentityIndex()).active, b.pubkeyHex);
      expect(await pointerInPreferences(), isNull);
    });

    test('is not written when preferences hold none', () async {
      await withPointerInPreferences(null);
      final watched = FaultySecretStore(store());
      SettingsStore.secretStore = watched;

      await SettingsStore.loadIdentityIndex();

      expect(watched.calls, ['read identities', 'read identities']);
    });

    test('is saved in the index and nowhere else', () async {
      await withPointerInPreferences(null);

      await SettingsStore.saveActiveIdentityPubkey(b.pubkeyHex);

      expect(storedIndex(store().values).active, b.pubkeyHex);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'theme_mode'});
    });

    test('is not saved for an identity that is not listed', () async {
      await withPointerInPreferences(null, inIndex: a.pubkeyHex);
      final inner = store();
      final watched = FaultySecretStore(inner);
      SettingsStore.secretStore = watched;

      await SettingsStore.saveActiveIdentityPubkey('f' * 64);

      expect(watched.calls.where((call) => call.startsWith('write')), isEmpty);
      expect(storedIndex(inner.values).active, a.pubkeyHex);
    });

    test('is not written again when it is stored already', () async {
      await withPointerInPreferences(null, inIndex: a.pubkeyHex);
      final watched = FaultySecretStore(store());
      SettingsStore.secretStore = watched;

      await SettingsStore.saveActiveIdentityPubkey(a.pubkeyHex);

      expect(watched.calls, ['read identities']);
    });

    test('can be cleared', () async {
      await withPointerInPreferences(null, inIndex: a.pubkeyHex);

      await SettingsStore.saveActiveIdentityPubkey(null);

      expect(storedIndex(store().values).active, isNull);
    });

    test('is never lost on its way into the index', () async {
      await forEveryFault(
        seed: currentStorage([a, b]),
        reset: () async => SharedPreferences.setMockInitialValues({
          'active_identity_pubkey': b.pubkeyHex,
        }),
        scenario: SettingsStore.loadIdentityIndex,
        check: (fault, after, error) async {
          final index = storedIndex(after.values);
          expect(index.identities.map((i) => i.pubkeyHex), [
            a.pubkeyHex,
            b.pubkeyHex,
          ], reason: fault);
          // It is in preferences or in the index, until the move is done.
          expect(
            await pointerInPreferences() == b.pubkeyHex ||
                index.active == b.pubkeyHex,
            isTrue,
            reason: '$fault: the pointer is nowhere',
          );

          await SettingsStore.loadIdentityIndex();
          expect(storedIndex(after.values).active, b.pubkeyHex, reason: fault);
          expect(await pointerInPreferences(), isNull, reason: fault);
        },
      );
    });
  });

  test('nothing but the index names an identity outside the keyring', () async {
    final held = newHeldIdentity();
    final other = newHeldIdentity();

    await SettingsStore.addIdentity(held.identity, held.privkeyHex);
    await SettingsStore.addIdentity(other.identity, other.privkeyHex);
    await SettingsStore.saveActiveIdentityPubkey(other.pubkeyHex);
    await SettingsStore.loadIdentityIndex();

    for (final entry in store().values.entries) {
      if (entry.key == 'identities') continue;
      expect(entry.key, isNot(contains(held.pubkeyHex)));
      expect(entry.key, isNot(contains(other.pubkeyHex)));
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
    expect(
      IdentityIndex.parse(store().values['identities']!).active,
      other.pubkeyHex,
    );
  });
}
