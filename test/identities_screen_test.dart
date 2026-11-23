import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/models/identity_index.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/identity_store.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/faulty_secret_store.dart';
import 'support/identity_storage.dart';

// Refuses to delete anything, like a locked keyring whose prompt was dismissed.
class _UndeletableSecretStore extends FakeSecretStore {
  var failDeletes = false;

  @override
  Future<void> delete(String key) {
    if (failDeletes) throw PlatformException(code: 'KeyringLocked');
    return super.delete(key);
  }
}

// Fails every write of the identity index, like a keyring that locked after
// the identities were read.
class _UnwritableIndexSecretStore extends FakeSecretStore {
  @override
  Future<void> write(String key, String value) {
    if (key == 'identities') throw PlatformException(code: 'KeyringLocked');
    return super.write(key, value);
  }
}

// Fails every read of the identity index while locked, like a keyring whose
// unlock prompt was dismissed, and answers only once [answer] completes.
class _LockedIndexSecretStore extends FakeSecretStore {
  _LockedIndexSecretStore([super.initial]);

  var locked = true;
  Completer<void>? answer;

  @override
  Future<String?> read(String key) async {
    if (key == 'identities') {
      await answer?.future;
      if (locked) throw PlatformException(code: 'KeyringLocked');
    }
    return super.read(key);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    IdentityStore.reset();
    // Without posts, HomeScreen's spinner keeps pumpAndSettle going forever.
    notesNotifier.value = const [];
    followingNotesNotifier.value = const [];
    identitiesNotifier.value = const [];
    activeIdentityPubkeyNotifier.value = null;
    SettingsStore.secretStore = FakeSecretStore();
  });

  tearDown(IdentityStore.reset);

  Future<void> openIdentitiesScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.byKey(const Key('profileAvatarButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settingsCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identitiesCard')));
    await tester.pumpAndSettle();
  }

  testWidgets('generates a keypair and makes it the active identity', (
    tester,
  ) async {
    await openIdentitiesScreen(tester);

    expect(find.text('No identities yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('generateIdentityButton')));
    await tester.pumpAndSettle();

    expect(find.text('No identities yet'), findsNothing);
    expect(identitiesNotifier.value, hasLength(1));
    expect(
      activeIdentityPubkeyNotifier.value,
      identitiesNotifier.value.single.pubkeyHex,
    );
    final privkeyHex = await SettingsStore.loadPrivateKey(
      identitiesNotifier.value.single.pubkeyHex,
    );
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(privkeyHex ?? ''), isTrue);
  });

  testWidgets('deleting the active identity clears the active pointer', (
    tester,
  ) async {
    await openIdentitiesScreen(tester);

    await tester.tap(find.byKey(const Key('generateIdentityButton')));
    await tester.pumpAndSettle();
    expect(identitiesNotifier.value, hasLength(1));
    final pubkeyHex = identitiesNotifier.value.single.pubkeyHex;

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(identitiesNotifier.value, isEmpty);
    expect(activeIdentityPubkeyNotifier.value, isNull);
    expect(find.text('No identities yet'), findsOneWidget);
    expect(await SettingsStore.loadPrivateKey(pubkeyHex), isNull);
  });

  Future<void> deleteFirstIdentity(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
  }

  testWidgets('a key that cannot be deleted keeps its identity and says so', (
    tester,
  ) async {
    final store = _UndeletableSecretStore();
    SettingsStore.secretStore = store;
    await openIdentitiesScreen(tester);
    await tester.tap(find.byKey(const Key('generateIdentityButton')));
    await tester.pumpAndSettle();
    final pubkeyHex = identitiesNotifier.value.single.pubkeyHex;

    store.failDeletes = true;
    await deleteFirstIdentity(tester);

    // The failure is reported, not swallowed.
    expect(tester.takeException(), isA<PlatformException>());
    expect(find.text('Could not delete this key'), findsOneWidget);
    expect(identitiesNotifier.value.single.pubkeyHex, pubkeyHex);
    expect(activeIdentityPubkeyNotifier.value, pubkeyHex);
    expect(find.text('No identities yet'), findsNothing);
    expect(await SettingsStore.loadPrivateKey(pubkeyHex), isNotNull);

    // Once storage cooperates again, the same delete goes through.
    store.failDeletes = false;
    await deleteFirstIdentity(tester);

    expect(identitiesNotifier.value, isEmpty);
    expect(activeIdentityPubkeyNotifier.value, isNull);
    expect(await SettingsStore.loadPrivateKey(pubkeyHex), isNull);
  });

  testWidgets('deleting an identity forgets when its follow list was seen', (
    tester,
  ) async {
    resetKnownContactLists();
    addTearDown(resetKnownContactLists);
    await openIdentitiesScreen(tester);
    await tester.tap(find.byKey(const Key('generateIdentityButton')));
    await tester.pumpAndSettle();
    final pubkeyHex = identitiesNotifier.value.single.pubkeyHex;
    noteOwnContactList(pubkeyHex, DateTime.now(), 3);
    noteOwnContactList('ab' * 32, DateTime.now(), 7);

    await deleteFirstIdentity(tester);

    expect(identitiesNotifier.value, isEmpty);
    // Another identity's record stays.
    expect(seenOwnContactLists.value.keys, ['ab' * 32]);
  });

  testWidgets('a key that cannot be deleted keeps when its list was seen', (
    tester,
  ) async {
    final store = _UndeletableSecretStore();
    SettingsStore.secretStore = store;
    resetKnownContactLists();
    addTearDown(resetKnownContactLists);
    await openIdentitiesScreen(tester);
    await tester.tap(find.byKey(const Key('generateIdentityButton')));
    await tester.pumpAndSettle();
    final pubkeyHex = identitiesNotifier.value.single.pubkeyHex;
    noteOwnContactList(pubkeyHex, DateTime.now(), 3);

    store.failDeletes = true;
    await deleteFirstIdentity(tester);

    expect(tester.takeException(), isA<PlatformException>());
    expect(identitiesNotifier.value.single.pubkeyHex, pubkeyHex);
    expect(seenOwnContactLists.value.keys, [pubkeyHex]);

    // Once storage cooperates again, the identity and its record go together.
    store.failDeletes = false;
    await deleteFirstIdentity(tester);

    expect(identitiesNotifier.value, isEmpty);
    expect(seenOwnContactLists.value, isEmpty);
  });

  group('when the identities cannot be read', () {
    final held = generateNostrKeyPair();
    late _LockedIndexSecretStore store;

    bool disabled(WidgetTester tester, String key) =>
        tester.widget<IconButton>(find.byKey(Key(key))).onPressed == null;

    setUp(() {
      store = _LockedIndexSecretStore({
        'identities': IdentityIndex.empty
            .withIdentity(
              Identity(pubkeyHex: held.publicKeyHex, createdAt: DateTime(2026)),
            )
            .encode(),
        'identity_secret_${held.publicKeyHex}': held.privateKeyHex,
      });
      SettingsStore.secretStore = store;
    });

    testWidgets('says so instead of showing none, and adds nothing', (
      tester,
    ) async {
      await IdentityStore.load();
      expect(tester.takeException(), isA<PlatformException>());
      await openIdentitiesScreen(tester);

      expect(find.text('Could not read your identities'), findsOneWidget);
      expect(find.text('No identities yet'), findsNothing);
      expect(find.byKey(const Key('retryIdentitiesButton')), findsOneWidget);
      expect(disabled(tester, 'generateIdentityButton'), isTrue);
      expect(disabled(tester, 'importIdentityButton'), isTrue);

      await tester.tap(
        find.byKey(const Key('generateIdentityButton')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(identitiesNotifier.value, isEmpty);
      expect(store.values.keys, [
        'identities',
        'identity_secret_${held.publicKeyHex}',
      ]);
    });

    testWidgets('Retry lists the identities once storage answers', (
      tester,
    ) async {
      await IdentityStore.load();
      expect(tester.takeException(), isA<PlatformException>());
      await openIdentitiesScreen(tester);

      store.locked = false;
      await tester.tap(find.byKey(const Key('retryIdentitiesButton')));
      await tester.pumpAndSettle();

      expect(find.text('Could not read your identities'), findsNothing);
      expect(find.byType(ListTile), findsOneWidget);
      expect(identitiesNotifier.value.single.pubkeyHex, held.publicKeyHex);
      expect(disabled(tester, 'generateIdentityButton'), isFalse);
      expect(disabled(tester, 'importIdentityButton'), isFalse);
    });

    testWidgets('what is generated after a retry joins the identities that '
        'could not be read before', (tester) async {
      await IdentityStore.load();
      expect(tester.takeException(), isA<PlatformException>());
      await openIdentitiesScreen(tester);
      store.locked = false;
      await tester.tap(find.byKey(const Key('retryIdentitiesButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('generateIdentityButton')));
      await tester.pumpAndSettle();

      // What a restart finds: the earlier identity and the new one.
      final listed = (await SettingsStore.loadIdentityIndex()).identities;
      expect(listed.map((i) => i.pubkeyHex), [
        held.publicKeyHex,
        identitiesNotifier.value.last.pubkeyHex,
      ]);
      expect(identitiesNotifier.value, hasLength(2));
    });

    testWidgets('offers no way to delete an identity it has listed', (
      tester,
    ) async {
      identitiesNotifier.value = [
        Identity(pubkeyHex: held.publicKeyHex, createdAt: DateTime(2026)),
      ];
      await IdentityStore.load();
      expect(tester.takeException(), isA<PlatformException>());
      await openIdentitiesScreen(tester);

      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('Retry cannot be pressed again while it is reading', (
      tester,
    ) async {
      await IdentityStore.load();
      expect(tester.takeException(), isA<PlatformException>());
      await openIdentitiesScreen(tester);
      store.locked = false;
      store.answer = Completer<void>();
      bool retryDisabled() =>
          tester
              .widget<FilledButton>(
                find.byKey(const Key('retryIdentitiesButton')),
              )
              .onPressed ==
          null;
      expect(retryDisabled(), isFalse);

      await tester.tap(find.byKey(const Key('retryIdentitiesButton')));
      await tester.pump();

      expect(find.text('Could not read your identities'), findsOneWidget);
      expect(retryDisabled(), isTrue);

      store.answer!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Could not read your identities'), findsNothing);
      expect(identitiesNotifier.value.single.pubkeyHex, held.publicKeyHex);
    });

    testWidgets('a retry that fails again keeps saying so', (tester) async {
      await IdentityStore.load();
      expect(tester.takeException(), isA<PlatformException>());
      await openIdentitiesScreen(tester);

      await tester.tap(find.byKey(const Key('retryIdentitiesButton')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<PlatformException>());
      expect(find.text('Could not read your identities'), findsOneWidget);
      expect(disabled(tester, 'generateIdentityButton'), isTrue);
      expect(identitiesNotifier.value, isEmpty);
    });
  });

  group('keys that no identity refers to', () {
    final lost = generateNostrKeyPair();
    late FakeSecretStore store;

    setUp(() {
      store = FakeSecretStore({
        'identity_secret_${lost.publicKeyHex}': lost.privateKeyHex,
      });
      SettingsStore.secretStore = store;
    });

    testWidgets(
      'are offered instead of "No identities yet", and listed on Add',
      (tester) async {
        await IdentityStore.load();
        await openIdentitiesScreen(tester);

        expect(find.text('No identities yet'), findsNothing);
        expect(
          find.text('Found on this device, but not in your list'),
          findsOneWidget,
        );

        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        expect(
          find.text('Found on this device, but not in your list'),
          findsNothing,
        );
        expect(identitiesNotifier.value.single.pubkeyHex, lost.publicKeyHex);
        expect(activeIdentityPubkeyNotifier.value, lost.publicKeyHex);
        expect(find.byType(ListTile), findsOneWidget);
        expect(
          (await SettingsStore.loadIdentityIndex()).identities.single.pubkeyHex,
          lost.publicKeyHex,
        );
      },
    );

    testWidgets('are offered after the identities that are listed', (
      tester,
    ) async {
      final held = generateNostrKeyPair();
      store = FakeSecretStore({
        ...store.values,
        ...currentStorage([
          (
            identity: Identity(
              pubkeyHex: held.publicKeyHex,
              createdAt: DateTime(2026),
            ),
            privkeyHex: held.privateKeyHex,
          ),
        ]),
      });
      SettingsStore.secretStore = store;
      await IdentityStore.load();
      await openIdentitiesScreen(tester);

      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      expect(tiles, hasLength(2));
      expect(
        (tiles.first.title as Text).data,
        truncateNpub(npubFromHex(held.publicKeyHex)),
      );
      expect(tiles.last.trailing, isA<TextButton>());
    });

    testWidgets('stay offered, with a message, when they cannot be added', (
      tester,
    ) async {
      await IdentityStore.load();
      await openIdentitiesScreen(tester);
      // Reading the index, reading the key, then writing the index fails.
      SettingsStore.secretStore = FaultySecretStore(store, failCall: 3);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<StateError>());
      expect(find.text('Could not add this key'), findsOneWidget);
      expect(
        find.text('Found on this device, but not in your list'),
        findsOneWidget,
      );
      expect(identitiesNotifier.value, isEmpty);
      expect(store.values.keys, ['identity_secret_${lost.publicKeyHex}']);
    });
  });

  const seckeyHex =
      '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';
  const nsec =
      'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5';

  testWidgets('a key pair that cannot be listed is not shown, and says so', (
    tester,
  ) async {
    SettingsStore.secretStore = _UnwritableIndexSecretStore();
    await openIdentitiesScreen(tester);

    await tester.tap(find.byKey(const Key('generateIdentityButton')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isA<PlatformException>());
    expect(find.text('Could not generate a key pair'), findsOneWidget);
    expect(find.text('No identities yet'), findsOneWidget);
    expect(identitiesNotifier.value, isEmpty);
    expect(activeIdentityPubkeyNotifier.value, isNull);
  });

  testWidgets('imports an nsec and makes it the active identity', (
    tester,
  ) async {
    await openIdentitiesScreen(tester);

    await tester.tap(find.byKey(const Key('importIdentityButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), nsec);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(identitiesNotifier.value, hasLength(1));
    expect(
      await SettingsStore.loadPrivateKey(
        identitiesNotifier.value.single.pubkeyHex,
      ),
      seckeyHex,
    );
    expect(
      activeIdentityPubkeyNotifier.value,
      identitiesNotifier.value.single.pubkeyHex,
    );
  });

  testWidgets(
    'an imported key that cannot be listed is not shown, and says so',
    (tester) async {
      SettingsStore.secretStore = _UnwritableIndexSecretStore();
      await openIdentitiesScreen(tester);

      await tester.tap(find.byKey(const Key('importIdentityButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), nsec);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<PlatformException>());
      expect(find.text('Could not import this key'), findsOneWidget);
      expect(identitiesNotifier.value, isEmpty);
      expect(activeIdentityPubkeyNotifier.value, isNull);
    },
  );

  testWidgets('rejects a malformed nsec without adding an identity', (
    tester,
  ) async {
    await openIdentitiesScreen(tester);

    await tester.tap(find.byKey(const Key('importIdentityButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'not an nsec');
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid nsec key'), findsOneWidget);
    expect(identitiesNotifier.value, isEmpty);
  });

  testWidgets('rejects importing an already-imported identity', (tester) async {
    await openIdentitiesScreen(tester);

    await tester.tap(find.byKey(const Key('importIdentityButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), nsec);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(identitiesNotifier.value, hasLength(1));

    await tester.tap(find.byKey(const Key('importIdentityButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), nsec);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('This identity is already imported'), findsOneWidget);
    expect(identitiesNotifier.value, hasLength(1));
  });
}
