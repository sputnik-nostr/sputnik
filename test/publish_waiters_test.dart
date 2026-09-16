import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/relay_connection_pool.dart';

void main() {
  const accepted = RelayPublishResult(RelayPublishOutcome.accepted);
  const failed = RelayPublishResult(RelayPublishOutcome.connectionFailed);

  test('resolve() completes the single waiter for an event id', () {
    final waiters = PublishWaiters();
    final completer = waiters.add('event-1');

    waiters.resolve('event-1', accepted);

    expect(completer.isCompleted, isTrue);
    expect(completer.future, completion(accepted));
  });

  test('two concurrent waiters for the same event id both resolve from one '
      'OK, instead of one overwriting the other', () {
    final waiters = PublishWaiters();
    final first = waiters.add('event-1');
    final second = waiters.add('event-1');

    waiters.resolve('event-1', accepted);

    expect(first.isCompleted, isTrue);
    expect(second.isCompleted, isTrue);
    expect(first.future, completion(accepted));
    expect(second.future, completion(accepted));
  });

  test('resolving one event id does not affect a different one', () {
    final waiters = PublishWaiters();
    final a = waiters.add('event-a');
    final b = waiters.add('event-b');

    waiters.resolve('event-a', accepted);

    expect(a.isCompleted, isTrue);
    expect(b.isCompleted, isFalse);
  });

  test('resolving an unknown event id is a no-op', () {
    final waiters = PublishWaiters();
    final completer = waiters.add('event-1');

    waiters.resolve('unknown-id', accepted);

    expect(completer.isCompleted, isFalse);
  });

  test('remove() drops a waiter without completing it', () {
    final waiters = PublishWaiters();
    final completer = waiters.add('event-1');

    waiters.remove('event-1', completer);
    waiters.resolve('event-1', accepted);

    expect(completer.isCompleted, isFalse);
  });

  test('failAll() completes every pending waiter across all event ids', () {
    final waiters = PublishWaiters();
    final a = waiters.add('event-a');
    final b1 = waiters.add('event-b');
    final b2 = waiters.add('event-b');

    waiters.failAll(failed);

    expect(a.future, completion(failed));
    expect(b1.future, completion(failed));
    expect(b2.future, completion(failed));
  });

  test('an already-completed waiter is left alone by resolve()', () {
    final waiters = PublishWaiters();
    final completer = waiters.add('event-1');
    completer.complete(accepted);

    // Should not throw for double-completing.
    waiters.resolve('event-1', failed);

    expect(completer.future, completion(accepted));
  });
}
