import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/services/bounded_cache.dart';

void main() {
  test('a full map drops its oldest entry, not everything', () {
    final map = BoundedMap<String, int>(2)
      ..['a'] = 1
      ..['b'] = 2
      ..['c'] = 3;

    expect(map.length, 2);
    expect(map.containsKey('a'), isFalse);
    expect(map['b'], 2);
    expect(map['c'], 3);
  });

  test('rewriting a key makes it the newest', () {
    final map = BoundedMap<String, int>(2)
      ..['a'] = 1
      ..['b'] = 2
      ..['a'] = 10
      ..['c'] = 3;

    expect(map.containsKey('b'), isFalse);
    expect(map['a'], 10);
  });

  test('a set reports repeats and stays bounded', () {
    final set = BoundedSet<String>(2);

    expect(set.add('a'), isTrue);
    expect(set.add('a'), isFalse);
    set
      ..add('b')
      ..add('c');

    expect(set.length, 2);
    expect(set.contains('a'), isFalse);
    expect(set.contains('c'), isTrue);
  });
}
