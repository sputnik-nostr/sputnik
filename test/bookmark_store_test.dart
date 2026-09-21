import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sputnik/models/note.dart';
import 'package:sputnik/services/bookmark_store.dart';

Note _note(String id, {String content = 'hello'}) => Note(
  id: id,
  pubkey: 'a' * 64,
  displayName: 'Alice',
  handle: '@alice',
  content: content,
  postedAt: '1m',
  createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
);

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bookmark_store_test');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await BookmarkStore.close();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  // A fresh start, as after the app is closed and reopened.
  Future<Map<String, Note>> reload() async {
    await BookmarkStore.close();
    return BookmarkStore.load(directory: dir);
  }

  test('starts empty', () async {
    expect(await BookmarkStore.load(directory: dir), isEmpty);
  });

  test('keeps saved bookmarks across a restart', () async {
    await BookmarkStore.load(directory: dir);
    await BookmarkStore.save({'1': _note('1'), '2': _note('2', content: 'x')});

    final loaded = await reload();

    expect(loaded.keys, unorderedEquals(['1', '2']));
    expect(loaded['2']!.content, 'x');
  });

  test('a removed bookmark stays removed', () async {
    await BookmarkStore.load(directory: dir);
    await BookmarkStore.save({'1': _note('1'), '2': _note('2')});
    await BookmarkStore.save({'2': _note('2')});

    expect((await reload()).keys, ['2']);
  });

  test('writes only what changed', () async {
    await BookmarkStore.load(directory: dir);
    await BookmarkStore.save({'1': _note('1')});
    final box = Hive.box<String>('bookmarks');
    // A marker a full rewrite would replace.
    await box.put('1', 'marker');

    await BookmarkStore.save({'1': _note('1'), '2': _note('2')});

    expect(box.get('1'), 'marker');
    expect(box.containsKey('2'), isTrue);
  });

  test('never deletes an entry it could not read', () async {
    await BookmarkStore.load(directory: dir);
    await Hive.box<String>('bookmarks').put('odd', '{"not": "a note"}');

    final loaded = await reload();
    await BookmarkStore.save({...loaded, '1': _note('1')});

    expect(loaded, isEmpty);
    expect(Hive.box<String>('bookmarks').containsKey('odd'), isTrue);
  });

  group('moving over the old shared_preferences blob', () {
    String legacy(Map<String, Note> notes) => jsonEncode({
      for (final entry in notes.entries) entry.key: entry.value.toJson(),
    });

    test('imports every bookmark and forgets the blob', () async {
      SharedPreferences.setMockInitialValues({
        'bookmarked_notes': legacy({'1': _note('1'), '2': _note('2')}),
      });

      final loaded = await BookmarkStore.load(directory: dir);

      expect(loaded.keys, unorderedEquals(['1', '2']));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('bookmarked_notes'), isFalse);
    });

    test('does not bring back a bookmark removed after moving', () async {
      SharedPreferences.setMockInitialValues({
        'bookmarked_notes': legacy({'1': _note('1'), '2': _note('2')}),
      });
      await BookmarkStore.load(directory: dir);
      await BookmarkStore.save({'2': _note('2')});

      expect((await reload()).keys, ['2']);
    });

    test('keeps only the entries it could not read', () async {
      SharedPreferences.setMockInitialValues({
        'bookmarked_notes': jsonEncode({
          '1': _note('1').toJson(),
          'bad': {'id': 'bad'},
        }),
      });

      final loaded = await BookmarkStore.load(directory: dir);

      expect(loaded.keys, ['1']);
      final prefs = await SharedPreferences.getInstance();
      final left = jsonDecode(prefs.getString('bookmarked_notes')!) as Map;
      expect(left.keys, ['bad']);
    });

    test('keeps a blob that cannot be parsed at all', () async {
      SharedPreferences.setMockInitialValues({'bookmarked_notes': '{oops'});

      final loaded = await BookmarkStore.load(directory: dir);

      expect(loaded, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('bookmarked_notes'), '{oops');
    });

    test('leaves a bookmark already in the box alone', () async {
      await BookmarkStore.load(directory: dir);
      await BookmarkStore.save({'1': _note('1', content: 'new')});
      SharedPreferences.setMockInitialValues({
        'bookmarked_notes': legacy({'1': _note('1', content: 'old')}),
      });

      final loaded = await reload();

      expect(loaded['1']!.content, 'new');
    });
  });
}
