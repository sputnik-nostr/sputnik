import 'package:flutter_test/flutter_test.dart';

import 'package:sputnik/services/settings_store.dart';

import 'fake_secret_store.dart';

/// How the call that [FaultySecretStore] fails behaves.
enum Fault {
  /// The call fails without taking effect; later calls work again.
  transient,

  /// The call takes effect but reports a failure, like a timeout that comes
  /// after the write has landed.
  lateFailure,

  /// The process dies before the call: it and every later call do nothing.
  crashBefore,

  /// The process dies right after the call took effect; later calls do nothing.
  crashAfter,
}

/// A [SecretStore] that fails numbered calls, to show that no failure loses a
/// key or leaves the index pointing at nothing.
class FaultySecretStore implements SecretStore {
  /// Fails call [failCall] as [fault] says, counting from 1, and every call in
  /// [faults] as it says; no call if neither is given.
  FaultySecretStore(
    this.inner, {
    int? failCall,
    Fault fault = Fault.transient,
    Map<int, Fault> faults = const {},
  }) : faults = {?failCall: fault, ...faults};

  final SecretStore inner;

  /// How each call to fail behaves, by its number.
  final Map<int, Fault> faults;

  /// Every call made so far, such as `write identities`.
  final calls = <String>[];

  var _dead = false;

  Future<T> _call<T>(String call, Future<T> Function() run) async {
    calls.add(call);
    if (_dead) throw StateError('process gone: $call');
    final fault = faults[calls.length];
    if (fault == null) return run();

    switch (fault) {
      case Fault.transient:
        throw StateError('injected failure: $call');
      case Fault.lateFailure:
        await run();
        throw StateError('injected failure after the call took effect: $call');
      case Fault.crashBefore:
        _dead = true;
        throw StateError('process gone before: $call');
      case Fault.crashAfter:
        await run();
        _dead = true;
        throw StateError('process gone after: $call');
    }
  }

  @override
  Future<String?> read(String key) => _call('read $key', () => inner.read(key));

  @override
  Future<Map<String, String>> readAll() => _call('readAll', inner.readAll);

  @override
  Future<void> write(String key, String value) =>
      _call('write $key', () => inner.write(key, value));

  @override
  Future<void> delete(String key) =>
      _call('delete $key', () => inner.delete(key));
}

/// Runs [scenario] once on [seed] to count its storage calls, then again for
/// every call and every [Fault], each time on a fresh copy of [seed].
///
/// After each faulted run storage works again, as at the next start, and
/// [check] sees what the run left behind: a description of the fault, the
/// store, and the error the scenario ended with (null if it finished).
Future<void> forEveryFault({
  required Map<String, String> seed,
  required Future<void> Function() scenario,
  required Future<void> Function(
    String fault,
    FakeSecretStore after,
    Object? error,
  )
  check,
  Future<void> Function()? reset,
}) async {
  Future<FaultySecretStore> start(int? failCall, Fault fault) async {
    await reset?.call();
    final store = FaultySecretStore(
      FakeSecretStore(seed),
      failCall: failCall,
      fault: fault,
    );
    SettingsStore.secretStore = store;
    return store;
  }

  final clean = await start(null, Fault.transient);
  await scenario();
  final callCount = clean.calls.length;
  expect(callCount, greaterThan(0), reason: 'the scenario never used storage');
  await check('no fault', clean.inner as FakeSecretStore, null);

  for (var call = 1; call <= callCount; call++) {
    for (final fault in Fault.values) {
      final store = await start(call, fault);
      Object? error;
      try {
        await scenario();
      } catch (e) {
        error = e;
      }
      final inner = store.inner as FakeSecretStore;
      SettingsStore.secretStore = inner;
      await check(
        '${fault.name} at call $call (${clean.calls[call - 1]})',
        inner,
        error,
      );
    }
  }
}
