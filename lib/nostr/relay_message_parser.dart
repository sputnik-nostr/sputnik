import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'models/nostr_event.dart';
import 'models/text_sanitizer.dart';

/// OK messages are attacker-controlled, so sanitize/bound them like any
/// other untrusted relay text.
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

/// A relay message that passed validation. [event] is set for EVENT messages
/// and [accepted] for OK messages.
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

  /// Only set for OK messages, where [subscriptionId] is the event ID being
  /// acknowledged.
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
    // Malformed or unexpected message from the relay; drop it rather than
    // letting a bad payload take down the parser isolate.
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

/// Parses and verifies relay messages in a background isolate.
class RelayMessageParser {
  RelayMessageParser._();

  static final instance = RelayMessageParser._();

  SendPort? _workerSendPort;
  Future<void>? _spawning;
  int _nextRequestId = 0;
  final _pending = <int, Completer<ParsedRelayMessage?>>{};

  /// With [subscriptionIds], an EVENT for any other subscription is dropped.
  Future<ParsedRelayMessage?> parse(
    String raw, {
    Set<String>? subscriptionIds,
  }) async {
    if (_workerSendPort == null) {
      final spawning = _spawning ??= _spawn();
      try {
        await spawning;
      } catch (_) {
        if (identical(_spawning, spawning)) _spawning = null;
        rethrow;
      }
    }

    final id = _nextRequestId++;
    final completer = Completer<ParsedRelayMessage?>();
    _pending[id] = completer;
    _workerSendPort!.send(_ParseRequest(id, raw, subscriptionIds));
    return completer.future;
  }

  Future<void> _spawn() async {
    final receivePort = ReceivePort();
    final exitPort = ReceivePort();
    final sendPortCompleter = Completer<SendPort>();

    void discardWorker() {
      _workerSendPort = null;
      _spawning = null;
      for (final completer in _pending.values) {
        if (!completer.isCompleted) completer.complete(null);
      }
      _pending.clear();
      receivePort.close();
      exitPort.close();
    }

    exitPort.listen((dynamic _) {
      if (!sendPortCompleter.isCompleted) {
        sendPortCompleter.completeError(
          StateError('parser isolate exited before it was ready'),
        );
      }
      discardWorker();
    });

    try {
      await Isolate.spawn(
        _parserIsolateMain,
        receivePort.sendPort,
        onExit: exitPort.sendPort,
        onError: exitPort.sendPort,
      );
    } catch (_) {
      receivePort.close();
      exitPort.close();
      rethrow;
    }

    receivePort.listen((dynamic data) {
      if (data is SendPort) {
        sendPortCompleter.complete(data);
        return;
      }
      final response = data as _ParseResponse;
      _pending.remove(response.id)?.complete(response.message);
    });

    _workerSendPort = await sendPortCompleter.future;
  }
}
