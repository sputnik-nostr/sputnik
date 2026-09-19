import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/identity.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/screens/relays_screen.dart';
import 'package:sputnik/screens/user_relays_screen.dart';
import 'package:sputnik/services/settings_store.dart';

import 'support/fake_secret_store.dart';
import 'support/in_memory_relay_client.dart';

NostrEvent _listEvent(String pubkey, List<List<String>> tags, {String? id}) =>
    fakeEvent(id: id, pubkey: pubkey, kind: 10002, tags: tags);

void main() {
  group('relayListFromEvent', () {
    List<RelayListEntry> parse(List<List<String>> tags) =>
        relayListFromEvent(_listEvent('aa', tags));

    test('reads markers', () {
      final entries = parse([
        ['r', 'wss://both.example'],
        ['r', 'wss://read.example', 'read'],
        ['r', 'wss://write.example', 'write'],
      ]);

      expect(
        [for (final e in entries) (e.url, e.read, e.write)],
        [
          ('wss://both.example', true, true),
          ('wss://read.example', true, false),
          ('wss://write.example', false, true),
        ],
      );
    });

    test('drops invalid urls and other tags', () {
      final entries = parse([
        ['r', 'https://not-a-relay.example'],
        ['r', 'wss://user@host.example'],
        ['r'],
        ['p', 'bb' * 32],
        ['r', 'wss://ok.example'],
      ]);

      expect([for (final e in entries) e.url], ['wss://ok.example']);
    });

    test('merges a relay listed twice and normalizes its url', () {
      final entries = parse([
        ['r', 'WSS://Relay.Example/', 'read'],
        ['r', 'wss://relay.example', 'write'],
      ]);

      expect(entries, hasLength(1));
      expect(entries.single.url, 'wss://relay.example');
      expect(entries.single.marker, isNull);
    });

    test('bounds how many entries it reads', () {
      final entries = parse([
        for (var i = 0; i < 200; i++) ['r', 'wss://relay$i.example'],
      ]);

      expect(entries, hasLength(maxRelayListEntries));
    });

    test('writes the marker back as a tag', () {
      expect(const RelayListEntry(url: 'wss://a.example').toTag(), [
        'r',
        'wss://a.example',
      ]);
      expect(
        const RelayListEntry(url: 'wss://a.example', write: false).toTag(),
        ['r', 'wss://a.example', 'read'],
      );
      expect(
        const RelayListEntry(url: 'wss://a.example', read: false).toTag(),
        ['r', 'wss://a.example', 'write'],
      );
    });
  });

  group('relays screen', () {
    late Identity identity;
    late InMemoryRelayClient client;

    setUp(() async {
      final keypair = generateNostrKeyPair();
      identity = Identity(
        pubkeyHex: keypair.publicKeyHex,
        createdAt: DateTime.now(),
      );
      identitiesNotifier.value = [identity];
      activeIdentityPubkeyNotifier.value = identity.pubkeyHex;
      customRelaysNotifier.value = const {};
      selectedRelaysNotifier.value = {'wss://a.example', 'wss://b.example'};

      SettingsStore.secretStore = FakeSecretStore();
      await SettingsStore.savePrivateKey(
        identity.pubkeyHex,
        keypair.privateKeyHex,
      );

      client = InMemoryRelayClient([
        _listEvent(identity.pubkeyHex, [
          ['r', 'wss://a.example', 'write'],
          ['r', 'wss://c.example'],
          ['alt', 'kept'],
        ], id: '0a'),
      ]);
    });

    Future<void> openScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: RelaysScreen(relayClient: client)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the published list with its markers', (tester) async {
      await openScreen(tester);

      expect(find.text('Your relay list'), findsOneWidget);
      expect(find.text('Write only'), findsOneWidget);
      expect(find.text('Read and write'), findsOneWidget);
    });

    testWidgets('is hidden without an identity', (tester) async {
      activeIdentityPubkeyNotifier.value = null;
      await openScreen(tester);

      expect(find.text('Your relay list'), findsNothing);
      expect(client.queries, isEmpty);
    });

    testWidgets('says when no list is published', (tester) async {
      client.events.clear();
      await openScreen(tester);

      expect(find.text('You have not published a relay list yet'), findsOne);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('useRelayListButton')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('using the list replaces the selected relays', (tester) async {
      await openScreen(tester);

      await tester.tap(find.byKey(const Key('useRelayListButton')));
      await tester.pumpAndSettle();
      expect(find.text('Use your relay list?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmUseRelayListButton')));
      await tester.pumpAndSettle();

      expect(selectedRelaysNotifier.value, {
        'wss://a.example',
        'wss://c.example',
      });
      expect(customRelaysNotifier.value, {
        'wss://a.example',
        'wss://c.example',
      });
    });

    testWidgets('cancelling leaves the selection alone', (tester) async {
      await openScreen(tester);

      await tester.tap(find.byKey(const Key('useRelayListButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(selectedRelaysNotifier.value, {
        'wss://a.example',
        'wss://b.example',
      });
    });

    testWidgets('publishing sends the selection, keeping known markers', (
      tester,
    ) async {
      await openScreen(tester);

      await tester.tap(find.byKey(const Key('publishRelayListButton')));
      await tester.pumpAndSettle();
      // One relay of the published list is not selected, so it goes away.
      expect(find.textContaining('1 relay(s)'), findsWidgets);
      await tester.tap(find.byKey(const Key('confirmPublishRelayListButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final event = client.published.single;
      expect(event.kind, 10002);
      expect(event.pubkey, identity.pubkeyHex);
      expect(event.tags, [
        ['alt', 'kept'],
        ['r', 'wss://a.example', 'write'],
        ['r', 'wss://b.example'],
      ]);
      expect(find.textContaining('Published relay list to 2/2'), findsOne);

      await tester.pumpAndSettle();
      expect(find.text('wss://b.example'), findsWidgets);
    });

    testWidgets('a rejected publish is reported', (tester) async {
      client.publishOutcome = RelayPublishOutcome.rejected;
      await openScreen(tester);

      await tester.tap(find.byKey(const Key('publishRelayListButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmPublishRelayListButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Could not publish your relay list to any relay'),
        findsOneWidget,
      );
    });

    testWidgets('warns when the published list could not be checked', (
      tester,
    ) async {
      client.events.clear();
      client.relaysAnswer = false;
      await openScreen(tester);

      expect(find.byKey(const Key('retryLoadRelayListButton')), findsOne);

      await tester.tap(find.byKey(const Key('publishRelayListButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be checked'), findsWidgets);
      expect(client.published, isEmpty);
    });
  });

  group('someone else relay list', () {
    final author = 'ab' * 32;
    late InMemoryRelayClient client;

    setUp(() {
      customRelaysNotifier.value = const {};
      selectedRelaysNotifier.value = {'wss://a.example'};
      client = InMemoryRelayClient([
        _listEvent(author, [
          ['r', 'wss://a.example'],
          ['r', 'wss://read.example', 'read'],
        ]),
      ]);
    });

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          // Desktop settings, which shrink icon buttons.
          theme: ThemeData(
            platform: TargetPlatform.linux,
            visualDensity: VisualDensity.compact,
          ),
          home: UserRelaysScreen(pubkeyHex: author, relayClient: client),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists their relays and lets you add the missing ones', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Read only'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(
        tester.getCenter(find.byIcon(Icons.check)).dx,
        tester.getCenter(find.byIcon(Icons.add)).dx,
      );

      await tester.tap(find.byKey(const Key('addRelay-wss://read.example')));
      await tester.pumpAndSettle();

      expect(selectedRelaysNotifier.value, contains('wss://read.example'));
      expect(customRelaysNotifier.value, contains('wss://read.example'));
      expect(find.byIcon(Icons.check), findsNWidgets(2));
    });

    testWidgets('says when there is no list', (tester) async {
      client.events.clear();
      await open(tester);

      expect(find.text('No relay list found'), findsOneWidget);
    });
  });
}
