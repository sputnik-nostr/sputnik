import 'dart:convert';

// Deprecated spellings that would otherwise shadow an edited field.
const _staleKeys = {'display_name': 'displayName'};

// Applies [fields] over [existingContent], keeping keys it does not edit.
String editedProfileContent(
  String? existingContent,
  Map<String, String> fields,
) {
  final content = <String, dynamic>{};
  if (existingContent != null) {
    try {
      final decoded = jsonDecode(existingContent);
      if (decoded is Map<String, dynamic>) content.addAll(decoded);
    } catch (_) {
      // Unreadable content is replaced rather than merged.
    }
  }

  for (final entry in fields.entries) {
    final value = entry.value.trim();
    if (value.isEmpty) {
      content.remove(entry.key);
    } else {
      content[entry.key] = value;
    }
    final stale = _staleKeys[entry.key];
    if (stale != null) content.remove(stale);
  }
  return jsonEncode(content);
}
