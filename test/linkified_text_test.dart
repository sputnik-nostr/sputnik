import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/widgets/linkified_text.dart';

const _npub =
    'nostr:npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6';
const _otherNpub =
    'nostr:npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg';

class _Pushes extends NavigatorObserver {
  int count = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => count++;
}

class _Host extends StatefulWidget {
  const _Host({super.key, required this.text});

  final String text;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  var _generation = 0;

  void rebuild() => setState(() => _generation++);

  @override
  Widget build(BuildContext context) {
    return LinkifiedText(
      widget.text,
      style: TextStyle(fontSize: 14 + _generation * 0.0),
    );
  }
}

void main() {
  Future<int> tapLink(
    WidgetTester tester, {
    required bool rebuildMidGesture,
  }) async {
    final observer = _Pushes();
    final key = GlobalKey<_HostState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: _Host(key: key, text: _npub),
        ),
      ),
    );
    observer.count = 0;

    final target =
        tester.getTopLeft(find.byType(RichText).first) + const Offset(8, 8);
    final gesture = await tester.startGesture(target);
    if (rebuildMidGesture) {
      key.currentState!.rebuild();
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    return observer.count;
  }

  testWidgets('a link opens when nothing interrupts the gesture', (
    tester,
  ) async {
    expect(await tapLink(tester, rebuildMidGesture: false), 1);
  });

  testWidgets('a link still opens when a rebuild lands mid-gesture', (
    tester,
  ) async {
    expect(await tapLink(tester, rebuildMidGesture: true), 1);
  });

  testWidgets('a link introduced by new text is tappable', (tester) async {
    final observer = _Pushes();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const Scaffold(body: _Host(text: _npub)),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const Scaffold(body: _Host(text: _otherNpub)),
      ),
    );
    observer.count = 0;

    await tester.tapAt(
      tester.getTopLeft(find.byType(RichText).first) + const Offset(8, 8),
    );
    await tester.pump();

    expect(observer.count, 1);
  });

  testWidgets('a link that cannot be opened says so', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: _Host(text: 'https://example.com/thing')),
      ),
    );

    final spot =
        tester.getTopLeft(find.byType(RichText).first) + const Offset(8, 8);
    await tester.runAsync(() async {
      await tester.tapAt(spot);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('Could not open this link'), findsOneWidget);
  });

  testWidgets('a link removed by new text stops responding', (tester) async {
    final observer = _Pushes();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const Scaffold(body: _Host(text: _npub)),
      ),
    );
    final spot =
        tester.getTopLeft(find.byType(RichText).first) + const Offset(8, 8);

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const Scaffold(body: _Host(text: 'no links here at all')),
      ),
    );
    observer.count = 0;

    await tester.tapAt(spot);
    await tester.pump();

    expect(observer.count, 0);
  });
}
