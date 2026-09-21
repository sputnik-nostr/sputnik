import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/bech32.dart';
import 'package:sputnik/nostr/hex.dart';
import 'package:sputnik/nostr/models/nostr_media.dart';
import 'package:sputnik/nostr/nip19.dart';
import 'package:sputnik/screens/post_screen.dart';
import 'package:sputnik/widgets/note_content.dart';
import 'package:sputnik/widgets/quoted_note.dart';

import 'support/in_memory_relay_client.dart';

final _quotedId = 'c' * 64;
final _otherId = 'd' * 64;

String _nevent(String id) => bech32Encode(
  'nevent',
  convertBits([0, 32, ...hexDecode(id)], 8, 5, pad: true),
);

Note _note(String content, {List<NostrMedia> media = const []}) => Note(
  id: 'a' * 64,
  pubkey: 'b' * 64,
  displayName: 'Quoter',
  handle: 'h',
  content: content,
  postedAt: '1m',
  createdAt: DateTime(2024),
  media: media,
);

Future<void> _pump(
  WidgetTester tester,
  Note note,
  InMemoryRelayClient client,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NoteContent(note: note, relayClient: client),
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    clearQuotedNoteCache();
    // No relays, so the post screen's own thread lookup finishes at once.
    selectedRelaysNotifier.value = const {};
    profileCacheNotifier.value = const {};
    loadNoteImagesNotifier.value = false;
  });

  testWidgets('a cited note is shown as a card in place of its reference', (
    tester,
  ) async {
    final client = InMemoryRelayClient([
      fakeEvent(id: _quotedId, content: 'the quoted words'),
    ]);

    await _pump(
      tester,
      _note('my take\n\nnostr:${_nevent(_quotedId)}\n\nmore'),
      client,
    );

    expect(find.byType(QuotedNote), findsOneWidget);
    expect(find.text('the quoted words'), findsOneWidget);
    expect(find.text('my take'), findsOneWidget);
    expect(find.text('more'), findsOneWidget);
    expect(find.textContaining('nevent1'), findsNothing);

    final take = tester.getTopLeft(find.text('my take')).dy;
    final card = tester.getTopLeft(find.byType(Card)).dy;
    final more = tester.getTopLeft(find.text('more')).dy;
    expect(take, lessThan(card));
    expect(card, lessThan(more));
  });

  testWidgets('the card shows the quoted author and opens the post', (
    tester,
  ) async {
    final client = InMemoryRelayClient([
      fakeEvent(id: _quotedId, pubkey: 'ee', content: 'the quoted words'),
      fakeEvent(
        id: 'f1',
        pubkey: 'ee',
        kind: 0,
        content: '{"name":"Quoted Person"}',
      ),
    ]);

    await _pump(tester, _note('nostr:${_nevent(_quotedId)}'), client);
    expect(find.text('Quoted Person'), findsOneWidget);

    await tester.tap(find.text('the quoted words'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(PostScreen), findsOneWidget);
  });

  testWidgets('a note that cannot be found stays a link', (tester) async {
    final nevent = _nevent(_quotedId);

    await _pump(tester, _note('look nostr:$nevent'), InMemoryRelayClient());

    expect(find.byType(Card), findsNothing);
    expect(
      find.textContaining(
        truncateMiddle(nevent, totalLength: 20, suffixLength: 5),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a note is looked up once however often it is cited', (
    tester,
  ) async {
    final client = InMemoryRelayClient([
      fakeEvent(id: _quotedId, content: 'the quoted words'),
    ]);
    final nevent = _nevent(_quotedId);

    await _pump(tester, _note('nostr:$nevent\nnostr:$nevent'), client);

    expect(find.byType(Card), findsOneWidget);
    expect(
      client.queries.where(
        (filter) => filter.ids?.contains(_quotedId) ?? false,
      ),
      hasLength(1),
    );
  });

  testWidgets('only the first few distinct citations become cards', (
    tester,
  ) async {
    final ids = [for (var i = 0; i < 5; i++) '${i + 1}' * 64];
    final client = InMemoryRelayClient([
      for (final id in ids) fakeEvent(id: id, content: 'quote $id'),
    ]);

    await _pump(
      tester,
      _note([for (final id in ids) 'nostr:${_nevent(id)}'].join('\n')),
      client,
    );

    expect(find.byType(Card), findsNWidgets(3));
    // The two left over share one block of text.
    expect(find.textContaining('nevent1'), findsOneWidget);
  });

  testWidgets('a quoted note shows its text and a media count, not media', (
    tester,
  ) async {
    const url = 'https://img.example.com/q.jpg';
    final client = InMemoryRelayClient([
      fakeEvent(id: _quotedId, content: 'pic $url'),
    ]);

    await _pump(tester, _note('nostr:${_nevent(_quotedId)}'), client);

    expect(find.text('pic'), findsOneWidget);
    expect(find.textContaining('https://'), findsNothing);
    expect(find.text('Contains 1 attachment'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a card comes before the note\'s own media', (tester) async {
    const url = 'https://img.example.com/own.jpg';
    final client = InMemoryRelayClient([
      fakeEvent(id: _otherId, content: 'the quoted words'),
    ]);

    await _pump(
      tester,
      _note(
        'look $url\nnostr:${_nevent(_otherId)}',
        media: [const NostrMedia(url: url)],
      ),
      client,
    );

    expect(find.text('Tap to load'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(Card)).dy,
      lessThan(tester.getTopLeft(find.text('Tap to load')).dy),
    );
  });
}
