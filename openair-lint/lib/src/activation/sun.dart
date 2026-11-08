/// Sun events (sunrise, sunset and civil twilight).
///
/// The calculation uses the NOAA solar position equations (based on
/// "Astronomical Algorithms" by Jean Meeus). The result is accurate to
/// about one minute between latitudes 72° N and 72° S. The specification
/// says that different calculation methods can give results that differ
/// by a few minutes.
///
/// The specification defines the events (`SR` and `SS`: the upper edge of
/// the sun at the horizon, `BCMT` and `EECT`: the centre of the sun 6°
/// below the horizon) and says that the weekday and the date mean the
/// local day at the airspace. These details are choices of openair-lint:
///
/// - Local day: the local solar day, from 00:00 to 24:00 local solar time.
///   Local solar time is UTC plus the longitude divided by 15, in hours
///   (east is positive). It does not use time zones or daylight saving
///   time. The event is the one that happens on this local solar day.
/// - Position: the centre of the box around the airspace.
/// - Horizon: flat, at sea level.
/// - `SR` and `SS`: the centre of the sun is 0°50′ below the horizon (the
///   usual value for the radius of the sun and the refraction).
/// - `BCMT` and `EECT`: without refraction.
/// - Polar regions: on a day without the event, the sun is above or below
///   the horizon of the event for the whole day ([SunAllDay]).
///
/// Times are minutes after 00:00Z of the UTC day that has the same date as
/// the local solar day. For example, at 15° E the local solar day
/// 2026-07-04 is from -60 (23:00Z on 2026-07-03) to 1380 (23:00Z on
/// 2026-07-04).
library;

import 'dart:math' as math;

import '../geometry/lat_lng.dart';
import 'civil_date.dart';

/// A sun event that a weekday `AA` command can use in place of a time.
enum SunEvent {
  /// `SR`: the upper edge of the sun appears at the horizon.
  sunrise('SR', 'sunrise', 90 + 50 / 60, morning: true),

  /// `SS`: the upper edge of the sun disappears below the horizon.
  sunset('SS', 'sunset', 90 + 50 / 60, morning: false),

  /// `BCMT`: the beginning of civil morning twilight. The centre of the sun
  /// is 6° below the horizon in the morning.
  civilDawn('BCMT', 'the beginning of civil morning twilight', 96,
      morning: true),

  /// `EECT`: the end of evening civil twilight. The centre of the sun is 6°
  /// below the horizon in the evening.
  civilDusk('EECT', 'the end of evening civil twilight', 96, morning: false);

  const SunEvent(this.keyword, this.description, this.zenithDeg,
      {required this.morning});

  /// The keyword in OpenAir, for example `SR`.
  final String keyword;

  /// A description for messages, for example `sunrise`.
  final String description;

  /// The angle between the zenith and the centre of the sun at the event,
  /// in degrees.
  final double zenithDeg;

  /// True for morning events (`SR`, `BCMT`).
  final bool morning;

  /// The horizon of the event, for messages: `0°50′ below the horizon` or
  /// `6° below the horizon`.
  String get horizon =>
      zenithDeg == 96 ? '6° below the horizon' : '0°50′ below the horizon';

  /// The event with this keyword (any case), or null.
  static SunEvent? fromKeyword(String keyword) {
    final k = keyword.toUpperCase();
    for (final e in values) {
      if (e.keyword == k) return e;
    }
    return null;
  }
}

/// Where the sun is during a local solar day on which a sun event does not
/// happen.
enum SunAllDay {
  /// The sun is above the horizon of the event during the whole day (for
  /// `SR` and `SS`: the polar day).
  above,

  /// The sun is below the horizon of the event during the whole day (for
  /// `SR` and `SS`: the polar night).
  below,
}

/// A sun event on one local solar day: the time of the event, or where the
/// sun is if the event does not happen on that day.
class LocalSunEvent {
  const LocalSunEvent.at(double this.minutes) : allDay = null;
  const LocalSunEvent.missing(SunAllDay this.allDay) : minutes = null;

  /// The time of the event, in minutes after 00:00Z of the UTC day with the
  /// same date as the local solar day. Null if the event does not happen.
  final double? minutes;

  /// Where the sun is if the event does not happen, else null.
  final SunAllDay? allDay;

  /// True if the event happens on the day.
  bool get happens => minutes != null;
}

/// The start of a local solar day at [longitude] (degrees, east positive),
/// in minutes after 00:00Z of the UTC day with the same date. The day ends
/// 1440 minutes later.
///
/// Local solar time is UTC plus `longitude / 15` hours. So at 15° E the
/// local solar day starts at -60 (23:00Z on the day before), and at 120° W
/// it starts at 480 (08:00Z).
double localDayStartMinutes(double longitude) => -4 * longitude;

/// The minutes after 00:00Z of the UTC day with the same date as the local
/// solar day, for the UTC time of day [timeOfDayMinutes] (0 to 1440) inside
/// the local solar day at [longitude]. Each UTC time of day happens exactly
/// once in a local solar day. `24:00Z` is the same time of day as `00:00Z`.
double placeInLocalDay(double timeOfDayMinutes, double longitude) {
  final start = localDayStartMinutes(longitude);
  var t = timeOfDayMinutes % 1440;
  while (t < start) {
    t += 1440;
  }
  while (t >= start + 1440) {
    t -= 1440;
  }
  return t;
}

/// The sun [event] on the local solar day [day] at [position].
///
/// The result is the event that happens on this local solar day. The
/// calculation starts at the solar noon of the day. In rare cases near a
/// polar day or a polar night, the event of the solar day is a few minutes
/// before or after the local solar day. Then the event of the next or of the
/// previous day is used if it is inside the local solar day. If neither is
/// inside, the event of the solar day is used.
///
/// If the event does not happen (polar day or polar night), the result says
/// whether the sun is above or below the horizon of the event during the
/// whole day.
LocalSunEvent sunEventOnLocalDay(
    SunEvent event, CivilDate day, LatLng position) {
  final start = localDayStartMinutes(position.lon);
  final end = start + 1440;
  final r = _eventOfSolarDay(event, day, position);
  final t = r.minutes;
  if (t == null || (t >= start && t < end)) return r;
  if (t < start) {
    final next = _eventOfSolarDay(event, day.addDays(1), position).minutes;
    if (next != null && next + 1440 >= start && next + 1440 < end) {
      return LocalSunEvent.at(next + 1440);
    }
  } else {
    final previous = _eventOfSolarDay(event, day.addDays(-1), position).minutes;
    if (previous != null && previous - 1440 >= start && previous - 1440 < end) {
      return LocalSunEvent.at(previous - 1440);
    }
  }
  return r;
}

/// The event of the solar day [date] (the day with the solar noon near
/// 12:00 local solar time), in minutes after 00:00Z of [date].
LocalSunEvent _eventOfSolarDay(
    SunEvent event, CivilDate date, LatLng position) {
  // Start with the solar position at the mean solar noon.
  final noon = 720 - 4 * position.lon;
  final first = _iterate(event, date, position, noon, true);
  if (first.minutes != null || !first.failedAtStart) return first.result;
  // If the sun stays below the angle of the event at noon, its highest
  // point of the day is below the angle. Then the event does not happen.
  // Sunrise and sunset (and BCMT and EECT) get the same result, because
  // they use the same position of the sun at noon.
  if (first.allDay == SunAllDay.below) return first.result;
  // Near a polar day, the sun can stay above the angle of the event at
  // noon, but reach it about 12 hours earlier (a morning event) or later
  // (an evening event), near midnight, when the declination is a little
  // different. Start again at that time.
  final edge = event.morning ? noon - 720 : noon + 720;
  final second = _iterate(event, date, position, edge, false);
  if (second.minutes != null) return second.result;
  // The event does not happen. Use the position of the sun at noon.
  return first.result;
}

/// The result of [_iterate].
class _Iteration {
  _Iteration(this.minutes, this.allDay, {this.failedAtStart = false});

  final double? minutes;
  final SunAllDay? allDay;

  /// True if the sun does not reach the angle of the event at the start
  /// estimate.
  final bool failedAtStart;

  LocalSunEvent get result => minutes != null
      ? LocalSunEvent.at(minutes!)
      : LocalSunEvent.missing(allDay!);
}

/// Calculates the event from the start estimate [start] (minutes after
/// 00:00Z of [date]).
_Iteration _iterate(SunEvent event, CivilDate date, LatLng position,
    double start, bool cached) {
  final lat = position.lat;
  final lon = position.lon;
  // Calculate the solar position again at the last estimate of the event,
  // until the estimate changes by less than one minute. Then the result is
  // exact to a few seconds. Below 60° latitude this needs two steps. When
  // the sun only just reaches the angle of the event (the hour angle is
  // near 0° or 180°, close to a polar day or a polar night), more steps are
  // needed to know if the event happens.
  var t = start;
  for (var i = 0; i < 10; i++) {
    final jd = date.dayNumber + 2440587.5 + t / 1440;
    final s = i == 0 && cached ? _solarCached(jd) : _solar(jd);
    final cosH = _cosHourAngle(lat, s.declination, event.zenithDeg);
    if (cosH < -1) {
      return _Iteration(null, SunAllDay.above, failedAtStart: i == 0);
    }
    if (cosH > 1) {
      return _Iteration(null, SunAllDay.below, failedAtStart: i == 0);
    }
    final ha = math.acos(cosH) / _rad;
    final noon = 720 - 4 * lon - s.equationOfTime;
    final next = event.morning ? noon - 4 * ha : noon + 4 * ha;
    final change = (next - t).abs();
    t = next;
    final nearEdge = ha < 20 || ha > 160;
    if (i >= 1 && change < (nearEdge ? 0.01 : 1)) break;
  }
  return _Iteration(t, null);
}

// The last solar position at the solar noon. All events of one day at one
// position start with the same value, so this saves time when a linter
// calculates several events for each day.
double? _cachedJd;
({double declination, double equationOfTime})? _cachedSolar;

({double declination, double equationOfTime}) _solarCached(double jd) {
  if (jd == _cachedJd) return _cachedSolar!;
  final s = _solar(jd);
  _cachedJd = jd;
  _cachedSolar = s;
  return s;
}

const double _rad = math.pi / 180;

/// The declination of the sun (degrees) and the equation of time
/// (minutes) at the Julian day [jd].
({double declination, double equationOfTime}) _solar(double jd) {
  final t = (jd - 2451545.0) / 36525.0;
  final l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)) % 360;
  final m = 357.52911 + t * (35999.05029 - 0.0001537 * t);
  final e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  final mRad = m * _rad;
  final c = math.sin(mRad) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
      math.sin(2 * mRad) * (0.019993 - 0.000101 * t) +
      math.sin(3 * mRad) * 0.000289;
  final trueLong = l0 + c;
  final omega = 125.04 - 1934.136 * t;
  final lambda = trueLong - 0.00569 - 0.00478 * math.sin(omega * _rad);
  final seconds = 21.448 - t * (46.815 + t * (0.00059 - t * 0.001813));
  final eps0 = 23 + (26 + seconds / 60) / 60;
  final eps = eps0 + 0.00256 * math.cos(omega * _rad);
  final decl = math.asin(math.sin(eps * _rad) * math.sin(lambda * _rad)) / _rad;
  final y = math.pow(math.tan(eps * _rad / 2), 2).toDouble();
  final l0Rad = l0 * _rad;
  final eqTime = 4 *
      (y * math.sin(2 * l0Rad) -
          2 * e * math.sin(mRad) +
          4 * e * y * math.sin(mRad) * math.cos(2 * l0Rad) -
          0.5 * y * y * math.sin(4 * l0Rad) -
          1.25 * e * e * math.sin(2 * mRad)) /
      _rad;
  return (declination: decl, equationOfTime: eqTime);
}

/// The cosine of the hour angle of the sun at the zenith angle
/// [zenithDeg]. A value below -1 means that the sun stays above this angle
/// during the whole day, a value above 1 that it stays below.
double _cosHourAngle(double latDeg, double declDeg, double zenithDeg) {
  final lat = latDeg * _rad;
  final decl = declDeg * _rad;
  final numerator = math.cos(zenithDeg * _rad) - math.sin(lat) * math.sin(decl);
  final denominator = math.cos(lat) * math.cos(decl);
  if (denominator.abs() < 1e-12) {
    // At a pole the height of the sun does not change during the day.
    return numerator < 0 ? double.negativeInfinity : double.infinity;
  }
  return numerator / denominator;
}
