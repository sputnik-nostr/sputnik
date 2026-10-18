import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/services/ssrf_guard.dart';

import 'support/black_hole.dart';
import 'support/eventually.dart';
import 'support/fake_connector.dart';

/// Where a future stands, without waiting for it.
class _Outcome {
  _Outcome(Future<Object?> future) {
    future.then(
      (value) => socket = value,
      onError: (Object error) => this.error = error,
    );
  }

  Object? socket;
  Object? error;
}

/// Runs [body] and returns the errors that nothing caught while it ran.
///
/// A failed expectation in [body] is rethrown, instead of being swallowed by
/// the error zone and leaving the test to time out.
Future<List<Object>> _uncaughtDuring(Future<void> Function() body) async {
  final uncaught = <Object>[];
  final finished = Completer<(Object, StackTrace)?>();
  unawaited(
    runZonedGuarded(() async {
      try {
        await body();
        finished.complete(null);
      } catch (error, stack) {
        finished.complete((error, stack));
      }
    }, (error, stack) => uncaught.add(error)),
  );
  final failure = await finished.future;
  if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
  return uncaught;
}

void main() {
  // connectToAny never vets, and the fake connector never connects anywhere.
  final addresses = [for (var i = 1; i <= 3; i++) InternetAddress('8.8.8.$i')];

  group('connectToAny task', () {
    testWidgets('cancelling during the stagger fails the socket', (
      tester,
    ) async {
      final connector = FakeConnector();
      await connector.run(() async {
        final task = connectToAny(addresses, 80);
        final outcome = _Outcome(task.socket);
        await tester.pump(const Duration(milliseconds: 100));
        expect(connector.attempts, hasLength(1)); // the others still wait

        task.cancel();
        await tester.pump(const Duration(seconds: 1));

        expect(outcome.error, isA<SocketException>());
        expect(connector.attempts, hasLength(1));
        expect(connector.attempts.single.cancelled, isTrue);
      });
    });

    test(
      'cancelling before an attempt has started leaves no uncaught error',
      () async {
        final connector = FakeConnector()..holdStarts = true;
        final uncaught = await _uncaughtDuring(
          () => connector.run(() async {
            final task = connectToAny(addresses, 80);
            final outcome = _Outcome(task.socket);
            task.cancel();
            connector.attempts.single.start(); // startConnect answers too late
            await pumpEventQueue();

            expect(outcome.error, isA<SocketException>());
            expect(connector.attempts.single.cancelled, isTrue);
          }),
        );
        expect(uncaught, isEmpty);
      },
    );

    test(
      'a synchronous error from startConnect only fails that attempt',
      () async {
        final winner = FakeSocket();
        final connector = FakeConnector()
          ..onAttempt = (attempt) {
            if (attempt.address == addresses.first) throw ArgumentError('bad');
            attempt.connect(winner);
          };
        final uncaught = await _uncaughtDuring(
          () => connector.run(() async {
            final task = connectToAny(addresses, 80);
            expect(await task.socket, same(winner));
            expect(
              connector.attempts.map((attempt) => attempt.address),
              addresses.take(2),
            );
          }),
        );
        expect(uncaught, isEmpty);
      },
    );

    test('attempts that all fail synchronously fail the socket', () async {
      final connector = FakeConnector()
        ..onAttempt = (attempt) => throw StateError('bad');
      final uncaught = await _uncaughtDuring(
        () => connector.run(() async {
          final task = connectToAny(addresses, 80);
          await expectLater(task.socket, throwsA(isA<StateError>()));
          expect(connector.attempts, hasLength(addresses.length));
        }),
      );
      expect(uncaught, isEmpty);
    });

    testWidgets('destroys a socket that connects after the race was decided', (
      tester,
    ) async {
      final winner = FakeSocket();
      final loser = FakeSocket();
      final connector = FakeConnector()..holdStarts = true;
      await connector.run(() async {
        final task = connectToAny(addresses.take(2).toList(), 80);
        final outcome = _Outcome(task.socket);
        await tester.pump(const Duration(milliseconds: 300));
        expect(connector.attempts, hasLength(2));

        connector.attempts[0].start();
        connector.attempts[0].connect(winner);
        connector.attempts[1].connect(loser);
        await tester.pump(Duration.zero);
        expect(outcome.socket, same(winner));

        // Only now does the second startConnect hand over its task.
        connector.attempts[1].start();
        await tester.pump(Duration.zero);

        expect(loser.destroyed, isTrue);
        expect(connector.attempts[1].cancelled, isTrue);
        expect(winner.destroyed, isFalse);
      });
    });

    testWidgets('the winner closes the attempts that are still open', (
      tester,
    ) async {
      final winner = FakeSocket();
      final connector = FakeConnector();
      await connector.run(() async {
        final task = connectToAny(addresses, 80);
        final outcome = _Outcome(task.socket);
        await tester.pump(const Duration(milliseconds: 600));
        expect(connector.open, hasLength(3)); // nobody has answered yet

        connector.attempts[1].connect(winner);
        await tester.pump(Duration.zero);

        expect(outcome.socket, same(winner));
        expect(connector.attempts[0].cancelled, isTrue);
        expect(connector.attempts[2].cancelled, isTrue);
        expect(connector.attempts[1].cancelled, isFalse);
        expect(connector.open, isEmpty);
      });
    });

    testWidgets('destroys an attempt that connects as the race is won', (
      tester,
    ) async {
      final winner = FakeSocket();
      final loser = FakeSocket();
      final connector = FakeConnector();
      await connector.run(() async {
        final task = connectToAny(addresses.take(2).toList(), 80);
        final outcome = _Outcome(task.socket);
        await tester.pump(const Duration(milliseconds: 300));
        expect(connector.attempts, hasLength(2));

        // Both sockets arrive in the same turn, the loser's after the winner's.
        connector.attempts[0].connect(winner);
        connector.attempts[1].connect(loser);
        await tester.pump(Duration.zero);

        expect(outcome.socket, same(winner));
        expect(loser.destroyed, isTrue);
        expect(winner.destroyed, isFalse);
      });
    });

    testWidgets('tries the next address at once when one fails', (
      tester,
    ) async {
      final connector = FakeConnector()
        ..onAttempt = (attempt) {
          if (attempt.address == addresses.first) attempt.fail();
        };
      await connector.run(() async {
        final task = connectToAny(addresses, 80);
        final outcome = _Outcome(task.socket);
        await tester.pump(Duration.zero); // the first address is refused
        await tester.pump(Duration.zero);

        // No time has passed, so this is not the stagger firing.
        expect(
          connector.attempts.map((attempt) => attempt.address),
          addresses.take(2),
        );

        task.cancel();
        await tester.pump(Duration.zero);
        expect(outcome.error, isA<SocketException>());
      });
    });

    test('cancelling after the race was won leaves the socket alone', () async {
      final winner = FakeSocket();
      final connector = FakeConnector()
        ..onAttempt = (attempt) => attempt.connect(winner);
      await connector.run(() async {
        final task = connectToAny(addresses, 80);
        expect(await task.socket, same(winner));

        task.cancel();
        await pumpEventQueue();

        expect(winner.destroyed, isFalse);
      });
    });

    test('cancelling right away leaves no uncaught error', () async {
      final uncaught = await _uncaughtDuring(() async {
        for (var i = 0; i < 20; i++) {
          // Nothing listens on the discard port; the cancel comes first anyway.
          final task = connectToAny([InternetAddress.loopbackIPv4], 9);
          task.socket.ignore();
          task.cancel();
        }
        await pumpEventQueue();
      });
      expect(uncaught, isEmpty);
    });

    test('cancelling closes real connects and fails the socket', () async {
      final hole = await BlackHole.bind();
      addTearDown(hole.close);
      final task = connectToAny([
        InternetAddress.loopbackIPv4,
        InternetAddress('127.0.0.2'),
      ], hole.port);
      final outcome = _Outcome(task.socket);
      await eventually(() => hole.pendingConnects == 1);

      task.cancel(); // the second address has not been tried yet
      await pumpEventQueue();

      expect(outcome.error, isA<SocketException>());
      await eventually(() => hole.pendingConnects == 0);
    }, skip: BlackHole.isSupported ? false : 'needs /proc/net/tcp');
  });
}
