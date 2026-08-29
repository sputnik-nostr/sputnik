import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';

final _random = Random();

String _generateSubscriptionId() {
  final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class RelayConnectionPool {
  RelayConnectionPool._();

  static final instance = RelayConnectionPool._();

  final _connections = <String, _RelayConnection>{};

  Future<List<NostrEvent>> query(
    Set<String> relayUrls,
    NostrFilter filter, {
    required Duration timeout,
  }) async {
    final eventsByRelay = await Future.wait(
      relayUrls.map((relayUrl) => _queryRelay(relayUrl, filter, timeout)),
    );

    final eventsById = <String, NostrEvent>{};
    for (final events in eventsByRelay) {
      for (final event in events) {
        eventsById[event.id] = event;
      }
    }
    return eventsById.values.toList();
  }

  Future<List<NostrEvent>> _queryRelay(
    String relayUrl,
    NostrFilter filter,
    Duration timeout,
  ) async {
    try {
      final connection = await _connectionFor(relayUrl);
      return await connection.subscribe(filter, timeout);
    } catch (_) {
      // Relay is unreachable, or the persistent connection just failed;
      // drop it so the next query reconnects fresh.
      await _connections.remove(relayUrl)?.close();
      return const [];
    }
  }

  Future<_RelayConnection> _connectionFor(String relayUrl) async {
    final existing = _connections[relayUrl];
    if (existing != null && !existing.isClosed) return existing;

    final connection = _RelayConnection(relayUrl);
    _connections[relayUrl] = connection;
    await connection.ready;
    return connection;
  }
}

class _RelayConnection {
  _RelayConnection(String relayUrl)
    : _channel = WebSocketChannel.connect(Uri.parse(relayUrl)) {
    ready = _channel.ready;
    _streamSubscription = _channel.stream.listen(
      _handleMessage,
      onError: (_) => _fail(),
      onDone: _fail,
    );
  }

  final WebSocketChannel _channel;
  late final Future<void> ready;
  late final StreamSubscription<dynamic> _streamSubscription;

  final _handlers = <String, void Function(dynamic message)>{};
  final _completers = <String, Completer<void>>{};
  bool _closed = false;

  bool get isClosed => _closed;

  void _handleMessage(dynamic raw) {
    final message = jsonDecode(raw as String);
    if (message is! List || message.length < 2) return;
    final subscriptionId = message[1];
    if (subscriptionId is! String) return;
    _handlers[subscriptionId]?.call(message);
  }

  void _fail() {
    _closed = true;
    for (final completer in _completers.values) {
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<List<NostrEvent>> subscribe(
    NostrFilter filter,
    Duration timeout,
  ) async {
    await ready;
    final subscriptionId = _generateSubscriptionId();
    final events = <NostrEvent>[];
    final completer = Completer<void>();
    Timer? idleTimer;

    void resetIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });
    }

    _handlers[subscriptionId] = (message) {
      resetIdleTimer();
      switch (message[0]) {
        case 'EVENT':
          events.add(NostrEvent.fromJson(message[2] as Map<String, dynamic>));
        case 'EOSE':
        case 'CLOSED':
          if (!completer.isCompleted) completer.complete();
      }
    };
    _completers[subscriptionId] = completer;

    resetIdleTimer();
    _channel.sink.add(jsonEncode(['REQ', subscriptionId, filter.toJson()]));

    await completer.future;
    idleTimer?.cancel();
    _handlers.remove(subscriptionId);
    _completers.remove(subscriptionId);
    if (!_closed) {
      _channel.sink.add(jsonEncode(['CLOSE', subscriptionId]));
    }

    return events;
  }

  Future<void> close() async {
    _closed = true;
    await _streamSubscription.cancel();
    await _channel.sink.close();
  }
}
