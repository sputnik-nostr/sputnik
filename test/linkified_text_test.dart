import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/nostr/bech32.dart';
import 'package:sputnik/nostr/hex.dart';
import 'package:sputnik/nostr/models/nostr_metadata.dart';
import 'package:sputnik/nostr/nip19.dart';
import 'package:sputnik/screens/post_screen.dart';
import 'package:sputnik/widgets/linkified_text.dart';

import 'support/in_memory_relay_client.dart';

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

NostrMetadata _profile(String content) => NostrMetadata.fromContent(content);

String get _hex => hexFromNpub(_npub.substring('nostr:'.length))!;

Future<void> _pumpText(WidgetTester tester, String text) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: LinkifiedText(text))));

// The text of the whole rich text, as shown.
String _shown(WidgetTester tester) =>
    tester.widget<RichText>(find.byType(RichText).first).text.toPlainText();

void main() {
  setUp(() {
    // No relays, so a lookup for a missing name finishes at once.
    selectedRelaysNotifier.value = const {};
    profileCacheNotifier.value = const {};
  });

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

  group('mentions', () {
    testWidgets('a cited npub shows the profile name instead', (tester) async {
      profileCacheNotifier.value = {_hex: _profile('{"display_name":"Alice"}')};

      await _pumpText(tester, 'thanks $_npub for this');

      expect(_shown(tester), 'thanks @Alice for this');
    });

    testWidgets('a bare npub is a mention too', (tester) async {
      profileCacheNotifier.value = {_hex: _profile('{"name":"alice"}')};

      await _pumpText(tester, 'cc ${_npub.substring('nostr:'.length)}.');

      expect(_shown(tester), 'cc @alice.');
    });

    testWidgets('an nprofile shows the name too', (tester) async {
      const nprofile =
          'nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p';
      profileCacheNotifier.value = {
        hexFromNprofile(nprofile)!: _profile('{"name":"alice"}'),
      };

      await _pumpText(tester, 'nostr:$nprofile');

      expect(_shown(tester), '@alice');
    });

    testWidgets('without a known name it shows a short npub', (tester) async {
      await _pumpText(tester, 'hi $_npub');

      final npub = _npub.substring('nostr:'.length);
      expect(_shown(tester), 'hi @${truncateNpub(npub)}');
    });

    testWidgets('the name appears once the profile is cached', (tester) async {
      await _pumpText(tester, 'hi $_npub');

      profileCacheNotifier.value = {_hex: _profile('{"name":"alice"}')};
      await tester.pump();

      expect(_shown(tester), 'hi @alice');
    });

    testWidgets('a long, multi-line name is kept to one short line', (
      tester,
    ) async {
      final name = 'x' * 100;
      profileCacheNotifier.value = {
        _hex: _profile('{"name":"line one\\n\\nline two $name"}'),
      };

      await _pumpText(tester, _npub);

      final shown = _shown(tester);
      expect(shown, startsWith('@line one line two '));
      expect(shown.length, lessThanOrEqualTo(41));
      expect(shown, endsWith('...'));
    });

    testWidgets('tapping the name opens the profile', (tester) async {
      final observer = _Pushes();
      profileCacheNotifier.value = {_hex: _profile('{"name":"alice"}')};

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: Scaffold(body: LinkifiedText(_npub)),
        ),
      );
      observer.count = 0;
      await tester.tapAt(
        tester.getTopLeft(find.byType(RichText).first) + const Offset(8, 8),
      );
      await tester.pump();

      expect(observer.count, 1);
    });

    testWidgets('an npub inside a web address is left alone', (tester) async {
      final url = 'https://example.com/${_npub.substring('nostr:'.length)}';

      await _pumpText(tester, url);

      expect(_shown(tester), url);
    });
  });

  group('cited notes', () {
    final noteId = 'c' * 64;
    final note = noteFromHex(noteId);
    final nevent = bech32Encode(
      'nevent',
      convertBits([0, 32, ...hexDecode(noteId)], 8, 5, pad: true),
    );

    testWidgets('a cited note is shortened but keeps its link', (tester) async {
      await _pumpText(tester, 'see nostr:$note');

      expect(
        _shown(tester),
        'see ${truncateMiddle(note, totalLength: 20, suffixLength: 5)}',
      );
    });

    testWidgets('a bare note id and an nevent are citations too', (
      tester,
    ) async {
      await _pumpText(tester, '$note and nostr:$nevent');

      expect(
        _shown(tester),
        '${truncateMiddle(note, totalLength: 20, suffixLength: 5)} and '
        '${truncateMiddle(nevent, totalLength: 20, suffixLength: 5)}',
      );
    });

    testWidgets('ordinary words that start like a note id stay text', (
      tester,
    ) async {
      await _pumpText(tester, 'note1 is not one, nor is event1abc');

      expect(_shown(tester), 'note1 is not one, nor is event1abc');
    });

    Future<void> tapCitation(
      WidgetTester tester,
      String text,
      InMemoryRelayClient client,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LinkifiedText(text, relayClient: client)),
        ),
      );
      await tester.tapAt(
        tester.getTopLeft(find.byType(RichText).first) + const Offset(8, 8),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('tapping a cited note opens that post', (tester) async {
      final client = InMemoryRelayClient([
        fakeEvent(id: noteId, content: 'the cited post'),
      ]);

      await tapCitation(tester, 'nostr:$note', client);

      expect(find.byType(PostScreen), findsOneWidget);
      expect(find.text('the cited post'), findsWidgets);
    });

    testWidgets('an nevent opens the post as well', (tester) async {
      final client = InMemoryRelayClient([
        fakeEvent(id: noteId, content: 'the cited post'),
      ]);

      await tapCitation(tester, nevent, client);

      expect(find.byType(PostScreen), findsOneWidget);
    });

    testWidgets('a cited note that cannot be found says so', (tester) async {
      await tapCitation(tester, 'nostr:$note', InMemoryRelayClient());

      expect(find.byType(PostScreen), findsNothing);
      expect(find.text('Note not found'), findsOneWidget);
    });
  });

  group('web links stop where the URL stops', () {
    List<String> linkTexts(WidgetTester tester) {
      final root = tester.widget<RichText>(find.byType(RichText).first).text;
      final found = <String>[];
      root.visitChildren((span) {
        if (span is TextSpan && span.recognizer != null) {
          found.add(span.text ?? '');
        }
        return true;
      });
      return found;
    }

    Future<void> expectLinks(
      WidgetTester tester,
      String text,
      List<String> links,
    ) async {
      await _pumpText(tester, text);
      expect(linkTexts(tester), links, reason: text);
      expect(_shown(tester), text, reason: 'the text itself is unchanged');
    }

    testWidgets('a sentence-ending period is not part of the link', (
      tester,
    ) async {
      await expectLinks(tester, 'see https://example.com/a.', [
        'https://example.com/a',
      ]);
    });

    testWidgets('other trailing punctuation is left out too', (tester) async {
      await expectLinks(tester, 'wow https://example.com/a?b=1, ok', [
        'https://example.com/a?b=1',
      ]);
      await expectLinks(tester, 'https://example.com!!!', [
        'https://example.com',
      ]);
      await expectLinks(tester, 'why https://example.com/x?', [
        'https://example.com/x',
      ]);
    });

    testWidgets('a closing bracket is left out unless the URL opened it', (
      tester,
    ) async {
      await expectLinks(tester, '(see https://example.com/a)', [
        'https://example.com/a',
      ]);
      await expectLinks(
        tester,
        'https://en.wikipedia.org/wiki/Nostr_(protocol)',
        ['https://en.wikipedia.org/wiki/Nostr_(protocol)'],
      );
      await expectLinks(tester, '(https://en.wikipedia.org/wiki/A_(b)).', [
        'https://en.wikipedia.org/wiki/A_(b)',
      ]);
    });

    testWidgets('quotes and angle brackets around a URL are not in it', (
      tester,
    ) async {
      await expectLinks(tester, '<https://example.com/x>', [
        'https://example.com/x',
      ]);
      await expectLinks(tester, 'say "https://example.com/x" now', [
        'https://example.com/x',
      ]);
    });

    testWidgets('punctuation that leaves no host is not a link', (
      tester,
    ) async {
      await expectLinks(tester, 'https://.', const []);
    });
  });
}
