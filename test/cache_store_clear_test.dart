import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:sputnik/nostr/models/nostr_metadata.dart';
import 'package:sputnik/nostr/models/nostr_payment_target.dart';
import 'package:sputnik/services/cache_store.dart';

void main() {
  late Directory dir;

  // The boxes are late final, so they can only be opened once per process.
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('cache_store_clear_test');
    await CacheStore.init(directory: dir);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('keeps its boxes in the given directory', () {
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toList();

    expect(names, containsAll(['profiles.hive', 'contacts.hive']));
  });

  test('clearAll empties profiles, follow lists and payment targets', () async {
    await CacheStore.putProfiles({'a' * 64: const NostrMetadata(name: 'a')});
    await CacheStore.putFollowing('a' * 64, ['b' * 64]);
    await CacheStore.putFollowers('a' * 64, ['c' * 64]);
    await CacheStore.putPaymentTargets('a' * 64, [
      const NostrPaymentTarget(type: 'monero', address: '4abc'),
    ]);

    await CacheStore.clearAll();

    expect(CacheStore.loadAllProfiles(), isEmpty);
    expect(CacheStore.getFollowing('a' * 64), isNull);
    expect(CacheStore.getFollowers('a' * 64), isNull);
    expect(CacheStore.getPaymentTargets('a' * 64), isNull);
  });
}
