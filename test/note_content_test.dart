import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/models/nostr_media.dart';
import 'package:sputnik/screens/image_viewer_screen.dart';
import 'package:sputnik/screens/post_screen.dart';
import 'package:sputnik/widgets/linkified_text.dart';
import 'package:sputnik/widgets/media_frame.dart';
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

  testWidgets('several images scroll sideways while a lone one does not', (
    tester,
  ) async {
    final second = '${url}b.png';
    bool sideways(Widget w) =>
        w is SingleChildScrollView && w.scrollDirection == Axis.horizontal;

    await tester.pumpWidget(_host(_note(url, [NostrMedia(url: url)])));
    expect(find.byWidgetPredicate(sideways), findsNothing);

    await tester.pumpWidget(
      _host(
        _note('$url $second', [NostrMedia(url: url), NostrMedia(url: second)]),
      ),
    );
    expect(find.byWidgetPredicate(sideways), findsOneWidget);
  });

  testWidgets(
    'tapping an image opens the viewer on it, among the note images',
    (tester) async {
      loadNoteImagesNotifier.value = true;
      final second = '${url}b.png';
      await tester.pumpWidget(
        _host(
          _note('$url $second', [
            NostrMedia(url: url),
            NostrMedia(url: second),
          ]),
        ),
      );

      await tester.tap(find.byType(NetworkMediaImage).last);
      // The viewer's spinner never stops, so the route is pumped for a while.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final viewer = tester.widget<ImageViewerScreen>(
        find.byType(ImageViewerScreen),
      );
      expect(viewer.initialIndex, 1);
      expect(viewer.sources.map((s) => s.url), [url, second]);
    },
  );

  testWidgets(
    'on a narrow feed the next image peeks in, so the row shows it scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final second = '${url}b.png';
      final note = _note('$url $second', [
        NostrMedia(url: url),
        NostrMedia(url: second),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: [NoteTile(note: note)]),
          ),
        ),
      );

      final frames = find.byType(MediaFrame);
      // The first tile must not fill (or overflow) the row on its own.
      expect(tester.getRect(frames.at(0)).right, lessThan(400));
      expect(tester.getRect(frames.at(1)).left, lessThan(400));
    },
  );

  testWidgets('a blurhash stands in before the image loads, with no download', (
    tester,
  ) async {
    final media = NostrMedia(
      url: url,
      blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
    );
    await tester.pumpWidget(_host(_note(url, [media])));

    expect(find.byType(BlurHash), findsOneWidget);
    expect(find.text('Tap to load'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
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
