/// Builds the boundary of an airspace from its geometry commands, and
/// computes its bounds and centre.
library;

import '../model/openair_file.dart';
import '../values/coordinate.dart';
import '../values/text_parts.dart';
import '../values/variable.dart';
import 'arcs.dart';
import 'geo_math.dart';
import 'lat_lng.dart';

/// The geometry commands: `DP`, `DA`, `DB`, `DC`, `DY` and `V`.
const Set<String> geometryKeywords = {'DP', 'DA', 'DB', 'DC', 'DY', 'V'};

/// The boundary of one airspace, as a list of points.
class AirspaceBoundary {
  const AirspaceBoundary({
    required this.points,
    required this.unusedCommands,
    required this.hasCircle,
    required this.hasAirway,
  });

  /// All boundary points in file order. Arcs and circles are replaced by
  /// many points (see [defaultArcStepDeg]). For a `DC` circle the list is
  /// closed (the last point is the first point). For `DP` polygons the list
  /// is as written: it is closed only if the file closes it.
  final List<LatLng> points;

  /// Geometry commands that could not be used: the value could not be
  /// read, or an arc or circle came before any `V X=` centre.
  final List<Command> unusedCommands;

  /// True if the airspace has a `DC` command.
  final bool hasCircle;

  /// True if the airspace has a `DY` command. `DY` points are added as
  /// plain points (the airway width is not used).
  final bool hasAirway;

  /// True if there are no points.
  bool get isEmpty => points.isEmpty;

  /// The bounds of [points], or null if there are no points.
  GeoBounds? get bounds => GeoBounds.of(points);

  /// The position of the airspace that openair-lint uses for sun events,
  /// or null if there are no points. See [GeoBounds.centre].
  LatLng? get centre => bounds?.centre;
}

/// Builds the boundary of [airspace]. It never throws.
///
/// It follows the commands in file order:
///
/// - `V X=<point>` sets the centre for `DA`, `DB` and `DC`.
/// - `V D=+` (clockwise, the default) or `V D=-` sets the arc direction.
///   The direction is reset to clockwise at the start of each airspace.
/// - `DP <point>` and `DY <point>` add one point.
/// - `DA radius, start, end` adds an arc between two bearings.
/// - `DB point1, point2` adds an arc between two points.
/// - `DC radius` adds a full circle.
///
/// Values are read leniently with [parseCoordinate] and [parseDecimal]. A
/// command with a value that cannot be read is listed in
/// [AirspaceBoundary.unusedCommands] and skipped.
AirspaceBoundary buildBoundary(Airspace airspace,
    {double stepDeg = defaultArcStepDeg}) {
  final points = <LatLng>[];
  final unused = <Command>[];
  LatLng? centre;
  var clockwise = true;
  var hasCircle = false;
  var hasAirway = false;

  for (final c in airspace.commands) {
    switch (c.upperKeyword) {
      case 'V':
        final v = parseVariable(c);
        switch (v.upperName) {
          case 'X':
            centre = parseCoordinate(v.value).value;
            if (centre == null) unused.add(c);
          case 'D':
            if (v.value == '+') {
              clockwise = true;
            } else if (v.value == '-') {
              clockwise = false;
            } else {
              unused.add(c);
            }
          case 'W':
            break;
          default:
            unused.add(c);
        }
      case 'DP':
      case 'DY':
        if (c.upperKeyword == 'DY') hasAirway = true;
        final p = parseCoordinate(c.argument).value;
        if (p == null) {
          unused.add(c);
        } else {
          points.add(p);
        }
      case 'DA':
        final parts = splitParts(c.argument, ',');
        final values = [for (final p in parts) parseDecimal(p.text)];
        if (centre == null ||
            values.length != 3 ||
            values.any((v) => v == null) ||
            values[0]! <= 0) {
          unused.add(c);
        } else {
          points.addAll(arcByBearings(
              centre, values[0]!, values[1]!, values[2]!,
              clockwise: clockwise, stepDeg: stepDeg));
        }
      case 'DB':
        final parts = splitParts(c.argument, ',');
        final a =
            parts.isNotEmpty ? parseCoordinate(parts[0].text).value : null;
        final b =
            parts.length == 2 ? parseCoordinate(parts[1].text).value : null;
        if (centre == null || a == null || b == null) {
          unused.add(c);
        } else {
          points.addAll(arcByPoints(centre, a, b,
              clockwise: clockwise, stepDeg: stepDeg));
        }
      case 'DC':
        final r = parseDecimal(c.argument);
        if (centre == null || r == null || r <= 0) {
          unused.add(c);
        } else {
          hasCircle = true;
          points.addAll(circlePoints(centre, r, stepDeg: stepDeg));
        }
    }
  }
  return AirspaceBoundary(
    points: List.unmodifiable(points),
    unusedCommands: List.unmodifiable(unused),
    hasCircle: hasCircle,
    hasAirway: hasAirway,
  );
}

/// The smallest latitude/longitude box that contains a set of points.
///
/// The box can cross the antimeridian (180°). Then [west] is greater than
/// [east], for example west 170 and east -170.
class GeoBounds {
  const GeoBounds(this.south, this.north, this.west, this.east);

  /// The lowest latitude.
  final double south;

  /// The highest latitude.
  final double north;

  /// The westernmost longitude, -180 to 180.
  final double west;

  /// The easternmost longitude, -180 to 180.
  final double east;

  /// The width of the box in degrees of longitude (0 to 360).
  double get widthDeg {
    final w = east - west;
    return w < 0 ? w + 360 : w;
  }

  /// True if the box crosses the antimeridian.
  bool get crossesAntimeridian => west > east;

  /// The centre of the box: the midpoint between the lowest and the highest
  /// latitude, and the midpoint between the westernmost and the easternmost
  /// longitude. openair-lint uses it as the position of the airspace for
  /// sun events. The specification says only "the position of the
  /// airspace".
  LatLng get centre =>
      LatLng((south + north) / 2, normalizeLongitude(west + widthDeg / 2));

  /// Computes the bounds of [points], or null if [points] is empty.
  ///
  /// For the longitude, it finds the smallest interval that contains all
  /// points. It is the circle of longitudes minus the largest gap between
  /// two neighbour longitudes. So an airspace from 179°E to 179°W has west
  /// 179 and east -179 (2 degrees wide), not 358 degrees wide.
  static GeoBounds? of(List<LatLng> points) {
    if (points.isEmpty) return null;
    var south = points.first.lat;
    var north = south;
    final lons = <double>[];
    for (final p in points) {
      if (p.lat < south) south = p.lat;
      if (p.lat > north) north = p.lat;
      lons.add(normalizeLongitude(p.lon));
    }
    lons.sort();
    // Largest gap, including the gap that wraps around 180.
    var gapIndex = lons.length - 1; // gap between last and first
    var gap = lons.first + 360 - lons.last;
    for (var i = 0; i < lons.length - 1; i++) {
      final g = lons[i + 1] - lons[i];
      if (g > gap) {
        gap = g;
        gapIndex = i;
      }
    }
    final west = lons[(gapIndex + 1) % lons.length];
    final east = lons[gapIndex];
    return GeoBounds(south, north, west, east);
  }

  @override
  String toString() => 'GeoBounds(S $south, N $north, W $west, E $east)';
}

/// The direction of a polygon, or null if it has no area (fewer than three
/// different points, or all points on one line).
///
/// Returns true for clockwise (as seen on a map with north up). The
/// polygon can be open or closed. Longitudes are unwrapped, so polygons
/// across the antimeridian work. Polygons around a pole do not have a
/// clear direction; the result is then not useful.
bool? isClockwise(List<LatLng> points) {
  if (points.length < 3) return null;
  final xs = <double>[points.first.lon];
  for (var i = 1; i < points.length; i++) {
    xs.add(xs[i - 1] + normalizeLongitude(points[i].lon - points[i - 1].lon));
  }
  var area2 = 0.0;
  for (var i = 0; i < points.length; i++) {
    final j = (i + 1) % points.length;
    area2 += xs[i] * points[j].lat - xs[j] * points[i].lat;
  }
  if (area2.abs() < 1e-12) return null;
  return area2 < 0;
}
