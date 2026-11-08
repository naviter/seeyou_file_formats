/// Great-circle calculations on a sphere.
///
/// Distances are in nautical miles (NM), angles in degrees. Bearings are
/// true bearings, clockwise from north, in the range 0 (inclusive) to 360
/// (exclusive).
library;

import 'dart:math' as math;

import 'lat_lng.dart';

/// The mean radius of the earth in nautical miles (6371008.8 m / 1852 m).
const double earthRadiusNm = 6371008.8 / 1852.0;

const double _toRad = math.pi / 180;
const double _toDeg = 180 / math.pi;

/// Returns [degrees] in the range 0 (inclusive) to 360 (exclusive).
double normalizeBearing(double degrees) {
  final r = degrees % 360;
  return r < 0 ? r + 360 : r;
}

/// Returns [degrees] in the range -180 (inclusive) to 180 (exclusive).
double normalizeLongitude(double degrees) {
  final r = (degrees + 180) % 360;
  return (r < 0 ? r + 360 : r) - 180;
}

/// The great-circle distance between [a] and [b] in nautical miles
/// (haversine formula).
double distanceNm(LatLng a, LatLng b) {
  final lat1 = a.lat * _toRad;
  final lat2 = b.lat * _toRad;
  final dLat = lat2 - lat1;
  final dLon = (b.lon - a.lon) * _toRad;
  final s1 = math.sin(dLat / 2);
  final s2 = math.sin(dLon / 2);
  final h = s1 * s1 + math.cos(lat1) * math.cos(lat2) * s2 * s2;
  return 2 * earthRadiusNm * math.asin(math.min(1.0, math.sqrt(h)));
}

/// The initial true bearing from [from] to [to], 0 to 360 degrees.
///
/// If the points are the same, the result is 0.
double initialBearing(LatLng from, LatLng to) {
  final lat1 = from.lat * _toRad;
  final lat2 = to.lat * _toRad;
  final dLon = (to.lon - from.lon) * _toRad;
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  if (x == 0 && y == 0) return 0;
  return normalizeBearing(math.atan2(y, x) * _toDeg);
}

/// The point at [distanceNm] nautical miles from [origin] in the direction
/// [bearingDeg].
LatLng destinationPoint(LatLng origin, double bearingDeg, double distanceNm) {
  final d = distanceNm / earthRadiusNm;
  final brg = bearingDeg * _toRad;
  final lat1 = origin.lat * _toRad;
  final lon1 = origin.lon * _toRad;
  final sinLat2 = math.sin(lat1) * math.cos(d) +
      math.cos(lat1) * math.sin(d) * math.cos(brg);
  final lat2 = math.asin(sinLat2.clamp(-1.0, 1.0));
  final lon2 = lon1 +
      math.atan2(math.sin(brg) * math.sin(d) * math.cos(lat1),
          math.cos(d) - math.sin(lat1) * sinLat2);
  return LatLng(lat2 * _toDeg, normalizeLongitude(lon2 * _toDeg));
}
