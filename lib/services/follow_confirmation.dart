import 'package:flutter/material.dart';

import '../app_state.dart';
import '../nostr/nostr.dart';
import 'publishing.dart';

/// "1 person" or "3 people".
String peopleCount(int count) => count == 1 ? '1 person' : '$count people';

/// What confirming a tap on the follow button says: that the whole list is
/// published, and how long it will be once it has loaded.
String followListChangeMessage({required bool follow, int? listSize}) {
  final change = follow ? 'adds them to' : 'removes them from';
  if (listSize == null) {
    return 'This $change your follow list and publishes it to your relays. '
        'The list has not loaded yet, so it is fetched first.';
  }
  final after = peopleCount(follow ? listSize + 1 : listSize - 1);
  return 'This $change your follow list, which then has $after, and publishes '
      'it to your relays.';
}

/// What the user is told before a follow list is published that may replace
/// the real one, naming how many relays answered and how long the lists are.
String followConfirmationMessage(FollowNeedsConfirmation update) {
  final answered = update.answeredRelays;
  final queried = update.queriedRelays;
  final found = update.found;
  final seen = update.lastSeen;
  final seenSize = seen == null ? '' : ' with ${peopleCount(seen.count)}';
  final sentences = <String>[];

  if (found != null) {
    sentences.add(
      'The newest follow list on your relays has '
      '${peopleCount(found.count)}, but this device last saw a newer one'
      '$seenSize.',
    );
    if (answered < queried) {
      sentences.add('Only $answered of $queried relays answered.');
    }
    sentences.add(
      'Publishing now would replace the newer list with a list of '
      '${peopleCount(update.resultingCount)}.',
    );
  } else {
    if (answered < queried) {
      sentences.add(
        'No follow list was found on $answered of $queried relays and '
        '${queried - answered} did not answer.',
      );
      if (seen != null) sentences.add('This device last saw a list$seenSize.');
    } else {
      final returned = queried == 1
          ? 'Your relay returned no follow list'
          : 'None of your $queried relays returned a follow list';
      sentences.add('$returned, but this device last saw one$seenSize.');
    }
    final count = update.resultingCount;
    sentences.add(
      'Publishing now would replace your list with only '
      '${count == 1 ? 'this person' : '$count people'}.',
    );
  }
  sentences.add('Publish anyway?');
  return sentences.join(' ');
}

/// Asks the user; null when there is no screen to ask on.
Future<bool?> confirmFollowPublish(FollowNeedsConfirmation update) async {
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) return null;
  return confirmAction(
    context,
    title: 'Publish your follow list?',
    message: followConfirmationMessage(update),
    action: 'Publish',
    actionKey: const Key('confirmPublishFollowListButton'),
  );
}
