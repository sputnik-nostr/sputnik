String sanitizeUtf16(String input) {
  final buffer = StringBuffer();
  for (var i = 0; i < input.length; i++) {
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
