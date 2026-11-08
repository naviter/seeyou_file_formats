/// A calendar date without time zone, and helpers for UTC instants.
///
/// The activation code uses its own small date type. `DateTime` from
/// `dart:core` accepts invalid dates such as February 30 and moves them to
/// the next month. That is not what a linter wants.
library;

/// The number of milliseconds in one day.
const int msPerDay = 86400000;

/// The number of milliseconds in one minute.
const int msPerMinute = 60000;

/// Weekday numbers as in ISO 8601: 1 = Monday, 7 = Sunday.
const List<String> weekdayAbbreviations = [
  'MON',
  'TUE',
  'WED',
  'THU',
  'FRI',
  'SAT',
  'SUN',
];

/// English names of the weekdays, for messages. Index 0 is Monday.
const List<String> weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// English names of the months, for messages. Index 0 is January.
const List<String> monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// True if [year] is a leap year in the Gregorian calendar.
bool isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

/// The number of days in [month] (1 to 12) of [year].
int daysInMonth(int year, int month) {
  const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && isLeapYear(year)) return 29;
  return days[month - 1];
}

/// The number of days in [year].
int daysInYear(int year) => isLeapYear(year) ? 366 : 365;

/// The number of ISO 8601 weeks in [year] (52 or 53).
int isoWeeksInYear(int year) {
  // A year has 53 weeks if January 1 is a Thursday, or if it is a leap
  // year and January 1 is a Wednesday.
  final jan1 = CivilDate(year, 1, 1).weekday;
  if (jan1 == DateTime.thursday) return 53;
  if (jan1 == DateTime.wednesday && isLeapYear(year)) return 53;
  return 52;
}

/// A date in the Gregorian calendar (proleptic), for example 2026-07-04.
///
/// The date is always valid. Use [CivilDate.tryCreate] to check user input.
class CivilDate implements Comparable<CivilDate> {
  /// Creates a date. The values must be valid (see [tryCreate]).
  const CivilDate(this.year, this.month, this.day);

  /// The date with this day number (days since 1970-01-01).
  factory CivilDate.fromDayNumber(int dayNumber) {
    // Algorithm by Howard Hinnant ("civil_from_days").
    final z = dayNumber + 719468;
    final era = (z >= 0 ? z : z - 146096) ~/ 146097;
    final doe = z - era * 146097;
    final yoe = (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365;
    final doy = doe - (365 * yoe + yoe ~/ 4 - yoe ~/ 100);
    final mp = (5 * doy + 2) ~/ 153;
    final d = doy - (153 * mp + 2) ~/ 5 + 1;
    final m = mp < 10 ? mp + 3 : mp - 9;
    final y = yoe + era * 400 + (m <= 2 ? 1 : 0);
    return CivilDate(y, m, d);
  }

  /// The date of a UTC instant in milliseconds since 1970-01-01T00:00Z.
  factory CivilDate.fromInstant(int ms) =>
      CivilDate.fromDayNumber(_floorDiv(ms, msPerDay));

  /// Returns the date, or null if the values are not a valid date.
  static CivilDate? tryCreate(int year, int month, int day) {
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > daysInMonth(year, month)) return null;
    return CivilDate(year, month, day);
  }

  /// The year, for example 2026.
  final int year;

  /// The month, 1 to 12.
  final int month;

  /// The day of the month, 1 to 31.
  final int day;

  /// The number of days since 1970-01-01 (negative before).
  int get dayNumber {
    // Algorithm by Howard Hinnant ("days_from_civil").
    final y = month <= 2 ? year - 1 : year;
    final era = (y >= 0 ? y : y - 399) ~/ 400;
    final yoe = y - era * 400;
    final mp = month > 2 ? month - 3 : month + 9;
    final doy = (153 * mp + 2) ~/ 5 + day - 1;
    final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy;
    return era * 146097 + doe - 719468;
  }

  /// The ISO 8601 weekday: 1 = Monday, 7 = Sunday.
  int get weekday {
    // 1970-01-01 was a Thursday (4).
    final w = (dayNumber + 3) % 7;
    return (w < 0 ? w + 7 : w) + 1;
  }

  /// The day of the year, 1 to 366.
  int get dayOfYear => dayNumber - CivilDate(year, 1, 1).dayNumber + 1;

  /// The UTC instant at the start of this day, in milliseconds since
  /// 1970-01-01T00:00Z.
  int get startInstant => dayNumber * msPerDay;

  /// This date plus [days] days (can be negative).
  CivilDate addDays(int days) => CivilDate.fromDayNumber(dayNumber + days);

  /// This date plus [months] calendar months. If the day does not exist in
  /// the new month, the last day of that month is used.
  CivilDate addMonths(int months) {
    final total = year * 12 + (month - 1) + months;
    final y = _floorDiv(total, 12);
    final m = total - y * 12 + 1;
    final dim = daysInMonth(y, m);
    return CivilDate(y, m, day > dim ? dim : day);
  }

  /// The three-letter weekday, for example `MON`.
  String get weekdayAbbreviation => weekdayAbbreviations[weekday - 1];

  /// A text for messages, for example `Saturday 2026-07-04`.
  String get withWeekday => '${weekdayNames[weekday - 1]} $this';

  @override
  int compareTo(CivilDate other) => dayNumber.compareTo(other.dayNumber);

  bool operator <(CivilDate other) => compareTo(other) < 0;
  bool operator <=(CivilDate other) => compareTo(other) <= 0;
  bool operator >(CivilDate other) => compareTo(other) > 0;
  bool operator >=(CivilDate other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is CivilDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  /// The date as `YYYY-MM-DD`.
  @override
  String toString() => '${_pad(year, 4)}-${_pad(month, 2)}-${_pad(day, 2)}';
}

int _floorDiv(int a, int b) {
  final q = a ~/ b;
  return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
}

String _pad(int v, int width) {
  if (v < 0) return '-${(-v).toString().padLeft(width, '0')}';
  return v.toString().padLeft(width, '0');
}

/// Formats a time of day in milliseconds after 00:00Z as `hh:mmZ`, or as
/// `hh:mm:ssZ` if it has seconds. 86 400 000 is written as `24:00Z`.
String formatTimeOfDay(int ms) {
  final totalSeconds = ms ~/ 1000;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  final base = '${_pad(h, 2)}:${_pad(m, 2)}';
  return s == 0 ? '${base}Z' : '$base:${_pad(s, 2)}Z';
}

/// Formats minutes after 00:00Z (from the sun calculation) as `hh:mmZ`,
/// rounded to the nearest minute. Only the time of day is shown: -7 and
/// 1433 both give 23:53Z.
String formatMinutes(double minutes) {
  var m = minutes.round();
  while (m < 0) {
    m += 1440;
  }
  m %= 1440;
  return '${_pad(m ~/ 60, 2)}:${_pad(m % 60, 2)}Z';
}

/// Formats a UTC instant as `YYYY-MM-DDThh:mmZ` (with seconds if needed).
String formatInstant(int ms) {
  final date = CivilDate.fromInstant(ms);
  final ofDay = ms - date.startInstant;
  return '${date}T${formatTimeOfDay(ofDay)}';
}
