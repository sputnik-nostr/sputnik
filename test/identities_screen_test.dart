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
}
