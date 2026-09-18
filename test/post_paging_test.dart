import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/post_cursor.dart';

import 'support/in_memory_relay_client.dart';

final _base = DateTime.fromMillisecondsSinceEpoch(1700000000000);

NostrEvent _note(
  int n, {
  String pubkey = 'aa',
  int secondsAgo = 0,
  bool reply = false,
}) => fakeEvent(
  id: n.toString().padLeft(64, '0'),
  pubkey: pubkey,
  content: 'note $n',
  createdAt: _base.subtract(Duration(seconds: secondsAgo)),
  tags: [
    if (reply) ['e', 'f' * 64, '', 'reply'],
  ],
);

RelayPostRepository _repository(InMemoryRelayClient client, {int limit = 3}) =>
    RelayPostRepository(
      relayUrls: const {'wss://r'},
      client: client,
      limit: limit,
    );

// Walks every page and returns their contents in order.
Future<List<List<String>>> _pages(
  RelayPostRepository repository, {
  List<String>? authors,
  bool includeReplies = true,
}) async {
  final pages = <List<String>>[];
  DateTime? until;
  do {
    final page = await repository.fetchPage(
      authors: authors,
      includeReplies: includeReplies,
      until: until,
    );
    pages.add([for (final post in page.posts) post.content]);
    until = page.next;
  } while (until != null && pages.length < 50);
  return pages;
}

void main() {
  group('fetchPage', () {
    test('walks back through every post exactly once', () async {
      final client = InMemoryRelayClient([
        for (var i = 0; i < 8; i++) _note(i, secondsAgo: i * 10),
      ]);

      final pages = await _pages(_repository(client));

      // A page starts at the previous page's last second, so a post can repeat.
      final seen = <String>[];
      for (final content in pages.expand((p) => p)) {
        if (!seen.contains(content)) seen.add(content);
      }
      expect(seen, [for (var i = 0; i < 8; i++) 'note $i']);
      expect(pages.first, hasLength(3));
    });

    test('says there is nothing older once a short page comes back', () async {
      final client = InMemoryRelayClient([_note(0), _note(1, secondsAgo: 5)]);

      final page = await _repository(client).fetchPage();

      expect(page.posts, hasLength(2));
      expect(page.next, isNull);
    });

    test('keeps going past a page that is only replies', () async {
      final client = InMemoryRelayClient([
        for (var i = 0; i < 12; i++) _note(i, secondsAgo: i * 10, reply: true),
        _note(20, secondsAgo: 200),
      ]);

      final pages = await _pages(_repository(client), includeReplies: false);

      expect(pages.expand((p) => p).toSet(), {'note 20'});
    });

    test('moves on when more posts share a second than fit a page', () async {
      final client = InMemoryRelayClient([
        for (var i = 0; i < 8; i++) _note(i, secondsAgo: 0),
        _note(50, secondsAgo: 30),
      ]);

      final pages = await _pages(_repository(client));

      // Same-second posts beyond a page can be skipped, but paging must end.
      expect(pages.length, lessThan(50));
      expect(pages.expand((p) => p), contains('note 50'));
    });

    test('pages across author chunks without skipping or reordering', () async {
      final authors = [
        for (var i = 0; i <= authorsChunkSize; i++)
          i.toString().padLeft(64, '0'),
      ];
      // The chunk holding the first author is dense; the other is sparse.
      final client = InMemoryRelayClient([
        for (var i = 0; i < 10; i++)
          _note(i, pubkey: authors.first, secondsAgo: i * 2),
        _note(100, pubkey: authors.last, secondsAgo: 7),
        _note(101, pubkey: authors.last, secondsAgo: 15),
      ]);

      final pages = await _pages(
        _repository(client, limit: 4),
        authors: authors,
      );
      final seen = <String>[];
      for (final content in pages.expand((p) => p)) {
        if (!seen.contains(content)) seen.add(content);
      }

      expect(seen, [
        'note 0', 'note 1', 'note 2', 'note 3', 'note 100', 'note 4', //
        'note 5', 'note 6', 'note 7', 'note 101', 'note 8', 'note 9',
      ]);
    });
  });

  test('a busy author of replies does not hide their older posts', () async {
    final authors = [
      for (var i = 0; i <= authorsChunkSize; i++) i.toString().padLeft(64, '0'),
    ];
    // Both chunks fill their query, but the first is nearly all replies.
    final client = InMemoryRelayClient([
      _note(0, pubkey: authors.first),
      for (var i = 1; i < 9; i++)
        _note(i, pubkey: authors.first, secondsAgo: i, reply: true),
      _note(10, pubkey: authors.first, secondsAgo: 10),
      for (var i = 0; i < 9; i++)
        _note(100 + i, pubkey: authors.last, secondsAgo: i * 50),
    ]);

    final pages = await _pages(
      _repository(client),
      authors: authors,
      includeReplies: false,
    );

    expect(pages.expand((p) => p), contains('note 10'));
  });

  group('PostCursor', () {
    test('returns only posts it has not returned before', () async {
      final client = InMemoryRelayClient([
        for (var i = 0; i < 7; i++) _note(i, secondsAgo: i * 10),
      ]);
      final repository = _repository(client);
      final cursor = PostCursor((until) => repository.fetchPage(until: until));

      final shown = [...await cursor.first()];
      expect(cursor.hasMore.value, isTrue);
      while (cursor.hasMore.value) {
        shown.addAll(await cursor.more());
      }

      expect(shown.map((p) => p.content), [
        for (var i = 0; i < 7; i++) 'note $i',
      ]);
      expect(await cursor.more(), isEmpty);
    });

    test('starting over forgets what it returned', () async {
      final client = InMemoryRelayClient([
        for (var i = 0; i < 5; i++) _note(i, secondsAgo: i * 10),
      ]);
      final repository = _repository(client);
      final cursor = PostCursor((until) => repository.fetchPage(until: until));

      await cursor.first();
      await cursor.more();
      final again = await cursor.first();

      expect(again.map((p) => p.content), ['note 0', 'note 1', 'note 2']);
      expect(cursor.hasMore.value, isTrue);
    });

    test('stops paging once it has a bounded number of posts', () async {
      final client = InMemoryRelayClient([
        for (var i = 0; i < maxCursorPosts + 500; i++)
          _note(i, secondsAgo: i * 10),
      ]);
      final repository = _repository(client, limit: 100);
      final cursor = PostCursor((until) => repository.fetchPage(until: until));

      var total = (await cursor.first()).length;
      while (cursor.hasMore.value) {
        total += (await cursor.more()).length;
      }

      // The bound is checked per page, so it can overshoot by up to one.
      expect(total, inInclusiveRange(maxCursorPosts, maxCursorPosts + 100));
    });
  });
}
