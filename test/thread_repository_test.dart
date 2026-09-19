import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';

import 'support/in_memory_relay_client.dart';
import 'support/no_reactions.dart';

DateTime _at(int minutes) =>
    DateTime.fromMillisecondsSinceEpoch(1700000000000 + minutes * 60000);

void main() {
  const relays = {'wss://r'};

  // root <- a <- b <- c, plus a sibling of b under a, and another reply to root.
  late NostrEvent root, a, b, c, sibling, other;
  late InMemoryRelayClient client;

  RelayThreadRepository repository() => RelayThreadRepository(
    client: client,
    reactionsRepository: const NoReactions(),
  );

  setUp(() {
    root = fakeEvent(id: '01', content: 'root', createdAt: _at(0));
    a = fakeEvent(
      id: '02',
      content: 'a',
      createdAt: _at(1),
      tags: [
        ['e', root.id, '', 'root'],
      ],
    );
    b = fakeEvent(
      id: '03',
      content: 'b',
      createdAt: _at(2),
      tags: [
        ['e', root.id, '', 'root'],
        ['e', a.id, '', 'reply'],
      ],
    );
    c = fakeEvent(
      id: '04',
      content: 'c',
      createdAt: _at(3),
      tags: [
        ['e', root.id, '', 'root'],
        ['e', b.id, '', 'reply'],
      ],
    );
    sibling = fakeEvent(
      id: '05',
      content: 'sibling',
      createdAt: _at(4),
      tags: [
        ['e', root.id, '', 'root'],
        ['e', a.id, '', 'reply'],
      ],
    );
    other = fakeEvent(
      id: '06',
      content: 'other',
      createdAt: _at(5),
      tags: [
        ['e', root.id, '', 'root'],
      ],
    );
    client = InMemoryRelayClient([root, a, b, c, sibling, other]);
  });

  List<String> contents(Iterable<NostrPost> posts) => [
    for (final post in posts) post.content,
  ];

  test('a top-level note has no ancestors and a nested reply tree', () async {
    final thread = await repository().fetchThread(root.id, relays);

    expect(thread.ancestors, isEmpty);
    expect(contents(thread.replies.map((r) => r.post)), [
      'a',
      'b',
      'c',
      'sibling',
      'other',
    ]);
    expect([for (final reply in thread.replies) reply.depth], [0, 1, 2, 1, 0]);
    expect(thread.directReplyCount, 2);
  });

  test('a reply lists its ancestors root first', () async {
    final thread = await repository().fetchThread(c.id, relays);

    expect(contents(thread.ancestors), ['root', 'a', 'b']);
    expect(thread.replies, isEmpty);
  });

  test('a middle reply shows only its own subtree', () async {
    final thread = await repository().fetchThread(b.id, relays);

    expect(contents(thread.ancestors), ['root', 'a']);
    expect(contents(thread.replies.map((r) => r.post)), ['c']);
  });

  test('stops climbing when an ancestor cannot be found', () async {
    client.events.remove(a);

    final thread = await repository().fetchThread(c.id, relays);

    expect(contents(thread.ancestors), ['b']);
  });

  test('includes replies the relays have not returned yet', () async {
    final mine = fakeEvent(
      id: '07',
      content: 'mine',
      createdAt: _at(9),
      tags: [
        ['e', root.id, '', 'root'],
        ['e', c.id, '', 'reply'],
      ],
    );

    final thread = await repository().fetchThread(
      c.id,
      relays,
      extraEvents: [mine],
    );

    expect(contents(thread.replies.map((r) => r.post)), ['mine']);
  });

  test(
    'a note that cites the viewed one only as a mention is not a reply',
    () async {
      client.events.add(
        fakeEvent(
          id: '08',
          content: 'mention',
          tags: [
            ['e', a.id, '', 'mention'],
          ],
        ),
      );

      final thread = await repository().fetchThread(a.id, relays);

      expect(contents(thread.replies.map((r) => r.post)), [
        'b',
        'c',
        'sibling',
      ]);
    },
  );

  test('replies in the deprecated positional scheme are threaded', () async {
    final legacy = fakeEvent(
      id: '09',
      content: 'legacy',
      createdAt: _at(6),
      tags: [
        ['e', root.id],
        ['e', a.id],
      ],
    );
    client.events.add(legacy);

    final thread = await repository().fetchThread(a.id, relays);

    expect(contents(thread.replies.map((r) => r.post)), contains('legacy'));
  });
}
