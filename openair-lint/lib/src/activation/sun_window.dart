/// The window of a weekday `AA` command with a sun event on one local solar
/// day, as the section "Sun events" of the specification defines it.
///
/// ```dart
/// final w = sunWindowOnDay(
///     const AaTimeOfDay.fixed(7 * 3600000),
///     const AaTimeOfDay.sun(SunEvent.sunset),
///     const CivilDate(2026, 6, 1),
///     14.5,
///     (e, d) => sunEventOnLocalDay(e, d, const LatLng(46, 14.5)));
/// print(w.start); // 420.0 (07:00Z)
/// ```
library;

import 'aa_command.dart';
import 'civil_date.dart';
import 'sun.dart';

/// The kind of a window with a sun event. The table "Polar regions" of the
/// specification uses it.
enum SunWindowKind {
  /// From a morning event to an evening event, for example `SR/SS`.
  morningToEvening,

  /// From an evening event to a morning event, for example `SS/SR`.
  eveningToMorning,

  /// A sun event and a fixed time, for example `07:00Z/SS`.
  mixed,

  /// Two morning events or two evening events, for example `SR/BCMT`. The
  /// specification does not name this kind. It is treated like
  /// [morningToEvening].
  other;

  /// The kind of the window [start]/[end]. At least one of them must be a
  /// sun event.
  static SunWindowKind of(AaTimeOfDay start, AaTimeOfDay end) {
    final s = start.sunEvent;
    final e = end.sunEvent;
    if (s == null || e == null) return mixed;
    if (s.morning && !e.morning) return morningToEvening;
    if (!s.morning && e.morning) return eveningToMorning;
    return other;
  }
}

/// What a window means on a local solar day on which one of its sun events
/// does not happen (see the table "Polar regions" of the specification).
enum SunPolarOutcome {
  /// The window is active for the whole local solar day.
  wholeDay('the window is active for the whole local solar day'),

  /// The window is not active on that day.
  notActive('the window is not active'),

  /// The missing morning event is replaced by the start of the local solar
  /// day.
  startsAtDayStart('the window starts at the start of the local solar day '
      '(00:00 local solar time)'),

  /// The missing evening event at the start is replaced by the end of the
  /// local solar day.
  startsAtDayEnd('the window starts at the end of the local solar day '
      '(24:00 local solar time)'),

  /// The missing event at the end is replaced by the end of the local solar
  /// day.
  endsAtDayEnd('the window ends at the end of the local solar day '
      '(24:00 local solar time)');

  const SunPolarOutcome(this.text);

  /// The meaning for messages, for example `the window is not active`.
  final String text;
}

/// The window of one weekday command on one local solar day.
class SunWindowDay {
  SunWindowDay._(this.day, this.start, this.end,
      {this.startOnDay,
      this.endOnDay,
      this.missingEvents = const [],
      this.allDay,
      this.polar});

  /// The local solar day.
  final CivilDate day;

  /// The start of the window, in minutes after 00:00Z of the UTC day with
  /// the same date as [day]. Null if the window is not active on this day.
  final double? start;

  /// The end of the window, in the same unit as [start]. If the end is on
  /// the next local solar day, it is more than [start] by the length of the
  /// window. Null if the window is not active on this day.
  final double? end;

  /// The start time as calculated on [day], before the polar rules. Null on
  /// a day on which a sun event does not happen.
  final double? startOnDay;

  /// The end time as calculated on [day], before it is moved to the next
  /// local solar day. Null on a day on which a sun event does not happen.
  final double? endOnDay;

  /// The sun events of the window that do not happen on this day (empty on
  /// a normal day).
  final List<SunEvent> missingEvents;

  /// Where the sun is during the day when [missingEvents] is not empty. This
  /// is the position for the first missing event.
  final SunAllDay? allDay;

  /// What the window means on this day when [missingEvents] is not empty.
  final SunPolarOutcome? polar;

  /// True if both times happen on this day, so the normal rules apply.
  bool get isNormal => polar == null;

  /// True if the window ends on the next local solar day: the end time is
  /// earlier than or equal to the start time.
  bool get endsNextDay =>
      startOnDay != null && endOnDay != null && endOnDay! <= startOnDay!;

  /// True if the window is active on this day.
  bool get isActive => start != null && end != null && end! > start!;
}

/// A function that gives a sun event on a local solar day. The rules pass a
/// function with a cache.
typedef SunEventOn = LocalSunEvent Function(SunEvent event, CivilDate day);

/// The window [start]/[end] (at least one is a sun event) on the local
/// solar day [day] at [longitude] (the centre of the airspace).
///
/// - A fixed time is the UTC time inside the local solar day.
/// - A sun event is the event of the local solar day ([eventOn]).
/// - If the end is earlier than or equal to the start, the window ends on
///   the next local solar day.
/// - If a sun event does not happen on [day], the table "Polar regions" of
///   the specification gives the window ([SunWindowDay.polar]).
SunWindowDay sunWindowOnDay(AaTimeOfDay start, AaTimeOfDay end, CivilDate day,
    double longitude, SunEventOn eventOn) {
  final dayStart = localDayStartMinutes(longitude);
  final dayEnd = dayStart + 1440;
  final startEvent = start.sunEvent;
  final endEvent = end.sunEvent;
  final startSun = startEvent == null ? null : eventOn(startEvent, day);
  final endSun = endEvent == null ? null : eventOn(endEvent, day);
  final s = startSun == null
      ? placeInLocalDay(start.ms! / msPerMinute, longitude)
      : startSun.minutes;
  final e = endSun == null
      ? placeInLocalDay(end.ms! / msPerMinute, longitude)
      : endSun.minutes;

  if (s != null && e != null) {
    if (e > s) {
      return SunWindowDay._(day, s, e, startOnDay: s, endOnDay: e);
    }
    // The window ends on the next local solar day.
    double next;
    if (endEvent == null) {
      next = e + 1440;
    } else {
      final n = eventOn(endEvent, day.addDays(1));
      if (n.minutes != null) {
        next = n.minutes! + 1440;
      } else if (n.allDay == SunAllDay.above && !endEvent.morning) {
        next = dayEnd + 1440;
      } else {
        next = dayEnd;
      }
    }
    return SunWindowDay._(day, s, next, startOnDay: s, endOnDay: e);
  }

  // A sun event does not happen on this day.
  final startMissing = startSun != null && startSun.minutes == null;
  final endMissing = endSun != null && endSun.minutes == null;
  final missingEvents = [
    if (startMissing) startEvent!,
    if (endMissing && endEvent != startEvent) endEvent!,
  ];
  final allDay = <SunAllDay>{
    if (startMissing) startSun.allDay!,
    if (endMissing) endSun.allDay!,
  };
  SunWindowDay result(SunPolarOutcome outcome, [double? from, double? to]) =>
      SunWindowDay._(day, from, to,
          missingEvents: missingEvents, allDay: allDay.first, polar: outcome);

  final kind = SunWindowKind.of(start, end);
  if (kind == SunWindowKind.eveningToMorning) {
    // The window is the night. If the sun stays above the horizon of an
    // event, there is no night.
    if (allDay.contains(SunAllDay.above)) {
      return result(SunPolarOutcome.notActive);
    }
    return result(SunPolarOutcome.wholeDay, dayStart, dayEnd);
  }
  // From morning to evening, or a sun event and a fixed time. If the sun
  // stays below the horizon of an event, the window is not active.
  if (allDay.contains(SunAllDay.below)) {
    return result(SunPolarOutcome.notActive);
  }
  // The sun stays above the horizon: a missing morning event is the start
  // of the local solar day, a missing evening event is the end. Then the
  // normal rules apply: an end earlier than or equal to the start is on
  // the next local solar day.
  double replace(SunEvent ev) => ev.morning ? dayStart : dayEnd;
  final from = s ?? replace(startEvent!);
  var to = e ?? replace(endEvent!);
  if (to <= from) to += 1440;
  if (from == dayStart && to == dayEnd) {
    return result(SunPolarOutcome.wholeDay, from, to);
  }
  if (s == null) {
    return result(
        startEvent!.morning
            ? SunPolarOutcome.startsAtDayStart
            : SunPolarOutcome.startsAtDayEnd,
        from,
        to);
  }
  return result(SunPolarOutcome.endsAtDayEnd, from, to);
}
