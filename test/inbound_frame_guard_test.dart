import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/inbound_frame_guard.dart';

import 'support/raw_relay.dart';

const _text = 1;
const _binary = 2;
const _close = 8;
const _ping = 9;
const _pong = 10;

Uint8List _bytes(List<List<int>> parts) =>
    Uint8List.fromList([for (final part in parts) ...part]);

Uint8List _reply([String status = '101 Switching Protocols']) =>
    Uint8List.fromList(
      ascii.encode(
        'HTTP/1.1 $status\r\n'
        'Upgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        'Sec-WebSocket-Accept: x\r\n\r\n',
      ),
    );

/// A frame of [length] filler bytes, the way a server writes it.
Uint8List _frame(int opcode, int length, {bool fin = true}) =>
    webSocketFrame(opcode, Uint8List(length), fin: fin);

/// [frames] after a 101 reply, as one buffer.
Uint8List _stream(List<Uint8List> frames) => _bytes([_reply(), ...frames]);

/// Whether the guard let each of [chunks] through, in turn.
List<bool> _feed(InboundFrameGuard guard, List<Uint8List> chunks) => [
  for (final chunk in chunks) guard.accept(chunk),
];

List<Uint8List> _cut(Uint8List bytes, List<int> at) {
  final points = [0, ...at, bytes.length];
  return [
    for (var i = 0; i < points.length - 1; i++)
      Uint8List.sublistView(bytes, points[i], points[i + 1]),
  ];
}

void main() {
  group('the reply to the upgrade', () {
    test('frames that follow a 101 pass, wherever the reply is cut', () {
      final bytes = _stream([_frame(_text, 40), _frame(_ping, 0)]);

      for (var at = 1; at < bytes.length; at++) {
        final guard = InboundFrameGuard();

        expect(_feed(guard, _cut(bytes, [at])), [true, true], reason: '$at');
        expect(guard.violation, isNull, reason: 'cut at $at');
      }
    });

    test('one byte at a time is the same', () {
      final guard = InboundFrameGuard();
      final bytes = _stream([_frame(_text, 300), _frame(_text, 5)]);

      for (final chunk in _cut(bytes, [
        for (var i = 1; i < bytes.length; i++) i,
      ])) {
        expect(guard.accept(chunk), isTrue);
      }
      expect(guard.violation, isNull);
    });

    test('a bare LF ends a line and the headers, as it does for dart:io', () {
      final reply = ascii.encode(
        'HTTP/1.1 101 Switching Protocols\nUpgrade: websocket\n\n',
      );
      final guard = InboundFrameGuard(maxFrameDebt: 0);

      expect(guard.accept(_bytes([reply, _frame(_text, 80)])), isTrue);
      // The empty frame that follows is only a frame if the headers ended.
      expect(guard.accept(_frame(_text, 0)), isFalse);
      expect(guard.violation, InboundViolation.frameFlood);
    });

    test('a status line with no reason phrase is an upgrade too', () {
      final guard = InboundFrameGuard();
      final reply = ascii.encode('HTTP/1.0 101\r\nUpgrade: websocket\r\n\r\n');

      expect(guard.accept(_bytes([reply, _frame(_text, 80)])), isTrue);
    });

    test('anything but a 101 first is a violation', () {
      // dart:io would follow a redirect over the same connection, and the
      // reply to that could no longer be told from frames.
      for (final status in [
        '200 OK',
        '301 Moved Permanently',
        '426 Upgrade Required',
        '100 Continue',
        '1011 Switching Protocols',
        '101Switching',
      ]) {
        final guard = InboundFrameGuard();

        expect(guard.accept(_reply(status)), isFalse, reason: status);
        expect(guard.violation, InboundViolation.protocol, reason: status);
        expect(guard.accept(Uint8List(10)), isFalse, reason: status);
      }
    });

    test('a status line that is not HTTP is a violation', () {
      for (final line in [
        'GARBAGE',
        'HTTP/2 101',
        'HTTP/1.1 10x',
        '',
        'HTTP/1.1',
      ]) {
        final guard = InboundFrameGuard();
        final bytes = Uint8List.fromList(ascii.encode('$line\r\n\r\n'));

        expect(guard.accept(bytes), isFalse, reason: line);
        expect(guard.violation, InboundViolation.protocol, reason: line);
      }
    });

    test('the headers cannot end before the status line', () {
      // Whatever follows would be taken for a valid frame.
      final g = InboundFrameGuard();

      expect(g.accept(Uint8List.fromList([0x0a, 0x81, 0x00])), isFalse);
      expect(g.violation, InboundViolation.protocol);
    });

    test('a violation in the status line stops it before the headers end', () {
      final guard = InboundFrameGuard();

      expect(
        guard.accept(Uint8List.fromList(ascii.encode('HTTP/1.1 404 N'))),
        isTrue,
      );
      expect(
        guard.accept(Uint8List.fromList(ascii.encode('ot Found\r\n'))),
        isFalse,
      );
    });
  });

  group('frame headers', () {
    test('every length encoding is read, however the bytes arrive', () {
      // 8-byte lengths are legal for small payloads, so cover that too.
      final long = _bytes([
        [0x81, 127, 0, 0, 0, 0, 0, 0, 0, 5],
        List.filled(5, 0x78),
      ]);
      final frames = [
        _frame(_text, 0),
        _frame(_text, 125),
        _frame(_text, 126),
        _frame(_text, 300),
        _frame(_text, 65535),
        _frame(_text, 65536),
        long,
      ];
      final bytes = _stream(frames);
      final random = Random(7);

      for (var round = 0; round < 40; round++) {
        final cuts = {
          for (var i = 0; i < 60; i++) 1 + random.nextInt(bytes.length - 1),
        }.toList()..sort();
        final guard = InboundFrameGuard(maxFrameDebt: 1 << 30);

        expect(_feed(guard, _cut(bytes, cuts)), everyElement(isTrue));
        expect(guard.violation, isNull, reason: '$cuts');
      }
    });

    test('a valid stream is never cut, whatever the chunking', () {
      final random = Random(11);
      for (var round = 0; round < 60; round++) {
        final frames = <Uint8List>[];
        for (var message = 0; message < 25; message++) {
          final pieces = 1 + random.nextInt(4);
          for (var piece = 0; piece < pieces; piece++) {
            frames.add(
              _frame(
                piece == 0 ? _text : 0,
                // Some long enough to pay for the short ones.
                random.nextBool()
                    ? random.nextInt(200)
                    : 64 + random.nextInt(3000),
                fin: piece == pieces - 1,
              ),
            );
            if (random.nextInt(5) == 0) {
              frames.add(_frame(_ping, random.nextInt(126)));
            }
          }
        }
        final bytes = _stream(frames);
        final cuts = {
          for (var i = 0; i < 80; i++) 1 + random.nextInt(bytes.length - 1),
        }.toList()..sort();
        final guard = InboundFrameGuard(controlBurst: 1 << 20);

        expect(
          _feed(guard, _cut(bytes, cuts)),
          everyElement(isTrue),
          reason: '$round',
        );
        expect(guard.violation, isNull, reason: '$round');
      }
    });

    test('whatever it is fed, it neither throws nor takes back a no', () {
      final random = Random(3);
      for (var round = 0; round < 300; round++) {
        final guard = InboundFrameGuard(
          maxMessageBytes: 5000,
          maxFrameDebt: 2000,
        );
        final chunks = [
          if (random.nextBool()) _reply(),
          for (var i = 0; i < 6; i++)
            Uint8List.fromList([
              for (var k = 0; k < random.nextInt(400); k++) random.nextInt(256),
            ]),
        ];
        var refused = false;

        for (final chunk in chunks) {
          final accepted = guard.accept(chunk);
          if (refused) expect(accepted, isFalse);
          refused = guard.violation != null;
          expect(accepted, !refused);
        }
      }
    });
  });

  group('message size', () {
    InboundFrameGuard guard() =>
        InboundFrameGuard(maxMessageBytes: 100, maxFrameDebt: 1 << 30);

    Uint8List message(List<int> lengths) => _stream([
      for (var i = 0; i < lengths.length; i++)
        _frame(i == 0 ? _text : 0, lengths[i], fin: i == lengths.length - 1),
    ]);

    test('a message of exactly the cap passes, whole or in pieces', () {
      for (final lengths in [
        [100],
        [60, 40],
        [1, 98, 1],
      ]) {
        final g = guard();

        expect(g.accept(message(lengths)), isTrue, reason: '$lengths');
        expect(g.violation, isNull, reason: '$lengths');
      }
    });

    test('one byte over is a violation, whole or in pieces', () {
      for (final lengths in [
        [101],
        [60, 41],
        [1, 98, 2],
        [50, 50, 1],
      ]) {
        final g = guard();

        expect(g.accept(message(lengths)), isFalse, reason: '$lengths');
        expect(
          g.violation,
          InboundViolation.oversizeMessage,
          reason: '$lengths',
        );
      }
    });

    test('the size is taken from the header, before the payload arrives', () {
      final g = guard();
      final header = _frame(_text, 1000).sublist(0, 4);

      expect(g.accept(_reply()), isTrue);
      expect(g.accept(header), isFalse);
      expect(g.violation, InboundViolation.oversizeMessage);
    });

    test('lengths that overflow or go negative are not let through', () {
      for (final top in [0x7f, 0xff, 0x80, 0x40]) {
        final g = guard();
        // A continuation, so that only the length is wrong.
        final frame = [
          0x80,
          127,
          top,
          0xff,
          0xff,
          0xff,
          0xff,
          0xff,
          0xff,
          0xff,
        ];

        g.accept(_stream([_frame(_text, 30, fin: false)]));

        expect(g.accept(_bytes([frame])), isFalse, reason: '$top');
        expect(g.violation, isNotNull, reason: '$top');
      }
    });

    test('a finished message starts the count again', () {
      final g = guard();
      final bytes = _stream([
        _frame(_text, 90),
        _frame(_text, 90),
        _frame(_text, 90),
      ]);

      expect(g.accept(bytes), isTrue);
    });

    test('nothing passes once a limit was broken', () {
      final g = guard();
      g.accept(_stream([_frame(_text, 500)]));

      expect(g.accept(_frame(_text, 1)), isFalse);
      expect(g.accept(Uint8List(0)), isFalse);
    });
  });

  group('frames that carry too little', () {
    InboundFrameGuard guard() => InboundFrameGuard(maxFrameDebt: 64 * 10);

    test('ten empty frames owe the limit, an eleventh breaks it', () {
      final ten = _stream([for (var i = 0; i < 10; i++) _frame(_text, 0)]);

      expect(guard().accept(ten), isTrue);

      final g = guard();
      expect(g.accept(_bytes([ten, _frame(_text, 0)])), isFalse);
      expect(g.violation, InboundViolation.frameFlood);
    });

    test('so do frames of a byte', () {
      final ten = _stream([for (var i = 0; i < 10; i++) _frame(_text, 1)]);

      // 63 owed each, so ten are within the limit of 640 and the eleventh not.
      expect(guard().accept(ten), isTrue);
      final g = guard();
      expect(g.accept(_bytes([ten, _frame(_text, 1)])), isFalse);
      expect(g.violation, InboundViolation.frameFlood);
    });

    test('frames of 64 bytes or more are never behind', () {
      final g = guard();
      final frames = [for (var i = 0; i < 5000; i++) _frame(_text, 64)];

      expect(g.accept(_stream(frames)), isTrue);
    });

    test('a long frame pays back what short ones owed', () {
      final g = guard();
      final frames = [
        for (var i = 0; i < 9; i++) _frame(_text, 0),
        _frame(_text, 1000),
        for (var i = 0; i < 9; i++) _frame(_text, 0),
      ];

      expect(g.accept(_stream(frames)), isTrue);
    });

    test('but cannot be saved up in advance', () {
      final g = guard();
      final frames = [
        _frame(_text, 100000),
        for (var i = 0; i < 11; i++) _frame(_text, 0),
      ];

      expect(g.accept(_stream(frames)), isFalse);
      expect(g.violation, InboundViolation.frameFlood);
    });

    test('the pieces of a message count as frames', () {
      final g = guard();
      final frames = [
        _frame(_text, 1, fin: false),
        for (var i = 0; i < 20; i++) _frame(0, 1, fin: false),
      ];

      expect(g.accept(_stream(frames)), isFalse);
      expect(g.violation, InboundViolation.frameFlood);
    });

    test('a million empty frames in one read are stopped, and cheaply', () {
      final g = InboundFrameGuard();
      final flood = repeated(_frame(_text, 0), 1000000);
      g.accept(_reply());

      expect(g.accept(flood), isFalse);
      expect(g.violation, InboundViolation.frameFlood);
    });
  });

  group('pings, pongs and closes', () {
    var now = Duration.zero;
    InboundFrameGuard guard() {
      now = Duration.zero;
      return InboundFrameGuard(
        controlBurst: 4,
        controlsPerSecond: 1,
        clock: () => now,
      );
    }

    test('a burst is allowed and then stopped at the frame over it', () {
      final four = _stream([for (var i = 0; i < 4; i++) _frame(_ping, 0)]);

      expect(guard().accept(four), isTrue);
      final g = guard();
      expect(g.accept(_bytes([four, _frame(_ping, 0)])), isFalse);
      expect(g.violation, InboundViolation.controlFlood);
    });

    test('a steady trickle goes on for ever', () {
      final g = guard();
      g.accept(_reply());

      for (var second = 0; second < 1000; second++) {
        now = Duration(seconds: second);
        expect(g.accept(_frame(_ping, 4)), isTrue);
      }
      expect(g.violation, isNull);
    });

    test('the budget fills up again with time', () {
      final g = guard();
      g.accept(_stream([for (var i = 0; i < 4; i++) _frame(_ping, 0)]));
      now = const Duration(seconds: 2);

      expect(g.accept(_bytes([_frame(_ping, 0), _frame(_ping, 0)])), isTrue);
      expect(g.accept(_frame(_ping, 0)), isFalse);
      expect(g.violation, InboundViolation.controlFlood);
    });

    test('but idle time does not buy a bigger burst', () {
      final four = _stream([for (var i = 0; i < 4; i++) _frame(_ping, 0)]);
      final g = guard();
      g.accept(_reply());
      now = const Duration(hours: 1);

      expect(g.accept(four.sublist(_reply().length)), isTrue);
      expect(g.accept(_frame(_ping, 0)), isFalse);
      expect(g.violation, InboundViolation.controlFlood);
    });

    test('pongs and closes are counted like pings', () {
      for (final opcode in [_pong, _close]) {
        final g = guard();
        final five = [for (var i = 0; i < 5; i++) _frame(opcode, 0)];

        expect(g.accept(_stream(five)), isFalse, reason: '$opcode');
        expect(g.violation, InboundViolation.controlFlood, reason: '$opcode');
      }
    });

    test('and do not use up the message budget or the frame debt', () {
      final g = InboundFrameGuard(
        maxMessageBytes: 100,
        maxFrameDebt: 64,
        controlBurst: 1000,
      );
      final bytes = _stream([
        _frame(_text, 64, fin: false),
        for (var i = 0; i < 500; i++) _frame(_ping, 125),
        _frame(0, 36),
      ]);

      expect(g.accept(bytes), isTrue);
    });

    test('a million pings in one read are stopped, and cheaply', () {
      final g = InboundFrameGuard();
      g.accept(_reply());

      expect(g.accept(repeated(_frame(_ping, 0), 1000000)), isFalse);
      expect(g.violation, InboundViolation.controlFlood);
    });
  });

  group('what no relay should send', () {
    void expectViolation(List<int> frame, {List<int> after = const []}) {
      final g = InboundFrameGuard();

      expect(
        g.accept(_bytes([_reply(), after, frame])),
        isFalse,
        reason: '$frame',
      );
      expect(g.violation, InboundViolation.protocol, reason: '$frame');
    }

    test('binary data', () => expectViolation(_frame(_binary, 4)));

    test('reserved opcodes', () {
      for (final opcode in [3, 4, 5, 6, 7, 11, 12, 13, 14, 15]) {
        expectViolation(_frame(opcode, 0));
      }
    });

    test('extension bits, which nothing was negotiated for', () {
      for (final bit in [0x40, 0x20, 0x10]) {
        final frame = _frame(_text, 3);
        frame[0] |= bit;
        expectViolation(frame);
      }
    });

    test('a masked frame', () {
      expectViolation([0x81, 0x80 | 3, 1, 2, 3, 4, 0x61, 0x62, 0x63]);
      // Ignoring the mask bit, this is an empty frame, and so are the next
      // two, which are in fact the key.
      expectViolation([0x81, 0x80, 0x81, 0x00, 0x81, 0x00]);
    });

    test('a continuation with nothing to continue', () {
      expectViolation(_frame(0, 3));
    });

    test('a new message in the middle of another', () {
      expectViolation(_frame(_text, 3), after: _frame(_text, 3, fin: false));
    });

    test('a fragmented or long control frame', () {
      expectViolation(_frame(_ping, 3, fin: false));
      expectViolation(_frame(_ping, 126));
    });
  });
}
