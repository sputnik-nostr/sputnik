/// A map that drops its oldest entry once it holds more than [capacity].
class BoundedMap<K, V> {
  BoundedMap(this.capacity);

  final int capacity;

  // Dart maps keep insertion order, so the first key is the oldest.
  final _entries = <K, V>{};

  int get length => _entries.length;

  V? operator [](K key) => _entries[key];

  void operator []=(K key, V value) {
    _entries.remove(key);
    _entries[key] = value;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
  }

  bool containsKey(K key) => _entries.containsKey(key);

  V? remove(K key) => _entries.remove(key);

  void clear() => _entries.clear();
}

/// A set that drops its oldest element once it holds more than [capacity].
class BoundedSet<T> {
  BoundedSet(int capacity) : _map = BoundedMap(capacity);

  final BoundedMap<T, bool> _map;

  int get length => _map.length;

  bool contains(T value) => _map.containsKey(value);

  /// False if [value] was already present.
  bool add(T value) {
    if (contains(value)) return false;
    _map[value] = true;
    return true;
  }

  void clear() => _map.clear();
}
