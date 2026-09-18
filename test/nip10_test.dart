import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';
import 'package:sputnik/nostr/models/nostr_post.dart';
import 'package:sputnik/nostr/nip10.dart';

NostrEvent _note(List<List<String>> tags) => NostrEvent(
  id: 'ff' * 32,
  pubkey: 'aa' * 32,
  createdAt: DateTime.now(),
  kind: 1,
  tags: tags,
  content: 'hi',
  sig: 'sig',
);

void main() {
  final root = '11' * 32;
  final parent = '22' * 32;
  final cited = '33' * 32;

  group('replyParentId', () {
    test('is null for a note with no e tags', () {
      expect(
        replyParentId(
          _note([
            ['p', 'aa' * 32],
            ['t', 'nostr'],
          ]),
        ),
        isNull,
      );
    });

    test('a lone root marker is a direct reply to the root', () {
      expect(
        replyParentId(
          _note([
            ['e', root, '', 'root'],
          ]),
        ),
        root,
      );
    });

    test('prefers the reply marker over the root marker', () {
      expect(
        replyParentId(
          _note([
            ['e', root, '', 'root'],
            ['e', parent, '', 'reply'],
          ]),
        ),
        parent,
      );
    });

    test('a mention marker alone does not make a reply', () {
      expect(
        replyParentId(
          _note([
            ['e', cited, '', 'mention'],
          ]),
        ),
        isNull,
      );
    });

    test('ignores a mention marker next to a real reply', () {
      expect(
        replyParentId(
          _note([
            ['e', cited, '', 'mention'],
            ['e', parent, '', 'reply'],
          ]),
        ),
        parent,
      );
    });

    test('unmarked e tags use the last one as the parent', () {
      expect(
        replyParentId(
          _note([
            ['e', root],
            ['e', cited],
            ['e', parent],
          ]),
        ),
        parent,
      );
    });

    test('lowercases the id', () {
      expect(
        replyParentId(
          _note([
            ['e', 'AB' * 32, '', 'reply'],
          ]),
        ),
        'ab' * 32,
      );
    });
  });

  group('threadRootId', () {
    test('is null for a note that is not a reply', () {
      expect(threadRootId(_note(const [])), isNull);
    });

    test('uses the root marker', () {
      expect(
        threadRootId(
          _note([
            ['e', root, '', 'root'],
            ['e', parent, '', 'reply'],
          ]),
        ),
        root,
      );
    });

    test('a lone reply marker is its own root', () {
      expect(
        threadRootId(
          _note([
            ['e', parent, '', 'reply'],
          ]),
        ),
        parent,
      );
    });

    test('unmarked e tags use the first one', () {
      expect(
        threadRootId(
          _note([
            ['e', root],
            ['e', cited],
            ['e', parent],
          ]),
        ),
        root,
      );
    });
  });

  group('replyTags', () {
    final author = 'aa' * 32;
    final other = 'bb' * 32;

    NostrEvent target(String id, List<List<String>> tags) => NostrEvent(
      id: id,
      pubkey: author,
      createdAt: DateTime.now(),
      kind: 1,
      tags: tags,
      content: 'hi',
      sig: 'sig',
    );

    test('a reply to a top-level note has a single root e tag', () {
      expect(replyTags(target(root, const [])), [
        ['e', root, '', 'root', author],
        ['p', author],
      ]);
    });

    test('a reply to a reply marks the root and the parent', () {
      final tags = replyTags(
        target(parent, [
          ['e', root, '', 'root'],
        ]),
      );

      expect(tags.take(2), [
        ['e', root, '', 'root'],
        ['e', parent, '', 'reply', author],
      ]);
    });

    test('carries the parent p tags after the parent author', () {
      final tags = replyTags(
        target(root, [
          ['p', other],
          ['p', author],
          ['p', 'not a pubkey'],
        ]),
      );

      expect(
        [
          for (final tag in tags)
            if (tag[0] == 'p') tag[1],
        ],
        [author, other],
      );
    });

    test('bounds how many people a reply mentions', () {
      final tags = replyTags(
        target(root, [
          for (var i = 0; i < 200; i++)
            ['p', i.toRadixString(16).padLeft(64, '0')],
        ]),
      );

      expect(tags.where((tag) => tag[0] == 'p').length, lessThanOrEqualTo(50));
      expect(tags.where((tag) => tag[0] == 'p').first[1], author);
    });
  });

  test('nostrPostFromEvent flags replies', () {
    expect(nostrPostFromEvent(_note(const [])).isReply, isFalse);
    expect(
      nostrPostFromEvent(
        _note([
          ['e', parent, '', 'reply'],
        ]),
      ).isReply,
      isTrue,
    );
  });
}
