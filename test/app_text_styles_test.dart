import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/theme/app_text_styles.dart';

void main() {
  group('avatarInitial', () {
    test('upper-cases the first letter', () {
      expect(avatarInitial('alice'), 'A');
    });

    test('keeps an emoji whole instead of splitting its surrogate pair', () {
      expect(avatarInitial('\u{1F600} alice'), '\u{1F600}');
    });

    test('is empty for an empty name', () {
      expect(avatarInitial(''), '');
    });
  });
}
