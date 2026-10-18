import 'dart:math';

import 'package:flutter/widgets.dart' show CharacterRange;

// The engine lays a paragraph out in more than linear time when it is one
// unbroken run, a long run of combining marks, or text that keeps switching
// direction, and relays accept events of 64 KiB and more. Text from a relay is
// cut to these lengths, in UTF-16 code units, before it is laid out.

/// A note in a feed row, a quote or a thread.
const maxNoteLength = 8000;

/// [text] cut to at most [maxLength] code units, after a whole grapheme
/// cluster: never inside a surrogate pair, nor between a letter and its
/// accent. A cluster longer than [maxLength] is dropped whole.
String truncateText(String text, int maxLength) {
  assert(maxLength >= 0);
  if (text.length <= maxLength) return text;

  // Only the start is read, so a huge text costs no more than a long one. The
  // code point at the limit is read whole, as it may join the cluster before.
  final head = text.substring(0, min(text.length, maxLength + 2));
  final clusters = CharacterRange(head);
  var end = 0;
  while (clusters.moveNext()) {
    final next = head.length - clusters.stringAfterLength;
    if (next > maxLength) break;
    end = next;
  }
  return text.substring(0, end);
}
