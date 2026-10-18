import 'package:flutter/material.dart';

import '../app_state.dart';
import '../nostr/nostr.dart';
import 'publishing.dart';

String _people(int count) => count == 1 ? '1 person' : '$count people';

/// What the user is told before a follow list is published that may replace
/// the real one, naming how many relays answered and how long the lists are.
String followConfirmationMessage(FollowNeedsConfirmation update) {
  final answered = update.answeredRelays;
  final queried = update.queriedRelays;
  final found = update.found;
  final seen = update.lastSeen;
  final seenSize = seen == null ? '' : ' with ${_people(seen.count)}';
  final sentences = <String>[];

  if (found != null) {
    sentences.add(
      'The newest follow list on your relays has ${_people(found.count)}, but '
      'this device last saw a newer one$seenSize.',
    );
    if (answered < queried) {
      sentences.add('Only $answered of $queried relays answered.');
    }
    sentences.add(
      'Publishing now would replace the newer list with a list of '
      '${_people(update.resultingCount)}.',
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
