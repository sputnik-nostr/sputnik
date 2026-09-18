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
