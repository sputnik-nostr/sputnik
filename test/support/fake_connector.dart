import 'dart:async';
import 'dart:io';

/// A socket that only remembers whether it was destroyed.
class FakeSocket implements Socket {
  bool destroyed = false;

  @override
  void destroy() => destroyed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One call to `Socket.startConnect` made while a [FakeConnector] is installed.
class FakeAttempt {
  FakeAttempt(this.address, this.port);

  final InternetAddress address;
  final int port;

  /// Whether the code under test cancelled this attempt.
  bool cancelled = false;

  final _socket = Completer<Socket>();
  final _started = Completer<void>();
  bool _settled = false;

  /// Neither connected, failed nor cancelled yet, like a black-holed address.
  bool get isOpen => !_settled;

  /// Hands the task to the caller, when the connector holds starts back.
  void start() => _started.complete();

  /// Ends the attempt with [socket], on the next event-loop turn like a real
  /// connect (a task's socket has no listener until the task is handed over).
  void connect(Socket socket) => _settle(() => _socket.complete(socket));

  void fail([Object? error]) {
    _settle(
      () => _socket.completeError(error ?? const SocketException('refused')),
    );
  }

  void _settle(void Function() complete) {
    if (_settled) return;
    _settled = true;
    Timer.run(complete);
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

  /// Hold every task back until its attempt is started by the test.
  bool holdStarts = false;

  /// Called synchronously for each attempt; may throw, like a bad argument.
  void Function(FakeAttempt attempt)? onAttempt;

  Iterable<FakeAttempt> get open => attempts.where((a) => a.isOpen);

  Future<ConnectionTask<Socket>> _startConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
  }) {
    final attempt = FakeAttempt(host as InternetAddress, port);
    attempts.add(attempt);
    onAttempt?.call(attempt);
    final task = ConnectionTask.fromSocket(
      attempt._socket.future,
      attempt._cancel,
    );
    if (!holdStarts) return Future.value(task);
    return attempt._started.future.then((_) => task);
  }

  /// Runs [body] with `Socket.startConnect` replaced.
  R run<R>(R Function() body) =>
      IOOverrides.runZoned(body, socketStartConnect: _startConnect);
}
