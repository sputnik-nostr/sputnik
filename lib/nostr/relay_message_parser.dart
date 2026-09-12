import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'models/nostr_event.dart';

class ParsedRelayMessage {
  const ParsedRelayMessage({
    required this.subscriptionId,
    required this.type,
    this.event,
  });

  final String subscriptionId;
  final String type;
  final NostrEvent? event;
}

class _ParseRequest {
  const _ParseRequest(this.id, this.raw);

  final int id;
  final String raw;
}

class _ParseResponse {
  const _ParseResponse(this.id, this.message);

  final int id;
  final ParsedRelayMessage? message;
}

ParsedRelayMessage? _parse(String raw) {
  try {
    final message = jsonDecode(raw);
    if (message is! List || message.length < 2) return null;

    final type = message[0];
    final subscriptionId = message[1];
    if (type is! String || subscriptionId is! String) return null;

    NostrEvent? event;
    if (type == 'EVENT' && message.length >= 3) {
      event = NostrEvent.fromJson(message[2] as Map<String, dynamic>);
    }
    return ParsedRelayMessage(
      subscriptionId: subscriptionId,
      type: type,
      event: event,
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
    mainSendPort.send(_ParseResponse(request.id, _parse(request.raw)));
  });
}

class RelayMessageParser {
  RelayMessageParser._();

  static final instance = RelayMessageParser._();

  SendPort? _workerSendPort;
  Future<void>? _spawning;
  int _nextRequestId = 0;
  final _pending = <int, Completer<ParsedRelayMessage?>>{};

  Future<ParsedRelayMessage?> parse(String raw) async {
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
    _workerSendPort!.send(_ParseRequest(id, raw));
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
