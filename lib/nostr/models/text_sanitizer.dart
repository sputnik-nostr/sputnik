/// Replaces unpaired UTF-16 surrogates with U+FFFD to keep the text valid.
String sanitizeUtf16(String input) {
  // Almost every string has no surrogates at all, so skip the copy for those.
  var first = 0;
  while (first < input.length && input.codeUnitAt(first) & 0xF800 != 0xD800) {
    first++;
  }
  if (first == input.length) return input;

  final buffer = StringBuffer(input.substring(0, first));
  for (var i = first; i < input.length; i++) {
    final unit = input.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      final next = i + 1 < input.length ? input.codeUnitAt(i + 1) : null;
      if (next != null && next >= 0xDC00 && next <= 0xDFFF) {
        buffer.writeCharCode(unit);
        buffer.writeCharCode(next);
        i++;
      } else {
        buffer.writeCharCode(0xFFFD);
      }
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      buffer.writeCharCode(0xFFFD);
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}
