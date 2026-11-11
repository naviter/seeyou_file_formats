/// Problems that the AA parser finds in one `AA` command.
library;

/// The kind of a problem in one `AA` command.
///
/// Each kind belongs to one lint rule ([ruleId]). A kind is [blocking] if a
/// reader cannot use the command. Rules that compare several `AA` commands
/// (for example overlapping intervals) skip commands with a blocking
/// problem.
enum AaIssueKind {
  /// `AA` without a value.
  missingValue('aa-missing-value'),

  /// The command does not match any `AA` form.
  invalidSyntax('aa-invalid-syntax'),

  /// A `Date` value (or the date part of a `DateTime`) is not valid.
  invalidDate('aa-invalid-date'),

  /// A `Time` value (or the time part of a `DateTime`) is not valid.
  invalidTime('aa-invalid-time'),

  /// A duration such as `PT8H` is not valid. Version 3.0 does not allow
  /// durations at all ([intervalFormNotAllowed]), so the rule checks only
  /// version 2.1.
  invalidDuration('aa-invalid-duration'),

  /// A time of day has no `Z`.
  timeMissingZ('aa-time-missing-z'),

  /// A time of day has a time zone offset or name in place of `Z`.
  timeZoneNotZ('aa-time-zone-not-z'),

  /// `24:00Z` is used as a start time.
  time24AsStart('aa-time-24-as-start'),

  /// `00:00Z` is used as an end time. The meaning is known (midnight), so
  /// the other rules can still use the command.
  time00AsEnd('aa-time-00-as-end', blocking: false),

  /// `NONE` where the specification does not allow it.
  noneNotAllowed('aa-none-not-allowed'),

  /// `AA NONE/NONE`.
  noneNone('aa-none-none'),

  /// A sun event in an interval command or in a date.
  sunEventNotAllowed('aa-sun-event-not-allowed'),

  /// A weekday name that does not exist, for example `MO`.
  weekdayInvalidName('aa-weekday-invalid-name'),

  /// A weekday range with the same first and last day, for example
  /// `MON-MON`.
  weekdayRangeSameDay('aa-weekday-range-same-day'),

  /// Spaces in the list of weekdays, for example `MON, WED`.
  weekdayListHasSpaces('aa-weekday-list-has-spaces'),

  /// A weekday that is in the list more than once.
  weekdayDuplicateDay('aa-weekday-duplicate-day', blocking: false),

  /// The weekdays cover all seven days. They can be left out.
  weekdayEveryDay('aa-weekday-every-day', blocking: false),

  /// A date or a time in an ISO 8601 form that the specification does not
  /// allow, for example the basic format `20260704T0800Z` or a week date.
  /// The value is known, so the other rules can still use the command.
  valueFormNotAllowed('aa-value-form-not-allowed', blocking: false),

  /// An interval that is not written as `StartDateTime/EndDateTime`, for
  /// example with a duration or with an end without a date. The interval is
  /// known when the values are valid, so the other rules can still use the
  /// command.
  intervalFormNotAllowed('aa-interval-form-not-allowed', blocking: false),

  /// The end of an interval is before or equal to its start.
  intervalEndBeforeStart('aa-interval-end-before-start'),

  /// The end date of a weekday date range is before its start date.
  dateRangeEndBeforeStart('aa-date-range-end-before-start'),

  /// The end date of an `AA EXCEPT` range is before its start date.
  exceptEndBeforeStart('aa-except-end-before-start'),

  /// A weekday date range `NONE/NONE`.
  dateRangeNoneNone('aa-date-range-none-none', blocking: false);

  const AaIssueKind(this.ruleId, {this.blocking = true});

  /// The ID of the lint rule that reports this kind.
  final String ruleId;

  /// True if a reader cannot use a command with this problem.
  final bool blocking;
}

/// One problem in an `AA` command.
class AaIssue {
  const AaIssue(this.kind, this.offset, this.length, this.message,
      {this.v21Message, this.replacement, int? fixOffset, int? fixLength})
      : fixOffset = fixOffset ?? offset,
        fixLength = fixLength ?? length;

  /// The kind of problem.
  final AaIssueKind kind;

  /// The position of the problem in the argument of the command (0-based).
  final int offset;

  /// The length of the problem in characters (at least 1 when reported).
  final int length;

  /// A message in plain English.
  final String message;

  /// The message for a file of version 2.1, if it is different from
  /// [message]. For example, version 2.1 allows forms of ISO 8601 that
  /// version 3.0 does not allow.
  final String? v21Message;

  /// The text that replaces the part from [fixOffset] with the length
  /// [fixLength], or null. It is set only when there is exactly one correct
  /// result with the same meaning. The rules use it for the automatic fix.
  final String? replacement;

  /// The start of the part that [replacement] replaces. Usually [offset].
  final int fixOffset;

  /// The length of the part that [replacement] replaces. Usually [length].
  final int fixLength;

  /// This issue at another place in the text. The part that [replacement]
  /// replaces moves to [fixOffset] and [fixLength].
  AaIssue at(int offset, int length, {int? fixOffset, int? fixLength}) =>
      AaIssue(kind, offset, length, message,
          v21Message: v21Message,
          replacement: replacement,
          fixOffset: fixOffset ?? offset,
          fixLength: fixLength ?? length);

  @override
  String toString() => 'AaIssue(${kind.ruleId} at $offset+$length: $message)';
}
