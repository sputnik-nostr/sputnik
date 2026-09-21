import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/models/nostr_media.dart';
import 'package:sputnik/services/media_loader.dart';
import 'package:sputnik/services/video_store.dart';
import 'package:sputnik/widgets/note_content.dart';
import 'package:sputnik/widgets/note_video.dart';

typedef _OnProgress = void Function(int received, int? total);

class _FakeStore extends VideoStore {
  _FakeStore();

  final calls = <MediaSource>[];
  final cancellers = <DownloadCanceller?>[];
  final pending = <Completer<File>>[];
  _OnProgress? onProgress;

  @override
  Future<File> fetch(
    MediaSource source, {
    _OnProgress? onProgress,
    DownloadCanceller? canceller,
  }) {
    calls.add(source);
    cancellers.add(canceller);
    this.onProgress = onProgress;
    final completer = Completer<File>();
    pending.add(completer);
    return completer.future;
  }
}

const _url = 'https://cdn.example.com/clip.mp4';

Widget _tile(_FakeStore store, {NostrMedia? media}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: NoteVideoTile(
        media: media ?? const NostrMedia(url: _url, type: MediaType.video),
        authorPubkey: 'a' * 64,
        store: store,
        playerBuilder: (context, file) => Text('PLAYING ${file.path}'),
      ),
    ),
  ),
);

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

Widget _content(Note note) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(child: NoteContent(note: note)),
  ),
);

void main() {
  late _FakeStore store;

  setUp(() {
    store = _FakeStore();
    loadNoteImagesNotifier.value = false;
    selectedRelaysNotifier.value = const {};
  });

  group('NoteVideoTile', () {
    testWidgets('waits for a tap and downloads nothing before it', (
      tester,
    ) async {
      await tester.pumpWidget(_tile(store));

      expect(find.text('Tap to play'), findsOneWidget);
      expect(find.text('cdn.example.com'), findsOneWidget);
      expect(store.calls, isEmpty);
    });

    testWidgets('a tap downloads, then plays the file', (tester) async {
      await tester.pumpWidget(_tile(store));

      await tester.tap(find.text('Tap to play'));
      await tester.pump();
      expect(find.textContaining('Downloading'), findsOneWidget);
      expect(store.calls, hasLength(1));

      store.pending.single.complete(File('/tmp/clip.mp4'));
      await tester.pump();

      expect(find.text('PLAYING /tmp/clip.mp4'), findsOneWidget);
      expect(find.textContaining('Downloading'), findsNothing);
    });

    testWidgets('shows download progress', (tester) async {
      await tester.pumpWidget(_tile(store));
      await tester.tap(find.text('Tap to play'));
      await tester.pump();

      store.onProgress!(50, 200);
      await tester.pump();

      expect(find.textContaining('Downloading 25%'), findsOneWidget);
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.value, 0.25);
    });

    testWidgets('tapping while downloading cancels it', (tester) async {
      await tester.pumpWidget(_tile(store));
      await tester.tap(find.text('Tap to play'));
      await tester.pump();

      await tester.tap(find.textContaining('Downloading'));
      expect(store.cancellers.single!.cancelled, isTrue);
      store.pending.single.completeError(const DownloadCancelled());
      await tester.pump();

      expect(find.text('Tap to play'), findsOneWidget);
    });

    testWidgets('leaving the screen cancels a download in progress', (
      tester,
    ) async {
      await tester.pumpWidget(_tile(store));
      await tester.tap(find.text('Tap to play'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());

      expect(store.cancellers.single!.cancelled, isTrue);
      store.pending.single.completeError(const DownloadCancelled());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failure says so and a tap tries again', (tester) async {
      await tester.pumpWidget(_tile(store));
      await tester.tap(find.text('Tap to play'));
      await tester.pump();

      store.pending.single.completeError(const HttpException('nope'));
      await tester.pump();
      expect(find.textContaining('Could not load video'), findsOneWidget);
      expect(find.text('Open link'), findsOneWidget);

      await tester.tap(find.textContaining('Could not load video'));
      await tester.pump();
      expect(store.calls, hasLength(2));
      store.pending.last.complete(File('/tmp/clip.mp4'));
      await tester.pump();

      expect(find.text('PLAYING /tmp/clip.mp4'), findsOneWidget);
    });

    testWidgets('hands the hash and fallbacks to the download', (tester) async {
      final media = NostrMedia(
        url: _url,
        type: MediaType.video,
        sha256: 'ab' * 32,
        fallbackUrls: const ['https://mirror.example.com/clip.mp4'],
      );
      await tester.pumpWidget(_tile(store, media: media));

      await tester.tap(find.text('Tap to play'));
      await tester.pump();

      final source = store.calls.single;
      expect(source.url, _url);
      expect(source.sha256, 'ab' * 32);
      expect(source.fallbackUrls, ['https://mirror.example.com/clip.mp4']);
      expect(source.serverLookup, isNotNull);
    });
  });

  group('previews and playing order', () {
    Widget two() => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              for (final url in [_url, 'https://cdn.example.com/other.mp4'])
                NoteVideoTile(
                  media: NostrMedia(url: url, type: MediaType.video),
                  authorPubkey: 'a' * 64,
                  frameHeight: 150,
                  store: store,
                  playerBuilder: (context, file) =>
                      Text('PLAYING ${file.path}'),
                ),
            ],
          ),
        ),
      ),
    );

    testWidgets('starting one video stops the one that was playing', (
      tester,
    ) async {
      await tester.pumpWidget(two());
      await tester.tap(find.text('Tap to play').first);
      await tester.pump();
      store.pending[0].complete(File('/tmp/a.mp4'));
      await tester.pump();
      expect(find.text('PLAYING /tmp/a.mp4'), findsOneWidget);

      await tester.tap(find.text('Tap to play'));
      await tester.pump();

      expect(find.textContaining('PLAYING'), findsNothing);
      expect(find.text('Tap to play'), findsOneWidget);
      expect(find.textContaining('Downloading'), findsOneWidget);
    });

    testWidgets('it also cancels a download still in progress', (tester) async {
      await tester.pumpWidget(two());
      await tester.tap(find.text('Tap to play').first);
      await tester.pump();

      await tester.tap(find.text('Tap to play'));
      await tester.pump();

      expect(store.cancellers[0]!.cancelled, isTrue);
      expect(store.cancellers[1]!.cancelled, isFalse);
    });

    testWidgets('a poster loads only when images are allowed to', (
      tester,
    ) async {
      final media = NostrMedia(
        url: _url,
        type: MediaType.video,
        blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
        posterUrl: 'https://cdn.example.com/poster.jpg',
      );
      await tester.pumpWidget(_tile(store, media: media));

      // The blurhash needs no download, so it is there either way.
      expect(find.byType(BlurHash), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      loadNoteImagesNotifier.value = true;
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('videos in a note', () {
    const video = NostrMedia(url: _url, type: MediaType.video);

    testWidgets('show a play tile and hide their URL from the text', (
      tester,
    ) async {
      await tester.pumpWidget(_content(_note('watch $_url', [video])));

      expect(find.text('Tap to play'), findsOneWidget);
      expect(find.textContaining('https://'), findsNothing);
      expect(find.text('watch'), findsOneWidget);
    });

    testWidgets('still wait for a tap when images load automatically', (
      tester,
    ) async {
      loadNoteImagesNotifier.value = true;

      await tester.pumpWidget(_content(_note(_url, [video])));

      expect(find.text('Tap to play'), findsOneWidget);
      expect(find.byType(NoteVideoTile), findsOneWidget);
    });
  });
}
