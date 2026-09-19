import 'package:sputnik/services/settings_store.dart';

// An in-memory stand-in for the platform's secure storage.
class FakeSecretStore implements SecretStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
