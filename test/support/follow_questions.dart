import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';
import 'package:sputnik/services/follow_sync.dart';

/// Has [reply] answer the questions the follow queue asks before it publishes,
/// in place of the dialog.
///
/// A queue that keeps asking about a change the user has already answered
/// never ends, and a test run caught in that dies without a verdict, so the
/// question after the [limit]th fails the test instead.
void answerFollowQuestions(
  FutureOr<bool?> Function(FollowNeedsConfirmation update) reply, {
  int limit = 3,
}) {
  var asked = 0;
  confirmFollowUpdate = (update) async {
    if (++asked > limit) {
      fail('The user was asked $asked times and the questions do not end.');
    }
    return reply(update);
  };
}
