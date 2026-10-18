import 'dart:async';
import 'dart:io';

/// One call to `Socket.startConnect` made while a [FakeConnector] is installed.
class FakeAttempt {
  FakeAttempt(this.address, this.port);

  final InternetAddress address;
  final int port;

  /// Whether the code under test cancelled this attempt.
  bool cancelled = false;

  final _socket = Completer<Socket>();
  bool _settled = false;

  /// Ends the attempt with an error, on the next event-loop turn like a real
  /// connect (a task's socket has no listener until the task is handed over).
  void fail([Object? error]) {
    if (_settled) return;
    _settled = true;
    Timer.run(
      () => _socket.completeError(error ?? const SocketException('refused')),
    );
  }

  void _cancel() {
    cancelled = true;
    if (_settled) return;
    _settled = true;
    _socket.completeError(
      const SocketException('Connection attempt cancelled'),
    );
  }
}

/// Stands in for `Socket.startConnect`, so a test sees every address the code
/// dials and decides how each attempt ends. Mirrors the contract of dart:io's
/// tasks: cancelling an open attempt fails its socket.
class FakeConnector {
  final attempts = <FakeAttempt>[];

  /// Called synchronously for each attempt.
  void Function(FakeAttempt attempt)? onAttempt;

  Future<ConnectionTask<Socket>> _startConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
  }) {
    final attempt = FakeAttempt(host as InternetAddress, port);
    attempts.add(attempt);
    onAttempt?.call(attempt);
    return Future.value(
      ConnectionTask.fromSocket(attempt._socket.future, attempt._cancel),
    );
  }

  /// Runs [body] with `Socket.startConnect` replaced.
  R run<R>(R Function() body) =>
      IOOverrides.runZoned(body, socketStartConnect: _startConnect);
}
