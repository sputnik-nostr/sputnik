import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/screens/image_viewer_screen.dart';
import 'package:sputnik/services/image_saver.dart';
import 'package:sputnik/services/media_loader.dart';

final _sources = [
  for (var i = 1; i <= 3; i++) MediaSource(url: 'https://a.example/$i.png'),
];

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

  testWidgets('saves the image on screen and says where it went', (
    tester,
  ) async {
    final saved = <String>[];
    await tester.pumpWidget(
      _viewer(
        index: 1,
        save: (source) async {
          saved.add(source.url);
          return const SaveResult(SaveOutcome.saved, '/home/me/2.png');
        },
      ),
    );

    await tester.tap(find.byKey(const Key('saveImageButton')));
    await tester.pump();
    await tester.pump();

    expect(saved, ['https://a.example/2.png']);
    expect(find.text('Saved to /home/me/2.png'), findsOneWidget);
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
