import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/services/media_loader.dart';
import 'package:sputnik/widgets/fade_in_avatar.dart';

void main() {
  Future<void> pumpAvatar(
    WidgetTester tester, {
    String imageUrl = 'https://example.com/pic.png',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FadeInAvatar(
          imageUrl: imageUrl,
          backgroundColor: Colors.blue,
          fallback: const Text('A'),
        ),
      ),
    );
  }

  testWidgets('does not build an Image when media loading is off', (
    tester,
  ) async {
    loadMediaNotifier.value = false;
    await pumpAvatar(tester);
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('no image URL means no Image regardless of the setting', (
    tester,
  ) async {
    loadMediaNotifier.value = true;
    await tester.pumpWidget(
      const MaterialApp(
        home: FadeInAvatar(
          imageUrl: null,
          backgroundColor: Colors.blue,
          fallback: Text('A'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
  });

  testWidgets('loads through the size-capped provider', (tester) async {
    loadMediaNotifier.value = true;
    await pumpAvatar(tester);

    final image = tester.widget<Image>(find.byType(Image)).image;
    expect(image, isA<ResizeImage>());
    expect((image as ResizeImage).imageProvider, isA<BoundedNetworkImage>());
  });

  testWidgets('never fetches a plain http picture', (tester) async {
    loadMediaNotifier.value = true;
    await pumpAvatar(tester, imageUrl: 'http://example.com/pic.png');

    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });
}
