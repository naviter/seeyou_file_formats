import '../activation/aa_command.dart';
import '../activation/aa_issue.dart';
import '../activation/civil_date.dart';
import '../activation/sun.dart';
import '../diagnostic.dart';
import '../geometry/lat_lng.dart';
import '../lint_context.dart';
import '../model/openair_file.dart';
import '../spec_version.dart';
import 'rule.dart';

/// Rules for the activation times AA (intervals, weekdays, exceptions, sun
/// events).
///
/// The rules share one parse of each `AA` command ([parseAa], memoized per
/// command). Most value and syntax rules only report the issues that the
/// parser found. The other rules compare the `AA` commands of one airspace.
final List<Rule> activationRules = [
  // Syntax and values of one command.
  _missingValue,
  _invalidSyntax,
  _invalidDate,
  _invalidTime,
  _invalidDuration,
  _timeMissingZ,
  _timeZoneNotZ,
  _time24AsStart,
  _valueNotRecommendedForm,
  _noneNotAllowed,
  _noneNone,
  // Intervals.
  _intervalEndBeforeStart,
  _intervalNotRecommendedForm,
  _intervalsOverlap,
  _intervalsAdjacent,
  _intervalsNotSorted,
  _intervalsNotSortedV21,
  // Weekday commands.
  _weekdayInvalidName,
  _weekdayRangeSameDay,
  _weekdayListHasSpaces,
  _weekdayDuplicateDay,
  _weekdayEveryDay,
  _dateRangeEndBeforeStart,
  _dateRangeNoneNone,
  _weekdayNeverActive,
  // Exceptions.
  _exceptEndBeforeStart,
  _exceptWithoutWeekday,
  _exceptNoEffect,
  // Sun events.
  _sunEventNotAllowed,
  _sunEventOrderChanges,
  _sunEventStartCrossesMidnight,
  _sunEventNearFixedTime,
  _sunEventMissingDay,
  _sunEventNoPosition,
  // Combining AA commands.
  _noneCombined,
  _duplicate,
  _orderNotRecommended,
  _needsVersion3,
];

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// The parsed form of an `AA` command, computed once per file.
AaCommand _aa(LintContext ctx, Command c) =>
    ctx.memo(('aa', c), () => parseAa(c.argument));

/// All `AA` commands of an airspace with their parsed form.
List<(Command, AaCommand)> _aaOf(LintContext ctx, Airspace a) =>
    ctx.memo(('aa-airspace', a), () {
      final result = <(Command, AaCommand)>[];
      for (final c in a.commands) {
        if (c.upperKeyword == 'AA') result.add((c, _aa(ctx, c)));
      }
      return result;
    });

/// A rule that reports the parser issues of one kind.
Rule _issueRule(
  AaIssueKind kind, {
  required Severity severity,
  Set<SpecVersion> versions = SpecVersion.all,
  required String specAnchor,
  required String description,
  required String explanation,
  required String correctExample,
  required String incorrectExample,
}) =>
    Rule(
      id: kind.ruleId,
      severity: severity,
      versions: versions,
      specAnchor: specAnchor,
      description: description,
      explanation: explanation,
      correctExample: correctExample,
      incorrectExample: incorrectExample,
      keywords: const {'AA'},
      checkCommand: (ctx, c, a) {
        for (final issue in _aa(ctx, c).issues) {
          if (issue.kind != kind) continue;
          ctx.reportArgument(c, issue.message,
              offset: issue.offset, length: issue.length);
        }
      },
    );

String _lines(Iterable<Command> commands) {
  final lines = commands.map((c) => c.line).toList();
  if (lines.length == 1) return 'line ${lines.first}';
  if (lines.length <= 5) {
    return 'lines ${lines.sublist(0, lines.length - 1).join(', ')} and '
        '${lines.last}';
  }
  return 'lines ${lines.take(5).join(', ')} and ${lines.length - 5} more';
}

// Instants for open interval ends (NONE). They are outside every real date.
const int _farPast = -8640000000000000;
const int _farFuture = 8640000000000000;

class _Interval {
  _Interval(this.command, this.aa)
      : start = aa.startIsNone ? _farPast : aa.start!,
        end = aa.endIsNone ? _farFuture : aa.end!;

  final Command command;
  final AaIntervalCommand aa;
  final int start;
  final int end;

  String get label => '${aa.startIsNone ? 'NONE' : formatInstant(start)}/'
      '${aa.endIsNone ? 'NONE' : formatInstant(end)}';
}

/// The usable interval commands of an airspace, in file order.
List<_Interval> _intervals(LintContext ctx, Airspace a) =>
    ctx.memo(('aa-intervals', a), () {
      return [
        for (final (c, aa) in _aaOf(ctx, a))
          if (aa is AaIntervalCommand &&
              aa.isUsable &&
              (aa.startIsNone || aa.start != null) &&
              (aa.endIsNone || aa.end != null))
            _Interval(c, aa)
      ];
    });

/// The intervals of [list] that overlap at least one other interval of
/// [list] (exact duplicates count too), in the order of [list].
///
/// The intervals are sorted by their start once. An interval overlaps
/// another one if an interval before it (in this order) ends after its
/// start, or if the next interval starts before its end. This takes
/// O(n log n) time.
List<_Interval> _overlapCandidates(List<_Interval> list) {
  if (list.length < 2) return const [];
  final order = List<int>.generate(list.length, (i) => i)
    ..sort((x, y) => list[x].start.compareTo(list[y].start));
  final overlaps = List<bool>.filled(list.length, false);
  var maxEnd = _farPast;
  for (var k = 0; k < order.length; k++) {
    final y = list[order[k]];
    if (k > 0 && maxEnd > y.start) overlaps[order[k]] = true;
    if (k + 1 < order.length && list[order[k + 1]].start < y.end) {
      overlaps[order[k]] = true;
    }
    if (y.end > maxEnd) maxEnd = y.end;
  }
  return [
    for (var i = 0; i < list.length; i++)
      if (overlaps[i]) list[i]
  ];
}

/// The days that the usable `AA EXCEPT` commands of an airspace remove, as
/// sorted ranges that do not overlap. A lookup is a binary search, so a file
/// with many `AA EXCEPT` commands stays fast.
class _ExceptIndex {
  _ExceptIndex(Iterable<AaExceptCommand> excepts) {
    final ranges = [
      for (final e in excepts)
        if (e.fromDate != null && e.toDate != null && e.fromDate! <= e.toDate!)
          (e.fromDate!.dayNumber, e.toDate!.dayNumber)
    ]..sort((x, y) => x.$1.compareTo(y.$1));
    for (final (from, to) in ranges) {
      if (_ends.isNotEmpty && from <= _ends.last + 1) {
        if (to > _ends.last) _ends[_ends.length - 1] = to;
      } else {
        _starts.add(from);
        _ends.add(to);
      }
    }
  }

  final List<int> _starts = [];
  final List<int> _ends = [];

  /// True if an `AA EXCEPT` command removes [d].
  bool contains(CivilDate d) => containsDay(d.dayNumber);

  /// True if an `AA EXCEPT` command removes the day with the day number [n]
  /// (see [CivilDate.dayNumber]).
  bool containsDay(int n) {
    var lo = 0;
    var hi = _starts.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (n < _starts[mid]) {
        hi = mid - 1;
      } else if (n > _ends[mid]) {
        lo = mid + 1;
      } else {
        return true;
      }
    }
    return false;
  }
}

/// The days that the `AA EXCEPT` commands of an airspace remove.
_ExceptIndex _excepts(LintContext ctx, Airspace a) =>
    ctx.memo(('aa-except-index', a), () {
      return _ExceptIndex([
        for (final (_, aa) in _aaOf(ctx, a))
          if (aa is AaExceptCommand && aa.isUsable) aa
      ]);
    });

String _dayList(Iterable<int> days) {
  final names = [for (final d in days) weekdayNames[d - 1]];
  if (names.length == 1) return names.first;
  return '${names.sublist(0, names.length - 1).join(', ')} or ${names.last}';
}

// ---------------------------------------------------------------------------
// Syntax and values
// ---------------------------------------------------------------------------

final Rule _missingValue = _issueRule(
  AaIssueKind.missingValue,
  severity: Severity.error,
  specAnchor: 'aa-airspace-activation-times',
  description: 'An AA command must have a value.',
  explanation: 'An AA command without a value has no meaning. Write an '
      'interval, a weekday command, an exception or NONE. Remove the AA '
      'command if the airspace is always active.',
  correctExample: 'AA MON-FRI 07:00Z/15:00Z',
  incorrectExample: 'AA',
);

final Rule _invalidSyntax = _issueRule(
  AaIssueKind.invalidSyntax,
  severity: Severity.error,
  specAnchor: 'aa-airspace-activation-times',
  description: 'The AA command must have one of the forms of the '
      'specification.',
  explanation: 'There are four forms of AA command:\n'
      '\n'
      'AA StartDateTime/EndDateTime (an interval)\n'
      'AA [Weekdays] StartTime/EndTime [StartDate/EndDate] (a weekday '
      'command)\n'
      'AA EXCEPT Date or AA EXCEPT StartDate/EndDate (an exception)\n'
      'AA NONE\n'
      '\n'
      'This rule reports a command that matches none of these forms, for '
      'example a command with extra text, a missing "/" or an ICAO code such '
      'as H24 or HJ. A reader that cannot parse an AA command ignores all AA '
      'commands of the airspace.',
  correctExample: 'AA 2026-07-04T08:00Z/2026-07-04T16:00Z\n'
      'AA SR/SS',
  incorrectExample: 'AA 2026-07-04 08:00Z/2026-07-04 16:00Z\n'
      'AA HJ',
);

final Rule _invalidDate = _issueRule(
  AaIssueKind.invalidDate,
  severity: Severity.error,
  specAnchor: 'time',
  description: 'A date in an AA command must be a valid ISO 8601 date.',
  explanation: 'Dates in AA commands are ISO 8601 dates in the form '
      'YYYY-MM-DD. The date must exist in the calendar: 2026-02-30 is not '
      'valid. In date ranges and in AA EXCEPT, write only the date, '
      'without a time.',
  correctExample: 'AA MON-FRI 07:00Z/15:00Z\n'
      'AA EXCEPT 2026-12-25',
  incorrectExample: 'AA MON-FRI 07:00Z/15:00Z\n'
      'AA EXCEPT 2026-02-30',
);

final Rule _invalidTime = _issueRule(
  AaIssueKind.invalidTime,
  severity: Severity.error,
  specAnchor: 'time',
  description: 'A time in an AA command must be a valid ISO 8601 time.',
  explanation: 'Times in AA commands are ISO 8601 times of day in UTC, '
      'for example 09:00Z. The hour is 00 to 23 and the minutes are 00 to '
      '59. Write two digits for each value. An interval needs a date and a '
      'time on both sides, for example 2026-07-04T08:00Z. A weekday command '
      'uses times without a date.',
  correctExample: 'AA MON 09:00Z/11:30Z',
  incorrectExample: 'AA MON 9:00Z/25:00Z',
);

final Rule _invalidDuration = _issueRule(
  AaIssueKind.invalidDuration,
  severity: Severity.error,
  specAnchor: 'interval-activation',
  description: 'A duration in an interval must be a valid ISO 8601 '
      'duration.',
  explanation: 'An interval can have a start and a duration, for example '
      '2026-07-04T08:00Z/PT8H. The duration has the form PnYnMnDTnHnMnS, '
      'for example PT8H (8 hours), P1D (1 day) or P1DT12H. Only the last '
      'value can have a decimal fraction. The alternative format of ISO '
      '8601, for example P0000-00-01T00:00:00, is also read.\n'
      '\n'
      'A duration must be shorter than 10 000 years, and the interval must '
      'stay between the years 0000 and 9999. The recommended form is '
      'StartDateTime/EndDateTime.',
  correctExample: 'AA 2026-07-04T08:00Z/PT8H',
  incorrectExample: 'AA 2026-07-04T08:00Z/P8H',
);

final Rule _timeMissingZ = _issueRule(
  AaIssueKind.timeMissingZ,
  severity: Severity.error,
  specAnchor: 'time',
  description: 'Every time of day must end with Z (UTC).',
  explanation: 'All times in OpenAir are UTC. Write Z after every time of '
      'day. In ISO 8601, a time without Z is local time, and OpenAir does '
      'not support local time. If the source publishes local time, convert '
      'it to UTC first.',
  correctExample: 'AA 2026-07-04T08:00Z/2026-07-04T16:00Z',
  incorrectExample: 'AA 2026-07-04T08:00/2026-07-04T16:00',
);

final Rule _timeZoneNotZ = _issueRule(
  AaIssueKind.timeZoneNotZ,
  severity: Severity.error,
  specAnchor: 'time',
  description: 'Times must use Z, not a time zone offset or a zone name.',
  explanation: 'OpenAir supports only UTC, written as Z. Time zone offsets '
      'such as +01:00 and names such as UTC, GMT, LT or CET are not '
      'allowed. Convert the time to UTC and write Z. For UTC and GMT, only '
      'write Z in place of the name.',
  correctExample: 'AA MON-FRI 06:00Z/14:00Z',
  incorrectExample: 'AA MON-FRI 08:00+02:00/16:00+02:00',
);

final Rule _time24AsStart = _issueRule(
  AaIssueKind.time24AsStart,
  severity: Severity.error,
  specAnchor: 'time',
  description: '24:00Z is allowed only as an end time.',
  explanation: '24:00Z means the end of the day. It can only be an end '
      'time. As a start time, write 00:00Z (in an interval: 00:00Z of the '
      'next day).',
  correctExample: 'AA 2026-07-05T00:00Z/2026-07-05T06:00Z',
  incorrectExample: 'AA 2026-07-04T24:00Z/2026-07-05T06:00Z',
);

final Rule _valueNotRecommendedForm = _issueRule(
  AaIssueKind.valueNotRecommendedForm,
  severity: Severity.warning,
  versions: SpecVersion.only3,
  specAnchor: 'time',
  description: 'Dates and times should use the recommended form.',
  explanation: 'The specification allows every ISO 8601 form of a date '
      'and a time, for example seconds, the basic format without separators, '
      'week dates (2026-W27-6) and ordinal dates (2026-185). Writers should '
      'use the recommended forms: YYYY-MM-DD, hh:mmZ and '
      'YYYY-MM-DDThh:mmZ. Some readers can read only these forms.\n'
      '\n'
      'Version 2.1 of the specification has no recommended form. So this '
      'rule checks only files of version 3.0.',
  correctExample: 'AA 2026-07-04T08:00Z/2026-07-04T16:00Z',
  incorrectExample: 'AA 20260704T0800Z/20260704T1600Z',
);

final Rule _noneNotAllowed = _issueRule(
  AaIssueKind.noneNotAllowed,
  severity: Severity.error,
  specAnchor: 'aa-airspace-activation-times',
  description: 'NONE is allowed only where the specification allows it.',
  explanation: 'NONE is allowed in AA NONE, on one side of an interval '
      '(AA NONE/EndDateTime, AA StartDateTime/NONE) and on one side of the '
      'date range of a weekday command. It is not allowed in the time window '
      'of a weekday command and not in AA EXCEPT.',
  correctExample: 'AA MON-FRI 07:00Z/15:00Z 2026-04-01/NONE',
  incorrectExample: 'AA MON-FRI 07:00Z/NONE',
);

final Rule _noneNone = _issueRule(
  AaIssueKind.noneNone,
  severity: Severity.error,
  specAnchor: 'interval-activation',
  description: 'AA NONE/NONE is not allowed. Write AA NONE.',
  explanation: 'An older draft of the specification used AA NONE/NONE for '
      'an airspace without known activation times. The specification '
      'replaced it with AA NONE. Readers can understand NONE/NONE in '
      'different ways: as "never active until known" or as "always active".',
  correctExample: 'AA NONE',
  incorrectExample: 'AA NONE/NONE',
);

// ---------------------------------------------------------------------------
// Intervals
// ---------------------------------------------------------------------------

final Rule _intervalEndBeforeStart = _issueRule(
  AaIssueKind.intervalEndBeforeStart,
  severity: Severity.error,
  specAnchor: 'interval-activation',
  description: 'The end of an interval must be after its start.',
  explanation: 'An interval AA command defines one activation interval '
      'from StartDateTime to EndDateTime. If the end is before the start, '
      'or the same as the start, the interval is empty. This is usually a '
      'typing error in the date or the time.',
  correctExample: 'AA 2026-07-04T08:00Z/2026-07-04T16:00Z',
  incorrectExample: 'AA 2026-07-04T16:00Z/2026-07-04T08:00Z',
);

final Rule _intervalNotRecommendedForm = _issueRule(
  AaIssueKind.intervalNotRecommendedForm,
  severity: Severity.warning,
  versions: SpecVersion.only3,
  specAnchor: 'interval-activation',
  description: 'Intervals should use the form StartDateTime/EndDateTime.',
  explanation: 'The specification allows every ISO 8601 interval form, for '
      'example a start and a duration (2026-07-04T08:00Z/PT8H), an end '
      'with only the time (2026-07-04T08:00Z/16:00Z) or an end without the '
      'year (2026-07-04T08:00Z/07-05T16:00Z). In a short end, the missing '
      'parts of the date are the same as in the start. Writers should use '
      'the form StartDateTime/EndDateTime. Some readers can read only this '
      'form.\n'
      '\n'
      'Version 2.1 of the specification has no recommended form. So this '
      'rule checks only files of version 3.0.',
  correctExample: 'AA 2026-07-04T08:00Z/2026-07-04T16:00Z',
  incorrectExample: 'AA 2026-07-04T08:00Z/PT8H',
);

final Rule _intervalsOverlap = Rule(
  id: 'aa-intervals-overlap',
  severity: Severity.warning,
  specAnchor: 'interval-activation',
  description: 'Activation intervals should not overlap.',
  explanation: 'Two interval AA commands of one airspace should not cover '
      'the same time. Overlapping intervals are often a typing error. If the '
      'intervals are correct, merge them into one interval.',
  correctExample: 'AA 2026-07-04T08:00Z/2026-07-04T12:00Z\n'
      'AA 2026-07-04T14:00Z/2026-07-04T16:00Z',
  incorrectExample: 'AA 2026-07-04T08:00Z/2026-07-04T12:00Z\n'
      'AA 2026-07-04T10:00Z/2026-07-04T16:00Z',
  checkAirspace: (ctx, a) {
    // Only intervals that overlap some other interval are compared. In a
    // normal airspace no interval overlaps, so this is fast also for many
    // intervals.
    final list = _overlapCandidates(_intervals(ctx, a));
    for (var j = 1; j < list.length; j++) {
      final b = list[j];
      for (var i = 0; i < j; i++) {
        final x = list[i];
        if (x.start == b.start && x.end == b.end) continue; // duplicate
        if (x.start < b.end && b.start < x.end) {
          ctx.reportCommand(
              b.command,
              'This interval overlaps with the interval on line '
              '${x.command.line} (${x.label}). Intervals should not overlap.');
          break;
        }
      }
    }
  },
);

final Rule _intervalsAdjacent = Rule(
  id: 'aa-intervals-adjacent',
  severity: Severity.info,
  specAnchor: 'interval-activation',
  description: 'Adjacent intervals can be merged into one interval.',
  explanation: 'If one interval ends exactly when another interval starts, '
      'the two intervals can be one AA command. The specification allows '
      'separate commands, but encourages maintainers to merge them.',
  correctExample: 'AA 2026-07-04T08:00Z/2026-07-04T16:00Z',
  incorrectExample: 'AA 2026-07-04T08:00Z/2026-07-04T12:00Z\n'
      'AA 2026-07-04T12:00Z/2026-07-04T16:00Z',
  checkAirspace: (ctx, a) {
    final list = _intervals(ctx, a);
    // The positions of the intervals by their start and by their end. Only
    // these intervals can touch an interval, so the rule does not compare
    // every pair.
    final byStart = <int, List<int>>{};
    final byEnd = <int, List<int>>{};
    for (var k = 0; k < list.length; k++) {
      (byStart[list[k].start] ??= []).add(k);
      (byEnd[list[k].end] ??= []).add(k);
    }
    for (var j = 1; j < list.length; j++) {
      final b = list[j];
      final candidates = <int>{
        for (final i in byEnd[b.start] ?? const <int>[])
          if (i < j) i,
        for (final i in byStart[b.end] ?? const <int>[])
          if (i < j) i,
      }.toList()
        ..sort();
      for (final i in candidates) {
        final x = list[i];
        final first = x.end == b.start ? x : (b.end == x.start ? b : null);
        if (first == null) continue;
        final second = identical(first, x) ? b : x;
        if (first.aa.startIsNone && second.aa.endIsNone) continue;
        final merged =
            '${first.aa.startIsNone ? 'NONE' : formatInstant(first.start)}/'
            '${second.aa.endIsNone ? 'NONE' : formatInstant(second.end)}';
        ctx.reportCommand(
            b.command,
            'This interval and the interval on line ${x.command.line} '
            'touch at ${formatInstant(first.end)}. You can merge them into '
            'one command: AA $merged.');
        break;
      }
    }
  },
);

/// Reports each interval that starts before an interval above it.
void _checkIntervalOrder(LintContext ctx, Airspace a, String advice) {
  _Interval? latest;
  for (final x in _intervals(ctx, a)) {
    if (latest != null && x.start < latest.start) {
      ctx.reportCommand(
          x.command,
          'This interval starts before the interval on line '
          '${latest.command.line}. $advice');
    } else {
      latest = x;
    }
  }
}

final Rule _intervalsNotSorted = Rule(
  id: 'aa-intervals-not-sorted',
  severity: Severity.warning,
  versions: SpecVersion.only3,
  specAnchor: 'interval-activation',
  description: 'Interval AA commands should be sorted by their start time.',
  explanation: 'When an airspace has more than one interval, the intervals '
      'should be sorted from the earliest to the latest start time. Version '
      '3.0 recommends this order, and readers must accept any order.\n'
      '\n'
      'Version 2.1 of the specification required this order. For files that '
      'are checked as version 2.1, the rule aa-intervals-not-sorted-v21 '
      'reports it as an error.',
  correctExample: 'AA 2026-07-04T08:00Z/2026-07-04T12:00Z\n'
      'AA 2026-07-05T08:00Z/2026-07-05T12:00Z',
  incorrectExample: 'AA 2026-07-05T08:00Z/2026-07-05T12:00Z\n'
      'AA 2026-07-04T08:00Z/2026-07-04T12:00Z',
  checkAirspace: (ctx, a) =>
      _checkIntervalOrder(ctx, a, 'Sort the intervals by their start time.'),
);

final Rule _intervalsNotSortedV21 = Rule(
  id: 'aa-intervals-not-sorted-v21',
  severity: Severity.error,
  versions: SpecVersion.only21,
  specAnchor: 'aa-airspace-activation-times',
  anchorInVersion21Text: true,
  description: 'In version 2.1, interval AA commands must be sorted by their '
      'start time.',
  explanation: 'Version 2.1 of the specification says that the intervals of '
      'an airspace must be sorted from the earliest to the latest start time. '
      'A reader of version 2.1 can depend on this order. So in a file that is '
      'checked as version 2.1, intervals in another order are an error.\n'
      '\n'
      'Version 3.0 only recommends this order. For version 3.0 files, the '
      'rule aa-intervals-not-sorted reports it as a warning.',
  correctExample: '*VERSION: 2.1\n'
      '...\n'
      'AA 2026-07-04T08:00Z/2026-07-04T12:00Z\n'
      'AA 2026-07-05T08:00Z/2026-07-05T12:00Z',
  incorrectExample: '*VERSION: 2.1\n'
      '...\n'
      'AA 2026-07-05T08:00Z/2026-07-05T12:00Z\n'
      'AA 2026-07-04T08:00Z/2026-07-04T12:00Z',
  checkAirspace: (ctx, a) => _checkIntervalOrder(
      ctx,
      a,
      'Version 2.1 requires the intervals to be sorted by their start '
      'time.'),
);

// ---------------------------------------------------------------------------
// Weekday commands
// ---------------------------------------------------------------------------

final Rule _weekdayInvalidName = _issueRule(
  AaIssueKind.weekdayInvalidName,
  severity: Severity.error,
  specAnchor: 'weekday-activation',
  description: 'Weekdays must be MON, TUE, WED, THU, FRI, SAT or SUN.',
  explanation: 'A weekday AA command can start with a list of weekdays. '
      'Use only the three-letter names MON, TUE, WED, THU, FRI, SAT and SUN. '
      'A list uses commas (MON,WED,FRI) and a range uses a dash (MON-FRI). '
      'Other names, such as MO or MONDAY, and codes such as PH (public '
      'holidays) are not allowed.',
  correctExample: 'AA MON-FRI 07:00Z/15:00Z',
  incorrectExample: 'AA MO-FR 07:00Z/15:00Z',
);

final Rule _weekdayRangeSameDay = _issueRule(
  AaIssueKind.weekdayRangeSameDay,
  severity: Severity.error,
  specAnchor: 'weekday-activation',
  description: 'The first and the last day of a weekday range must be '
      'different.',
  explanation: 'A range such as MON-MON is not allowed, because it is not '
      'clear: it can mean one day or every day. For one day, write only the '
      'day (MON). For every day, leave the weekdays out. A reader treats a '
      'command with such a range as a command it cannot parse, and then '
      'ignores all AA commands of the airspace.',
  correctExample: 'AA MON 09:00Z/11:30Z',
  incorrectExample: 'AA MON-MON 09:00Z/11:30Z',
);

final Rule _weekdayListHasSpaces = _issueRule(
  AaIssueKind.weekdayListHasSpaces,
  severity: Severity.error,
  specAnchor: 'weekday-activation',
  description: 'The list of weekdays must not contain spaces.',
  explanation: 'Write the weekdays as one word, without spaces: MON,WED,FRI '
      'or MON-FRI,SUN. A reader uses the spaces to find the parts of the '
      'command, so it cannot parse a list with spaces.',
  correctExample: 'AA MON,WED,FRI 09:00Z/11:30Z',
  incorrectExample: 'AA MON, WED, FRI 09:00Z/11:30Z',
);

final Rule _weekdayDuplicateDay = _issueRule(
  AaIssueKind.weekdayDuplicateDay,
  severity: Severity.info,
  specAnchor: 'weekday-activation',
  description: 'A weekday should be in the list only once.',
  explanation: 'A day that is in the list more than once does not change '
      'the meaning, but it can be a typing error. For example MON-FRI,WED '
      'has Wednesday two times.',
  correctExample: 'AA MON-FRI,SUN 07:00Z/15:00Z',
  incorrectExample: 'AA MON-FRI,WED 07:00Z/15:00Z',
);

final Rule _weekdayEveryDay = _issueRule(
  AaIssueKind.weekdayEveryDay,
  severity: Severity.info,
  specAnchor: 'weekday-activation',
  description: 'Leave the weekdays out when the command is for every day.',
  explanation: 'If the weekdays are left out, the schedule applies to every '
      'day. A list with all seven days, such as MON-SUN, means the same. '
      'The shorter form is easier to read.',
  correctExample: 'AA 06:00Z/20:00Z',
  incorrectExample: 'AA MON-SUN 06:00Z/20:00Z',
);

final Rule _dateRangeEndBeforeStart = _issueRule(
  AaIssueKind.dateRangeEndBeforeStart,
  severity: Severity.error,
  specAnchor: 'weekday-activation',
  description: 'The end date of a weekday date range must not be before the '
      'start date.',
  explanation: 'The date range StartDate/EndDate of a weekday command '
      'includes both dates. The end date can be the same as the start date, '
      'but not earlier. If it is earlier, the command never applies.',
  correctExample: 'AA MON-FRI 06:00Z/14:00Z 2026-03-29/2026-10-24',
  incorrectExample: 'AA MON-FRI 06:00Z/14:00Z 2026-10-24/2026-03-29',
);

final Rule _dateRangeNoneNone = _issueRule(
  AaIssueKind.dateRangeNoneNone,
  severity: Severity.warning,
  specAnchor: 'weekday-activation',
  description: 'A weekday date range should not be NONE/NONE.',
  explanation: 'NONE is for one open end of a date range, for example '
      '2026-04-01/NONE. The specification does not show NONE/NONE. For a '
      'schedule with no time limit, leave the date range out. Some readers '
      'may not accept NONE on both sides.',
  correctExample: 'AA MON-FRI 07:00Z/15:00Z',
  incorrectExample: 'AA MON-FRI 07:00Z/15:00Z NONE/NONE',
);

final Rule _weekdayNeverActive = Rule(
  id: 'aa-weekday-never-active',
  severity: Severity.warning,
  specAnchor: 'weekday-activation',
  description: 'A weekday command should have at least one window in its '
      'date range.',
  explanation: 'A weekday command with a date range has no effect when none '
      'of its weekdays is in the date range, or when AA EXCEPT commands '
      'remove every day of it. This is usually a mistake in the weekdays or '
      'in the dates.',
  correctExample: 'AA SAT,SUN 08:00Z/18:00Z 2026-07-04/2026-07-05',
  incorrectExample: 'AA SAT,SUN 08:00Z/18:00Z 2026-07-06/2026-07-10',
  checkAirspace: (ctx, a) {
    final excepts = _excepts(ctx, a);
    for (final (c, aa) in _aaOf(ctx, a)) {
      if (aa is! AaWeekdayCommand || !aa.isUsable) continue;
      final from = aa.fromDate;
      final to = aa.toDate;
      if (from == null || to == null || to < from) continue;
      final length = to.dayNumber - from.dayNumber + 1;
      var scheduled = 0;
      var excepted = 0;
      for (var i = 0; i < length && i < 3700; i++) {
        final d = from.addDays(i);
        if (!aa.weekdays.contains(d.weekday)) continue;
        scheduled++;
        if (excepts.contains(d)) {
          excepted++;
        } else {
          break;
        }
      }
      if (scheduled == 0) {
        final missing = [
          for (final d in aa.weekdays.toList()..sort()) d,
        ];
        ctx.reportCommand(
            c,
            'No window of this command starts in the date range $from/$to, '
            'because the range has no ${_dayList(missing)}. The command has '
            'no effect.');
      } else if (scheduled == excepted && length <= 3700) {
        ctx.reportCommand(
            c,
            'AA EXCEPT commands remove every day of this command in the date '
            'range $from/$to. The command has no effect.');
      }
    }
  },
);

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

final Rule _exceptEndBeforeStart = _issueRule(
  AaIssueKind.exceptEndBeforeStart,
  severity: Severity.error,
  specAnchor: 'exceptions',
  description: 'The end date of an AA EXCEPT range must not be before the '
      'start date.',
  explanation: 'AA EXCEPT StartDate/EndDate removes the weekday windows that '
      'start on the dates from StartDate to EndDate. Both dates are '
      'included. If the end date is before the start date, the command '
      'removes nothing.',
  correctExample: 'AA MON-FRI 07:00Z/15:00Z\n'
      'AA EXCEPT 2026-12-31/2027-01-01',
  incorrectExample: 'AA MON-FRI 07:00Z/15:00Z\n'
      'AA EXCEPT 2027-01-01/2026-12-31',
);

final Rule _exceptWithoutWeekday = Rule(
  id: 'aa-except-without-weekday',
  severity: Severity.error,
  specAnchor: 'exceptions',
  description: 'AA EXCEPT can be used only in an airspace with a weekday AA '
      'command.',
  explanation: 'AA EXCEPT removes windows of weekday AA commands. It does '
      'not change interval commands. An airspace that has AA EXCEPT must '
      'have at least one weekday AA command.',
  correctExample: 'AA MON-FRI 07:00Z/15:00Z\n'
      'AA EXCEPT 2026-12-25',
  incorrectExample: 'AA 2026-12-24T07:00Z/2026-12-26T15:00Z\n'
      'AA EXCEPT 2026-12-25',
  checkAirspace: (ctx, a) {
    final list = _aaOf(ctx, a);
    if (list.any((e) => e.$2 is AaWeekdayCommand)) return;
    for (final (c, aa) in list) {
      if (aa is AaExceptCommand) {
        ctx.reportCommand(
            c,
            'AA EXCEPT needs a weekday AA command in the same airspace. '
            'AA EXCEPT does not change interval commands.');
      }
    }
  },
);

final Rule _exceptNoEffect = Rule(
  id: 'aa-except-no-effect',
  severity: Severity.warning,
  specAnchor: 'exceptions',
  description: 'An AA EXCEPT command should remove at least one weekday '
      'window.',
  explanation: 'AA EXCEPT removes the weekday windows that start on its '
      'dates. If no weekday command has a window that starts on these dates, '
      'the exception has no effect. For example, the date is outside the '
      'date ranges of all weekday commands, or the date is a Saturday and '
      'the weekday commands are for MON-FRI only.',
  correctExample: 'AA MON-FRI 07:00Z/15:00Z\n'
      'AA EXCEPT 2026-12-25',
  incorrectExample: 'AA MON-FRI 07:00Z/15:00Z\n'
      'AA EXCEPT 2026-12-26',
  checkAirspace: (ctx, a) {
    final list = _aaOf(ctx, a);
    final weekdays = <AaWeekdayCommand>[];
    for (final (_, aa) in list) {
      if (aa is AaWeekdayCommand) {
        if (!aa.isUsable) return; // Cannot tell.
        weekdays.add(aa);
      }
    }
    if (weekdays.isEmpty) return;
    for (final (c, aa) in list) {
      if (aa is! AaExceptCommand || !aa.isUsable) continue;
      final from = aa.fromDate;
      final to = aa.toDate;
      if (from == null || to == null || to < from) continue;
      var inSomeRange = false;
      var hit = false;
      for (final w in weekdays) {
        final lo =
            (w.fromDate != null && w.fromDate! > from) ? w.fromDate! : from;
        final hi = (w.toDate != null && w.toDate! < to) ? w.toDate! : to;
        if (lo > hi) continue;
        inSomeRange = true;
        for (var d = lo, i = 0; d <= hi && i < 7; d = d.addDays(1), i++) {
          if (w.weekdays.contains(d.weekday)) {
            hit = true;
            break;
          }
        }
        if (hit) break;
      }
      if (hit) continue;
      final dates = from == to ? from.withWeekday : '$from to $to';
      if (!inSomeRange) {
        ctx.reportCommand(
            c,
            'This AA EXCEPT has no effect. $dates is outside the date ranges '
            'of all weekday commands of this airspace.');
      } else {
        ctx.reportCommand(
            c,
            'This AA EXCEPT has no effect. No weekday command has a window '
            'that starts on ${from == to ? dates : 'the dates $dates'}.');
      }
    }
  },
);

// ---------------------------------------------------------------------------
// Sun events
// ---------------------------------------------------------------------------

final Rule _sunEventNotAllowed = _issueRule(
  AaIssueKind.sunEventNotAllowed,
  severity: Severity.error,
  specAnchor: 'sun-events',
  description: 'Sun events are allowed only in the time window of a weekday '
      'command.',
  explanation: 'The sun events SR, SS, BCMT and EECT can replace a Time '
      'value in a weekday AA command. They cannot be used in interval '
      'commands, in dates or in AA EXCEPT.',
  correctExample: 'AA SAT,SUN SR/SS 2026-07-04/2026-07-05',
  incorrectExample: 'AA 2026-07-04T08:00Z/SS',
);

/// One scheduled day of a weekday command with a sun event.
class _SunDay {
  _SunDay(this.dayNumber, this.start, this.end);

  /// The UTC day on which the window starts, as a day number (see
  /// [CivilDate.dayNumber]).
  final int dayNumber;

  /// The UTC day on which the window starts.
  CivilDate get day => CivilDate.fromDayNumber(dayNumber);

  /// The start in minutes after 00:00Z of [day]. A sun event can be below 0
  /// or at or above 1440 on a day without this event (see
  /// [sunEventMinutes]).
  final double start;

  /// The end as calculated for [day], in minutes after 00:00Z of [day].
  final double end;

  /// True if the window ends on the next day: the end is not after the
  /// start.
  bool get endsNextDay => end <= start;

  /// The length of the window in minutes.
  double get length => endsNextDay ? end + 1440 - start : end - start;
}

/// What the sun check found for one weekday command.
class _SunCheck {
  /// The scheduled days that are not removed by AA EXCEPT.
  int checkedDays = 0;

  /// The checked days on which both times could be calculated.
  int calculatedDays = 0;

  /// The calculated days on which the window ends on the next day.
  int nextDay = 0;

  /// The number of times the length of the window changes by more than
  /// [_jumpMinutes] from one scheduled day to the next, and the first time.
  int lengthJumps = 0;
  (_SunDay, _SunDay)? firstLengthJump;

  /// The number of times the start changes by more than [_jumpMinutes]
  /// from one scheduled day to the next, and the first time.
  int startJumps = 0;
  (_SunDay, _SunDay)? firstStartJump;

  /// The first day on which a fixed time and a sun event are less than
  /// 2 minutes apart.
  _SunDay? firstNear;

  int missing = 0;
  CivilDate? firstMissing;
  SunEvent? missingEvent;
  bool noPosition = false;
}

/// A change of more than this many minutes between two scheduled days is a
/// jump of about one day. The normal movement of a sun event is much
/// smaller.
const double _jumpMinutes = 720;

/// The first day of the fixed period that the sun check uses when the date
/// range does not limit the days. A fixed period makes the result the same
/// on every day the linter runs.
const CivilDate _sunReferenceStart = CivilDate(2026, 1, 1);

/// The sun check uses at most four years (1461 days). The sun times repeat
/// almost exactly every four years.
const int _sunCheckMaxDays = 1461;

/// The days that the sun check uses for [w]:
///
/// - without a date range: the four years 2026 to 2029,
/// - with an open start (NONE/EndDate): the four years before EndDate,
/// - with an open end (StartDate/NONE) or a date range longer than four
///   years: four years from StartDate, but not before 2026 when the range
///   allows it,
/// - else the date range.
(CivilDate, CivilDate) _sunCheckPeriod(AaWeekdayCommand w) {
  const last = _sunCheckMaxDays - 1;
  final from = w.fromDate;
  final to = w.toDate;
  if (from == null && to == null) {
    return (_sunReferenceStart, _sunReferenceStart.addDays(last));
  }
  if (from == null) return (to!.addDays(-last), to);
  if (to != null && to.dayNumber - from.dayNumber <= last) return (from, to);
  var start = from > _sunReferenceStart ? from : _sunReferenceStart;
  if (to != null && start.dayNumber > to.dayNumber - last) {
    start = to.addDays(-last);
  }
  return (start, start.addDays(last));
}

/// A function that gives the time of [t] on a day (a day number, see
/// [CivilDate.dayNumber]), in minutes after 00:00Z of that day, or null if a
/// sun event does not happen on that day. Sun events are calculated at
/// [centre] and cached per airspace and event, because several commands of
/// one airspace often use the same event.
double? Function(int) _timeOnDay(
    LintContext ctx, Airspace a, AaTimeOfDay t, LatLng centre) {
  final event = t.sunEvent;
  if (event == null) {
    final fixed = t.ms! / msPerMinute;
    return (_) => fixed;
  }
  final cache = ctx.memo(('aa-sun-cache', a, event), () => <int, double?>{});
  return (n) {
    if (cache.containsKey(n)) return cache[n];
    return cache[n] =
        sunEventMinutes(event, CivilDate.fromDayNumber(n), centre);
  };
}

/// A time of a window as a date and a time, for example
/// `SR (sunrise) at 2026-03-15T05:59Z` or `2026-03-15T06:00Z`.
/// [minutes] counts from 00:00Z of [day] and can be below 0 or above 1440.
/// With [seconds], the time has seconds, for example `06:00:20Z`.
String _describeAt(AaTimeOfDay t, CivilDate day, double minutes,
    {bool seconds = false}) {
  final s = (minutes * 60).round();
  final unit = seconds ? 1 : 60;
  final rounded = (s / unit).round() * unit;
  final dayOffset = (rounded / 86400).floor();
  final at = '${day.addDays(dayOffset)}T'
      '${formatTimeOfDay((rounded - dayOffset * 86400) * 1000)}';
  final e = t.sunEvent;
  if (e == null) return at;
  return '${e.keyword} (${e.description}) at $at';
}

/// The window of [w] on one day, for example
/// `from 2026-03-15T06:00Z to SR (sunrise) at 2026-03-16T05:59Z`. If the
/// start and the end show the same time of day, the times have seconds.
String _window(AaWeekdayCommand w, _SunDay d) {
  final end = d.endsNextDay ? d.end + 1440 : d.end;
  final seconds = (d.start.round() - end.round()) % 1440 == 0;
  return 'from ${_describeAt(w.startTime!, d.day, d.start, seconds: seconds)} '
      'to ${_describeAt(w.endTime!, d.day, end, seconds: seconds)}';
}

_SunCheck _sunCheck(LintContext ctx, Airspace a, AaWeekdayCommand w) =>
    ctx.memo(('aa-sun', w), () {
      final r = _SunCheck();
      final centre = ctx.boundaryOf(a).centre;
      if (centre == null) {
        r.noPosition = true;
        return r;
      }
      final start = w.startTime!;
      final end = w.endTime!;
      final mixed = start.isSunEvent != end.isSunEvent;
      final excepts = _excepts(ctx, a);
      final startOn = _timeOnDay(ctx, a, start, centre);
      final endOn = _timeOnDay(ctx, a, end, centre);
      final (from, to) = _sunCheckPeriod(w);
      // The ISO weekday (1 = Monday) of each day of the week, starting with
      // the weekday of the first day.
      final weekdayOf = [
        for (var i = 0; i < 7; i++) from.addDays(i).weekday,
      ];
      final last = to.dayNumber;
      _SunDay? previous;
      for (var n = from.dayNumber, i = 0; n <= last; n++, i++) {
        if (!w.weekdays.contains(weekdayOf[i % 7])) continue;
        if (excepts.containsDay(n)) continue;
        r.checkedDays++;
        final s = startOn(n);
        final e = endOn(n);
        if (s == null || e == null) {
          r.missing++;
          if (r.firstMissing == null) {
            r.firstMissing = CivilDate.fromDayNumber(n);
            r.missingEvent = s == null ? start.sunEvent : end.sunEvent;
          }
          continue;
        }
        final day = _SunDay(n, s, e);
        r.calculatedDays++;
        if (day.endsNextDay) r.nextDay++;
        // An end that crosses 00:00Z (sunset in Texas, for example) does not
        // change the window: the length stays about the same. Only a jump of
        // about one day in the length or in the start changes the window.
        if (previous != null) {
          if ((day.length - previous.length).abs() > _jumpMinutes) {
            r.lengthJumps++;
            r.firstLengthJump ??= (previous, day);
          } else if ((day.start - previous.start).abs() > _jumpMinutes) {
            r.startJumps++;
            r.firstStartJump ??= (previous, day);
          }
        }
        if (mixed && r.firstNear == null) {
          final gap = (e - s) % 1440;
          if (gap < 2 || gap > 1438) r.firstNear = day;
        }
        previous = day;
      }
      return r;
    });

/// The weekday commands of an airspace that use a sun event and can be
/// checked.
Iterable<(Command, AaWeekdayCommand)> _sunCommands(
    LintContext ctx, Airspace a) sync* {
  for (final (c, aa) in _aaOf(ctx, a)) {
    if (aa is AaWeekdayCommand &&
        aa.isUsable &&
        aa.usesSunEvent &&
        aa.startTime != null &&
        aa.endTime != null) {
      yield (c, aa);
    }
  }
}

/// The text that the sun event rules use for the days that they check.
const String _sunCheckPeriodText = 'Without a date range, openair-lint '
    'checks the four years 2026 to 2029. With an open end, it checks four '
    'years from the start date, but not before 2026. It checks at most four '
    'years. The sun times repeat almost exactly every four years. Days '
    'removed by AA EXCEPT are not checked.';

String _hours(double minutes) => '${(minutes.abs() / 60).round()}';

String _times(int n) =>
    n > 1 ? ' This happens $n times in the checked days.' : '';

final Rule _sunEventOrderChanges = Rule(
  id: 'aa-sun-event-order-changes',
  severity: Severity.error,
  specAnchor: 'weekday-activation',
  description: 'The order of a fixed time and a sun event must be the same '
      'on every day of the schedule.',
  explanation: 'If the end time of a weekday window is earlier than or '
      'equal to the start time, the window ends on the next day. With a sun '
      'event, the client compares the calculated times. So 06:00Z/SR ends on '
      'the same day when sunrise is after 06:00 UTC, but on the next day '
      'when sunrise is before 06:00 UTC. The specification says that the '
      'writer must check that the order is correct on every day of the '
      'schedule. It uses 06:00Z/SR as an example of a wrong command.\n'
      '\n'
      'openair-lint calculates the sun events at the centre of the airspace '
      'for every scheduled day. It compares the window of each day with the '
      'window of the scheduled day before. It reports the command when the '
      'length of the window changes by more than 12 hours. This happens when '
      'the order of the start and the end changes.\n'
      '\n'
      'A sun event at the end that crosses 00:00Z is not a problem. For '
      'example, AA SR/SS at 97° W: the sunset is before 00:00Z in winter and '
      'after 00:00Z in summer. The window ends on the same day in winter and '
      'on the next day in summer, but it always ends at sunset.\n'
      '\n'
      'Two other rules check related problems. '
      'aa-sun-event-start-crosses-midnight reports a sun event at the start '
      'that crosses 00:00Z. aa-sun-event-near-fixed-time reports a fixed time '
      'and a sun event that are less than 2 minutes apart.\n'
      '\n'
      '$_sunCheckPeriodText\n'
      '\n'
      'To fix it, split the command with date ranges, or use a different '
      'time.',
  correctExample: 'AA MON-FRI 07:00Z/SS 2026-04-01/2026-09-30',
  incorrectExample: 'AA 06:00Z/SR',
  checkAirspace: (ctx, a) {
    for (final (c, w) in _sunCommands(ctx, a)) {
      final r = _sunCheck(ctx, a, w);
      if (r.firstLengthJump case (final p, final d)) {
        ctx.reportCommand(
            c,
            'The order of the start and the end changes during the schedule, '
            'so the length of the window changes by about '
            '${_hours(d.length - p.length)} hours. On ${p.day.withWeekday} '
            'the window is ${_window(w, p)}. On ${d.day.withWeekday} it is '
            '${_window(w, d)}.${_times(r.lengthJumps)} On ${r.nextDay} of '
            '${r.calculatedDays} checked days the window ends on the next '
            'day.');
      }
    }
  },
);

final Rule _sunEventStartCrossesMidnight = Rule(
  id: 'aa-sun-event-start-crosses-midnight',
  severity: Severity.warning,
  specAnchor: 'weekday-activation',
  description: 'A sun event at the start of a window should not cross '
      '00:00Z during the schedule.',
  explanation: 'A client calculates a sun event for the UTC day on which the '
      'window starts. For airspaces far east or far west of Greenwich, a sun '
      'event can be just after 00:00Z on some days and just before 24:00Z '
      'on other days. For example, SR/SS at 96° E: on some days the sunrise '
      'of the UTC day is just after 00:00Z, on other days it is just before '
      '24:00Z. Then the window starts about one day later, and it belongs to '
      'a different weekday. This is very probably not what the writer '
      'wants.\n'
      '\n'
      'openair-lint reports the command when the start of the window changes '
      'by more than 12 hours from one scheduled day to the next. If the '
      'length of the window also changes by more than 12 hours, the rule '
      'aa-sun-event-order-changes reports the command, and this rule does '
      'not.\n'
      '\n'
      '$_sunCheckPeriodText\n'
      '\n'
      'To fix it, use a fixed time for the start, or check that the windows '
      'start on the weekdays that you want.',
  correctExample: 'AA SR/SS                 * an airspace at 14° E\n'
      'V X=46:00:00N 014:00:00E\n'
      'DC 5',
  incorrectExample: 'AA SR/SS                 * an airspace at 96° E\n'
      'V X=20:00:00N 096:00:00E\n'
      'DC 5',
  checkAirspace: (ctx, a) {
    for (final (c, w) in _sunCommands(ctx, a)) {
      final r = _sunCheck(ctx, a, w);
      if (r.firstLengthJump != null) continue;
      if (r.firstStartJump case (final p, final d)) {
        final e = w.startTime!.sunEvent;
        final name = e == null ? '' : ' ${e.keyword} (${e.description})';
        ctx.reportCommand(
            c,
            'The start$name crosses 00:00Z during '
            'the schedule, so the start of the window moves by about '
            '${_hours(d.start - p.start)} hours. On ${p.day.withWeekday} the '
            'window is ${_window(w, p)}. On ${d.day.withWeekday} it is '
            '${_window(w, d)}.${_times(r.startJumps)}');
      }
    }
  },
);

final Rule _sunEventNearFixedTime = Rule(
  id: 'aa-sun-event-near-fixed-time',
  severity: Severity.warning,
  specAnchor: 'weekday-activation',
  description: 'A fixed time and a sun event of one window should not be '
      'less than 2 minutes apart.',
  explanation: 'If the end time of a weekday window is earlier than or '
      'equal to the start time, the window ends on the next day. Different '
      'calculation methods can give sun events that differ by about one '
      'minute. If a fixed time and a sun event are less than 2 minutes '
      'apart on some day, readers can disagree on the order. Then one reader '
      'ends the window on the same day, and another reader ends it on the '
      'next day.\n'
      '\n'
      'openair-lint reports the first scheduled day on which this happens. '
      'It does not report a command that aa-sun-event-order-changes or '
      'aa-sun-event-start-crosses-midnight already reports.\n'
      '\n'
      '$_sunCheckPeriodText\n'
      '\n'
      'To fix it, use a fixed time that is further from the sun event, or '
      'split the command with date ranges.',
  correctExample: 'AA 02:00Z/SR 2026-06-20/2026-06-22',
  incorrectExample: 'AA 03:12Z/SR 2026-06-20/2026-06-22',
  checkAirspace: (ctx, a) {
    for (final (c, w) in _sunCommands(ctx, a)) {
      final r = _sunCheck(ctx, a, w);
      if (r.firstLengthJump != null || r.firstStartJump != null) continue;
      if (r.firstNear case final d?) {
        ctx.reportCommand(
            c,
            'On ${d.day.withWeekday} the start and the end are less than 2 '
            'minutes apart: the window is ${_window(w, d)}. Readers can '
            'calculate sun events with a difference of about one minute, so '
            'they can disagree on whether the window ends on the same day or '
            'on the next day.');
      }
    }
  },
);

final Rule _sunEventMissingDay = Rule(
  id: 'aa-sun-event-missing-day',
  severity: Severity.info,
  specAnchor: 'sun-events',
  description: 'A sun event does not happen on some days of the schedule.',
  explanation: 'In polar regions the sun does not rise or set on some days. '
      'If a weekday window uses a sun event that does not happen on that '
      'day, the airspace is active for the whole UTC day. This rule tells '
      'you on which days this happens, so that you can check that this is '
      'what you want.',
  correctExample: 'AA SR/SS                 * an airspace at 46° N\n'
      'V X=46:00:00N 014:00:00E\n'
      'DC 5',
  incorrectExample: 'AA SR/SS                 * an airspace at 70° N\n'
      'V X=70:00:00N 020:00:00E\n'
      'DC 5',
  checkAirspace: (ctx, a) {
    for (final (c, w) in _sunCommands(ctx, a)) {
      final r = _sunCheck(ctx, a, w);
      if (r.missing == 0) continue;
      final e = r.missingEvent!;
      ctx.reportCommand(
          c,
          '${e.keyword} (${e.description}) does not happen at the centre of '
          'the airspace on ${r.missing} of ${r.checkedDays} days, the first '
          'is ${r.firstMissing!.withWeekday}. On these days the airspace is '
          'active for the whole UTC day.');
    }
  },
);

final Rule _sunEventNoPosition = Rule(
  id: 'aa-sun-event-no-position',
  severity: Severity.info,
  specAnchor: 'sun-events',
  description: 'Sun events need the position of the airspace.',
  explanation: 'A client calculates a sun event at the centre of the '
      'airspace. openair-lint could not find any valid point in the geometry '
      'of this airspace, so it could not check the sun events. Fix the '
      'geometry first.',
  correctExample: 'AA SR/SS\n'
      'V X=46:03:00N 014:30:00E\n'
      'DC 5',
  incorrectExample: 'AA SR/SS\n'
      'DC 5',
  checkAirspace: (ctx, a) {
    for (final (c, w) in _sunCommands(ctx, a)) {
      if (_sunCheck(ctx, a, w).noPosition) {
        ctx.reportCommand(
            c,
            'openair-lint cannot check the sun events of this command, '
            'because the airspace has no valid geometry. A client needs the '
            'centre of the airspace to calculate sun events.');
      }
    }
  },
);

// ---------------------------------------------------------------------------
// Combining AA commands
// ---------------------------------------------------------------------------

final Rule _noneCombined = Rule(
  id: 'aa-none-combined',
  severity: Severity.error,
  specAnchor: 'combining-aa-commands',
  description: 'AA NONE cannot be combined with other AA commands.',
  explanation: 'AA NONE means that no activation times are known. It '
      'overrides all other activation times. If an airspace has AA NONE, it '
      'must not have any other AA command. Readers can understand the '
      'combination in different ways.',
  correctExample: 'AA NONE',
  incorrectExample: 'AA NONE\n'
      'AA 2026-07-04T08:00Z/2026-07-04T16:00Z',
  checkAirspace: (ctx, a) {
    final list = _aaOf(ctx, a);
    final others = [
      for (final (c, aa) in list)
        if (aa is! AaNoneCommand) c
    ];
    if (others.isEmpty) return;
    for (final (c, aa) in list) {
      if (aa is AaNoneCommand) {
        ctx.reportCommand(
            c,
            'AA NONE cannot be combined with other AA commands. This '
            'airspace also has AA commands on ${_lines(others)}. Remove '
            'AA NONE or the other AA commands.');
      }
    }
  },
);

String _duplicateKey(AaCommand aa) {
  if (aa.isUsable) {
    switch (aa) {
      case AaNoneCommand():
        return 'NONE';
      case AaIntervalCommand(:final start, :final end):
        return 'I $start $end';
      case AaWeekdayCommand():
        final days = (aa.weekdays.toList()..sort()).join(',');
        return 'W $days ${aa.startTime} ${aa.endTime} ${aa.fromDate} '
            '${aa.toDate}';
      case AaExceptCommand(:final fromDate, :final toDate):
        return 'E $fromDate $toDate';
      case AaUnknownCommand():
        break;
    }
  }
  return 'T ${aa.text.toUpperCase().split(RegExp(r'\s+')).join(' ')}';
}

final Rule _duplicate = Rule(
  id: 'aa-duplicate',
  severity: Severity.warning,
  specAnchor: 'combining-aa-commands',
  description: 'An airspace should not have the same AA command twice.',
  explanation: 'Two AA commands with the same meaning in one airspace are '
      'usually a copy error. Remove one of them. The check compares the '
      'meaning, so 2026-07-04T08:00Z and 20260704T0800Z are the same.',
  correctExample: 'AA MON-FRI 07:00Z/15:00Z',
  incorrectExample: 'AA MON-FRI 07:00Z/15:00Z\n'
      'AA MON-FRI 07:00Z/15:00Z',
  checkAirspace: (ctx, a) {
    final seen = <String, Command>{};
    for (final (c, aa) in _aaOf(ctx, a)) {
      final key = _duplicateKey(aa);
      final first = seen[key];
      if (first == null) {
        seen[key] = c;
      } else {
        ctx.reportCommand(
            c,
            'This AA command has the same meaning as the AA command on line '
            '${first.line}. Remove one of them.');
      }
    }
  },
);

const List<String> _rankNames = [
  'interval commands',
  'weekday commands',
  'AA EXCEPT commands',
];

final Rule _orderNotRecommended = Rule(
  id: 'aa-order-not-recommended',
  severity: Severity.info,
  specAnchor: 'combining-aa-commands',
  description: 'AA commands should be in the recommended order.',
  explanation: 'The recommended order of the AA commands of one airspace '
      'is:\n'
      '\n'
      '1. Interval commands, sorted by StartDateTime.\n'
      '2. Weekday commands, sorted by StartDate. Commands without a date '
      'range come first.\n'
      '3. AA EXCEPT commands, sorted by Date or StartDate.\n'
      '\n'
      'This order makes the file easier to read. It does not change the '
      'meaning. The order of the intervals among themselves is checked by '
      'aa-intervals-not-sorted (version 3.0) and aa-intervals-not-sorted-v21 '
      '(version 2.1).',
  correctExample: 'AA 2026-07-04T08:00Z/2026-07-04T16:00Z\n'
      'AA MON-FRI 06:00Z/14:00Z 2026-03-29/2026-10-24\n'
      'AA EXCEPT 2026-05-01',
  incorrectExample: 'AA EXCEPT 2026-05-01\n'
      'AA MON-FRI 06:00Z/14:00Z 2026-03-29/2026-10-24\n'
      'AA 2026-07-04T08:00Z/2026-07-04T16:00Z',
  checkAirspace: (ctx, a) {
    var maxRank = -1;
    Command? maxRankCommand;
    final maxKey = <int, (int, Command)>{};
    for (final (c, aa) in _aaOf(ctx, a)) {
      if (!aa.isUsable) continue;
      final int rank;
      final int key;
      switch (aa) {
        case AaIntervalCommand():
          rank = 0;
          key = 0;
        case AaWeekdayCommand():
          rank = 1;
          key = aa.hasDateRange && aa.fromDate != null
              ? aa.fromDate!.dayNumber
              : _farPast;
        case AaExceptCommand(:final fromDate):
          if (fromDate == null) continue;
          rank = 2;
          key = fromDate.dayNumber;
        case AaNoneCommand():
        case AaUnknownCommand():
          continue;
      }
      if (rank < maxRank) {
        ctx.reportCommand(
            c,
            'The recommended order is: interval commands, then weekday '
            'commands, then AA EXCEPT commands. This ${aa.kindLabel} command '
            'comes after the ${_rankNames[maxRank]} on line '
            '${maxRankCommand!.line}.');
        continue;
      }
      if (rank > maxRank) {
        maxRank = rank;
        maxRankCommand = c;
      }
      if (rank == 0) continue;
      final prev = maxKey[rank];
      if (prev != null && key < prev.$1) {
        ctx.reportCommand(
            c,
            rank == 1
                ? 'Sort weekday commands by their start date. Commands '
                    'without a date range come first. This command should '
                    'come before line ${prev.$2.line}.'
                : 'Sort AA EXCEPT commands by date. This command should come '
                    'before line ${prev.$2.line}.');
        continue;
      }
      maxKey[rank] = (key, c);
    }
  },
);

// ---------------------------------------------------------------------------
// Version
// ---------------------------------------------------------------------------

final Rule _needsVersion3 = Rule(
  id: 'aa-needs-version-3',
  severity: Severity.error,
  versions: SpecVersion.only21,
  specAnchor: 'aa-commands-a-reader-does-not-understand',
  description: 'Weekday commands, AA EXCEPT and sun events need version 3.0.',
  explanation: 'Weekday AA commands, AA EXCEPT and the sun events SR, SS, '
      'BCMT and EECT are new in version 3.0. A reader of version 2.1 cannot '
      'parse them. It then ignores all AA commands of the airspace and shows '
      'the airspace as always active.\n'
      '\n'
      'Write "*VERSION: 3.0" in the header, or use only interval commands.',
  correctExample: '*VERSION: 2.1\n'
      '...\n'
      'AA 2026-07-06T07:00Z/2026-07-06T15:00Z',
  incorrectExample: '*VERSION: 2.1\n'
      '...\n'
      'AA MON 07:00Z/15:00Z',
  keywords: const {'AA'},
  checkCommand: (ctx, c, a) {
    final aa = _aa(ctx, c);
    final String what;
    if (aa is AaWeekdayCommand) {
      what = aa.usesSunEvent
          ? 'Weekday AA commands and sun events are'
          : 'Weekday AA commands are';
    } else if (aa is AaExceptCommand) {
      what = 'AA EXCEPT is';
    } else {
      return;
    }
    final version = ctx.target != null
        ? 'version ${ctx.specVersion.label} (the --target option)'
        : 'version ${ctx.specVersion.label}';
    ctx.reportCommand(
        c,
        '$what new in version 3.0, but this file is checked as $version. '
        'A reader of version 2.1 cannot parse this command, so it ignores '
        'all AA commands of this airspace. Write "*VERSION: 3.0" in the '
        'header, or use only interval commands.');
  },
);
