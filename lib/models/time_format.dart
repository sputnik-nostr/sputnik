import 'package:intl/intl.dart';

final _absoluteTimeFormat = DateFormat('h:mm a, MMM d, y');

String relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}

String formatLastActive(DateTime time) {
  final ago = relativeTime(time);
  return ago == 'now' ? 'Last active just now' : 'Last active $ago ago';
}

String formatAbsoluteTime(DateTime time) {
  return _absoluteTimeFormat.format(time.toLocal());
}
