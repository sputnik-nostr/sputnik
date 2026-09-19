import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/screens/post_screen.dart';
import 'package:sputnik/widgets/note_tile.dart';

void main() {
  setUp(() => selectedRelaysNotifier.value = const {});

  final note = Note(
    id: 'a' * 64,
    pubkey: 'b' * 64,
    displayName: 'Name',
    handle: 'h',
    content: 'hello world text',
    postedAt: '1m',
    createdAt: DateTime(2024),
  );

  testWidgets('renders an avatar for a display name starting with an emoji', (
    tester,
  ) async {
    final emojiNote = note.copyWith(displayName: '\u{1F600} Name');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NoteTile(note: emojiNote)),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('\u{1F600}'), findsOneWidget);
  });

  for (final platform in [TargetPlatform.linux, TargetPlatform.android]) {
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      testWidgets('clicking the note text opens the post ($platform, $kind)', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: NoteTile(note: note)),
          ),
        );

        await tester.tap(find.text('hello world text'), kind: kind);
        await tester.pumpAndSettle();

        expect(find.byType(PostScreen), findsOneWidget);
        // The binding checks this before any tearDown runs.
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
