/// Formats laptop uptime for the status pill, for example `3J 12M`.
///
/// Minutes are rounded down (C06). Under one hour only minutes are shown.
String formatUptime(Duration uptime) {
  final safe = uptime.isNegative ? Duration.zero : uptime;
  final totalMinutes = safe.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) {
    return '${minutes}M';
  }
  return '${hours}J ${minutes}M';
}
