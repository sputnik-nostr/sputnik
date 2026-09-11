import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'models/nostr_event.dart';
import 'models/nostr_filter.dart';
import 'relay_message_parser.dart';

final _random = Random();

const _firstResponseTimeout = Duration(seconds: 2);

const _maxSubscriptionDuration = Duration(seconds: 30);

const _maxEventsPerSubscription = 2000;

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
      final connection = await _connectionFor(relayUrl, timeout);
      return await connection.subscribe(filter, timeout);
    } catch (_) {
      // Relay is unreachable, or the persistent connection just failed;
      // drop it so the next query reconnects fresh.
      await _connections.remove(relayUrl)?.close();
      return const [];
    }
  }

  Future<_RelayConnection> _connectionFor(
    String relayUrl,
    Duration connectTimeout,
  ) async {
    final existing = _connections[relayUrl];
    if (existing != null && !existing.isClosed) return existing;

    final connection = _RelayConnection(relayUrl);
    _connections[relayUrl] = connection;
    await connection.ready.timeout(connectTimeout);
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

  final _handlers = <String, void Function(ParsedRelayMessage message)>{};
  final _completers = <String, Completer<void>>{};
  bool _closed = false;

  Future<void> _dispatchQueue = Future.value();

  bool get isClosed => _closed;

  void _handleMessage(dynamic raw) {
    if (raw is! String) return;

    final dispatched = _dispatchQueue.then((_) async {
      final parsed = await RelayMessageParser.instance.parse(raw);
      if (parsed == null) return;
      _handlers[parsed.subscriptionId]?.call(parsed);
    });
    _dispatchQueue = dispatched.catchError((Object _) {});
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
    var receivedAny = false;

    void resetIdleTimer() {
      idleTimer?.cancel();
      final duration = receivedAny
          ? timeout
          : (timeout < _firstResponseTimeout ? timeout : _firstResponseTimeout);
      idleTimer = Timer(duration, () {
        if (!completer.isCompleted) completer.complete();
      });
    }

    _handlers[subscriptionId] = (message) {
      receivedAny = true;
      resetIdleTimer();
      switch (message.type) {
        case 'EVENT':
          final event = message.event;
          if (event != null) events.add(event);
          if (events.length >= _maxEventsPerSubscription &&
              !completer.isCompleted) {
            completer.complete();
          }
        case 'EOSE':
        case 'CLOSED':
          if (!completer.isCompleted) completer.complete();
      }
    };
    _completers[subscriptionId] = completer;

    final overallTimer = Timer(
      timeout > _maxSubscriptionDuration ? timeout : _maxSubscriptionDuration,
      () {
        if (!completer.isCompleted) completer.complete();
      },
    );

    resetIdleTimer();

    try {
      _channel.sink.add(jsonEncode(['REQ', subscriptionId, filter.toJson()]));
      await completer.future;
    } finally {
      idleTimer?.cancel();
      overallTimer.cancel();
      _handlers.remove(subscriptionId);
      _completers.remove(subscriptionId);
    }

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
