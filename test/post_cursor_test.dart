import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/post_cursor.dart';

NostrPost _post(String id) => NostrPost(
  id: id,
  authorPubkey: 'aa' * 32,
  content: id,
  createdAt: DateTime(2024),
);

void main() {
  group('invalidate', () {
    test('a start in flight returns null', () async {
      final page = Completer<PostPage>();
      final cursor = PostCursor((until) => page.future);

      final start = cursor.first();
      cursor.invalidate();
      page.complete(PostPage([_post('1')], DateTime(2023)));

      expect(await start, isNull);
      expect(cursor.hasMore.value, isFalse);
    });

    test('a load of older posts in flight returns nothing', () async {
      final pages = [Completer<PostPage>(), Completer<PostPage>()];
      var calls = 0;
      final cursor = PostCursor((until) => pages[calls++].future);
      final start = cursor.first();
      pages[0].complete(PostPage([_post('1')], DateTime(2023)));
      await start;
      expect(cursor.hasMore.value, isTrue);

      final more = cursor.more();
      cursor.invalidate();
      pages[1].complete(PostPage([_post('2')], null));

      expect(await more, isEmpty);
      expect(cursor.hasMore.value, isFalse);
    });

    test('forgets the position', () async {
      var calls = 0;
      final cursor = PostCursor((until) async {
        calls++;
        return PostPage([_post('1')], DateTime(2023));
      });
      await cursor.first();
      expect(cursor.hasMore.value, isTrue);

      cursor.invalidate();
      calls = 0;

      expect(cursor.hasMore.value, isFalse);
      expect(await cursor.more(), isEmpty);
      expect(calls, 0, reason: 'there is nothing older to ask for');
      expect([for (final post in (await cursor.first())!) post.id], ['1']);
    });

    test('lets a load that starts afterwards through', () async {
      final pages = [Completer<PostPage>(), Completer<PostPage>()];
      var calls = 0;
      final cursor = PostCursor((until) => pages[calls++].future);

      final before = cursor.first();
      cursor.invalidate();
      final after = cursor.first();
      pages[1].complete(PostPage([_post('2')], null));
      pages[0].complete(PostPage([_post('1')], null));

      expect(await before, isNull);
      expect([for (final post in (await after)!) post.id], ['2']);
    });
  });
}
