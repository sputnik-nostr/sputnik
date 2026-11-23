import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/screens/image_viewer_screen.dart';
import 'package:sputnik/services/image_saver.dart';
import 'package:sputnik/services/media_loader.dart';

final _sources = [
  for (var i = 1; i <= 3; i++) MediaSource(url: 'https://a.example/$i.png'),
];

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

class _RealHttp extends HttpOverrides {}

// The test binding replaces every HttpClient with one that answers 400.
HttpClient _realClient() =>
    HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());

Future<SaveResult> _cancelled(MediaSource _) async {
  return const SaveResult(SaveOutcome.cancelled);
}

Widget _viewer({
  List<MediaSource>? sources,
  int index = 0,
  Future<SaveResult> Function(MediaSource)? save,
}) {
  return MaterialApp(
    home: ImageViewerScreen(
      sources: sources ?? _sources,
      initialIndex: index,
      save: save ?? _cancelled,
    ),
  );
}

// Images never finish loading here, so pump for time instead of settling.
Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

// Sockets and the image decoder move in real time, so give them some.
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

bool _saveOffered(WidgetTester tester) {
  final button = tester.widget<IconButton>(
    find.byKey(const Key('saveImageButton')),
  );
  return button.onPressed != null;
}

void main() {
  testWidgets('swipes and arrow keys move between images, with a counter', (
    tester,
  ) async {
    await tester.pumpWidget(_viewer(index: 1));
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await _pumpPage(tester);
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _pumpPage(tester);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('a lone image has no counter', (tester) async {
    await tester.pumpWidget(_viewer(sources: [_sources.first]));

    expect(find.textContaining('/'), findsNothing);
  });

  group('with images served from this machine', () {
    late HttpServer server;
    late String base;

    setUp(() async {
      replaceSharedImageClient(_realClient);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) {
        // Anything but the file called ok.png is not an image. The connection
        // is not kept, as an idle one would leave a timer pending.
        request.response
          ..persistentConnection = false
          ..add(
            request.uri.path == '/ok.png'
                ? _onePixelPng
                : utf8.encode('<html>not an image</html>'),
          )
          ..close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      replaceSharedImageClient(null);
    });

    // One picture under three names, to tell which of them was saved.
    List<MediaSource> pictures() => [
      for (final name in ['first', 'second', 'third'])
        MediaSource(url: '$base/ok.png?$name'),
    ];

    testWidgets('saves the image on screen and says where it went', (
      tester,
    ) async {
      final saved = <String>[];
      await tester.pumpWidget(
        _viewer(
          sources: pictures(),
          index: 1,
          save: (source) async {
            saved.add(source.url);
            return const SaveResult(SaveOutcome.saved, '/home/me/second.png');
          },
        ),
      );

      await _pumpUntil(tester, () => _saveOffered(tester));
      await tester.tap(find.byKey(const Key('saveImageButton')));
      await tester.pump();
      await tester.pump();

      expect(saved, ['$base/ok.png?second']);
      expect(find.text('Saved to /home/me/second.png'), findsOneWidget);
    });

    testWidgets('saves the image it was swiped to, not the one it opened on', (
      tester,
    ) async {
      final saved = <String>[];
      await tester.pumpWidget(
        _viewer(
          sources: pictures(),
          save: (source) async {
            saved.add(source.url);
            return const SaveResult(SaveOutcome.saved, '/home/me/ok.png');
          },
        ),
      );
      await _pumpUntil(tester, () => _saveOffered(tester));

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await _pumpPage(tester);
      expect(find.text('2 / 3'), findsOneWidget);
      await _pumpUntil(tester, () => _saveOffered(tester));
      await tester.tap(find.byKey(const Key('saveImageButton')));
      await tester.pump();
      await tester.pump();

      expect(saved, ['$base/ok.png?second']);
    });

    testWidgets('offers Save only once the image has decoded', (tester) async {
      await tester.pumpWidget(
        _viewer(sources: [MediaSource(url: '$base/ok.png')]),
      );

      expect(_saveOffered(tester), isFalse);

      await _pumpUntil(tester, () => _saveOffered(tester));
      expect(_saveOffered(tester), isTrue);
    });

    testWidgets('does not offer Save for bytes that are not an image', (
      tester,
    ) async {
      await tester.pumpWidget(
        _viewer(sources: [MediaSource(url: '$base/run.png')]),
      );

      await _pumpUntil(
        tester,
        () => find.byIcon(Icons.broken_image_outlined).evaluate().isNotEmpty,
      );
      await _pumpPage(tester);

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(_saveOffered(tester), isFalse);
    });

    testWidgets('decides for each image on its own', (tester) async {
      await tester.pumpWidget(
        _viewer(
          sources: [
            MediaSource(url: '$base/ok.png'),
            MediaSource(url: '$base/run.png'),
          ],
        ),
      );
      await _pumpUntil(tester, () => _saveOffered(tester));
      expect(_saveOffered(tester), isTrue);

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await _pumpUntil(
        tester,
        () => find.byIcon(Icons.broken_image_outlined).evaluate().isNotEmpty,
      );
      await _pumpPage(tester);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(_saveOffered(tester), isFalse);

      await tester.drag(find.byType(PageView), const Offset(500, 0));
      await _pumpPage(tester);
      expect(find.text('1 / 2'), findsOneWidget);
      await _pumpUntil(tester, () => _saveOffered(tester));
      expect(_saveOffered(tester), isTrue);
    });
  });

  testWidgets('copies the link of the image on screen', (tester) async {
    // Without a handler the platform call never answers and the test hangs.
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(_viewer(index: 2));

    await tester.tap(find.byKey(const Key('copyImageLinkButton')));
    await tester.pump();
    await tester.pump();

    expect(copied, ['https://a.example/3.png']);
    expect(find.text('Link copied'), findsOneWidget);
  });
}
