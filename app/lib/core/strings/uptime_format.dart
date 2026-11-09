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

/// Formats laptop uptime in lowercase for the Settings card, for example
/// `3j 12m`. Same rounding and rules as [formatUptime] (C06).
String formatUptimeLong(Duration uptime) {
  final safe = uptime.isNegative ? Duration.zero : uptime;
  final totalMinutes = safe.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) {
    return '${minutes}m';
  }
  return '${hours}j ${minutes}m';
}
