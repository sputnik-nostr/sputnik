import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/nostr/models/nostr_metadata.dart';
import 'package:sputnik/nostr/nip19.dart';
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

/// Compares the shown text, saying where it differs rather than printing it.
void _expectShown(WidgetTester tester, String expected) {
  final shown = _shown(tester);
  if (shown == expected) return;
  var at = 0;
  while (at < shown.length &&
      at < expected.length &&
      shown[at] == expected[at]) {
    at++;
  }
  fail(
    'Shown ${shown.length} code units, expected ${expected.length}; '
    'they first differ at $at.',
  );
}

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
      _expectShown(tester, links(700));
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

  group('long text', () {
    // The limit is 8,000 UTF-16 code units.
    const limit = 8000;

    testWidgets('up to the limit is shown as written', (tester) async {
      final text = 'word ' * 1600;
      await _pump(tester, text);

      expect(text.length, limit);
      _expectShown(tester, text);
    });

    testWidgets('past the limit is cut and ends with an ellipsis', (
      tester,
    ) async {
      final text = 'word ' * 20000;
      await _pump(tester, text);

      _expectShown(tester, '${text.substring(0, limit)}...');
    });

    testWidgets('that is a single word is cut as well', (tester) async {
      await _pump(tester, 'a' * 100000);

      _expectShown(tester, '${'a' * limit}...');
    });

    testWidgets('is never cut inside an emoji', (tester) async {
      // The emoji takes the 8,000th and 8,001st units, and so does not fit.
      await _pump(tester, '${'a' * (limit - 1)}\u{1F600}${'b' * 100}');

      _expectShown(tester, '${'a' * (limit - 1)}...');
    });

    testWidgets('keeps a letter together with its accent', (tester) async {
      await _pump(tester, '${'a' * (limit - 1)}e\u{301}${'b' * 100}');

      _expectShown(tester, '${'a' * (limit - 1)}...');
    });

    testWidgets('keeps an emoji together with its skin tone', (tester) async {
      await _pump(tester, '${'a' * (limit - 2)}\u{1F44D}\u{1F3FD}${'b' * 100}');

      _expectShown(tester, '${'a' * (limit - 2)}...');
    });

    testWidgets('that is one endless cluster leaves only the ellipsis', (
      tester,
    ) async {
      await _pump(tester, 'a${'\u{301}' * 50000}');

      expect(_shown(tester), '...');
    });

    testWidgets('does not make a link of an address that was cut', (
      tester,
    ) async {
      final text = '${'x ' * 3990}https://example.com/${'a' * 200}';
      await _pump(tester, text);

      _expectShown(tester, '${text.substring(0, limit)}...');
      expect(_links(tester), isEmpty);
    });

    testWidgets('keeps the links the cut leaves whole', (tester) async {
      await _pump(tester, 'https://example.com/a ${'x ' * 10000}');

      final found = _links(tester);
      expect(found, hasLength(1));
      expect(found.single.text, 'https://example.com/a');
    });

    testWidgets('can be limited further, or not at all', (tester) async {
      Future<String> shownWith(int maxLength) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: LinkifiedText('a' * 90, maxLength: maxLength)),
          ),
        );
        return _shown(tester);
      }

      expect(await shownWith(40), '${'a' * 40}...');
      expect(await shownWith(90), 'a' * 90);
    });

    testWidgets('that the caller cut ends with an ellipsis too', (
      tester,
    ) async {
      Future<void> pump({required bool truncated}) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LinkifiedText('half a sentence', truncated: truncated),
          ),
        ),
      );

      await pump(truncated: false);
      expect(_shown(tester), 'half a sentence');

      await pump(truncated: true);
      expect(_shown(tester), 'half a sentence...');
    });

    testWidgets('is cut again when the text or the limit changes', (
      tester,
    ) async {
      Future<void> pump(String text, {int maxLength = limit}) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: LinkifiedText(text, maxLength: maxLength)),
            ),
          );

      await pump('a' * 20000);
      _expectShown(tester, '${'a' * limit}...');

      await pump('b' * 20000);
      _expectShown(tester, '${'b' * limit}...');

      await pump('b' * 20000, maxLength: 10);
      expect(_shown(tester), '${'b' * 10}...');

      await pump('short');
      expect(_shown(tester), 'short');
    });

    testWidgets('a mention is not named with half an emoji', (tester) async {
      final pubkey = hexFromNpub(_npub.substring('nostr:'.length))!;
      profileCacheNotifier.value = {
        pubkey: NostrMetadata(name: '${'a' * 36}\u{1F600}${'b' * 50}'),
      };

      await _pump(tester, _npub);

      expect(_shown(tester), '@${'a' * 36}...');
    });

    testWidgets('costs about the same as a short note, whatever it holds', (
      tester,
    ) async {
      // Text that keeps switching direction takes the engine ten seconds to
      // lay out at this length, and a few tenths of one at most once it is
      // cut. The bound is far from both: it only tells if the cut was made.
      final text = 'a\u{628}' * 45000;
      final watch = Stopwatch()..start();
      await _pump(tester, text);
      watch.stop();

      _expectShown(tester, '${text.substring(0, limit)}...');
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });
}
