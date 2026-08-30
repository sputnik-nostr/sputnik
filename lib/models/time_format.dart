import 'package:intl/intl.dart';

final _absoluteTimeFormat = DateFormat('h:mm a · MMM d, y');

String relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}

String formatLastActive(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Last active just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return 'Last active $m minute${m == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return 'Last active $h hour${h == 1 ? '' : 's'} ago';
  }
  if (diff.inDays < 7) {
    final d = diff.inDays;
    return 'Last active $d day${d == 1 ? '' : 's'} ago';
  }
  final w = diff.inDays ~/ 7;
  return 'Last active $w week${w == 1 ? '' : 's'} ago';
}

String formatLastActiveFromPostedAt(String postedAt) {
  return postedAt == 'now'
      ? 'Last active just now'
      : 'Last active $postedAt ago';
}

String formatAbsoluteTime(DateTime time) {
  return _absoluteTimeFormat.format(time.toLocal());
}
