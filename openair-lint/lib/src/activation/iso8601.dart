/// A strict parser for the ISO 8601 values that `AA` commands use:
/// `Date`, `Time`, `DateTime` and durations.
///
/// Version 3.0 of the specification allows only these forms:
///
/// - `Date`: `YYYY-MM-DD`,
/// - `Time`: `hh:mmZ` or `hh:mm:ssZ`,
/// - `DateTime`: `YYYY-MM-DDThh:mmZ` or `YYYY-MM-DDThh:mm:ssZ`.
///
/// This parser also reads these other ISO 8601 forms, so that a rule can
/// show the value in an allowed form:
///
/// - the basic format without separators (`20260704`, `0800Z`),
/// - decimal fractions (`08:00:30.5Z`),
/// - a time with only the hour (`08Z`),
/// - a time with the time designator `T` in front (`T08:00Z`),
/// - week dates (`2026-W27-6`) and ordinal dates (`2026-185`),
/// - an interval end without the higher-order parts of the date
///   (`05T16:00Z` after `2026-07-04T08:00Z`, see [parseShortEndDateTime]),
/// - durations, also in the alternative format (`P0000-00-01T00:00:00`).
///
/// For the other forms of a value the result has a [IsoParse.formNote].
/// A time of day must end with `Z`. Time zone offsets (`+01:00`) and names
/// (`UTC`, `LT`) are errors.
///
/// Every function writes its problems to a list of [AaIssue]. Offsets are
/// `base` plus the position in the text, so they point into the `AA`
/// argument.
library;

import 'aa_issue.dart';
import 'civil_date.dart';

/// The result of parsing one value.
class IsoParse<T> {
  const IsoParse(this.value, {this.formNote, this.extended});

  /// The value, or null if the text has an error.
  final T? value;

  /// Why the value is not in an allowed form, for example
  /// `the basic format`, or null if it is in an allowed form.
  final String? formNote;

  /// True for the extended format (with `-` or `:`), false for the basic
  /// format, null if the value has no separators in any format (for example
  /// a time with only the hour).
  final bool? extended;
}

/// A duration such as `PT8H` or `P1DT2H`.
class IsoDuration {
  const IsoDuration({
    this.years = 0,
    this.months = 0,
    this.days = 0,
    this.ms = 0,
  });

  /// Calendar years.
  final int years;

  /// Calendar months.
  final int months;

  /// Days (weeks are counted as 7 days).
  final int days;

  /// Hours, minutes, seconds and fractions of days, in milliseconds.
  final int ms;

  /// True if every part is zero.
  bool get isZero => years == 0 && months == 0 && days == 0 && ms == 0;

  /// The instant [start] plus this duration. Years and months are added
  /// on the calendar. If the day does not exist in the new month, the last
  /// day of that month is used.
  int addTo(int start) {
    final date = CivilDate.fromInstant(start);
    final ofDay = start - date.startInstant;
    final d = date.addMonths(years * 12 + months).addDays(days);
    return d.startInstant + ofDay + ms;
  }

  /// The instant [end] minus this duration (the reverse of [addTo]).
  int subtractFrom(int end) {
    final t = end - ms;
    final date = CivilDate.fromInstant(t);
    final ofDay = t - date.startInstant;
    final d = date.addDays(-days).addMonths(-(years * 12 + months));
    return d.startInstant + ofDay;
  }
}

final RegExp _extDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _basicDate = RegExp(r'^(\d{4})(\d{2})(\d{2})$');
final RegExp _extWeek = RegExp(r'^(\d{4})-[Ww](\d{2})-(\d)$');
final RegExp _basicWeek = RegExp(r'^(\d{4})[Ww](\d{2})(\d)$');
final RegExp _extOrdinal = RegExp(r'^(\d{4})-(\d{3})$');
final RegExp _basicOrdinal = RegExp(r'^(\d{4})(\d{3})$');
final RegExp _sloppyDate = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
final RegExp _dayFirstDate = RegExp(r'^\d{1,2}[./-]\d{1,2}[./-]\d{4}$');
final RegExp _monthOnly = RegExp(r'^\d{4}-?\d{2}$');

/// The allowed form of a date, for messages.
const String allowedDateForm = 'YYYY-MM-DD';

/// The allowed forms of a time, for messages.
const String allowedTimeForms = 'hh:mmZ or hh:mm:ssZ';

/// The allowed forms of a date and time, for messages.
const String allowedDateTimeForms = 'YYYY-MM-DDThh:mmZ or YYYY-MM-DDThh:mm:ssZ';

// The short forms that messages use to ask for a value.
const String _dateForm = allowedDateForm;
const String _timeForm = 'hh:mmZ';
const String _dateTimeForm = 'YYYY-MM-DDThh:mmZ';

/// Parses a `Date` value, for example `2026-07-04`.
IsoParse<CivilDate> parseIsoDate(String text, int base, List<AaIssue> issues) {
  void error(String message) => issues.add(AaIssue(
      AaIssueKind.invalidDate, base, text.isEmpty ? 1 : text.length, message));

  if (text.isEmpty) {
    error('A date is missing. Write the date as $_dateForm, '
        'for example 2026-07-04.');
    return const IsoParse(null);
  }

  RegExpMatch? m;
  if ((m = _extDate.firstMatch(text)) != null ||
      (m = _basicDate.firstMatch(text)) != null) {
    final extended = text.contains('-');
    final y = int.parse(m!.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    if (mo < 1 || mo > 12) {
      error('"$text" is not a valid date. The month must be 01 to 12.');
      return const IsoParse(null);
    }
    final dim = daysInMonth(y, mo);
    if (d < 1 || d > dim) {
      error('"$text" is not a valid date. ${monthNames[mo - 1]} $y has '
          '$dim days.');
      return const IsoParse(null);
    }
    final date = CivilDate(y, mo, d);
    return IsoParse(date,
        extended: extended, formNote: extended ? null : 'the basic format');
  }

  if ((m = _extWeek.firstMatch(text)) != null ||
      (m = _basicWeek.firstMatch(text)) != null) {
    final y = int.parse(m!.group(1)!);
    final w = int.parse(m.group(2)!);
    final wd = int.parse(m.group(3)!);
    final weeks = isoWeeksInYear(y);
    if (w < 1 || w > weeks) {
      error('"$text" is not a valid week date. The year $y has weeks 01 to '
          '$weeks.');
      return const IsoParse(null);
    }
    if (wd < 1 || wd > 7) {
      error('"$text" is not a valid week date. The day of the week must be '
          '1 (Monday) to 7 (Sunday).');
      return const IsoParse(null);
    }
    final jan4 = CivilDate(y, 1, 4);
    final monday1 = jan4.addDays(1 - jan4.weekday);
    final date = monday1.addDays((w - 1) * 7 + wd - 1);
    return IsoParse(date,
        extended: text.contains('-'), formNote: 'a week date');
  }

  if ((m = _extOrdinal.firstMatch(text)) != null ||
      (m = _basicOrdinal.firstMatch(text)) != null) {
    final y = int.parse(m!.group(1)!);
    final n = int.parse(m.group(2)!);
    final days = daysInYear(y);
    if (n < 1 || n > days) {
      error('"$text" is not a valid ordinal date. The year $y has days 001 '
          'to $days.');
      return const IsoParse(null);
    }
    final date = CivilDate(y, 1, 1).addDays(n - 1);
    return IsoParse(date,
        extended: text.contains('-'), formNote: 'an ordinal date');
  }

  if (_sloppyDate.hasMatch(text)) {
    error('"$text" is not a valid date. Write two digits for the month and '
        'the day: $_dateForm, for example 2026-07-04.');
  } else if (_dayFirstDate.hasMatch(text)) {
    error('"$text" is not a valid date. Write the year first: '
        '$_dateForm, for example 2026-07-04.');
  } else if (_monthOnly.hasMatch(text)) {
    error('"$text" is not a full date. A date needs a year, a month and a '
        'day: $_dateForm, for example 2026-07-04.');
  } else {
    error('"$text" is not a valid date. Write the date as '
        '$_dateForm, for example 2026-07-04.');
  }
  return const IsoParse(null);
}

final RegExp _time = RegExp(r'^(\d+)(?::(\d+))?(?::(\d+))?(?:[.,](\d+))?(.*)$');
final RegExp _offset = RegExp(r'^([+\-−])(\d{2})(?::?(\d{2}))?$');
final RegExp _zoneName = RegExp(r'^[A-Za-z]+$');

/// Time zone names that mean UTC. They are still errors: the specification
/// asks for `Z`.
const Set<String> _utcNames = {'UTC', 'GMT', 'UT', 'ZULU'};

/// Parses a `Time` value, for example `09:00Z`.
///
/// The value is the time in milliseconds after 00:00Z. `24:00Z` is
/// 86 400 000 and is allowed only if [isEnd] is true.
///
/// [nextDayHint] is used in the message for `24:00Z` as a start, when the
/// time is part of a `DateTime`.
IsoParse<int> parseIsoTime(
  String text,
  int base,
  List<AaIssue> issues, {
  required bool isEnd,
  bool allowDesignator = true,
  String? nextDayHint,
}) {
  final length = text.isEmpty ? 1 : text.length;
  void error(AaIssueKind kind, String message,
          {int at = 0, int? len, String? replacement}) =>
      issues.add(AaIssue(kind, base + at, len ?? (length - at), message,
          replacement: replacement));
  void invalid(String message) => error(AaIssueKind.invalidTime, message);

  if (text.isEmpty) {
    invalid('A time is missing. Write the time as $_timeForm, '
        'for example 09:00Z.');
    return const IsoParse(null);
  }

  final notes = <String>[];
  var t = text;
  var skip = 0;
  if (t.startsWith('T') || t.startsWith('t')) {
    if (!allowDesignator) {
      invalid('"$text" is not a valid time. Write the time as '
          '$_timeForm, for example 09:00Z.');
      return const IsoParse(null);
    }
    t = t.substring(1);
    skip = 1;
    notes.add('the letter T in front');
  }

  final m = _time.firstMatch(t);
  if (m == null) {
    invalid('"$text" is not a valid time. Write the time as '
        '$_timeForm, for example 09:00Z.');
    return const IsoParse(null);
  }
  final g1 = m.group(1)!;
  final g2 = m.group(2);
  final g3 = m.group(3);
  final fraction = m.group(4);
  final zone = m.group(5)!;
  final zoneAt = skip + t.length - zone.length;

  int hour;
  int? minute;
  int? second;
  bool? extended;
  if (g2 != null) {
    extended = true;
    if (g1.length != 2 || g2.length != 2 || (g3 != null && g3.length != 2)) {
      invalid('"$text" is not a valid time. Write two digits for each part, '
          'for example 09:00Z.');
      return const IsoParse(null);
    }
    hour = int.parse(g1);
    minute = int.parse(g2);
    second = g3 == null ? null : int.parse(g3);
  } else {
    switch (g1.length) {
      case 2:
        hour = int.parse(g1);
      case 4:
        extended = false;
        hour = int.parse(g1.substring(0, 2));
        minute = int.parse(g1.substring(2, 4));
      case 6:
        extended = false;
        hour = int.parse(g1.substring(0, 2));
        minute = int.parse(g1.substring(2, 4));
        second = int.parse(g1.substring(4, 6));
      case 1:
        invalid('"$text" is not a valid time. Write two digits for the '
            'hour, for example 09:00Z.');
        return const IsoParse(null);
      default:
        invalid('"$text" is not a valid time. Write the time as '
            '$_timeForm, for example 09:00Z.');
        return const IsoParse(null);
    }
  }

  // The zone designator.
  var zoneOk = false;
  int? offsetMinutes;
  final upperZone = zone.toUpperCase();
  if (zone.isEmpty) {
    error(
        AaIssueKind.timeMissingZ,
        '"$text" has no Z. All times in OpenAir are UTC. Write Z after '
        'the time, for example ${_suggestZ(text)}.');
  } else if (upperZone == 'Z') {
    zoneOk = true;
  } else if (upperZone.startsWith('Z') && upperZone != 'ZULU') {
    invalid('"$text" is not a valid time. Remove "${zone.substring(1)}" '
        'after the Z.');
    return const IsoParse(null);
  } else if (_offset.firstMatch(zone) case final om?) {
    final sign = om.group(1) == '+' ? 1 : -1;
    final oh = int.parse(om.group(2)!);
    final omin = int.parse(om.group(3) ?? '0');
    offsetMinutes = sign * (oh * 60 + omin);
    if (offsetMinutes == 0) {
      error(AaIssueKind.timeZoneNotZ,
          'Write Z in place of "$zone". The time is already UTC.',
          at: zoneAt,
          // An offset of 0 is UTC, so only the zone text changes.
          replacement: 'Z');
    }
  } else if (_zoneName.hasMatch(zone)) {
    if (_utcNames.contains(upperZone)) {
      error(AaIssueKind.timeZoneNotZ,
          'Write Z in place of "$zone", for example ${_suggestZ(text)}.',
          at: zoneAt,
          // UTC, UT, ZULU and GMT are the same as Z.
          replacement: 'Z');
    } else if (upperZone == 'LT' || upperZone == 'L') {
      error(
          AaIssueKind.timeZoneNotZ,
          '"$zone" means local time. OpenAir supports only UTC. Convert the '
          'time to UTC and write Z after it.',
          at: zoneAt);
    } else {
      error(
          AaIssueKind.timeZoneNotZ,
          '"$zone" is a time zone name. OpenAir supports only UTC. Convert '
          'the time to UTC and write Z after it.',
          at: zoneAt);
    }
  } else {
    invalid('"$text" is not a valid time. Remove "$zone" after the time. '
        'Write the time as $_timeForm, for example 09:00Z.');
    return const IsoParse(null);
  }

  // The ranges of the values.
  if (hour > 24 || (minute != null && minute > 59)) {
    invalid('"$text" is not a valid time. The hour must be 00 to 23 and the '
        'minutes 00 to 59.');
    return const IsoParse(null);
  }
  if (second != null && second > 59) {
    invalid('"$text" is not a valid time. The seconds must be 00 to 59.');
    return const IsoParse(null);
  }
  var unitMs = 3600000;
  if (minute != null) unitMs = 60000;
  if (second != null) unitMs = 1000;
  var fractionMs = 0;
  if (fraction != null) {
    // Cut the fraction to whole milliseconds (do not round up). Rounding
    // up could make 23:59:59.9999Z the next day (24:00Z). Integer
    // arithmetic avoids errors of doubles. 9 digits are enough: the
    // smallest unit is one second, and the result must stay below 2^53 on
    // the web.
    final digits = fraction.length > 9 ? fraction.substring(0, 9) : fraction;
    var scale = 1;
    for (var i = 0; i < digits.length; i++) {
      scale *= 10;
    }
    fractionMs = int.parse(digits) * unitMs ~/ scale;
  }
  final ms = hour * 3600000 +
      (minute ?? 0) * 60000 +
      (second ?? 0) * 1000 +
      fractionMs;
  if (hour == 24) {
    if (ms != msPerDay) {
      invalid('"$text" is not a valid time. With the hour 24, only 24:00Z or '
          '24:00:00Z is allowed.');
      return const IsoParse(null);
    }
    if (!isEnd) {
      error(
          AaIssueKind.time24AsStart,
          nextDayHint == null
              ? '24:00Z is allowed only as an end time. Use 00:00Z as a '
                  'start time.'
              : '24:00Z is allowed only as an end time. As a start, write '
                  '$nextDayHint.');
      return const IsoParse(null);
    }
  }
  if (!zoneOk) {
    if (offsetMinutes != null && offsetMinutes != 0) {
      final utc = ms - offsetMinutes * 60000;
      final dayShift = utc < 0
          ? ' on the previous day'
          : (utc >= msPerDay ? ' on the next day' : '');
      final utcOfDay = ((utc % msPerDay) + msPerDay) % msPerDay;
      error(
          AaIssueKind.timeZoneNotZ,
          '"$zone" is a time zone offset. OpenAir supports only UTC. '
          '"$text" is ${formatTimeOfDay(utcOfDay)}$dayShift.',
          at: zoneAt);
    }
    return const IsoParse(null);
  }

  if (extended == false) notes.add('the basic format');
  if (fraction != null) notes.add('a decimal fraction');
  if (minute == null) notes.add('only the hour');
  return IsoParse(ms,
      extended: extended, formNote: notes.isEmpty ? null : _joinWords(notes));
}

/// A suggestion with Z for a time without Z or with a UTC name.
String _suggestZ(String text) {
  final m = RegExp(r'^[Tt]?(\d{2}):?(\d{2})').firstMatch(text);
  if (m == null) return '09:00Z';
  return '${m.group(1)}:${m.group(2)}Z';
}

final RegExp _dateTime = RegExp(r'^([0-9Ww-]+)[Tt](.*)$');

/// The names of the sun events (upper case).
const Set<String> sunEventKeywords = {'SR', 'SS', 'BCMT', 'EECT'};

/// Parses a `DateTime` value, for example `2026-07-04T08:00Z`.
///
/// The value is in milliseconds since 1970-01-01T00:00Z. `T24:00Z` is the
/// start of the next day and is allowed only if [isEnd] is true.
IsoParse<int> parseIsoDateTime(String text, int base, List<AaIssue> issues,
    {required bool isEnd}) {
  final m = _dateTime.firstMatch(text);
  if (m == null) {
    final probe = <AaIssue>[];
    if (text.isNotEmpty && parseIsoDate(text, 0, probe).value != null) {
      issues.add(AaIssue(
          AaIssueKind.invalidTime,
          base,
          text.length,
          '"$text" has no time of day. An interval needs a date and a time, '
          'for example ${text}T00:00Z.'));
    } else {
      issues.add(AaIssue(
          AaIssueKind.invalidTime,
          base,
          text.isEmpty ? 1 : text.length,
          '"$text" is not a valid date and time. Write it as '
          '$_dateTimeForm, for example 2026-07-04T08:00Z.'));
    }
    return const IsoParse(null);
  }
  final datePart = m.group(1)!;
  final timePart = m.group(2)!;
  final timeBase = base + datePart.length + 1;
  final date = parseIsoDate(datePart, base, issues);
  if (sunEventKeywords.contains(timePart.toUpperCase())) {
    issues.add(AaIssue(
        AaIssueKind.sunEventNotAllowed,
        timeBase,
        timePart.length,
        'The sun event $timePart cannot be used in a date. Sun events are '
        'allowed only in weekday AA commands, for example AA SR/SS.'));
    return const IsoParse(null);
  }
  final next = date.value?.addDays(1);
  final time = parseIsoTime(timePart, timeBase, issues,
      isEnd: isEnd,
      allowDesignator: false,
      nextDayHint: next == null ? null : '${next}T00:00Z');
  if (date.value == null || time.value == null) return const IsoParse(null);

  if (date.extended != null &&
      time.extended != null &&
      date.extended != time.extended) {
    issues.add(AaIssue(
        AaIssueKind.invalidTime,
        base,
        text.length,
        '"$text" mixes the basic format and the extended format. Use the '
        'same format for the date and the time, for example '
        '${formatInstant(date.value!.startInstant + time.value!)}.'));
    return const IsoParse(null);
  }
  final notes = [
    if (date.formNote != null) date.formNote!,
    if (time.formNote != null) time.formNote!,
  ];
  return IsoParse(date.value!.startInstant + time.value!,
      extended: date.extended ?? time.extended,
      formNote: notes.isEmpty ? null : _joinWords(notes.toSet()));
}

final RegExp _shortMonthDayExtended = RegExp(r'^(\d{2})-(\d{2})$');
final RegExp _shortMonthDayBasic = RegExp(r'^(\d{2})(\d{2})$');
final RegExp _shortDay = RegExp(r'^(\d{2})$');

/// Parses the end of an interval in which the higher-order parts of the
/// date are left out, for example `05T16:00Z` (only the day) or
/// `07-05T16:00Z` (the month and the day) after the start
/// `2026-07-04T08:00Z`. ISO 8601 takes the missing parts from the start
/// ([startDate]).
///
/// Returns null, and adds no issue, if the date part of [text] is not one of
/// these short forms. Then the caller reads [text] as a full `DateTime`.
IsoParse<int>? parseShortEndDateTime(
    String text, int base, List<AaIssue> issues, CivilDate startDate) {
  final m = _dateTime.firstMatch(text);
  if (m == null) return null;
  final datePart = m.group(1)!;
  final timePart = m.group(2)!;
  int month;
  int day;
  bool? extended;
  RegExpMatch? d;
  if ((d = _shortMonthDayExtended.firstMatch(datePart)) != null) {
    month = int.parse(d!.group(1)!);
    day = int.parse(d.group(2)!);
    extended = true;
  } else if ((d = _shortMonthDayBasic.firstMatch(datePart)) != null) {
    month = int.parse(d!.group(1)!);
    day = int.parse(d.group(2)!);
    extended = false;
  } else if ((d = _shortDay.firstMatch(datePart)) != null) {
    month = startDate.month;
    day = int.parse(d!.group(1)!);
  } else {
    return null;
  }
  final year = startDate.year;
  final date = CivilDate.tryCreate(year, month, day);
  if (date == null) {
    final reason = month < 1 || month > 12
        ? 'The month must be 01 to 12.'
        : '${monthNames[month - 1]} $year has ${daysInMonth(year, month)} '
            'days.';
    issues.add(AaIssue(
        AaIssueKind.invalidDate,
        base,
        datePart.length,
        '"$datePart" is not a valid date. The end takes the missing parts of '
        'the date from the start ($startDate). $reason'));
    return const IsoParse(null);
  }
  final timeBase = base + datePart.length + 1;
  if (sunEventKeywords.contains(timePart.toUpperCase())) {
    issues.add(AaIssue(
        AaIssueKind.sunEventNotAllowed,
        timeBase,
        timePart.length,
        'The sun event $timePart cannot be used in a date. Sun events are '
        'allowed only in weekday AA commands, for example AA SR/SS.'));
    return const IsoParse(null);
  }
  final time = parseIsoTime(timePart, timeBase, issues,
      isEnd: true, allowDesignator: false);
  if (time.value == null) return const IsoParse(null);
  final value = date.startInstant + time.value!;
  if (extended != null && time.extended != null && extended != time.extended) {
    issues.add(AaIssue(
        AaIssueKind.invalidTime,
        base,
        text.length,
        '"$text" mixes the basic format and the extended format. Use the '
        'same format for the date and the time, for example '
        '${formatInstant(value)}.'));
    return const IsoParse(null);
  }
  return IsoParse(value,
      extended: extended ?? time.extended,
      formNote: 'a short end without the year');
}

/// Joins words for a message: `a`, `a and b`, `a, b and c`.
String _joinWords(Iterable<String> words) {
  final list = words.toList();
  if (list.length <= 1) return list.join();
  return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
}

final RegExp _number = RegExp(r'^(\d+)(?:[.,](\d+))?$');
final RegExp _durationParts = RegExp(
    r'^[Pp]((?:\d+(?:[.,]\d+)?[YyMmWwDd])*)(?:[Tt]((?:\d+(?:[.,]\d+)?[HhMmSs])*))?$');
final RegExp _durationItem = RegExp(r'(\d+(?:[.,]\d+)?)([A-Za-z])');
final RegExp _altDurationExtended =
    RegExp(r'^[Pp](\d{4})-(\d{2})-(\d{2})(?:[Tt](\d{2}):(\d{2}):(\d{2}))?$');
final RegExp _altDurationBasic =
    RegExp(r'^[Pp](\d{4})(\d{2})(\d{2})(?:[Tt](\d{2})(\d{2})(\d{2}))?$');
final RegExp _altDurationLike = RegExp(r'^[Pp]\d{4}-?\d{2}');

/// The longest duration that the parser accepts, in days (about 10 000
/// years). A longer duration cannot give a valid date.
const int maxDurationDays = 3660000;

/// The largest number of digits in one value of a duration. A value with
/// more digits is too large in every case. The limit also keeps the
/// arithmetic exact when the code runs as JavaScript.
const int _maxDurationDigits = 9;

/// Parses a duration, for example `PT8H`, `P1D` or `P1DT12H`.
///
/// The alternative format of ISO 8601 (`P0000-00-01T00:00:00` or
/// `P00000001T000000`) is also read. Its form note is
/// `the alternative format`.
///
/// A duration longer than [maxDurationDays] is an error.
IsoParse<IsoDuration> parseIsoDuration(
    String text, int base, List<AaIssue> issues) {
  void error(String message) => issues.add(AaIssue(AaIssueKind.invalidDuration,
      base, text.isEmpty ? 1 : text.length, message));

  const help = 'Write a duration as PnYnMnDTnHnMnS, for example PT8H '
      '(8 hours) or P1D (1 day).';
  final tooLong = '"$text" is too long. A duration must be shorter than '
      '10 000 years.';
  final m = _durationParts.firstMatch(text);
  if (m == null) {
    final alt = _altDurationExtended.firstMatch(text) ??
        _altDurationBasic.firstMatch(text);
    if (alt != null) return _alternativeDuration(text, alt, error);
    if (_altDurationLike.hasMatch(text)) {
      error('"$text" is not a valid duration in the alternative format. '
          'Write it as PYYYY-MM-DDThh:mm:ss, for example P0000-00-01T00:00:00 '
          '(1 day). Or write it as PnYnMnDTnHnMnS, for example P1D.');
    } else {
      error('"$text" is not a valid duration. $help');
    }
    return const IsoParse(null);
  }
  final datePart = m.group(1)!;
  final timePart = m.group(2);
  if (timePart != null && timePart.isEmpty) {
    error('"$text" is not a valid duration. Write at least one value after '
        'T. $help');
    return const IsoParse(null);
  }
  final items = <(String, String, bool)>[
    for (final i in _durationItem.allMatches(datePart))
      (i.group(1)!, i.group(2)!.toUpperCase(), false),
    if (timePart != null)
      for (final i in _durationItem.allMatches(timePart))
        (i.group(1)!, i.group(2)!.toUpperCase(), true),
  ];
  if (items.isEmpty) {
    error('"$text" is not a valid duration. $help');
    return const IsoParse(null);
  }
  // The order of the designators must be Y M W D and H M S, each once.
  const dateOrder = ['Y', 'M', 'W', 'D'];
  const timeOrder = ['H', 'M', 'S'];
  var lastDate = -1;
  var lastTime = -1;
  for (final (_, unit, inTime) in items) {
    final order = inTime ? timeOrder : dateOrder;
    final idx = order.indexOf(unit);
    final last = inTime ? lastTime : lastDate;
    if (idx < 0 || idx <= last) {
      error('"$text" is not a valid duration. $help');
      return const IsoParse(null);
    }
    if (inTime) {
      lastTime = idx;
    } else {
      lastDate = idx;
    }
  }

  var years = 0;
  var months = 0;
  var days = 0;
  var ms = 0;
  for (var i = 0; i < items.length; i++) {
    final (value, unit, inTime) = items[i];
    final nm = _number.firstMatch(value)!;
    final digits = nm.group(1)!.replaceFirst(RegExp('^0+(?=.)'), '');
    if (digits.length > _maxDurationDigits) {
      error(tooLong);
      return const IsoParse(null);
    }
    final whole = int.parse(digits);
    final frac = nm.group(2);
    if (frac != null && i != items.length - 1) {
      error('"$text" is not a valid duration. Only the last value can have '
          'a decimal fraction.');
      return const IsoParse(null);
    }
    final f = frac == null ? 0.0 : double.parse('0.$frac');
    if (!inTime && (unit == 'Y' || unit == 'M')) {
      if (frac != null) {
        error('"$text" has a decimal fraction of a year or a month. The '
            'length of a year or a month is not fixed. Use days or hours.');
        return const IsoParse(null);
      }
      if (unit == 'Y') years = whole;
      if (unit == 'M') months = whole;
      continue;
    }
    final unitMs = inTime
        ? switch (unit) { 'H' => 3600000, 'M' => 60000, _ => 1000 }
        : (unit == 'W' ? 7 * msPerDay : msPerDay);
    if (!inTime) {
      days += whole * (unit == 'W' ? 7 : 1);
      ms += (f * unitMs).round();
    } else {
      ms += whole * unitMs + (f * unitMs).round();
    }
  }
  final duration =
      IsoDuration(years: years, months: months, days: days, ms: ms);
  if (!_durationFits(duration)) {
    error(tooLong);
    return const IsoParse(null);
  }
  return IsoParse(duration);
}

/// True if [d] is not longer than [maxDurationDays].
bool _durationFits(IsoDuration d) =>
    d.years * 366 + d.months * 31 + d.days + d.ms ~/ msPerDay <=
    maxDurationDays;

/// Reads a duration in the alternative format, for example
/// `P0000-00-01T00:00:00`. ISO 8601 does not allow values above the
/// "carry-over points": 12 months, 30 days, 24 hours, 59 minutes and 59
/// seconds.
IsoParse<IsoDuration> _alternativeDuration(
    String text, RegExpMatch m, void Function(String) error) {
  int part(int group) => int.parse(m.group(group) ?? '0');
  final years = part(1);
  final months = part(2);
  final days = part(3);
  final hours = part(4);
  final minutes = part(5);
  final seconds = part(6);
  if (months > 12 || days > 30 || hours > 24 || minutes > 59 || seconds > 59) {
    error('"$text" is not a valid duration in the alternative format. The '
        'months must be 00 to 12, the days 00 to 30, the hours 00 to 24, and '
        'the minutes and the seconds 00 to 59.');
    return const IsoParse(null);
  }
  final duration = IsoDuration(
      years: years,
      months: months,
      days: days,
      ms: hours * 3600000 + minutes * 60000 + seconds * 1000);
  if (!_durationFits(duration)) {
    error('"$text" is too long. A duration must be shorter than 10 000 '
        'years.');
    return const IsoParse(null);
  }
  return IsoParse(duration,
      formNote: 'the alternative format', extended: text.contains('-'));
}
