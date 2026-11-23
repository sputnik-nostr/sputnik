import 'package:sputnik/services/settings_store.dart';

// An in-memory stand-in for the platform's secure storage.
class FakeSecretStore implements SecretStore {
  FakeSecretStore([Map<String, String> initial = const {}]) {
    _values.addAll(initial);
  }

  final _values = <String, String>{};

  /// A copy of everything stored, to inspect or to start another store from.
  Map<String, String> get values => Map.of(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<Map<String, String>> readAll() async => values;

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
