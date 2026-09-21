import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/models/nostr_media.dart';
import 'package:sputnik/screens/post_screen.dart';
import 'package:sputnik/widgets/linkified_text.dart';
import 'package:sputnik/widgets/note_content.dart';
import 'package:sputnik/widgets/note_tile.dart';

// The approved set lives for the whole session, so each test uses its own URL.
var _counter = 0;

String _freshUrl() => 'https://img$_counter.example.com/a.jpg';

Note _note(String content, List<NostrMedia> media) => Note(
  id: 'a' * 64,
  pubkey: 'b' * 64,
  displayName: 'Name',
  handle: 'h',
  content: content,
  postedAt: '1m',
  createdAt: DateTime(2024),
  media: media,
);

Widget _host(Note note) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(child: NoteContent(note: note)),
  ),
);

void main() {
  late String url;

  setUp(() {
    _counter++;
    url = _freshUrl();
    loadNoteImagesNotifier.value = false;
    selectedRelaysNotifier.value = const {};
  });

  testWidgets('tap to load shows a placeholder and fetches nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_note('look $url', [NostrMedia(url: url)])));

    expect(find.text('Tap to load'), findsOneWidget);
    expect(find.text('img$_counter.example.com'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the image URL is hidden from the text once it is shown', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_note('look $url', [NostrMedia(url: url)])));

    expect(find.textContaining('look'), findsOneWidget);
    expect(find.textContaining('https://'), findsNothing);
  });

  testWidgets('a note that is only an image has no empty text block', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_note(url, [NostrMedia(url: url)])));

    expect(find.byType(LinkifiedText), findsNothing);
    expect(find.text('Tap to load'), findsOneWidget);
  });

  testWidgets('tapping the placeholder loads the image', (tester) async {
    await tester.pumpWidget(_host(_note(url, [NostrMedia(url: url)])));

    await tester.tap(find.text('Tap to load'));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Tap to load'), findsNothing);
  });

  testWidgets('a tapped image stays loaded when the tile is rebuilt', (
    tester,
  ) async {
    final note = _note(url, [NostrMedia(url: url)]);
    await tester.pumpWidget(_host(note));
    await tester.tap(find.text('Tap to load'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host(note));

    expect(find.text('Tap to load'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('automatic loading needs no tap', (tester) async {
    loadNoteImagesNotifier.value = true;

    await tester.pumpWidget(_host(_note(url, [NostrMedia(url: url)])));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Tap to load'), findsNothing);
  });

  testWidgets('a failed load explains itself instead of leaving a gap', (
    tester,
  ) async {
    loadNoteImagesNotifier.value = true;

    // The test binding answers every HTTP request with an error.
    await tester.pumpWidget(_host(_note(url, [NostrMedia(url: url)])));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.textContaining('Could not load image'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the alt text labels the image for screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(_note(url, [NostrMedia(url: url, alt: 'A small cat')])),
    );

    // The label also carries the placeholder's own text.
    expect(find.bySemanticsLabel(RegExp('A small cat')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a declared size keeps the tile from resizing on load', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_note(url, [NostrMedia(url: url, width: 400, height: 200)])),
    );

    final size = tester.getSize(find.byType(AspectRatio));
    expect(size.width / size.height, closeTo(2, 0.01));
  });

  testWidgets('tapping an image in a feed row does not open the post', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteTile(note: _note(url, [NostrMedia(url: url)])),
        ),
      ),
    );

    await tester.tap(find.text('Tap to load'));
    await tester.pump();

    expect(find.byType(PostScreen), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });
}
