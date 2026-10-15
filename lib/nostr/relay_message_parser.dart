import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'models/nostr_event.dart';
import 'models/text_sanitizer.dart';

/// OK messages are attacker-controlled, so they are bounded and sanitized.
const _maxOkMessageLength = 300;

String? _sanitizedOkMessage(Object? raw) {
  if (raw is! String) return null;
  final truncated = raw.length > _maxOkMessageLength
      ? raw.substring(0, _maxOkMessageLength)
      : raw;
  return sanitizeUtf16(truncated);
}

/// Events dated further ahead than this are dropped, to tolerate clock drift.
const maxEventFutureSkew = Duration(hours: 1);

/// [event] is set for EVENT messages and [accepted] for OK messages.
class ParsedRelayMessage {
  const ParsedRelayMessage({
    required this.subscriptionId,
    required this.type,
    this.event,
    this.accepted,
    this.message,
  });

  final String subscriptionId;

  /// The message verb, e.g. `EVENT`, `EOSE` or `OK`.
  final String type;

  final NostrEvent? event;

  /// For OK messages, where [subscriptionId] is the acknowledged event.
  final bool? accepted;
  final String? message;
}

class _ParseRequest {
  const _ParseRequest(this.id, this.raw, this.subscriptionIds);

  final int id;
  final String raw;
  final Set<String>? subscriptionIds;
}

class _ParseResponse {
  const _ParseResponse(this.id, this.message);

  final int id;
  final ParsedRelayMessage? message;
}

ParsedRelayMessage? _parse(String raw, Set<String>? subscriptionIds) {
  try {
    final message = jsonDecode(raw);
    if (message is! List || message.length < 2) return null;

    final type = message[0];
    final subscriptionId = message[1];
    if (type is! String || subscriptionId is! String) return null;

    NostrEvent? event;
    bool? accepted;
    String? okMessage;
    if (type == 'EVENT' && message.length >= 3) {
      // Checked before the signature so unsolicited events cost no crypto.
      if (subscriptionIds != null &&
          !subscriptionIds.contains(subscriptionId)) {
        return null;
      }
      event = NostrEvent.fromJson(message[2] as Map<String, dynamic>);
      if (event.createdAt.isAfter(DateTime.now().add(maxEventFutureSkew))) {
        return null;
      }
    } else if (type == 'OK') {
      accepted = message.length >= 3 && message[2] == true;
      okMessage = _sanitizedOkMessage(message.length >= 4 ? message[3] : null);
    }
    return ParsedRelayMessage(
      subscriptionId: subscriptionId,
      type: type,
      event: event,
      accepted: accepted,
      message: okMessage,
    );
  } catch (_) {
    // Drop a bad payload rather than let it kill the parser isolate.
    return null;
  }
}

void _parserIsolateMain(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);
  receivePort.listen((dynamic data) {
    final request = data as _ParseRequest;
    mainSendPort.send(
      _ParseResponse(request.id, _parse(request.raw, request.subscriptionIds)),
    );
  });
}

/// Signature checks are CPU-bound; a few workers leave cores free.
final _workerCount = (Platform.numberOfProcessors - 1).clamp(1, 4);

class _Worker {
  _Worker(this.sendPort);

  final SendPort sendPort;
  final pending = <int, Completer<ParsedRelayMessage?>>{};
  bool exited = false;
}

/// Parses and verifies relay messages in a pool of background isolates.
class RelayMessageParser {
  RelayMessageParser._();

  static final instance = RelayMessageParser._();

  final _workers = List<Future<_Worker>?>.filled(_workerCount, null);
  int _nextWorker = 0;
  int _nextRequestId = 0;

  /// With [subscriptionIds], an EVENT for any other subscription is dropped.
  Future<ParsedRelayMessage?> parse(
    String raw, {
    Set<String>? subscriptionIds,
  }) async {
    final slot = _nextWorker++ % _workerCount;
    final spawning = _workers[slot] ??= _spawn(slot);
    final _Worker worker;
    try {
      worker = await spawning;
    } catch (_) {
      if (identical(_workers[slot], spawning)) _workers[slot] = null;
      rethrow;
    }
    if (worker.exited) return null;

    final id = _nextRequestId++;
    final completer = Completer<ParsedRelayMessage?>();
    worker.pending[id] = completer;
    worker.sendPort.send(_ParseRequest(id, raw, subscriptionIds));
    return completer.future;
  }

  Future<_Worker> _spawn(int slot) {
    final ready = Completer<_Worker>();
    final receivePort = ReceivePort();
    final exitPort = ReceivePort();
    _Worker? worker;

    void discard() {
      final current = worker;
      if (current != null) {
        current.exited = true;
        for (final completer in current.pending.values) {
          if (!completer.isCompleted) completer.complete(null);
        }
        current.pending.clear();
      }
      if (identical(_workers[slot], ready.future)) _workers[slot] = null;
      receivePort.close();
      exitPort.close();
    }

    exitPort.listen((dynamic _) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError('parser isolate exited before it was ready'),
        );
      }
      discard();
    });

    receivePort.listen((dynamic data) {
      if (data is SendPort) {
        ready.complete(worker = _Worker(data));
        return;
      }
      final response = data as _ParseResponse;
      worker?.pending.remove(response.id)?.complete(response.message);
    });

    Isolate.spawn(
      _parserIsolateMain,
      receivePort.sendPort,
      onExit: exitPort.sendPort,
      onError: exitPort.sendPort,
    ).then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        receivePort.close();
        exitPort.close();
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );

    return ready.future;
  }
}
