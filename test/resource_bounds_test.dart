import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/main.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/nostr/models/nostr_post.dart';
import 'package:sputnik/nostr/relay_thread_repository.dart';
import 'package:sputnik/screens/post_screen.dart';
import 'package:sputnik/widgets/fade_in_avatar.dart';
import 'package:sputnik/widgets/note_tile.dart';

class _StubThread extends RelayThreadRepository {
  const _StubThread(this.replies);

  final List<NostrPost> replies;

  @override
  Future<ThreadData> fetchThread(String postId, Set<String> relayUrls) async {
    return ThreadData(
      replies: replies,
      likerPubkeys: const [],
      reposterPubkeys: const [],
    );
  }
}

NostrPost _reply(String id, String body) {
  return NostrPost(
    id: id,
    author: const NostrAuthor(
      pubkey: 'cc',
      displayName: 'someone',
      handle: 'someone',
    ),
    content: body,
    createdAt: DateTime(2024),
  );
}

void main() {
  final hostileName = 'A' * 5000;

  setUp(() {
    notesNotifier.value = [
      Note(
        id: '1',
        pubkey: 'a' * 64,
        displayName: hostileName,
        handle: 'npub1...',
        content: 'hello',
        postedAt: '2m',
        createdAt: DateTime.now(),
      ),
    ];
  });

  testWidgets('an avatar decodes at its rendered size, not the source size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FadeInAvatar(
          imageUrl: 'https://example.com/huge.png',
          backgroundColor: Colors.grey,
          fallback: Text('A'),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final resize = image.image as ResizeImage;

    expect(resize.width, 120);
    expect(resize.height, 120);
    expect(resize.policy, ResizeImagePolicy.fit);
  });

  testWidgets('a hostile display name cannot grow a feed row', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();

    final name = tester.widget<Text>(find.text(hostileName).first);
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
  });

  group('post screen list', () {
    Future<void> pumpPost(WidgetTester tester, List<NostrPost> replies) async {
      selectedRelaysNotifier.value = const {};
      await tester.pumpWidget(
        MaterialApp(
          home: PostScreen(
            note: Note(
              id: 'root',
              pubkey: 'b' * 64,
              displayName: 'Root',
              handle: 'root',
              content: 'root post',
              postedAt: '2m',
              createdAt: DateTime(2024),
            ),
            threadRepository: _StubThread(replies),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders every reply exactly once', (tester) async {
      await pumpPost(tester, [
        _reply('r1', 'first reply'),
        _reply('r2', 'second reply'),
      ]);

      expect(find.byType(NoteTile), findsNWidgets(2));
      expect(find.text('first reply'), findsOneWidget);
      expect(find.text('second reply'), findsOneWidget);
      expect(find.text('No replies yet'), findsNothing);
    });

    testWidgets('shows the placeholder when there are no replies', (
      tester,
    ) async {
      await pumpPost(tester, const []);

      expect(find.byType(NoteTile), findsNothing);
      expect(find.text('No replies yet'), findsOneWidget);
    });
  });
}
