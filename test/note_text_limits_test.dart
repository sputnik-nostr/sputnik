import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/bech32.dart';
import 'package:sputnik/nostr/hex.dart';
import 'package:sputnik/nostr/models/nostr_media.dart';
import 'package:sputnik/nostr/relay_client.dart';
import 'package:sputnik/screens/post_screen.dart';
import 'package:sputnik/widgets/linkified_text.dart';
import 'package:sputnik/widgets/note_tile.dart';
import 'package:sputnik/widgets/quoted_note.dart';

import 'support/in_memory_relay_client.dart';
import 'support/no_replies.dart';

Note _note(String content, {List<NostrMedia> media = const []}) => Note(
  id: 'a' * 64,
  pubkey: 'b' * 64,
  displayName: 'Name',
  content: content,
  createdAt: DateTime(2024),
  media: media,
);

String _nevent(String id) => bech32Encode(
  'nevent',
  convertBits([0, 32, ...hexDecode(id)], 8, 5, pad: true),
);

Future<void> _pumpRow(WidgetTester tester, Note note) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ListView(children: [NoteTile(note: note)]),
    ),
  ),
);

Future<void> _pumpPost(WidgetTester tester, Note note) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PostScreen(note: note, threadRepository: const NoReplies()),
    ),
  );
  await tester.pumpAndSettle();
}

/// The text of each paragraph [LinkifiedText] lays out under [within].
List<String> _paragraphs(WidgetTester tester, {Finder? within}) {
  final texts = find.descendant(
    of: within ?? find.byType(Scaffold),
    matching: find.descendant(
      of: find.byType(LinkifiedText),
      matching: find.byType(RichText),
    ),
  );
  return [
    for (final rich in tester.widgetList<RichText>(texts))
      rich.text.toPlainText(),
  ];
}

int _tappableSpans(WidgetTester tester) {
  var count = 0;
  for (final rich in tester.widgetList<RichText>(
    find.descendant(
      of: find.byType(LinkifiedText),
      matching: find.byType(RichText),
    ),
  )) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) count++;
      return true;
    });
  }
  return count;
}

/// Compares text, saying where it differs rather than printing all of it.
void _expectText(String shown, String expected) {
  if (shown == expected) return;
  var at = 0;
  while (at < shown.length &&
      at < expected.length &&
      shown[at] == expected[at]) {
    at++;
  }
  fail(
    'Shown ${shown.length} code units, expected ${expected.length}; '
    'they first differ at $at.',
  );
}

void main() {
  setUp(() {
    clearQuotedNoteCache();
    // No relays, so the post screen's own thread lookup finishes at once.
    selectedRelaysNotifier.value = const {};
    profileCacheNotifier.value = const {};
    loadNoteImagesNotifier.value = false;
  });

  group('a row', () {
    final long = 'word ' * 4000;

    testWidgets('shows a long note cut short, with a way to read more', (
      tester,
    ) async {
      await _pumpRow(tester, _note(long));

      _expectText(_paragraphs(tester).single, '${long.substring(0, 8000)}...');
      expect(find.text('Show more'), findsOneWidget);
    });

    testWidgets('opens the post from the way to read more', (tester) async {
      // It is at the end of a long row, so give the row room.
      tester.view.physicalSize = const Size(800, 8000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpRow(tester, _note(long));

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();

      expect(find.byType(PostScreen), findsOneWidget);
    });

    testWidgets('shows a note that fits whole', (tester) async {
      final fits = 'word ' * 1600;
      await _pumpRow(tester, _note(fits));

      _expectText(_paragraphs(tester).single, fits);
      expect(find.text('Show more'), findsNothing);
    });

    testWidgets('counts the whole note against the limit, cited notes too', (
      tester,
    ) async {
      RelayClient.instance = InMemoryRelayClient();
      final nevent = _nevent('c' * 64);
      await _pumpRow(
        tester,
        _note('${'a ' * 2500}\nnostr:$nevent\n${'b ' * 5000}'),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final paragraphs = _paragraphs(tester);
      expect(paragraphs, hasLength(3));
      expect(paragraphs[0], ('a ' * 2500).trim());
      // The note was cut where 8,000 code units of it had been shown.
      final shown = paragraphs[0].length + paragraphs[2].length;
      expect(shown, lessThan(8000));
      expect(shown, greaterThan(8000 - 200));
      expect(paragraphs[2], endsWith('b...'));
      expect(find.text('Show more'), findsOneWidget);
    });

    testWidgets('puts the way to read more before the media', (tester) async {
      const url = 'https://img.example.com/long.jpg';
      await _pumpRow(
        tester,
        _note('$long\n$url', media: [NostrMedia(url: url)]),
      );

      expect(find.text('Show more'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Show more')).dy,
        lessThan(tester.getTopLeft(find.text('Tap to load')).dy),
      );
    });
  });

  group('the post screen', () {
    testWidgets('shows up to 10,000 code units, and says it cut', (
      tester,
    ) async {
      final long = 'word ' * 8000;
      await _pumpPost(tester, _note(long));

      _expectText(_paragraphs(tester).first, '${long.substring(0, 10000)}...');
      expect(
        find.text('This post is too long to display in full'),
        findsOneWidget,
      );
      expect(find.text('Show more'), findsNothing);
    });

    testWidgets('shows a post of up to that length whole', (tester) async {
      final fits = 'word ' * 2000;
      await _pumpPost(tester, _note(fits));

      _expectText(_paragraphs(tester).first, fits);
      expect(
        find.text('This post is too long to display in full'),
        findsNothing,
      );
      expect(find.text('Show more'), findsNothing);
    });

    testWidgets('lets 200 of its links be tapped, however many it holds', (
      tester,
    ) async {
      await _pumpPost(tester, _note('http://a.b ' * 2500));

      expect(_tappableSpans(tester), 200);
    });

    // Both of these fit in 32,000 code units and are among the slowest text
    // for the engine to lay out: most of a second for the whole of either, and
    // a fifth of that for the first 10,000 of it. So only a lower limit keeps
    // the screen quick.
    testWidgets('does not lay out one letter under thousands of marks', (
      tester,
    ) async {
      // The cluster is longer than the limit, and a cluster is not cut.
      await _pumpPost(tester, _note('a${'\u{301}' * 31995}'));

      expect(_paragraphs(tester), isEmpty);
      expect(
        find.text('This post is too long to display in full'),
        findsOneWidget,
      );
    });

    testWidgets('cuts text that changes direction at every letter', (
      tester,
    ) async {
      final text = 'a\u{628}' * 16000;
      await _pumpPost(tester, _note(text));

      _expectText(_paragraphs(tester).single, '${text.substring(0, 10000)}...');
      expect(
        find.text('This post is too long to display in full'),
        findsOneWidget,
      );
    });
  });

  group('a quoted note', () {
    Future<void> pumpQuote(WidgetTester tester, String content) async {
      RelayClient.instance = InMemoryRelayClient([
        fakeEvent(id: 'c' * 64, content: content),
      ]);
      await _pumpRow(tester, _note('nostr:${_nevent('c' * 64)}'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('is cut too, with a way to read more', (tester) async {
      final long = 'word ' * 4000;
      await pumpQuote(tester, long);

      final card = find.byType(QuotedNote);
      _expectText(
        _paragraphs(tester, within: card).single,
        // Without the space it ends with.
        '${long.substring(0, 8000).trimRight()}...',
      );
      expect(
        find.descendant(of: card, matching: find.text('Show more')),
        findsOneWidget,
      );
    });

    testWidgets('that fits needs no way to read more', (tester) async {
      await pumpQuote(tester, 'word ' * 1600);

      expect(find.byType(QuotedNote), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
    });
  });
}
