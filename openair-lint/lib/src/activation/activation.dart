/// Parsers and models for AA activation times: ISO 8601 values, intervals,
/// weekday commands, exceptions and sun events.
///
/// ```dart
/// final aa = parseAa('MON-FRI 07:00Z/SS 2026-04-01/2026-09-30');
/// if (aa is AaWeekdayCommand && aa.isUsable) {
///   // Sunset on the local solar day 2026-06-01 at 46° N 14.5° E.
///   final sunset = sunEventOnLocalDay(
///       SunEvent.sunset, const CivilDate(2026, 6, 1), const LatLng(46, 14.5));
///   print(formatMinutes(sunset.minutes!)); // 18:52Z
/// }
/// ```
library;

export 'aa_command.dart';
export 'aa_issue.dart';
export 'civil_date.dart';
export 'iso8601.dart';
export 'sun.dart';
export 'sun_window.dart';
