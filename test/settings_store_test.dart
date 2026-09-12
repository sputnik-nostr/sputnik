import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sputnik/services/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('drops persisted relays that no longer pass validation', () async {
    SharedPreferences.setMockInitialValues({
      'custom_relays': <String>[
        'wss://good.example.com',
        'wss://relay.damus.io@158.51.42.7',
        'not a url',
      ],
    });

    expect(await SettingsStore.loadCustomRelays(), {'wss://good.example.com'});
  });

  test(
    'drops persisted selected relays that no longer pass validation',
    () async {
      SharedPreferences.setMockInitialValues({
        'selected_relays': <String>[
          'wss://good.example.com',
          'wss://relay.damus.io@158.51.42.7',
        ],
      });

      final selected = await SettingsStore.loadSelectedRelays({
        'wss://good.example.com',
        'wss://relay.damus.io@158.51.42.7',
      });

      expect(selected, {'wss://good.example.com'});
    },
  );
}
