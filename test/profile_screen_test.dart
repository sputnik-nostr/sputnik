import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/screens/identities_screen.dart';
import 'package:sputnik/screens/profile_screen.dart';

void main() {
  setUp(() {
    identitiesNotifier.value = const [];
    activeIdentityPubkeyNotifier.value = null;
  });

  testWidgets('with no active identity, shows a prompt instead of a profile', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No identity yet'), findsOneWidget);
    expect(
      find.byKey(const Key('createIdentityFromProfileButton')),
      findsOneWidget,
    );
  });

  testWidgets('the prompt leads to the identities screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('createIdentityFromProfileButton')));
    await tester.pumpAndSettle();

    expect(find.byType(IdentitiesScreen), findsOneWidget);
  });
}
