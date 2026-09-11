import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';

void main() {
  setUp(() {
    // Avoid HomeScreen's indefinite loading spinner, which would keep
    // pumpAndSettle spinning forever.
    notesNotifier.value = const [];
    identitiesNotifier.value = const [];
    activeIdentityPubkeyNotifier.value = null;
  });

  Future<void> openIdentitiesScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.byKey(const Key('profileAvatarButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settingsCard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identitiesCard')));
    await tester.pumpAndSettle();
  }

  testWidgets('generates a keypair and makes it the active identity', (
    tester,
  ) async {
    await openIdentitiesScreen(tester);

    expect(find.text('No identities yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('generateIdentityButton')));
    await tester.pumpAndSettle();

    expect(find.text('No identities yet'), findsNothing);
    expect(identitiesNotifier.value, hasLength(1));
    expect(
      activeIdentityPubkeyNotifier.value,
      identitiesNotifier.value.single.pubkeyHex,
    );
    expect(
      RegExp(r'^[0-9a-f]{64}$')
          .hasMatch(identitiesNotifier.value.single.privkeyHex),
      isTrue,
    );
  });

  testWidgets('deleting the active identity clears the active pointer', (
    tester,
  ) async {
    await openIdentitiesScreen(tester);

    await tester.tap(find.byKey(const Key('generateIdentityButton')));
    await tester.pumpAndSettle();
    expect(identitiesNotifier.value, hasLength(1));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(identitiesNotifier.value, isEmpty);
    expect(activeIdentityPubkeyNotifier.value, isNull);
    expect(find.text('No identities yet'), findsOneWidget);
  });

  const seckeyHex =
      '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';
  const nsec =
      'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5';

  testWidgets('imports an nsec and makes it the active identity', (
    tester,
  ) async {
    await openIdentitiesScreen(tester);

    await tester.tap(find.byKey(const Key('importIdentityButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), nsec);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(identitiesNotifier.value, hasLength(1));
    expect(identitiesNotifier.value.single.privkeyHex, seckeyHex);
    expect(
      activeIdentityPubkeyNotifier.value,
      identitiesNotifier.value.single.pubkeyHex,
    );
  });

  testWidgets('rejects a malformed nsec without adding an identity', (
    tester,
  ) async {
    await openIdentitiesScreen(tester);

    await tester.tap(find.byKey(const Key('importIdentityButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'not an nsec');
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid nsec key'), findsOneWidget);
    expect(identitiesNotifier.value, isEmpty);
  });

  testWidgets('rejects importing an already-imported identity', (tester) async {
    await openIdentitiesScreen(tester);

    await tester.tap(find.byKey(const Key('importIdentityButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), nsec);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(identitiesNotifier.value, hasLength(1));

    await tester.tap(find.byKey(const Key('importIdentityButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), nsec);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('This identity is already imported'), findsOneWidget);
    expect(identitiesNotifier.value, hasLength(1));
  });
}
