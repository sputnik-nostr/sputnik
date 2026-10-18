import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/app_state.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/models/nostr_metadata.dart';
import 'package:sputnik/nostr/relay_client.dart';
import 'package:sputnik/screens/compose_screen.dart';
import 'package:sputnik/screens/post_screen.dart';
import 'package:sputnik/screens/profile_screen.dart';
import 'package:sputnik/widgets/note_author_line.dart';
import 'package:sputnik/widgets/note_tile.dart';
import 'package:sputnik/widgets/profile_result_tile.dart';

import 'support/in_memory_relay_client.dart';
import 'support/no_replies.dart';

/// A name no relay should be trusted to keep short, ending in a letter that
/// must never be reached.
final _hostile = '${'A' * 5000}Z';

/// What is shown of it: the first 100 code units, and an ellipsis.
final _shown = '${'A' * 100}...';

final _pubkey = 'b' * 64;

Note _note({String name = 'Name', String content = 'hello', String? reposter}) {
  return Note(
    id: 'a' * 64,
    pubkey: _pubkey,
    displayName: name,
    content: content,
    createdAt: DateTime(2024),
    repostedByPubkey: reposter == null ? null : 'c' * 64,
    repostedByDisplayName: reposter,
    repostedAt: reposter == null ? null : DateTime(2024),
  );
}

/// The longest text, in code units, that any paragraph on screen holds: what
/// the engine is asked to lay out is bounded by this.
int _longestParagraph(WidgetTester tester) => tester.allRenderObjects
    .whereType<RenderParagraph>()
    .map((paragraph) => paragraph.text.toPlainText().length)
    .fold(0, max);

void main() {
  setUp(() {
    // No relays, so no lookup waits for an answer.
    selectedRelaysNotifier.value = const {};
    profileCacheNotifier.value = const {};
    notesNotifier.value = const [];
    loadNoteImagesNotifier.value = false;
    loadProfileImagesNotifier.value = false;
    autoVerifyNip05Notifier.value = false;
    RelayClient.instance = InMemoryRelayClient();
  });

  group('a display name', () {
    testWidgets('is cut in a feed row, and the row stays one line', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [NoteTile(note: _note(name: _hostile))],
            ),
          ),
        ),
      );

      final name = tester.widget<Text>(find.text(_shown));
      expect(name.maxLines, 1);
      expect(name.overflow, TextOverflow.ellipsis);
      expect(_longestParagraph(tester), lessThan(200));
    });

    testWidgets('is cut where a repost names who reposted', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [NoteTile(note: _note(reposter: _hostile))],
            ),
          ),
        ),
      );

      final line = tester.widget<Text>(find.text('$_shown reposted'));
      // A name this long does not fit beside the arrow, so it gives way.
      expect(line.maxLines, 1);
      expect(line.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
      expect(_longestParagraph(tester), lessThan(200));
    });

    testWidgets('is cut in the author line of a quote', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteAuthorLine(note: _note(name: _hostile)),
          ),
        ),
      );

      expect(find.text(_shown), findsOneWidget);
      expect(_longestParagraph(tester), lessThan(200));
    });

    testWidgets('is cut at the head of a post', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PostScreen(
            note: _note(name: _hostile),
            threadRepository: const NoReplies(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_shown), findsOneWidget);
      expect(_longestParagraph(tester), lessThan(200));
    });

    testWidgets('is cut at the head of a profile', (tester) async {
      profileCacheNotifier.value = {_pubkey: NostrMetadata(name: _hostile)};
      await tester.pumpWidget(
        MaterialApp(home: ProfileScreen(pubkeyHex: _pubkey)),
      );
      await tester.pumpAndSettle();

      expect(find.text(_shown), findsOneWidget);
      expect(_longestParagraph(tester), lessThan(200));
    });

    testWidgets('is cut in a list of people', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileResultTile(
              pubkeyHex: _pubkey,
              metadata: NostrMetadata(name: _hostile),
            ),
          ),
        ),
      );

      expect(find.text(_shown), findsOneWidget);
      expect(_longestParagraph(tester), lessThan(200));
    });

    testWidgets('is cut where a reply names who it answers', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ComposeScreen(replyTo: _note(name: _hostile)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining(_shown), findsOneWidget);
      expect(_longestParagraph(tester), lessThan(200));
    });

    testWidgets('is cut in a quote being composed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ComposeScreen(quoting: _note(name: _hostile)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_shown), findsOneWidget);
      expect(_longestParagraph(tester), lessThan(200));
    });

    testWidgets('that fits is shown whole', (tester) async {
      final fits = 'n' * 100;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [NoteTile(note: _note(name: fits))],
            ),
          ),
        ),
      );

      expect(find.text(fits), findsOneWidget);
    });

    testWidgets('is cut between letters, never through an emoji', (
      tester,
    ) async {
      // The emoji takes the 100th and 101st units, so it does not fit.
      final name = '${'n' * 99}\u{1F600}${'m' * 50}';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [NoteTile(note: _note(name: name))],
            ),
          ),
        ),
      );

      expect(find.text('${'n' * 99}...'), findsOneWidget);
    });
  });
}
