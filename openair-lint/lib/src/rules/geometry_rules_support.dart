/// Helpers for the geometry rules (geometry_rules.dart). Only the geometry
/// rule group uses this file.
library;

import 'dart:math' as math;

import '../geometry/arcs.dart';
import '../geometry/geo_math.dart';
import '../geometry/lat_lng.dart';
import '../lint_context.dart';
import '../model/openair_file.dart';
import '../values/coordinate.dart';
import '../values/text_parts.dart';
import '../values/variable.dart';

/// One coordinate inside the argument of a command.
class CommandCoordinate {
  CommandCoordinate(this.command, this.offset, this.text, this.result);

  /// The command that contains the coordinate.
  final Command command;

  /// The offset of [text] in [Command.argument] (0-based).
  final int offset;

  /// The coordinate text, without spaces at the start and the end.
  final String text;

  /// The parsed coordinate.
  final CoordinateParseResult result;

  /// The position for the shape checks.
  ///
  /// This is [CoordinateParseResult.value]. When the only problem is
  /// minutes or seconds of exactly 60 (for example `41:08:60N`), the parser
  /// gives no value. Then this is the position with the 60 carried to the
  /// next minute or degree (`41:09:00N`). The rule `coordinate-out-of-range`
  /// still reports the 60. Many real files have this problem, and the shape
  /// checks are still useful for them. Null if there is no position.
  late final LatLng? position = carriedPosition(text, result);
}

/// The position of [text] (parsed as [result]), also when its only fatal
/// problems are minutes or seconds of exactly 60. See
/// [CommandCoordinate.position].
///
/// The 60 is replaced by 00, and the removed 60 minutes (one degree) or 60
/// seconds (one minute) are added to the part again (away from 0, so `S`
/// and `W` stay correct). Returns null if
/// [result] has other fatal problems or a value that is not exactly 60, or
/// if the carry goes past 90 or 180 degrees.
LatLng? carriedPosition(String text, CoordinateParseResult result) {
  final value = result.value;
  if (value != null) return value;
  final fatal = [
    for (final i in result.issues)
      if (i.fatal) i
  ];
  if (fatal.isEmpty) return null;
  var fixed = text;
  var latAdd = 0.0;
  var lonAdd = 0.0;
  for (final i in fatal) {
    final isMinutes = i.kind == CoordinateIssueKind.minutesOutOfRange;
    final isSeconds = i.kind == CoordinateIssueKind.secondsOutOfRange;
    if (!isMinutes && !isSeconds) return null;
    final end = i.offset + i.length;
    if (end > text.length) return null;
    final group = text.substring(i.offset, end);
    if (double.tryParse(group) != 60) return null;
    // The same length, so the offsets of the other issues stay correct.
    fixed =
        fixed.replaceRange(i.offset, end, group.replaceAll(RegExp(r'\d'), '0'));
    // 60 minutes are one degree, and 60 seconds are one minute.
    final add = isMinutes ? 1.0 : 1 / 60;
    switch (i.part) {
      case CoordinatePart.latitude:
        latAdd += add;
      case CoordinatePart.longitude:
        lonAdd += add;
      case CoordinatePart.both:
        return null;
    }
  }
  final base = parseCoordinate(fixed).value;
  if (base == null) return null;
  final lat = base.lat.isNegative ? base.lat - latAdd : base.lat + latAdd;
  final lon = base.lon.isNegative ? base.lon - lonAdd : base.lon + lonAdd;
  if (lat.abs() > 90 + 1e-12 || lon.abs() > 180 + 1e-12) return null;
  return LatLng(lat, lon);
}

/// The coordinates of [command]: one for `DP`, `DY` and `V X=`, two for
/// `DB`, none for other commands.
///
/// A `DB` command without exactly two parts (separated by a comma) has no
/// coordinates here. The rule `db-wrong-format` reports it. An empty `V X=`
/// value is reported by `v-wrong-format`, so it has no coordinate here.
///
/// [airspace] is the airspace of [command], or null for a command before
/// the first `AC`.
List<CommandCoordinate> coordinatesOf(
        LintContext ctx, Command command, Airspace? airspace) =>
    _cacheOf(ctx).coordinates(ctx, command, airspace);

/// The geometry cache of one file. It is kept in [LintContext.memo], so it
/// is freed together with the context when the lint run ends.
class _GeometryCache {
  // About ten rules read the coordinates of every command, and real files
  // have a million coordinates. Keeping all results for the whole file is
  // slow (memory and garbage collection). The linter checks one airspace
  // after the other, so this cache keeps only the results of the current
  // airspace, in a table by command index. A cursor finds the next command
  // directly. If the cache does not have a result, it computes it again.
  // So the result is always correct, in any order of calls.
  List<Command>? _scope;
  List<List<CommandCoordinate>?> _table = const [];
  Command? _lastCommand;
  List<CommandCoordinate> _lastCoordinates = const [];
  int _lastIndex = -1;

  /// The airspace of [shape] (see [shapeOf]).
  Airspace? shapeAirspace;

  /// The shape of the last airspace (see [shapeOf]).
  GeometryShape? shape;

  List<CommandCoordinate> coordinates(
      LintContext ctx, Command command, Airspace? airspace) {
    if (identical(command, _lastCommand)) return _lastCoordinates;
    final scope = airspace?.commands ?? ctx.file.commandsOutsideAirspace;
    var start = _lastIndex + 1;
    if (!identical(scope, _scope)) {
      _scope = scope;
      _table = List<List<CommandCoordinate>?>.filled(scope.length, null);
      _lastCommand = null;
      start = 0;
    }
    var index = -1;
    for (var i = start; i < scope.length; i++) {
      if (identical(scope[i], command)) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      for (var i = 0; i < start && i < scope.length; i++) {
        if (identical(scope[i], command)) {
          index = i;
          break;
        }
      }
    }
    if (index < 0) return _coordinates(command); // Not in this scope.
    final result = _table[index] ??= _coordinates(command);
    _lastCommand = command;
    _lastCoordinates = result;
    _lastIndex = index;
    return result;
  }
}

_GeometryCache _cacheOf(LintContext ctx) =>
    ctx.memo('geometry-cache', _GeometryCache.new);

List<CommandCoordinate> _coordinates(Command c) {
  switch (c.upperKeyword) {
    case 'DP':
    case 'DY':
      return [CommandCoordinate(c, 0, c.argument, parseCoordinate(c.argument))];
    case 'DB':
      final parts = splitParts(c.argument, ',');
      if (parts.length != 2) return const [];
      return [
        for (final p in parts)
          if (p.text.isNotEmpty)
            CommandCoordinate(c, p.offset, p.text, parseCoordinate(p.text))
      ];
    case 'V':
      final v = parseVariable(c);
      if (v.upperName != 'X' || !v.hasEquals || v.value.isEmpty) {
        return const [];
      }
      return [
        CommandCoordinate(c, v.valueOffset, v.value, parseCoordinate(v.value))
      ];
  }
  return const [];
}

/// The three numbers of a `DA` command, or null if the argument does not
/// have three numbers. Signs are accepted, so that a negative value can be
/// reported as out of range.
List<double>? daValues(String argument) {
  final parts = splitParts(argument, ',');
  if (parts.length != 3) return null;
  final values = <double>[];
  for (final p in parts) {
    final v = parseDecimal(p.text, allowSign: true);
    if (v == null) return null;
    values.add(v);
  }
  return values;
}

/// True if a `DA` command can be drawn: three numbers, a positive radius
/// and bearings from 0 to 360.
bool daIsUsable(List<double>? v) =>
    v != null &&
    v[0] > 0 &&
    v[1] >= 0 &&
    v[1] <= 360 &&
    v[2] >= 0 &&
    v[2] <= 360;

/// The geometry commands that build a boundary.
const Set<String> shapeKeywords = {'DP', 'DA', 'DB', 'DC', 'DY'};

/// The boundary of an airspace, with the command that made each point.
class GeometryShape {
  GeometryShape({
    required this.points,
    required this.sources,
    required this.commands,
    required this.complete,
  });

  /// All boundary points in file order. Arcs and circles are replaced by
  /// many points.
  final List<LatLng> points;

  /// The command that made each point. Same length as [points].
  final List<Command> sources;

  /// The geometry commands (`DP`, `DA`, `DB`, `DC`, `DY`) in file order.
  final List<Command> commands;

  /// False if at least one geometry command could not be used, for example
  /// because a coordinate is wrong or the `V X=` centre is missing. A
  /// minute or second of exactly 60 does not make the shape incomplete (see
  /// [CommandCoordinate.position]). Other
  /// rules report these problems. The shape rules do not check incomplete
  /// shapes, because the result would be wrong.
  final bool complete;

  bool _has(String keyword) => commands.any((c) => c.upperKeyword == keyword);

  /// True if the airspace has a `DC` circle.
  bool get hasCircle => _has('DC');

  /// True if the airspace has a `DY` airway segment.
  bool get hasAirway => _has('DY');

  /// True if there are no geometry commands.
  bool get isEmpty => commands.isEmpty;

  /// The polygon without repeated points. See [ringOf].
  late final PolygonRing ring = ringOf(this);

  /// The crossings of [ring]. See [findCrossings].
  late final CrossingResult crossings = findCrossings(ring);
}

/// The shape of [airspace].
///
/// Only the shape of the last airspace is kept (see [coordinatesOf] for the
/// reason). All airspace rules run for one airspace before the next one, so
/// the shape is built once per airspace.
GeometryShape shapeOf(LintContext ctx, Airspace airspace) {
  final cache = _cacheOf(ctx);
  final cached = cache.shape;
  if (cached != null && identical(airspace, cache.shapeAirspace)) {
    return cached;
  }
  final shape = _buildShape(ctx, airspace);
  cache.shapeAirspace = airspace;
  cache.shape = shape;
  return shape;
}

GeometryShape _buildShape(LintContext ctx, Airspace airspace) {
  final points = <LatLng>[];
  final sources = <Command>[];
  final commands = <Command>[];
  var complete = true;
  LatLng? centre;
  var clockwise = true;

  void add(Iterable<LatLng> ps, Command c) {
    for (final p in ps) {
      points.add(p);
      sources.add(c);
    }
  }

  for (final c in airspace.commands) {
    final k = c.upperKeyword;
    if (k == 'V') {
      final v = parseVariable(c);
      switch (v.upperName) {
        case 'X':
          final coords = coordinatesOf(ctx, c, airspace);
          centre = coords.isEmpty ? null : coords.first.position;
        case 'D':
          if (v.value == '+') clockwise = true;
          if (v.value == '-') clockwise = false;
      }
      continue;
    }
    if (!shapeKeywords.contains(k)) continue;
    commands.add(c);
    switch (k) {
      case 'DP':
      case 'DY':
        final p = coordinatesOf(ctx, c, airspace).first.position;
        if (p == null) {
          complete = false;
        } else {
          add([p], c);
        }
      case 'DA':
        final v = daValues(c.argument);
        if (centre == null || !daIsUsable(v)) {
          complete = false;
        } else {
          add(arcByBearings(centre, v![0], v[1], v[2], clockwise: clockwise),
              c);
        }
      case 'DB':
        final coords = coordinatesOf(ctx, c, airspace);
        final a = coords.length == 2 ? coords[0].position : null;
        final b = coords.length == 2 ? coords[1].position : null;
        if (centre == null || a == null || b == null) {
          complete = false;
        } else {
          add(arcByPoints(centre, a, b, clockwise: clockwise), c);
        }
      case 'DC':
        final r = parseDecimal(c.argument);
        if (centre == null || r == null || r <= 0) {
          complete = false;
        } else {
          add(circlePoints(centre, r), c);
        }
    }
  }
  return GeometryShape(
    points: points,
    sources: sources,
    commands: commands,
    complete: complete,
  );
}

/// The tolerance in degrees for "the same point" (about 10 cm).
const double samePointToleranceDeg = 1e-6;

/// A polygon without repeated points, ready for the shape checks.
class PolygonRing {
  PolygonRing(this.points, this.drawnBy, this.closingCommand,
      {required this.explicitlyClosed});

  /// The corners. Neighbour corners are different. The last corner is not
  /// the same as the first one (the ring is closed implicitly).
  final List<LatLng> points;

  /// For each corner `i`: the command that draws the edge from corner `i-1`
  /// to corner `i`. For corner 0 this is the first command.
  final List<Command> drawnBy;

  /// The command that draws the closing edge (from the last corner back to
  /// the first). This is the last geometry command of the airspace.
  final Command closingCommand;

  /// True if the last point of the boundary is the same as the first point.
  /// Then [closingCommand] draws a real edge. Otherwise readers add the
  /// closing edge.
  final bool explicitlyClosed;

  int get length => points.length;

  /// The command that draws edge [i] (from corner `i` to corner `i+1`).
  Command edgeCommand(int i) =>
      i + 1 < points.length ? drawnBy[i + 1] : closingCommand;
}

/// Builds a [PolygonRing] from a shape: removes repeated neighbour points
/// and the closing point.
PolygonRing ringOf(GeometryShape shape) {
  final pts = <LatLng>[];
  final drawn = <Command>[];
  for (var i = 0; i < shape.points.length; i++) {
    final p = shape.points[i];
    if (pts.isNotEmpty &&
        pts.last.closeTo(p, toleranceDeg: samePointToleranceDeg)) {
      continue;
    }
    pts.add(p);
    drawn.add(shape.sources[i]);
  }
  var closed = false;
  while (pts.length > 1 &&
      pts.last.closeTo(pts.first, toleranceDeg: samePointToleranceDeg)) {
    pts.removeLast();
    drawn.removeLast();
    closed = true;
  }
  return PolygonRing(pts, drawn, shape.sources.last, explicitlyClosed: closed);
}

/// The number of different points in [points] (compared with
/// [samePointToleranceDeg], rounded to a grid).
int distinctPointCount(List<LatLng> points) {
  const scale = 1 / samePointToleranceDeg;
  final keys = <(int, int)>{};
  for (final p in points) {
    keys.add(((p.lat * scale).round(), (p.lon * scale).round()));
  }
  return keys.length;
}

/// True if the ring [points] goes around a pole: the unwrapped longitudes
/// change by about 360 degrees from the first point, around the ring and
/// back to the first point.
///
/// In the plane of longitude and latitude, such a ring is not closed. So
/// the checks for "all points on one line" and for the direction do not
/// work for it.
bool encirclesPole(List<LatLng> points) {
  if (points.length < 3) return false;
  var x = points.first.lon;
  for (var i = 1; i < points.length; i++) {
    x += normalizeLongitude(points[i].lon - points[i - 1].lon);
  }
  x += normalizeLongitude(points.first.lon - points.last.lon);
  return (x - points.first.lon).abs() > 180;
}

/// True if all [points] are on one straight line (in latitude and
/// unwrapped longitude), within about 1 cm. Also true for fewer than 3
/// points.
///
/// A ring around a pole (see [encirclesPole]) can have all points on one
/// latitude and still have an area. The caller must check that first.
///
/// This is not the same as "the signed area is 0": a symmetric bow tie has
/// a signed area of 0, but its points are not on one line.
bool allOnOneLine(List<LatLng> points) {
  if (points.length < 3) return true;
  final x0 = points.first.lon;
  final y0 = points.first.lat;
  double dx(LatLng p) => normalizeLongitude(p.lon - x0);
  // The point farthest from the first point gives the direction.
  var far = points.first;
  var farD = 0.0;
  for (final p in points) {
    final d = dx(p) * dx(p) + (p.lat - y0) * (p.lat - y0);
    if (d > farD) {
      farD = d;
      far = p;
    }
  }
  if (farD == 0) return true;
  final len = math.sqrt(farD);
  final ux = dx(far) / len;
  final uy = (far.lat - y0) / len;
  for (final p in points) {
    final dist = (dx(p) * uy - (p.lat - y0) * ux).abs();
    if (dist > 1e-7) return false;
  }
  return true;
}

/// Two edges of a ring that cross each other.
class EdgeCrossing {
  const EdgeCrossing(this.first, this.second, this.point, {this.corners});

  /// The edge with the smaller index. For a crossing at a corner (see
  /// [corners]), the edge that ends at the first corner.
  final int first;

  /// The edge with the larger index. For a crossing at a corner, the edge
  /// that ends at the second corner.
  final int second;

  /// The approximate crossing point.
  final LatLng point;

  /// For a crossing at a point that the boundary passes twice: the two
  /// corners (i < j) at this point. Null for a crossing inside two edges.
  final (int, int)? corners;
}

/// The result of [findCrossings].
class CrossingResult {
  const CrossingResult(this.count, this.first, this.limitReached);

  /// The number of crossings found (at most the limit).
  final int count;

  /// The crossing whose second edge comes first in drawing order, or null.
  final EdgeCrossing? first;

  /// True if the search stopped early (at the crossing limit or at the work
  /// limit). There can be more crossings.
  final bool limitReached;
}

class _Edge {
  _Edge(this.index, this.x1, this.y1, this.x2, this.y2, {required bool sweepX})
      : sweepMin = sweepX ? math.min(x1, x2) : math.min(y1, y2),
        sweepMax = sweepX ? math.max(x1, x2) : math.max(y1, y2),
        otherMin = sweepX ? math.min(y1, y2) : math.min(x1, x2),
        otherMax = sweepX ? math.max(y1, y2) : math.max(x1, x2);
  final int index;
  final double x1, y1, x2, y2;

  /// The range of the edge on the sweep axis.
  final double sweepMin, sweepMax;

  /// The range of the edge on the other axis.
  final double otherMin, otherMax;
}

/// Crossings that make a loop thinner than this (in metres, on average) are
/// not reported. See [findCrossings].
const double minLoopWidthMetres = 25;

/// Finds the places where the edges of [ring] cross each other.
///
/// It uses a sweep along the longer side of the ring (longitude or
/// latitude): the edges are sorted by their start on that axis, and each
/// edge is only compared with the edges whose range on that axis overlaps.
/// This is fast for real airspaces, also with thousands of points.
///
/// For unusual input the number of compared edge pairs can still grow with
/// the square of the point count. The work is the number of compared edge
/// pairs plus the corners of all loops whose width is calculated. The
/// search stops when the work is more than [workLimit].
/// Then the result has the crossings found so far and [CrossingResult.limitReached]
/// is true. This keeps the time short on the web page and in other hosts.
///
/// Only real crossings count: the boundary goes from one side of itself to
/// the other side. There are two kinds:
///
/// - Two edges cross each other at one point that is inside both edges.
/// - The boundary passes the same corner twice, and the second pass goes
///   from one side of the first pass to the other side. See
///   [_cornerCrossings].
///
/// The boundary can touch itself. Edges that only touch, neighbour edges,
/// collinear edges that overlap (for example a line that is drawn twice,
/// once in each direction) and a corner that the boundary passes twice
/// without crossing do not count. Longitudes are unwrapped, so rings across
/// the antimeridian work.
///
/// A crossing cuts a loop out of the boundary. If the smaller loop is very
/// thin (its average width, 2 x area / perimeter, is less than
/// [minLoopWidthMetres]), the crossing is not counted. Such slivers come
/// from rounded coordinates, from an arc that touches a straight edge, and
/// from arcs drawn as many short edges. They are not visible on a map.
CrossingResult findCrossings(PolygonRing ring,
    {int limit = 1000, int workLimit = 20000000}) {
  final n = ring.length;
  if (n < 4) return const CrossingResult(0, null, false);
  final xs = List<double>.filled(n, 0);
  final ys = List<double>.filled(n, 0);
  xs[0] = ring.points[0].lon;
  ys[0] = ring.points[0].lat;
  for (var i = 1; i < n; i++) {
    xs[i] = xs[i - 1] +
        normalizeLongitude(ring.points[i].lon - ring.points[i - 1].lon);
    ys[i] = ring.points[i].lat;
  }
  // The closing edge uses the unwrapped first point.
  final closeX = xs[n - 1] +
      normalizeLongitude(ring.points[0].lon - ring.points[n - 1].lon);
  // Unwrapping can move the closing point by 360 degrees for rings around
  // a pole. Then the closing edge is not useful; skip such rings.
  if ((closeX - xs[0]).abs() > 180) {
    return const CrossingResult(0, null, false);
  }
  // Sweep along the axis where the ring is longer. Then fewer edges overlap
  // on the sweep axis, for example in a long and narrow ring.
  var minX = xs[0], maxX = xs[0], minY = ys[0], maxY = ys[0];
  for (var i = 1; i < n; i++) {
    minX = math.min(minX, xs[i]);
    maxX = math.max(maxX, xs[i]);
    minY = math.min(minY, ys[i]);
    maxY = math.max(maxY, ys[i]);
  }
  final sweepX = maxX - minX >= maxY - minY;
  final edges = <_Edge>[
    for (var i = 0; i < n; i++)
      _Edge(i, xs[i], ys[i], i + 1 < n ? xs[i + 1] : closeX,
          i + 1 < n ? ys[i + 1] : ys[0],
          sweepX: sweepX),
  ];
  final sorted = [...edges]..sort((a, b) => a.sweepMin.compareTo(b.sweepMin));
  final active = <_Edge>[];
  var count = 0;
  var work = 0;
  EdgeCrossing? best;
  for (final e in sorted) {
    active.removeWhere((a) => a.sweepMax < e.sweepMin);
    work += active.length;
    if (work > workLimit) return CrossingResult(count, best, true);
    for (final a in active) {
      if (a.otherMax < e.otherMin || a.otherMin > e.otherMax) continue;
      final i = math.min(a.index, e.index);
      final j = math.max(a.index, e.index);
      if (j - i == 1 || (i == 0 && j == n - 1)) continue; // neighbours
      final p = _properCrossing(a, e);
      if (p == null) continue;
      // The loop width needs one step for each corner of the smaller loop.
      // Count these steps as work too, so that a ring with many thin
      // crossings also stops at the work limit.
      work += math.min(j - i, n - (j - i));
      if (work > workLimit) return CrossingResult(count, best, true);
      if (_loopWidthMetres(xs, ys, i, j, p) < minLoopWidthMetres) continue;
      count++;
      if (best == null ||
          j < best.second ||
          (j == best.second && i < best.first)) {
        best = EdgeCrossing(i, j, LatLng(p.$2, normalizeLongitude(p.$1)));
      }
      if (count >= limit) return CrossingResult(count, best, true);
    }
    active.add(e);
  }
  for (final c in _cornerCrossings(ring, xs, ys)) {
    work += c.loopCorners;
    if (work > workLimit) return CrossingResult(count, best, true);
    if (_loopWidthMetres(xs, ys, c.i - 1, c.j - 1, (xs[c.i], ys[c.i])) <
        minLoopWidthMetres) {
      continue;
    }
    count++;
    final second = c.j - 1;
    final first = c.i == 0 ? n - 1 : c.i - 1;
    if (best == null ||
        second < best.second ||
        (second == best.second && first < best.first)) {
      best = EdgeCrossing(first, second, ring.points[c.i], corners: (c.i, c.j));
    }
    if (count >= limit) return CrossingResult(count, best, true);
  }
  return CrossingResult(count, best, false);
}

/// Two corners `i < j` of a ring at the same point, where the boundary
/// crosses itself. [loopCorners] is the number of corners of the smaller
/// loop between the two passes.
typedef _CornerCrossing = ({int i, int j, int loopCorners});

/// The crossings at points that the ring passes more than once.
///
/// At such a point, each pass has an incoming and an outgoing direction.
/// The two directions of the first pass divide the area around the point
/// into two sides. The second pass crosses the first pass if it comes from
/// one side and goes to the other side.
///
/// If two of the four directions are the same, the two passes share an
/// edge. This is how a ring-shaped airspace is drawn: the connecting line
/// is used twice. The boundary touches itself there, so it is not a
/// crossing.
///
/// [xs] are the unwrapped longitudes and [ys] the latitudes of the corners.
List<_CornerCrossing> _cornerCrossings(
    PolygonRing ring, List<double> xs, List<double> ys) {
  final n = ring.length;
  const scale = 1 / samePointToleranceDeg;
  final byPoint = <(int, int), List<int>>{};
  var repeated = false;
  for (var k = 0; k < n; k++) {
    final p = ring.points[k];
    final key =
        ((p.lat * scale).round(), (normalizeLongitude(p.lon) * scale).round());
    final list = byPoint.putIfAbsent(key, () => <int>[])..add(k);
    if (list.length > 1) repeated = true;
  }
  if (!repeated) return const [];
  // The direction from corner [k] to corner [m], as an angle.
  double direction(int k, int m) =>
      math.atan2(ys[m] - ys[k], normalizeLongitude(xs[m] - xs[k]));
  const twoPi = 2 * math.pi;
  double turn(double from, double to) {
    final d = (to - from) % twoPi;
    return d < 0 ? d + twoPi : d;
  }

  bool same(double a, double b) {
    final d = turn(a, b);
    return d < 1e-9 || twoPi - d < 1e-9;
  }

  final result = <_CornerCrossing>[];
  for (final corners in byPoint.values) {
    // A point that the boundary passes very often is not normal input.
    // Check only the first passes, so the time stays short.
    if (corners.length < 2) continue;
    if (corners.length > 16) corners.length = 16;
    for (var x = 0; x < corners.length; x++) {
      for (var y = x + 1; y < corners.length; y++) {
        final i = corners[x];
        final j = corners[y];
        if (j - i == 1 || (i == 0 && j == n - 1)) continue; // neighbours
        final in1 = direction(i, (i - 1 + n) % n);
        final out1 = direction(i, (i + 1) % n);
        final in2 = direction(j, j - 1);
        final out2 = direction(j, (j + 1) % n);
        final all = [in1, out1, in2, out2];
        var shared = false;
        for (var a = 0; a < 4 && !shared; a++) {
          for (var b = a + 1; b < 4; b++) {
            if (same(all[a], all[b])) {
              shared = true;
              break;
            }
          }
        }
        if (shared) continue;
        // The side of each direction of the second pass: is it in the turn
        // from in1 to out1?
        final width = turn(in1, out1);
        final side2In = turn(in1, in2) < width;
        final side2Out = turn(in1, out2) < width;
        if (side2In == side2Out) continue; // The passes touch.
        result.add((i: i, j: j, loopCorners: math.min(j - i, n - (j - i))));
      }
    }
  }
  return result;
}

/// The average width in metres (2 x area / perimeter) of the smaller loop
/// that the crossing of edges [i] and [j] (i < j) cuts out of the ring.
///
/// [xs] are unwrapped longitudes and [ys] latitudes of the corners. [p] is
/// the crossing point (x, y). The loop with fewer corners is used: either
/// the corners i+1 to j, or the corners j+1 to i (around the end).
double _loopWidthMetres(
    List<double> xs, List<double> ys, int i, int j, (double, double) p) {
  final n = xs.length;
  final inner = j - i;
  final corners = <int>[
    if (inner <= n - inner)
      for (var k = i + 1; k <= j; k++) k
    else
      for (var k = 1; k <= n - inner; k++) (j + k) % n,
  ];
  // Local projection in metres around the crossing point. For the corners
  // after the end of the ring, the unwrapped longitude of the closing edge
  // is the same within 360 degrees; normalize the difference.
  const mPerDeg = 60 * 1852.0;
  final kx = mPerDeg * math.cos(p.$2 * math.pi / 180);
  double px(int k) => normalizeLongitude(xs[k] - p.$1) * kx;
  double py(int k) => (ys[k] - p.$2) * mPerDeg;
  var area2 = 0.0;
  var perimeter = 0.0;
  var lx = 0.0, ly = 0.0; // The crossing point is (0, 0).
  for (final k in corners) {
    final x = px(k), y = py(k);
    area2 += lx * y - x * ly;
    perimeter += math.sqrt((x - lx) * (x - lx) + (y - ly) * (y - ly));
    lx = x;
    ly = y;
  }
  area2 += lx * 0 - 0 * ly;
  perimeter += math.sqrt(lx * lx + ly * ly);
  if (perimeter == 0) return 0;
  return area2.abs() / perimeter;
}

/// The crossing point (x, y) of two edges, or null if they do not cross
/// properly.
(double, double)? _properCrossing(_Edge a, _Edge b) {
  final o1 = _orient(a.x1, a.y1, a.x2, a.y2, b.x1, b.y1);
  final o2 = _orient(a.x1, a.y1, a.x2, a.y2, b.x2, b.y2);
  final epsA = _len(a) * 1e-9;
  if (o1.abs() <= epsA || o2.abs() <= epsA || (o1 > 0) == (o2 > 0)) {
    return null;
  }
  final o3 = _orient(b.x1, b.y1, b.x2, b.y2, a.x1, a.y1);
  final o4 = _orient(b.x1, b.y1, b.x2, b.y2, a.x2, a.y2);
  final epsB = _len(b) * 1e-9;
  if (o3.abs() <= epsB || o4.abs() <= epsB || (o3 > 0) == (o4 > 0)) {
    return null;
  }
  final t = o3 / (o3 - o4);
  return (a.x1 + t * (a.x2 - a.x1), a.y1 + t * (a.y2 - a.y1));
}

double _orient(
        double ax, double ay, double bx, double by, double cx, double cy) =>
    (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);

double _len(_Edge e) {
  final dx = e.x2 - e.x1;
  final dy = e.y2 - e.y1;
  return math.sqrt(dx * dx + dy * dy);
}

/// Formats a distance in nautical miles for messages, for example `0.25 NM`
/// or `12.3 NM`.
String formatNm(double nm) {
  if (nm >= 10) return '${nm.toStringAsFixed(1)} NM';
  if (nm >= 0.1) return '${nm.toStringAsFixed(2)} NM';
  return '${nm.toStringAsFixed(3)} NM';
}

/// Formats a distance in nautical miles and metres, for example
/// `0.054 NM (100 m)`.
String formatNmAndMetres(double nm) =>
    '${formatNm(nm)} (${(nm * 1852).round()} m)';

/// The distance between two points in nautical miles.
double distanceBetween(LatLng a, LatLng b) => distanceNm(a, b);
