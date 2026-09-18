import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';
import 'package:sputnik/nostr/models/nostr_filter.dart';
import 'package:sputnik/nostr/relay_client.dart';
import 'package:sputnik/nostr/relay_post_repository.dart';

class _RecordingClient extends RelayClient {
  _RecordingClient(this.events);

  final List<NostrEvent> events;
  final filters = <NostrFilter>[];

  @override
  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter,
  ) async {
    filters.add(filter);
    return [
      for (final event in events)
        if (filter.authors?.contains(event.pubkey) ?? true) event,
    ];
  }
}

String _hex(int n) => n.toRadixString(16).padLeft(64, '0');

NostrEvent _note(
  int n,
  String pubkey, {
  int minutesAgo = 0,
  bool reply = false,
}) => NostrEvent(
  id: _hex(n + 1000),
  pubkey: pubkey,
  createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
  kind: 1,
  tags: [
    if (reply) ['e', _hex(9999), '', 'reply'],
  ],
  content: 'note $n',
  sig: 'sig',
);

void main() {
  group('leaving out replies', () {
    final author = _hex(1);

    RelayPostRepository repository(_RecordingClient client, {int limit = 3}) =>
        RelayPostRepository(
          relayUrls: const {'wss://r'},
          client: client,
          limit: limit,
        );

    test('drops replies from the author feed', () async {
      final client = _RecordingClient([
        _note(0, author, minutesAgo: 0),
        _note(1, author, minutesAgo: 1, reply: true),
        _note(2, author, minutesAgo: 2),
      ]);

      final posts = await repository(client)
          .fetchPostsByAuthors([author], includeReplies: false);

      expect(posts.map((p) => p.content), ['note 0', 'note 2']);
    });

    test('drops replies from the global feed', () async {
      final client = _RecordingClient([
        _note(0, author, minutesAgo: 0, reply: true),
        _note(1, author, minutesAgo: 1),
      ]);

      final posts = await repository(client).fetchPosts(includeReplies: false);

      expect(posts.map((p) => p.content), ['note 1']);
    });

    test('asks for extra so a page still fills up', () async {
      final client = _RecordingClient(const []);

      await repository(client)
          .fetchPostsByAuthors([author], includeReplies: false);
      await repository(client).fetchPostsByAuthors([author]);

      expect(client.filters.map((f) => f.limit), [9, 3]);
    });

    test('a mention marker alone is not a reply', () async {
      final mention = NostrEvent(
        id: _hex(5000),
        pubkey: author,
        createdAt: DateTime.now(),
        kind: 1,
        tags: [
          ['e', _hex(9999), '', 'mention'],
        ],
        content: 'cites another note',
        sig: 'sig',
      );
      final client = _RecordingClient([mention]);

      final posts = await repository(client).fetchPosts(includeReplies: false);

      expect(posts, hasLength(1));
    });

    test('keeps replies when asked to', () async {
      final client = _RecordingClient([_note(0, author, reply: true)]);

      final posts = await repository(client).fetchPostsByAuthors([author]);

      expect(posts, hasLength(1));
    });
  });

  test('fetchPostsByAuthors splits a large author list into chunks', () async {
    final authors = [for (var i = 1; i <= authorsChunkSize + 1; i++) _hex(i)];
    final client = _RecordingClient([
      _note(1, authors.first, minutesAgo: 5),
      _note(2, authors.last, minutesAgo: 1),
    ]);
    final repository = RelayPostRepository(
      relayUrls: const {'wss://r'},
      client: client,
    );

    final posts = await repository.fetchPostsByAuthors(authors);

    expect(client.filters, hasLength(2));
    expect(client.filters.map((f) => f.authors!.length), [authorsChunkSize, 1]);
    expect(posts.map((p) => p.content), ['note 2', 'note 1']);
  });

  test(
    'fetchPostsByAuthors keeps only the newest posts up to the limit',
    () async {
      final author = _hex(1);
      final client = _RecordingClient([
        for (var i = 0; i < 5; i++) _note(i, author, minutesAgo: i),
      ]);
      final repository = RelayPostRepository(
        relayUrls: const {'wss://r'},
        client: client,
        limit: 3,
      );

      final posts = await repository.fetchPostsByAuthors([author]);

      expect(posts.map((p) => p.content), ['note 0', 'note 1', 'note 2']);
    },
  );

  test('fetchPostsByAuthors does not query for an empty author list', () async {
    final client = _RecordingClient(const []);
    final repository = RelayPostRepository(
      relayUrls: const {'wss://r'},
      client: client,
    );

    expect(await repository.fetchPostsByAuthors(const []), isEmpty);
    expect(client.filters, isEmpty);
  });
}
