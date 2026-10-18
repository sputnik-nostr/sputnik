import 'dart:async';
import 'dart:io';

/// A loopback listener that never accepts and whose accept queue is full, so
/// more connects to it hang in SYN-SENT, like to a black-holed address.
///
/// Counting them reads /proc/net/tcp, so this is for Linux only.
class BlackHole {
  BlackHole._(this._server, this._fillers);

  final ServerSocket _server;
  final List<Socket> _fillers;

  static bool get isSupported => Platform.isLinux;

  static Future<BlackHole> bind() async {
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      backlog: 1,
    );
    // The kernel completes a few handshakes before it starts dropping SYNs.
    // Two connects in a row without an answer mean that the queue is full,
    // and a single connect that was merely slow doesn't end the filling.
    final fillers = <Socket>[];
    var unanswered = 0;
    while (unanswered < 2) {
      final task = await Socket.startConnect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      try {
        fillers.add(
          await task.socket.timeout(const Duration(milliseconds: 300)),
        );
        unanswered = 0;
      } on TimeoutException {
        task.cancel();
        unanswered++;
      }
    }
    return BlackHole._(server, fillers);
  }

  int get port => _server.port;

  /// How many connects to this listener are still waiting for an answer.
  int get pendingConnects {
    final hexPort = port.toRadixString(16).toUpperCase().padLeft(4, '0');
    var pending = 0;
    for (final line in File('/proc/net/tcp').readAsLinesSync().skip(1)) {
      final columns = line.trim().split(RegExp(r'\s+'));
      // Column 3 is the state (02 is SYN-SENT), column 2 the remote endpoint.
      if (columns[3] == '02' && columns[2].endsWith(':$hexPort')) pending++;
    }
    return pending;
  }

  Future<void> close() async {
    for (final filler in _fillers) {
      filler.destroy();
    }
    await _server.close();
  }
}
