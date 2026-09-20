import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:sputnik/services/cache_store.dart';

void main() {
  late Directory dir;
  late Box<Map> box;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cache_store_test');
    Hive.init(dir.path);
    box = await Hive.openBox<Map>('profiles');
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('pruneExpired drops only entries older than maxAge', () async {
    final now = DateTime(2026, 1, 31);
    int ago(Duration age) => now.subtract(age).millisecondsSinceEpoch;
    await box.putAll({
      'fresh': {'fetchedAt': ago(const Duration(days: 1))},
      'edge': {'fetchedAt': ago(CacheStore.maxAge - const Duration(hours: 1))},
      'old': {'fetchedAt': ago(CacheStore.maxAge + const Duration(hours: 1))},
      'undated': {'data': 'x'},
    });

    await CacheStore.pruneExpired(box, now: now);

    expect(box.keys, unorderedEquals(['fresh', 'edge']));
  });
}
