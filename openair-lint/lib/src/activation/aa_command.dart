/// The model of one `AA` command and its parser.
///
/// ```dart
/// final aa = parseAa('MON-FRI 07:00Z/15:00Z 2026-03-29/2026-10-24');
/// if (aa is AaWeekdayCommand) print(aa.weekdays); // {1, 2, 3, 4, 5}
/// ```
library;

import '../values/text_parts.dart';
import 'aa_issue.dart';
import 'civil_date.dart';
import 'iso8601.dart';
import 'sun.dart';

/// One parsed `AA` command.
///
/// The parser is lenient: it always returns a command, also when the text
/// has errors. [issues] lists the problems. A command with a blocking
/// problem ([isUsable] is false) has some values missing (null).
sealed class AaCommand {
  AaCommand(this.text, this.issues);

  /// The argument of the command as written, for example
  /// `MON 09:00Z/11:30Z`.
  final String text;

  /// The problems found, with offsets in [text].
  final List<AaIssue> issues;

  /// True if the command has no blocking problem, so that a reader can use
  /// it.
  bool get isUsable => !issues.any((i) => i.kind.blocking);

  /// The kind of command, for messages: `interval`, `weekday`, ...
  String get kindLabel;
}

/// `AA NONE`: no known activation time. Version 2.1 allows it. Version 3.0
/// does not allow it (rule `aa-none-removed`).
final class AaNoneCommand extends AaCommand {
  AaNoneCommand(super.text, super.issues);

  @override
  String get kindLabel => 'AA NONE';
}

/// An interval: `AA StartDateTime/EndDateTime`, also with `NONE` on one
/// side. The parser also reads the other ISO 8601 interval forms (with a
/// duration or with a short end) and reports them as not allowed.
final class AaIntervalCommand extends AaCommand {
  AaIntervalCommand(super.text, super.issues,
      {this.start, this.end, this.startIsNone = false, this.endIsNone = false});

  /// The start in milliseconds since 1970-01-01T00:00Z, or null if it is
  /// `NONE` or not valid.
  final int? start;

  /// The end in milliseconds since 1970-01-01T00:00Z, or null if it is
  /// `NONE` or not valid.
  final int? end;

  /// True if the start is `NONE` (no known start).
  final bool startIsNone;

  /// True if the end is `NONE` (no known end).
  final bool endIsNone;

  @override
  String get kindLabel => 'interval';
}

/// A time of day in a weekday command: a fixed time or a sun event.
class AaTimeOfDay {
  const AaTimeOfDay.fixed(int this.ms) : sunEvent = null;
  const AaTimeOfDay.sun(SunEvent this.sunEvent) : ms = null;

  /// Milliseconds after 00:00Z (0 to 86 400 000), or null for a sun event.
  final int? ms;

  /// The sun event, or null for a fixed time.
  final SunEvent? sunEvent;

  /// True for a sun event.
  bool get isSunEvent => sunEvent != null;

  @override
  bool operator ==(Object other) =>
      other is AaTimeOfDay && other.ms == ms && other.sunEvent == sunEvent;

  @override
  int get hashCode => Object.hash(ms, sunEvent);

  @override
  String toString() => sunEvent?.keyword ?? formatTimeOfDay(ms!);
}

/// A weekday command: `AA [Weekdays] StartTime/EndTime [StartDate/EndDate]`.
final class AaWeekdayCommand extends AaCommand {
  AaWeekdayCommand(
    super.text,
    super.issues, {
    required this.weekdays,
    required this.weekdaysGiven,
    this.startTime,
    this.endTime,
    this.hasDateRange = false,
    this.fromDate,
    this.toDate,
  });

  /// The ISO weekdays (1 = Monday, 7 = Sunday) on which windows start.
  /// All seven days if the weekdays are left out.
  final Set<int> weekdays;

  /// True if the command has a list of weekdays.
  final bool weekdaysGiven;

  /// The start of each window, or null if it is not valid.
  final AaTimeOfDay? startTime;

  /// The end of each window, or null if it is not valid.
  final AaTimeOfDay? endTime;

  /// True if the command has a date range (also `NONE/NONE`).
  final bool hasDateRange;

  /// The first date of the date range, or null (no limit or not valid).
  final CivilDate? fromDate;

  /// The last date of the date range (included), or null.
  final CivilDate? toDate;

  /// True if the start or the end is a sun event.
  bool get usesSunEvent =>
      (startTime?.isSunEvent ?? false) || (endTime?.isSunEvent ?? false);

  /// True if a window starts on [date] (the exceptions are not used).
  bool startsOn(CivilDate date) =>
      weekdays.contains(date.weekday) &&
      (fromDate == null || date >= fromDate!) &&
      (toDate == null || date <= toDate!);

  @override
  String get kindLabel => 'weekday';
}

/// An exception: `AA EXCEPT Date` or `AA EXCEPT StartDate/EndDate`.
final class AaExceptCommand extends AaCommand {
  AaExceptCommand(super.text, super.issues, {this.fromDate, this.toDate});

  /// The first excepted date, or null if it is not valid.
  final CivilDate? fromDate;

  /// The last excepted date (included), or null if it is not valid. For a
  /// single date it is the same as [fromDate].
  final CivilDate? toDate;

  /// True if [date] is excepted.
  bool contains(CivilDate date) =>
      fromDate != null &&
      toDate != null &&
      date >= fromDate! &&
      date <= toDate!;

  @override
  String get kindLabel => 'AA EXCEPT';
}

/// A command that does not match any form.
final class AaUnknownCommand extends AaCommand {
  AaUnknownCommand(super.text, super.issues);

  @override
  String get kindLabel => 'unknown';
}

/// The weekday keywords and their ISO numbers.
const Map<String, int> weekdayNumbers = {
  'MON': 1,
  'TUE': 2,
  'WED': 3,
  'THU': 4,
  'FRI': 5,
  'SAT': 6,
  'SUN': 7,
};

/// Wrong weekday names that people often write, and the right name.
const Map<String, String> _weekdayAliases = {
  'MO': 'MON',
  'MONDAY': 'MON',
  'TU': 'TUE',
  'TUES': 'TUE',
  'TUESDAY': 'TUE',
  'WE': 'WED',
  'WEDNESDAY': 'WED',
  'TH': 'THU',
  'THUR': 'THU',
  'THURS': 'THU',
  'THURSDAY': 'THU',
  'FR': 'FRI',
  'FRIDAY': 'FRI',
  'SA': 'SAT',
  'SATURDAY': 'SAT',
  'SU': 'SUN',
  'SUNDAY': 'SUN',
};

/// ICAO schedule abbreviations that OpenAir does not use, with advice.
const Map<String, String> _scheduleCodes = {
  'H24': 'H24 (continuous) is not an AA value. An airspace without AA '
      'commands is always active.',
  'HJ': 'HJ (sunrise to sunset) is not an AA value. Write AA SR/SS.',
  'HN': 'HN (sunset to sunrise) is not an AA value. Write AA SS/SR.',
  'HX': 'HX (no specific hours) is not an AA value. If the airspace is '
      'always active, leave out the AA commands. If the activation times '
      'are not known, remove the airspace from the file.',
  'HO': 'HO (service available to meet operational requests) is not an AA '
      'value. If the airspace is always active, leave out the AA commands. '
      'If the activation times are not known, remove the airspace from the '
      'file.',
  'NOTAM': 'NOTAM is not an AA value. Write AS NOTAM for an airspace that '
      'is activated by NOTAM, and write the known activation times as AA '
      'commands.',
  'PH': 'Public holidays are not an AA value. The file must be '
      'self-contained. Write each holiday as AA EXCEPT Date.',
  'HOL': 'Public holidays are not an AA value. The file must be '
      'self-contained. Write each holiday as AA EXCEPT Date.',
};

/// The advice of [_scheduleCodes] for a file of version 2.1, where it is
/// different. Version 2.1 allows `AA NONE`.
const Map<String, String> _scheduleCodesV21 = {
  'HX': 'HX (no specific hours) is not an AA value. Write AA NONE, or '
      'leave out the AA commands.',
  'HO': 'HO (service available to meet operational requests) is not an AA '
      'value. Write AA NONE, or leave out the AA commands.',
  'NOTAM': 'NOTAM is not an AA value. Write AA NONE for an airspace that is '
      'activated by NOTAM.',
};

/// The advice for a schedule code after a list of weekdays, for example
/// `MON-FRI HJ`.
String _scheduleCodeAfterDays(String code, String days) => switch (code) {
      'H24' => 'H24 (continuous) is not an AA value. For whole days, write '
          'AA $days 00:00Z/24:00Z.',
      'HJ' => 'HJ (sunrise to sunset) is not an AA value. Write AA $days '
          'SR/SS.',
      'HN' => 'HN (sunset to sunrise) is not an AA value. Write AA $days '
          'SS/SR.',
      _ => _scheduleCodes[code]!,
    };

const String _forms = 'Use one of these forms: '
    'AA 2026-07-04T08:00Z/2026-07-04T16:00Z, AA MON-FRI 07:00Z/15:00Z, '
    'AA EXCEPT 2026-12-25.';

final RegExp _dayWord = RegExp(r'^[A-Za-z,\-]+$');

/// A time window with "-" in place of "/", for example `07:00Z-15:00Z`.
final RegExp _dashWindow = RegExp(
    r'^(\d{1,2}:?\d{2}(?::?\d{2})?[Zz]?|SR|SS|BCMT|EECT)-'
    r'(\d{1,2}:?\d{2}(?::?\d{2})?[Zz]?|SR|SS|BCMT|EECT)$',
    caseSensitive: false);

/// Parses the argument of an `AA` command (the text after `AA`, without the
/// comment). It never throws.
///
/// Two common typing errors are reported and then repaired before the
/// command is read, so that the other issues are still useful:
///
/// - a dash that is not the hyphen `-`, for example the en dash `–`,
/// - spaces before or after `/`, for example `07:00Z /15:00Z`.
AaCommand parseAa(String argument) {
  final early = <AaIssue>[];
  // Other dashes have the same length as "-", so the offsets do not change.
  var text = argument;
  for (final m in _otherDash.allMatches(argument)) {
    early.add(AaIssue(AaIssueKind.invalidSyntax, m.start, 1,
        'Use "-" (hyphen), not "${m[0]}".',
        replacement: '-'));
  }
  if (early.isNotEmpty) text = argument.replaceAll(_otherDash, '-');

  final joined = _SlashJoin.of(text);
  final parser = _AaParser(joined?.text ?? text, argument);
  final command = parser.parse();
  final issues = parser.issues;
  if (joined != null) {
    for (var i = 0; i < issues.length; i++) {
      issues[i] = joined.mapIssue(issues[i]);
    }
    early.addAll(joined.issues);
  }
  issues.insertAll(0, early);
  return command;
}

/// Dashes that are not the hyphen "-": U+2010 to U+2015 (hyphen, en dash,
/// em dash and others) and U+2212 (minus sign).
final RegExp _otherDash = RegExp('[${String.fromCharCode(0x2010)}-'
    '${String.fromCharCode(0x2015)}${String.fromCharCode(0x2212)}]');

/// Removes the spaces around `/` and remembers where each character was in
/// the original text.
class _SlashJoin {
  _SlashJoin._(this.text, this._map, this._sourceLength, this.issues);

  /// The text without the spaces around `/`, or null if there are no such
  /// spaces.
  static _SlashJoin? of(String source) {
    final spaced = RegExp(r'[\x00-\x20]*/[\x00-\x20]*');
    final matches = [
      for (final m in spaced.allMatches(source))
        if (m.end - m.start > 1) m
    ];
    if (matches.isEmpty) return null;
    final buffer = StringBuffer();
    final map = <int>[];
    final slashes = <(int, int, int)>[]; // (start, end, index in text)
    var i = 0;
    for (final m in matches) {
      for (var k = i; k < m.start; k++) {
        buffer.write(source[k]);
        map.add(k);
      }
      slashes.add((m.start, m.end, buffer.length));
      buffer.write('/');
      map.add(source.indexOf('/', m.start));
      i = m.end;
    }
    for (var k = i; k < source.length; k++) {
      buffer.write(source[k]);
      map.add(k);
    }
    final text = buffer.toString();
    final issues = <AaIssue>[];
    for (final (start, end, at) in slashes) {
      var from = at;
      while (from > 0 && text.codeUnitAt(from - 1) > 0x20) {
        from--;
      }
      var to = at + 1;
      while (to < text.length && text.codeUnitAt(to) > 0x20) {
        to++;
      }
      issues.add(AaIssue(AaIssueKind.invalidSyntax, start, end - start,
          'Remove the spaces around "/". Write "${text.substring(from, to)}".',
          replacement: '/'));
    }
    return _SlashJoin._(text, map, source.length, issues);
  }

  /// The text without the spaces around `/`.
  final String text;

  /// For each character of [text], its position in the original text.
  final List<int> _map;

  final int _sourceLength;

  /// One issue for each `/` with spaces, in the original text.
  final List<AaIssue> issues;

  /// The issue with offsets in the original text.
  AaIssue mapIssue(AaIssue issue) {
    final n = _map.length;
    int start(int o) => o >= n ? _sourceLength : _map[o < 0 ? 0 : o];
    int end(int e) => e <= 0 ? 0 : (e > n ? _sourceLength : _map[e - 1] + 1);
    final s = start(issue.offset);
    final length = end(issue.offset + issue.length) - s;
    final fs = start(issue.fixOffset);
    final fixLength =
        issue.fixLength == 0 ? 0 : end(issue.fixOffset + issue.fixLength) - fs;
    return issue.at(s, length < 1 ? 1 : length,
        fixOffset: fs, fixLength: fixLength < 0 ? 0 : fixLength);
  }
}

/// The shape of one side of a `/`, before it is parsed.
enum _Shape { empty, none, sun, duration, dateTime, date, time, unknown }

final RegExp _dateTimeShape = RegExp(r'^[0-9Ww-]+[Tt]');
final RegExp _dateShape = RegExp(r'^(\d{4}-|\d{4}[Ww]|\d{7,8}$)');

_Shape _shapeOf(String s) {
  if (s.isEmpty) return _Shape.empty;
  final u = s.toUpperCase();
  if (u == 'NONE') return _Shape.none;
  if (sunEventKeywords.contains(u)) return _Shape.sun;
  if (u.startsWith('P')) return _Shape.duration;
  if (_dateTimeShape.hasMatch(s) && RegExp(r'^\d').hasMatch(s)) {
    return _Shape.dateTime;
  }
  if (RegExp(r'^[Tt]\d').hasMatch(s)) return _Shape.time;
  if (_dateShape.hasMatch(s)) return _Shape.date;
  if (RegExp(r'^\d').hasMatch(s)) return _Shape.time;
  return _Shape.unknown;
}

class _AaParser {
  _AaParser(this.text, this.source);

  /// The text that the parser reads (after the repairs of [parseAa]).
  final String text;

  /// The argument as written. The command keeps this text.
  final String source;

  final List<AaIssue> issues = [];

  void _issue(AaIssueKind kind, int offset, int length, String message,
          {String? v21Message,
          String? replacement,
          int? fixOffset,
          int? fixLength}) =>
      issues.add(AaIssue(kind, offset, length < 1 ? 1 : length, message,
          v21Message: v21Message,
          replacement: replacement,
          fixOffset: fixOffset,
          fixLength: fixLength));

  void _syntax(int offset, int length, String message,
          {String? v21Message, String? replacement}) =>
      _issue(AaIssueKind.invalidSyntax, offset, length, message,
          v21Message: v21Message, replacement: replacement);

  /// Reports a value in an ISO 8601 form that the specification does not
  /// allow. [note] says which form (from [IsoParse.formNote]); nothing is
  /// reported if it is null. [allowedForms] are the allowed forms and
  /// [correctValue] is the value in an allowed form.
  void _formNotAllowed(
      TextPart part, String? note, String allowedForms, String correctValue) {
    if (note == null) return;
    final what = '"${part.text}" uses $note.';
    final fix = 'Write it as $allowedForms: "$correctValue".';
    _issue(AaIssueKind.valueFormNotAllowed, part.offset, part.text.length,
        '$what This form is not allowed. $fix',
        v21Message: '$what This form is not allowed in version 3.0. $fix',
        // The correct value has whole seconds. A value with a decimal
        // fraction gets no automatic fix, because the fraction would be lost.
        replacement: note.contains('fraction') ? null : correctValue);
  }

  /// Reports an interval in an ISO 8601 form other than
  /// StartDateTime/EndDateTime. [what] says what is wrong, [form] names the
  /// form. If [start] and [end] are known, the message shows the interval
  /// in the allowed form.
  void _intervalFormNotAllowed(TextPart whole, String what, String form,
      {int? start, int? end}) {
    final known = start != null && end != null && end > start;
    final fix = start != null && end != null && end > start
        ? 'Write the interval as StartDateTime/EndDateTime: '
            '"${formatInstant(start)}/${formatInstant(end)}".'
        : 'Write the interval as StartDateTime/EndDateTime, for example '
            '2026-07-04T08:00Z/2026-07-04T16:00Z.';
    _issue(AaIssueKind.intervalFormNotAllowed, whole.offset, whole.text.length,
        '$what $form is not allowed. $fix',
        v21Message: '$what $form is not allowed in version 3.0. $fix',
        // formatInstant writes whole seconds. An interval with parts of a
        // second gets no automatic fix.
        replacement: known && start % 1000 == 0 && end % 1000 == 0
            ? '${formatInstant(start)}/${formatInstant(end)}'
            : null);
  }

  AaCommand parse() {
    final words = splitWords(text);
    if (words.isEmpty) {
      _issue(AaIssueKind.missingValue, 0, 1,
          'The AA command has no value. $_forms');
      return AaUnknownCommand(source, issues);
    }
    final first = words.first;
    final upper = first.text.toUpperCase();
    if (upper == 'NONE') {
      if (words.length > 1) {
        final rest = words[1];
        _syntax(rest.offset, text.length - rest.offset,
            'AA NONE must be alone. Remove the text after NONE.');
      }
      return AaNoneCommand(source, issues);
    }
    if (upper == 'EXCEPT') return _parseExcept(words);

    // An ICAO schedule code such as H24 or HJ, in any word. Report only this
    // problem: the other problems of such a command are not useful.
    for (var k = 0; k < words.length; k++) {
      final w = words[k];
      final codeKey = w.text.toUpperCase().split('/').first;
      if (!_scheduleCodes.containsKey(codeKey)) continue;
      final afterWeekdays =
          k > 0 && words.take(k).every((x) => _dayWord.hasMatch(x.text));
      if (!afterWeekdays) {
        _syntax(w.offset, w.text.length, _scheduleCodes[codeKey]!,
            v21Message: _scheduleCodesV21[codeKey]);
        return AaUnknownCommand(source, issues);
      }
      final days = text.substring(words.first.offset, words[k - 1].end);
      final weekdays = _parseDayList(words.sublist(0, k));
      _syntax(w.offset, w.text.length, _scheduleCodeAfterDays(codeKey, days),
          v21Message: _scheduleCodesV21[codeKey]);
      return AaWeekdayCommand(source, issues,
          weekdays: weekdays, weekdaysGiven: true);
    }

    var i = 0;
    while (i < words.length &&
        _dayWord.hasMatch(words[i].text) &&
        words[i].text.toUpperCase() != 'NONE') {
      i++;
    }
    if (i > 0) return _parseWeekday(words, i);

    if (!first.text.contains('/')) {
      _syntaxWithoutSlash(words);
      return AaUnknownCommand(source, issues);
    }

    final slash = first.text.indexOf('/');
    final left = TextPart(first.text.substring(0, slash), first.offset);
    final right =
        TextPart(first.text.substring(slash + 1), first.offset + slash + 1);
    if (right.text.contains('/')) {
      if (RegExp(r'^[Rr]\d*$').hasMatch(left.text)) {
        _syntax(
            first.offset,
            first.text.length,
            'Repeating intervals (R) are not supported. Use a weekday AA '
            'command, for example AA MON-FRI 07:00Z/15:00Z.');
      } else {
        _syntax(first.offset, first.text.length,
            '"${first.text}" has more than one "/". $_forms');
      }
      return AaUnknownCommand(source, issues);
    }
    final ls = _shapeOf(left.text);
    final rs = _shapeOf(right.text);
    bool any(Set<_Shape> s) => s.contains(ls) || s.contains(rs);

    if (ls == _Shape.none && rs == _Shape.none) {
      _issue(
          AaIssueKind.noneNone,
          first.offset,
          first.text.length,
          'AA NONE/NONE is not allowed. If the airspace is always active, '
          'remove the AA command. If the activation times are not known, '
          'remove the airspace from the file.',
          v21Message: 'AA NONE/NONE is not allowed. Write AA NONE for an '
              'airspace without known activation times.',
          replacement: words.length == 1 ? 'NONE' : null);
      _extraWords(words, 1, 'An interval');
      return AaIntervalCommand(source, issues,
          startIsNone: true, endIsNone: true);
    }
    if (any({_Shape.dateTime, _Shape.duration})) {
      return _parseInterval(words, left, right, ls, rs);
    }
    if (any({_Shape.time, _Shape.sun})) {
      return _parseWeekday(words, 0);
    }
    if (any({_Shape.date})) {
      // A week date or an ordinal date is also reported as a form that is
      // not allowed, with the date as YYYY-MM-DD.
      final dates = <CivilDate?>[];
      for (final side in [left, right]) {
        final r = parseIsoDate(side.text, side.offset, <AaIssue>[]);
        dates.add(r.value);
        if (r.value != null) {
          _formNotAllowed(side, r.formNote, 'YYYY-MM-DD', '${r.value}');
        }
      }
      final (from, to) = (dates[0], dates[1]);
      final known = from != null && to != null && !(to < from);
      final interval = known
          ? '${from}T00:00Z/${to.addDays(1)}T00:00Z'
          : '2026-07-04T00:00Z/2026-07-05T00:00Z';
      final weekday = known
          ? '00:00Z/24:00Z $from/$to'
          : '00:00Z/24:00Z 2026-07-04/2026-07-05';
      _syntax(
          first.offset,
          first.text.length,
          '"${first.text}" has dates without a time of day. An interval '
          'needs a date and a time on both sides, for example $interval. A '
          'weekday command needs the times before the date range, for '
          'example $weekday.');
      return AaUnknownCommand(source, issues);
    }
    _syntax(first.offset, first.text.length,
        'Cannot read "${first.text}". $_forms');
    return AaUnknownCommand(source, issues);
  }

  void _syntaxWithoutSlash(List<TextPart> words) {
    final first = words.first;
    final s = _shapeOf(first.text);
    if ((s == _Shape.date) &&
        words.length > 1 &&
        _shapeOf(words[1].text) == _Shape.time) {
      _syntax(
          first.offset,
          words[1].end - first.offset,
          'Write "T" between the date and the time, without a space, for '
          'example 2026-07-04T08:00Z.');
      return;
    }
    if (s == _Shape.dateTime && first.text.contains('-') ||
        s == _Shape.time && first.text.contains('-')) {
      final dash = RegExp(r'([Zz])-(\d)').firstMatch(first.text);
      if (dash != null) {
        _syntax(first.offset, first.text.length,
            'Use "/" between the start and the end, not "-".');
        return;
      }
    }
    if (s == _Shape.dateTime || s == _Shape.time || s == _Shape.date) {
      _syntax(
          first.offset,
          first.text.length,
          '"${first.text}" has no end. Write the start and the end with "/" '
          'between them. $_forms');
      return;
    }
    _syntax(first.offset, text.length - first.offset,
        'Cannot read this AA command. $_forms');
  }

  void _extraWords(List<TextPart> words, int from, String what) {
    if (words.length <= from) return;
    final w = words[from];
    _syntax(
        w.offset,
        text.length - w.offset,
        'Unexpected text "${text.substring(w.offset)}". $what has no more '
        'values.');
  }

  // ----- Interval -----

  AaCommand _parseInterval(List<TextPart> words, TextPart left, TextPart right,
      _Shape ls, _Shape rs) {
    final whole = words.first;
    _extraWords(words, 1, 'An interval command');
    int? start;
    int? end;
    IsoDuration? leftDuration;
    IsoDuration? rightDuration;
    var startIsNone = false;
    var endIsNone = false;
    // What is missing in a short end, for example "no date".
    String? shortEnd;
    var ok = true;

    // The start.
    switch (ls) {
      case _Shape.none:
        startIsNone = true;
      case _Shape.dateTime:
        final r =
            parseIsoDateTime(left.text, left.offset, issues, isEnd: false);
        start = r.value;
        if (start == null) ok = false;
        if (start != null) {
          _formNotAllowed(
              left, r.formNote, allowedDateTimeForms, formatInstant(start));
        }
      case _Shape.duration:
        final r = parseIsoDuration(left.text, left.offset, issues);
        leftDuration = r.value;
        if (leftDuration == null) ok = false;
      case _Shape.sun:
        _sunInInterval(left);
        ok = false;
      case _Shape.empty:
        _syntax(
            whole.offset,
            whole.text.length,
            'The start is missing before "/". Write NONE for an unknown '
            'start.');
        ok = false;
      case _Shape.date:
      case _Shape.time:
      case _Shape.unknown:
        parseIsoDateTime(left.text, left.offset, issues, isEnd: false);
        ok = false;
    }

    // The end.
    switch (rs) {
      case _Shape.none:
        endIsNone = true;
      case _Shape.dateTime:
        // ISO 8601 allows an end without the higher-order parts of the
        // date, for example 05T16:00Z: they are the same as in the start.
        final short = ls == _Shape.dateTime && start != null
            ? parseShortEndDateTime(
                right.text, right.offset, issues, CivilDate.fromInstant(start))
            : null;
        if (short != null) {
          end = short.value;
          if (end == null) ok = false;
          final datePart =
              right.text.substring(0, right.text.indexOf(RegExp('[Tt]')));
          shortEnd = datePart.length <= 2 ? 'no year and no month' : 'no year';
          break;
        }
        final r =
            parseIsoDateTime(right.text, right.offset, issues, isEnd: true);
        end = r.value;
        if (end == null) ok = false;
        if (end != null) {
          _formNotAllowed(
              right, r.formNote, allowedDateTimeForms, formatInstant(end));
        }
      case _Shape.duration:
        final r = parseIsoDuration(right.text, right.offset, issues);
        rightDuration = r.value;
        if (rightDuration == null) ok = false;
      case _Shape.time:
        // ISO 8601 allows an end with only the time: the date is the date
        // of the start.
        if (ls == _Shape.dateTime) {
          final r = parseIsoTime(right.text, right.offset, issues, isEnd: true);
          if (r.value != null && start != null) {
            end = CivilDate.fromInstant(start).startInstant + r.value!;
          } else {
            ok = false;
          }
          shortEnd = 'no date';
        } else {
          parseIsoDateTime(right.text, right.offset, issues, isEnd: true);
          ok = false;
        }
      case _Shape.sun:
        _sunInInterval(right);
        ok = false;
      case _Shape.empty:
        _syntax(whole.offset, whole.text.length,
            'The end is missing after "/". Write NONE for an unknown end.');
        ok = false;
      case _Shape.date:
      case _Shape.unknown:
        parseIsoDateTime(right.text, right.offset, issues, isEnd: true);
        ok = false;
    }

    // Durations. Version 3.0 does not allow them (see below). These problems
    // are invalid in version 2.1 too, so they are reported as invalid
    // durations (a rule for version 2.1 only).
    if (ls == _Shape.duration && rs == _Shape.duration) {
      _issue(
          AaIssueKind.invalidDuration,
          whole.offset,
          whole.text.length,
          'An interval cannot have two durations. Write the start and the '
          'end, for example 2026-07-04T08:00Z/2026-07-04T16:00Z.');
      ok = false;
    } else if ((ls == _Shape.duration && rs == _Shape.none) ||
        (ls == _Shape.none && rs == _Shape.duration)) {
      _issue(
          AaIssueKind.invalidDuration,
          whole.offset,
          whole.text.length,
          'A duration needs a fixed start or end. NONE cannot be used with '
          'a duration.');
      ok = false;
    }
    if (ok && leftDuration != null && end != null) {
      start = leftDuration.subtractFrom(end);
      if (!_isFourDigitYear(start)) {
        _issue(
            AaIssueKind.invalidDuration,
            left.offset,
            left.text.length,
            'The duration "${left.text}" is too long. The start would be '
            'before the year 0000.');
        ok = false;
        start = null;
      }
    }
    if (ok && rightDuration != null && start != null) {
      end = rightDuration.addTo(start);
      if (!_isFourDigitYear(end)) {
        _issue(
            AaIssueKind.invalidDuration,
            right.offset,
            right.text.length,
            'The duration "${right.text}" is too long. The end would be after '
            'the year 9999.');
        ok = false;
        end = null;
      }
    }

    if (ok && start != null && end != null) {
      if (end < start) {
        _issue(
            AaIssueKind.intervalEndBeforeStart,
            whole.offset,
            whole.text.length,
            'The end ${formatInstant(end)} is before the start '
            '${formatInstant(start)}.');
      } else if (end == start) {
        _issue(
            AaIssueKind.intervalEndBeforeStart,
            whole.offset,
            whole.text.length,
            'The interval has no length. The start and the end are both '
            '${formatInstant(start)}.');
      }
    }

    // Interval forms other than StartDateTime/EndDateTime.
    final fixStart = ok ? start : null;
    final fixEnd = ok ? end : null;
    if (ls == _Shape.duration || rs == _Shape.duration) {
      final d = ls == _Shape.duration ? left.text : right.text;
      _intervalFormNotAllowed(
          whole, '"$d" is a duration.', 'A duration in an interval',
          start: fixStart, end: fixEnd);
    } else if (shortEnd != null) {
      _intervalFormNotAllowed(whole, 'The end "${right.text}" has $shortEnd.',
          'An interval end without a full date',
          start: fixStart, end: fixEnd);
    }
    return AaIntervalCommand(source, issues,
        start: startIsNone ? null : start,
        end: endIsNone ? null : end,
        startIsNone: startIsNone,
        endIsNone: endIsNone);
  }

  static bool _isFourDigitYear(int instant) {
    final year = CivilDate.fromInstant(instant).year;
    return year >= 0 && year <= 9999;
  }

  void _sunInInterval(TextPart part) => _issue(
      AaIssueKind.sunEventNotAllowed,
      part.offset,
      part.text.length,
      'The sun event ${part.text} cannot be used in an interval command. '
      'Sun events are allowed only in weekday AA commands, for example '
      'AA SR/SS.');

  // ----- Weekday -----

  AaCommand _parseWeekday(List<TextPart> words, int dayWordCount) {
    var weekdays = <int>{1, 2, 3, 4, 5, 6, 7};
    if (dayWordCount > 0) {
      weekdays = _parseDayList(words.sublist(0, dayWordCount));
    }
    if (words.length <= dayWordCount) {
      final last = words.last;
      _syntax(
          words.first.offset,
          last.end - words.first.offset,
          'A weekday AA command needs a time window after the weekdays, for '
          'example MON 09:00Z/11:30Z.');
      return AaWeekdayCommand(source, issues,
          weekdays: weekdays, weekdaysGiven: dayWordCount > 0);
    }
    final slot = words[dayWordCount];
    AaTimeOfDay? startTime;
    AaTimeOfDay? endTime;
    final dashWindow = _dashWindow.firstMatch(slot.text);
    if (dashWindow != null) {
      _syntax(
          slot.offset,
          slot.text.length,
          'Use "/" between the start time and the end time, not "-". Write '
          '"${dashWindow[1]}/${dashWindow[2]}".',
          replacement: '${dashWindow[1]}/${dashWindow[2]}');
    } else if (!slot.text.contains('/')) {
      _syntax(
          slot.offset,
          slot.text.length,
          'Expected a time window StartTime/EndTime, for example '
          '09:00Z/11:30Z.');
    } else if ('/'.allMatches(slot.text).length > 1) {
      _syntax(slot.offset, slot.text.length,
          '"${slot.text}" has more than one "/". $_forms');
    } else {
      final slash = slot.text.indexOf('/');
      final left = TextPart(slot.text.substring(0, slash), slot.offset);
      final right =
          TextPart(slot.text.substring(slash + 1), slot.offset + slash + 1);
      startTime = _weekdayTime(left, isEnd: false);
      endTime = _weekdayTime(right, isEnd: true);
    }

    var hasRange = false;
    CivilDate? from;
    CivilDate? to;
    if (words.length > dayWordCount + 1) {
      hasRange = true;
      final range = words[dayWordCount + 1];
      final r = _parseDateRange(range, isExcept: false);
      from = r.$1;
      to = r.$2;
      _extraWords(words, dayWordCount + 2, 'A weekday command');
    }

    if (dayWordCount > 0 &&
        weekdays.length == 7 &&
        !issues.any((i) => i.kind.blocking)) {
      final dayText = words.first;
      _issue(
          AaIssueKind.weekdayEveryDay,
          dayText.offset,
          words[dayWordCount - 1].end - dayText.offset,
          'The weekdays cover every day of the week. You can leave the '
          'weekdays out.',
          replacement: '',
          fixOffset: dayText.offset,
          fixLength: words[dayWordCount].offset - dayText.offset);
    }

    return AaWeekdayCommand(source, issues,
        weekdays: weekdays,
        weekdaysGiven: dayWordCount > 0,
        startTime: startTime,
        endTime: endTime,
        hasDateRange: hasRange,
        fromDate: from,
        toDate: to);
  }

  /// Parses the weekday words. Returns the set of days (the valid ones).
  Set<int> _parseDayList(List<TextPart> dayWords) {
    final firstWord = dayWords.first;
    final spanStart = firstWord.offset;
    final spanEnd = dayWords.last.end;
    String list;
    var exactOffsets = true;
    if (dayWords.length > 1) {
      exactOffsets = false;
      // True if a "," was added between two words. Then the meaning is not
      // clear: "MON FRI" can be MON,FRI or MON-FRI.
      var added = false;
      final b = StringBuffer(firstWord.text);
      for (var i = 1; i < dayWords.length; i++) {
        final w = dayWords[i].text;
        final prev = b.toString();
        if (!(prev.endsWith(',') ||
            prev.endsWith('-') ||
            w.startsWith(',') ||
            w.startsWith('-'))) {
          b.write(',');
          added = true;
        }
        b.write(w);
      }
      list = b.toString();
      _issue(AaIssueKind.weekdayListHasSpaces, spanStart, spanEnd - spanStart,
          'Do not put spaces in the list of weekdays. Write "$list".',
          replacement: added ? null : list);
    } else {
      list = firstWord.text;
    }

    final days = <int>{};
    final duplicates = <String>{};
    var pos = 0;
    for (final element in list.split(',')) {
      final elOffset = exactOffsets ? spanStart + pos : spanStart;
      final elLength = exactOffsets ? element.length : spanEnd - spanStart;
      pos += element.length + 1;
      if (element.isEmpty) {
        _issue(AaIssueKind.weekdayInvalidName, elOffset, elLength,
            'The list of weekdays has an empty item. Remove the extra ",".');
        continue;
      }
      final parts = element.split('-');
      if (parts.length > 2) {
        _issue(
            AaIssueKind.weekdayInvalidName,
            elOffset,
            elLength,
            '"$element" is not a valid weekday range. A range has two days, '
            'for example MON-FRI.');
        continue;
      }
      final numbers = <int>[];
      var partPos = 0;
      for (final p in parts) {
        final n = weekdayNumbers[p.toUpperCase()];
        if (n == null) {
          _issue(
              AaIssueKind.weekdayInvalidName,
              exactOffsets ? elOffset + partPos : elOffset,
              exactOffsets ? (p.isEmpty ? 1 : p.length) : elLength,
              _badDayMessage(p));
        } else {
          numbers.add(n);
        }
        partPos += p.length + 1;
      }
      if (numbers.length != parts.length) continue;
      final List<int> covered;
      if (numbers.length == 2) {
        if (numbers[0] == numbers[1]) {
          _issue(
              AaIssueKind.weekdayRangeSameDay,
              elOffset,
              elLength,
              'The range "$element" starts and ends on the same day. For one '
              'day, write only "${parts[0].toUpperCase()}". For every day, '
              'leave the weekdays out.');
          continue;
        }
        covered = [];
        var d = numbers[0];
        while (true) {
          covered.add(d);
          if (d == numbers[1]) break;
          d = d == 7 ? 1 : d + 1;
        }
      } else {
        covered = numbers;
      }
      for (final d in covered) {
        if (!days.add(d)) duplicates.add(weekdayAbbreviations[d - 1]);
      }
    }
    if (duplicates.isNotEmpty) {
      _issue(
          AaIssueKind.weekdayDuplicateDay,
          spanStart,
          spanEnd - spanStart,
          'The list of weekdays has ${duplicates.join(', ')} more than '
          'once.');
    }
    return days;
  }

  String _badDayMessage(String p) {
    final u = p.toUpperCase();
    if (p.isEmpty) {
      return 'A weekday is missing in the range. Write a range as MON-FRI.';
    }
    final alias = _weekdayAliases[u];
    if (alias != null) return '"$p" is not a weekday name. Write "$alias".';
    final code = _scheduleCodes[u];
    if (code != null) return code;
    if (sunEventKeywords.contains(u)) {
      return 'The sun event "$p" must be part of a time window, for '
          'example $u/SS or SR/$u.';
    }
    return '"$p" is not a weekday name. Use MON, TUE, WED, THU, FRI, SAT '
        'or SUN.';
  }

  AaTimeOfDay? _weekdayTime(TextPart part, {required bool isEnd}) {
    final which = isEnd ? 'end' : 'start';
    final shape = _shapeOf(part.text);
    switch (shape) {
      case _Shape.empty:
        _issue(
            AaIssueKind.invalidTime,
            part.offset,
            1,
            'The $which time is missing. Write the time window as '
            'StartTime/EndTime, for example 09:00Z/11:30Z.');
        return null;
      case _Shape.none:
        _issue(
            AaIssueKind.noneNotAllowed,
            part.offset,
            part.text.length,
            'NONE is not allowed as the $which time of a weekday command. '
            'Write a time, for example 00:00Z/24:00Z for the whole day.');
        return null;
      case _Shape.sun:
        return AaTimeOfDay.sun(SunEvent.fromKeyword(part.text)!);
      case _Shape.dateTime:
      case _Shape.date:
        _issue(
            AaIssueKind.invalidTime,
            part.offset,
            part.text.length,
            '"${part.text}" is not a time of day. A weekday command uses times '
            'without a date, for example 09:00Z/11:30Z. Write the dates in '
            'the date range after the times.');
        return null;
      case _Shape.duration:
        _issue(
            AaIssueKind.invalidTime,
            part.offset,
            part.text.length,
            'A duration cannot be used in a weekday command. Write the end '
            'time, for example 09:00Z/17:00Z.');
        return null;
      case _Shape.time:
      case _Shape.unknown:
        final r = parseIsoTime(part.text, part.offset, issues, isEnd: isEnd);
        if (r.value == null) return null;
        _formNotAllowed(
            part, r.formNote, allowedTimeForms, formatTimeOfDay(r.value!));
        return AaTimeOfDay.fixed(r.value!);
    }
  }

  /// Parses `StartDate/EndDate` (or one date for `AA EXCEPT`).
  (CivilDate?, CivilDate?) _parseDateRange(TextPart word,
      {required bool isExcept}) {
    final t = word.text;
    final slashes = '/'.allMatches(t).length;
    if (slashes > 1) {
      _syntax(word.offset, t.length,
          '"$t" has more than one "/". Write the range as StartDate/EndDate.');
      return (null, null);
    }
    if (slashes == 0) {
      if (!isExcept && _dayWord.hasMatch(t)) {
        _syntax(
            word.offset,
            text.length - word.offset,
            'Unexpected text "${text.substring(word.offset)}". Write the '
            'weekdays before the time window, for example '
            'MON 09:00Z/11:30Z.');
        return (null, null);
      }
      if (!isExcept) {
        _syntax(
            word.offset,
            t.length,
            'A date range needs a start date and an end date, for example '
            '"$t/$t" for one day.');
        return (null, null);
      }
      final d = _dateValue(word, isExcept: true);
      return (d, d);
    }
    final slash = t.indexOf('/');
    final left = TextPart(t.substring(0, slash), word.offset);
    final right = TextPart(t.substring(slash + 1), word.offset + slash + 1);
    final from = _dateValue(left, isExcept: isExcept);
    final to = _dateValue(right, isExcept: isExcept);
    final leftNone = left.text.toUpperCase() == 'NONE';
    final rightNone = right.text.toUpperCase() == 'NONE';
    if (!isExcept && leftNone && rightNone) {
      _issue(
          AaIssueKind.dateRangeNoneNone,
          word.offset,
          t.length,
          'The date range NONE/NONE has no limit. Leave the date range out, '
          'then the schedule repeats with no time limit.');
    }
    if (from != null && to != null && to < from) {
      _issue(
          isExcept
              ? AaIssueKind.exceptEndBeforeStart
              : AaIssueKind.dateRangeEndBeforeStart,
          word.offset,
          t.length,
          'The end date $to is before the start date $from.');
    }
    return (from, to);
  }

  CivilDate? _dateValue(TextPart part, {required bool isExcept}) {
    final shape = _shapeOf(part.text);
    switch (shape) {
      case _Shape.none:
        if (isExcept) {
          _issue(
              AaIssueKind.noneNotAllowed,
              part.offset,
              part.text.length,
              'NONE is not allowed in AA EXCEPT. Write a date, for example '
              'AA EXCEPT 2026-12-25.');
        }
        return null;
      case _Shape.sun:
        _issue(
            AaIssueKind.sunEventNotAllowed,
            part.offset,
            part.text.length,
            'The sun event ${part.text} cannot be used as a date. Sun events '
            'are allowed only in the time window of a weekday AA command.');
        return null;
      case _Shape.dateTime:
        _issue(
            AaIssueKind.invalidDate,
            part.offset,
            part.text.length,
            '"${part.text}" has a time. Write only the date, for example '
            '2026-07-04. A date means a whole day.');
        return null;
      case _Shape.empty:
        _issue(
            AaIssueKind.invalidDate,
            part.offset,
            1,
            'A date is missing. ${isExcept ? 'Write AA EXCEPT Date or '
                'AA EXCEPT StartDate/EndDate' : 'Write the date range as '
                'StartDate/EndDate, or NONE for an open end'}.');
        return null;
      case _Shape.date:
      case _Shape.time:
      case _Shape.duration:
      case _Shape.unknown:
        final r = parseIsoDate(part.text, part.offset, issues);
        if (r.value != null) {
          _formNotAllowed(
              part, r.formNote, allowedDateForm, r.value!.toString());
        }
        return r.value;
    }
  }

  // ----- Exception -----

  AaCommand _parseExcept(List<TextPart> words) {
    final kw = words.first;
    if (words.length == 1) {
      _syntax(kw.offset, kw.text.length,
          'AA EXCEPT needs a date, for example AA EXCEPT 2026-12-25.');
      return AaExceptCommand(source, issues);
    }
    final word = words[1];
    if (word.text.contains(',') || words.length > 2) {
      _syntax(word.offset, text.length - word.offset,
          'Write one AA EXCEPT command for each date or date range.');
      return AaExceptCommand(source, issues);
    }
    final upper = word.text.toUpperCase();
    final code = _scheduleCodes[upper];
    if (code != null) {
      _syntax(word.offset, word.text.length, code,
          v21Message: _scheduleCodesV21[upper]);
      return AaExceptCommand(source, issues);
    }
    final dayParts = upper.split(RegExp('[-,]'));
    if (dayParts.every(weekdayNumbers.containsKey)) {
      _issue(
          AaIssueKind.invalidDate,
          word.offset,
          word.text.length,
          'AA EXCEPT needs a date, not a weekday. To remove a weekday, '
          'change the weekdays of the weekday command.');
      return AaExceptCommand(source, issues);
    }
    final r = _parseDateRange(word, isExcept: true);
    return AaExceptCommand(source, issues, fromDate: r.$1, toDate: r.$2);
  }
}
