import '../main.dart';
import '../models/relay.dart';

void setRelaySelected(String relay, bool selected) {
  final updated = Set<String>.from(selectedRelaysNotifier.value);
  if (selected) {
    updated.add(relay);
  } else {
    updated.remove(relay);
  }
  selectedRelaysNotifier.value = updated;
}

void removeCustomRelay(String relay) {
  customRelaysNotifier.value = Set<String>.from(customRelaysNotifier.value)
    ..remove(relay);

  if (selectedRelaysNotifier.value.contains(relay)) {
    setRelaySelected(relay, false);
  }
}

// Adds and selects a relay. False when the custom relay limit is reached.
bool addCustomRelay(String relay) {
  if (defaultRelays.contains(relay) ||
      customRelaysNotifier.value.contains(relay)) {
    setRelaySelected(relay, true);
    return true;
  }
  if (customRelaysNotifier.value.length >= maxCustomRelays) return false;

  customRelaysNotifier.value = {...customRelaysNotifier.value, relay};
  setRelaySelected(relay, true);
  return true;
}

// Selects exactly [relays]; returns how many the custom relay limit skipped.
int useRelays(Iterable<String> relays) {
  var skipped = 0;
  final selected = <String>{};
  for (final relay in relays) {
    final known =
        defaultRelays.contains(relay) ||
        customRelaysNotifier.value.contains(relay);
    if (!known && customRelaysNotifier.value.length >= maxCustomRelays) {
      skipped++;
      continue;
    }
    if (!known) {
      customRelaysNotifier.value = {...customRelaysNotifier.value, relay};
    }
    selected.add(relay);
  }
  selectedRelaysNotifier.value = selected;
  return skipped;
}
