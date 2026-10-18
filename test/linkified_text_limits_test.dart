import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/widgets/linkified_text.dart';

const _npub =
    'nostr:npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6';

Future<void> _pump(WidgetTester tester, String text) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: LinkifiedText(text))),
  ),
);

TextSpan _root(WidgetTester tester) =>
    tester.widget<RichText>(find.byType(RichText).first).text as TextSpan;

String _shown(WidgetTester tester) => _root(tester).toPlainText();

/// The spans that react to a tap, and where each starts in the shown text.
List<({int start, String text})> _links(WidgetTester tester) {
  final found = <({int start, String text})>[];
  var offset = 0;
  _root(tester).visitChildren((span) {
    if (span is TextSpan) {
      final text = span.text ?? '';
      if (span.recognizer != null) found.add((start: offset, text: text));
      offset += text.length;
    }
    return true;
  });
  return found;
}

/// How many nodes of the text's own semantics a screen reader can activate.
int _tappableNodes(WidgetTester tester) {
  var count = 0;
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().hasAction(SemanticsAction.tap)) count++;
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(find.byType(RichText).first));
  return count;
}

void main() {
  setUp(() {
    // No relays, so a lookup for a mention's name finishes at once.
    selectedRelaysNotifier.value = const {};
    profileCacheNotifier.value = const {};
  });

  group('links', () {
    // Ten characters, and a space after each.
    String links(int count) => List.filled(count, 'http://a.b').join(' ');

    testWidgets('are all tappable up to the limit', (tester) async {
      await _pump(tester, links(200));

      expect(_links(tester), hasLength(200));
    });

    testWidgets('past 200 in a paragraph stay plain text', (tester) async {
      await _pump(tester, links(700));

      final found = _links(tester);
      expect(found, hasLength(200));
      expect(found.last.start, 199 * 11);
      expect(_shown(tester), links(700), reason: 'the text is unchanged');
    });

    testWidgets('and mentions count together toward the limit', (tester) async {
      await _pump(tester, '${List.filled(90, _npub).join(' ')} ${links(150)}');

      final found = _links(tester);
      expect(found, hasLength(200));
      expect(found.where((link) => link.text.startsWith('@')), hasLength(90));
      expect(found.where((link) => link.text == 'http://a.b'), hasLength(110));
      // The 40 web links after the 200th read as they were written.
      final rest = _shown(tester)
          .substring(found.last.start + 'http://a.b'.length);
      expect(rest, ' ${links(40)}');
    });

    testWidgets('are not used up by entities that cannot be opened', (
      tester,
    ) async {
      // These stay plain text, so they take no recognizer.
      final plain = List.filled(300, 'nostr:naddr1abc').join(' ');
      await _pump(tester, '$plain ${links(150)}');

      expect(_links(tester), hasLength(150));
    });

    testWidgets('leave a screen reader 200 stops to step through', (
      tester,
    ) async {
      // Each link takes a node of its own in the tree a screen reader reads,
      // and building that tree takes time in proportion to their square.
      final handle = tester.ensureSemantics();
      await _pump(tester, links(3200));

      expect(_tappableNodes(tester), 200);
      handle.dispose();
    });
  });
}
