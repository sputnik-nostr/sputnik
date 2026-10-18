import 'dart:math';
import 'dart:typed_data';

/// Why an [InboundFrameGuard] gave up on a connection.
enum InboundViolation {
  /// One message, over all its frames, is longer than the cap.
  oversizeMessage,

  /// Too many frames for the bytes they carry, such as empty ones.
  frameFlood,

  /// Too many pings, pongs and closes.
  controlFlood,

  /// Something a relay has no reason to send: binary data, extension bits, a
  /// masked frame, or a reply to the upgrade that is not a 101.
  protocol,
}

/// Every data frame is charged as if it carried at least this many bytes.
const _frameCost = 64;

const _cr = 13;
const _lf = 10;
const _space = 32;

/// The start of a successful reply to the upgrade request, up to the status.
const _upgradedStatus = ['HTTP/1.1 101', 'HTTP/1.0 101'];

enum _Phase { response, frames }

/// Watches the bytes a relay sends, below the WebSocket that dart:io builds on
/// them.
///
/// dart:io checks the size of each frame, not of a message: it buffers a
/// fragmented message whole before the app sees how long it is, and it answers
/// every ping and walks every empty frame no matter how many arrive. The app
/// can only count what dart:io hands over, so a relay can spend memory and
/// time before that count starts. This reads just the frame headers, which a
/// server never masks, and so can tell when a relay has gone too far without
/// touching the bytes.
///
/// Feed it each chunk read from the socket, in order, starting with the reply
/// to the upgrade request.
class InboundFrameGuard {
  InboundFrameGuard({
    this.maxMessageBytes = 1 << 20,
    this.maxFrameDebt = 256 << 10,
    this.controlBurst = 256,
    this.controlsPerSecond = 1,
    Duration Function()? clock,
  }) : _clock = clock ?? _stopwatchClock(),
       _controlTokens = controlBurst.toDouble();

  /// The most bytes one message may have, summed over its frames.
  final int maxMessageBytes;

  /// How many bytes' worth of missing payload a run of short frames may add up
  /// to. A frame owes [_frameCost] minus its length, a longer frame pays back
  /// what is owed, so ordinary traffic stays at zero while a flood of empty or
  /// tiny frames hits the limit after `maxFrameDebt / 64` of them.
  final int maxFrameDebt;

  /// How many pings, pongs and closes may arrive back to back, and how many
  /// more per second after that. Relays send about one ping in 30 seconds.
  final int controlBurst;
  final double controlsPerSecond;

  final Duration Function() _clock;

  InboundViolation? _violation;
  _Phase _phase = _Phase.response;

  /// Set once a limit was broken; from then on [accept] passes nothing.
  InboundViolation? get violation => _violation;

  // The reply to the upgrade request: its status line, then headers up to an
  // empty line. dart:io accepts a bare LF for CRLF and so does this.
  final _statusLine = <int>[];
  int _lineLength = 0;
  int _lines = 0;

  // The frame being read: two bytes, an extended length of 0, 2 or 8 bytes,
  // then the payload, which is skipped.
  int _headerBytes = 0;
  int _byte0 = 0;
  int _extendedLength = 0;
  int _length = 0;
  int _payloadLeft = 0;

  bool _inMessage = false;
  int _messageBytes = 0;
  int _debt = 0;
  double _controlTokens;
  Duration _lastRefill = Duration.zero;

  /// Whether [chunk] may go on to the WebSocket. Once this is false it stays
  /// false, and the connection is to be closed.
  bool accept(Uint8List chunk) {
    var i = 0;
    while (i < chunk.length && _violation == null) {
      i = switch (_phase) {
        _Phase.response => _readResponse(chunk, i),
        _Phase.frames => _readFrames(chunk, i),
      };
    }
    return _violation == null;
  }

  void _break(InboundViolation violation) {
    _violation ??= violation;
  }

  /// Reads the reply to the upgrade up to the empty line that ends it. Only a
  /// 101 may come first: dart:io follows redirects over the same connection,
  /// and from then on its replies could no longer be told from frames.
  int _readResponse(Uint8List chunk, int i) {
    for (; i < chunk.length; i++) {
      final c = chunk[i];
      if (c == _cr) continue;
      if (c != _lf) {
        if (_lines == 0 && _statusLine.length < 13) _statusLine.add(c);
        _lineLength++;
        continue;
      }
      if (_lineLength > 0) {
        if (_lines++ == 0 && !_isUpgrade()) {
          _break(InboundViolation.protocol);
          return chunk.length;
        }
        _lineLength = 0;
        continue;
      }
      // An empty line ends the headers, but not before the status line.
      if (_lines == 0) {
        _break(InboundViolation.protocol);
        return chunk.length;
      }
      _phase = _Phase.frames;
      return i + 1;
    }
    return i;
  }

  bool _isUpgrade() {
    final line = String.fromCharCodes(_statusLine);
    return _upgradedStatus.any(
      (status) =>
          line.startsWith(status) &&
          (line.length == status.length ||
              _statusLine[status.length] == _space),
    );
  }

  int _readFrames(Uint8List chunk, int i) {
    final end = chunk.length;
    while (i < end && _violation == null) {
      if (_payloadLeft > 0) {
        final skipped = min(_payloadLeft, end - i);
        _payloadLeft -= skipped;
        i += skipped;
        continue;
      }
      final c = chunk[i++];
      if (_headerBytes == 0) {
        _byte0 = c;
        _headerBytes = 1;
      } else if (_headerBytes == 1) {
        _headerBytes = 2;
        final masked = c & 0x80 != 0;
        final short = c & 0x7f;
        _length = short;
        _extendedLength = short == 126 ? 2 : (short == 127 ? 8 : 0);
        if (masked) {
          // A server never masks. dart:io refuses it too.
          _break(InboundViolation.protocol);
        } else if (_extendedLength == 0) {
          _endHeader();
        } else {
          _length = 0;
        }
      } else {
        _length = (_length << 8) | c;
        if (--_extendedLength == 0) _endHeader();
      }
    }
    return i;
  }

  void _endHeader() {
    final fin = _byte0 & 0x80 != 0;
    final extensions = _byte0 & 0x70 != 0;
    final opcode = _byte0 & 0x0f;
    final length = _length;
    _headerBytes = 0;
    _payloadLeft = length;
    // A length with the top bit set is negative here, and is not allowed.
    if (extensions || length < 0) {
      _break(InboundViolation.protocol);
    } else if (opcode == 0 || opcode == 1) {
      _data(opcode == 0, fin, length);
    } else if (opcode >= 8 && opcode <= 10) {
      _control(fin, length);
    } else {
      // Binary and the reserved opcodes: Nostr is text.
      _break(InboundViolation.protocol);
    }
  }

  void _data(bool continuation, bool fin, int length) {
    // An unfinished message must continue, and only then.
    if (continuation != _inMessage) {
      _break(InboundViolation.protocol);
    } else if (length > maxMessageBytes - _messageBytes) {
      _break(InboundViolation.oversizeMessage);
    } else {
      _messageBytes += length;
      _debt = max(0, _debt + _frameCost - length);
      if (_debt > maxFrameDebt) _break(InboundViolation.frameFlood);
    }
    _inMessage = !fin;
    if (fin) _messageBytes = 0;
  }

  void _control(bool fin, int length) {
    // Control frames are short and never fragmented.
    if (!fin || length > 125) {
      _break(InboundViolation.protocol);
      return;
    }
    final now = _clock();
    _controlTokens = min(
      controlBurst.toDouble(),
      _controlTokens +
          (now - _lastRefill).inMicroseconds * controlsPerSecond / 1e6,
    );
    _lastRefill = now;
    if (_controlTokens < 1) {
      _break(InboundViolation.controlFlood);
    } else {
      _controlTokens -= 1;
    }
  }
}

Duration Function() _stopwatchClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}
