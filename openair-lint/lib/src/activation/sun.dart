/// Sun events (sunrise, sunset and civil twilight) as the OpenAir
/// specification defines them.
///
/// The calculation uses the NOAA solar position equations (based on
/// "Astronomical Algorithms" by Jean Meeus). The result is accurate to
/// about one minute between latitudes 72° N and 72° S. The specification
/// accepts differences of about one minute between methods.
///
/// The rules of the specification:
///
/// - Date: the UTC day. The result is the event that happens on that UTC
///   day.
/// - Position: the centre of the airspace.
/// - Horizon: flat, at sea level.
/// - `SR` and `SS`: the centre of the sun is 0°50′ below the horizon.
/// - `BCMT` and `EECT`: the centre of the sun is 6° below the horizon,
///   without refraction.
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

  /// The event with this keyword (any case), or null.
  static SunEvent? fromKeyword(String keyword) {
    final k = keyword.toUpperCase();
    for (final e in values) {
      if (e.keyword == k) return e;
    }
    return null;
  }
}

/// The time of [event] on the UTC day [date] at [position], in minutes
/// after 00:00Z of that day.
///
/// Returns null if the event does not happen (polar day or polar night).
///
/// The result is the event of the local solar day around [date]. If that
/// event is on the UTC day before or after, the event of the neighbour local
/// day is used. So the result is almost always 0 to 1440. In some rare
/// cases it is a little outside (for example -0.2 or 1440.2): this happens
/// when the UTC day has no such event because the events of two local days
/// are just before 00:00Z and just after 24:00Z. If the UTC day has two such
/// events (near a polar day or a polar night), only one is returned. The
/// specification does not say yet which event belongs to a UTC day in these
/// cases.
///
/// Callers that show the result with a date must use the day offset of the
/// result (a value below 0 is on the day before). [formatMinutes] shows only
/// the time of day.
double? sunEventMinutes(SunEvent event, CivilDate date, LatLng position) {
  final t = _eventNearDay(event, date, position);
  if (t == null) return null;
  // Far from Greenwich, the event of the local day can be on the UTC day
  // before or after. Then the event of the neighbour day is on this UTC
  // day.
  if (t < 0) {
    final n = _eventNearDay(event, date.addDays(1), position);
    return n == null ? null : n + 1440;
  }
  if (t >= 1440) {
    final p = _eventNearDay(event, date.addDays(-1), position);
    return p == null ? null : p - 1440;
  }
  return t;
}

/// The event for the local solar day around [date], in minutes after
/// 00:00Z of [date]. The result can be below 0 or above 1440.
double? _eventNearDay(SunEvent event, CivilDate date, LatLng position) {
  // Start with the solar position at the solar noon.
  final noon = 720 - 4 * position.lon;
  final (t, failedAtStart) = _iterate(event, date, position, noon, true);
  if (t != null || !failedAtStart) return t;
  // Near a polar day or a polar night, the sun can miss the angle of the
  // event at noon, but reach it about 12 hours later (or earlier), when the
  // declination is a little different. Start again at that time.
  final edge = event.morning ? noon - 720 : noon + 720;
  return _iterate(event, date, position, edge, false).$1;
}

/// Calculates the event from the start estimate [start] (minutes after
/// 00:00Z of [date]). Returns the time, or null and true if the sun does not
/// reach the angle of the event at [start].
(double?, bool) _iterate(SunEvent event, CivilDate date, LatLng position,
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
    final ha = _hourAngleDeg(lat, s.declination, event.zenithDeg);
    if (ha == null) return (null, i == 0);
    final noon = 720 - 4 * lon - s.equationOfTime;
    final next = event.morning ? noon - 4 * ha : noon + 4 * ha;
    final change = (next - t).abs();
    t = next;
    final nearEdge = ha < 20 || ha > 160;
    if (i >= 1 && change < (nearEdge ? 0.01 : 1)) break;
  }
  return (t, false);
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

/// The hour angle of the sun at the zenith angle [zenithDeg], in degrees,
/// or null if the sun does not reach this angle on that day.
double? _hourAngleDeg(double latDeg, double declDeg, double zenithDeg) {
  final lat = latDeg * _rad;
  final decl = declDeg * _rad;
  final denominator = math.cos(lat) * math.cos(decl);
  if (denominator.abs() < 1e-12) return null;
  final cosH = (math.cos(zenithDeg * _rad) - math.sin(lat) * math.sin(decl)) /
      denominator;
  if (cosH < -1 || cosH > 1) return null;
  return math.acos(cosH) / _rad;
}
