/// Arc and circle densification for `DA`, `DB` and `DC`.
library;

import 'dart:math' as math;

import 'geo_math.dart';
import 'lat_lng.dart';

/// The default largest angle between two points of an arc, in degrees.
const double defaultArcStepDeg = 2.0;

/// The angle that an arc covers, in degrees (0 to 360).
///
/// [clockwise] is the direction from [startDeg] to [endDeg]. If the two
/// bearings are exactly equal, the result is 0. If they differ but point in
/// the same direction (for example 0 and 360), the result is 360.
double arcSweep(double startDeg, double endDeg, {bool clockwise = true}) {
  if (startDeg == endDeg) return 0;
  final raw = clockwise ? endDeg - startDeg : startDeg - endDeg;
  final sweep = normalizeBearing(raw);
  return sweep == 0 ? 360 : sweep;
}

/// The points of an arc around [center] with [radiusNm], from bearing
/// [startDeg] to bearing [endDeg] (as used by `DA`).
///
/// The result starts at the start bearing and ends at the end bearing.
/// No two neighbour points are more than [stepDeg] degrees apart (seen from
/// the centre). See [arcSweep] for equal bearings.
List<LatLng> arcByBearings(
  LatLng center,
  double radiusNm,
  double startDeg,
  double endDeg, {
  bool clockwise = true,
  double stepDeg = defaultArcStepDeg,
}) {
  final sweep = arcSweep(startDeg, endDeg, clockwise: clockwise);
  final steps = math.max(1, (sweep / stepDeg).ceil());
  final dir = clockwise ? 1.0 : -1.0;
  if (sweep == 0) return [destinationPoint(center, startDeg, radiusNm)];
  return [
    for (var i = 0; i <= steps; i++)
      destinationPoint(center, startDeg + dir * sweep * i / steps, radiusNm),
  ];
}

/// The points of an arc around [center] from [from] to [to] (as used by
/// `DB`).
///
/// The radius is the distance from [center] to [from]. The result starts
/// exactly at [from] and ends exactly at [to], even if [to] has another
/// distance from the centre.
List<LatLng> arcByPoints(
  LatLng center,
  LatLng from,
  LatLng to, {
  bool clockwise = true,
  double stepDeg = defaultArcStepDeg,
}) {
  final radius = distanceNm(center, from);
  final start = initialBearing(center, from);
  final end = initialBearing(center, to);
  final points = arcByBearings(center, radius, start, end,
      clockwise: clockwise, stepDeg: stepDeg);
  if (points.length == 1) return [from, to];
  points[0] = from;
  points[points.length - 1] = to;
  return points;
}

/// The points of a circle around [center] with [radiusNm] (as used by
/// `DC`). The polygon is clockwise and closed: the last point is the same
/// as the first.
List<LatLng> circlePoints(LatLng center, double radiusNm,
    {double stepDeg = defaultArcStepDeg}) {
  final steps = math.max(8, (360 / stepDeg).ceil());
  final points = [
    for (var i = 0; i < steps; i++)
      destinationPoint(center, 360.0 * i / steps, radiusNm),
  ];
  points.add(points.first);
  return points;
}
