import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

Airspace airspaceOf(String body) =>
    parseOpenAir('AC D\n$body').airspaces.single;

void main() {
  group('great circle', () {
    test('one degree of latitude is 60 NM (about)', () {
      final d = distanceNm(const LatLng(45, 14), const LatLng(46, 14));
      expect(d, closeTo(60.04, 0.05));
    });

    test('distance is 0 for the same point', () {
      expect(distanceNm(const LatLng(1, 2), const LatLng(1, 2)), 0);
    });

    test('bearing east and north', () {
      expect(initialBearing(const LatLng(0, 0), const LatLng(0, 1)),
          closeTo(90, 1e-9));
      expect(initialBearing(const LatLng(0, 0), const LatLng(1, 0)),
          closeTo(0, 1e-9));
      expect(initialBearing(const LatLng(0, 0), const LatLng(0, -1)),
          closeTo(270, 1e-9));
    });

    test('destination point is the inverse of distance and bearing', () {
      const a = LatLng(46.2, 14.5);
      final b = destinationPoint(a, 123, 25);
      expect(distanceNm(a, b), closeTo(25, 1e-9));
      expect(initialBearing(a, b), closeTo(123, 1e-9));
    });

    test('destination point across the antimeridian', () {
      final b = destinationPoint(const LatLng(0, 179.9), 90, 30);
      expect(b.lon, lessThan(-179));
    });

    test('normalize', () {
      expect(normalizeBearing(-90), 270);
      expect(normalizeBearing(360), 0);
      expect(normalizeLongitude(190), -170);
      expect(normalizeLongitude(-180), -180);
    });
  });

  group('arcs', () {
    const c = LatLng(46, 14);

    test('arcSweep', () {
      expect(arcSweep(270, 290), 20);
      expect(arcSweep(320, 200), 240);
      expect(arcSweep(270, 290, clockwise: false), 340);
      expect(arcSweep(200, 270, clockwise: false), 290);
      expect(arcSweep(90, 90), 0);
      expect(arcSweep(0, 360), 360);
    });

    test('arcByBearings has start and end points on the radius', () {
      final pts = arcByBearings(c, 10, 270, 290);
      expect(pts.length, greaterThanOrEqualTo(3));
      for (final p in pts) {
        expect(distanceNm(c, p), closeTo(10, 1e-6));
      }
      expect(initialBearing(c, pts.first), closeTo(270, 1e-6));
      expect(initialBearing(c, pts.last), closeTo(290, 1e-6));
      // Clockwise: the bearings grow.
      expect(initialBearing(c, pts[1]), greaterThan(270));
    });

    test('arcByBearings counterclockwise', () {
      final pts = arcByBearings(c, 5, 200, 270, clockwise: false);
      expect(initialBearing(c, pts[1]), lessThan(200));
      expect(initialBearing(c, pts.last), closeTo(270, 1e-6));
    });

    test('arcByPoints ends exactly at the given points', () {
      final from = destinationPoint(c, 10, 8);
      final to = destinationPoint(c, 80, 8.1);
      final pts = arcByPoints(c, from, to);
      expect(pts.first, from);
      expect(pts.last, to);
      expect(pts.length, greaterThan(10));
    });

    test('circlePoints is closed', () {
      final pts = circlePoints(c, 2);
      expect(pts.first, pts.last);
      expect(isClockwise(pts), isTrue);
    });
  });

  group('bounds and centre', () {
    test('simple box', () {
      final b = GeoBounds.of(const [
        LatLng(45, 14),
        LatLng(46, 15),
        LatLng(45.5, 14.2),
      ])!;
      expect((b.south, b.north, b.west, b.east), (45, 46, 14, 15));
      expect(b.centre, const LatLng(45.5, 14.5));
      expect(b.crossesAntimeridian, isFalse);
    });

    test('across the antimeridian', () {
      final b = GeoBounds.of(const [
        LatLng(-40, 179),
        LatLng(-41, -179),
        LatLng(-40.5, 179.5),
      ])!;
      expect(b.west, 179);
      expect(b.east, -179);
      expect(b.widthDeg, closeTo(2, 1e-9));
      expect(b.crossesAntimeridian, isTrue);
      expect(b.centre.lat, -40.5);
      expect(b.centre.lon.abs(), closeTo(180, 1e-9));
    });

    test('empty list', () {
      expect(GeoBounds.of(const []), isNull);
    });
  });

  group('orientation', () {
    test('clockwise and counterclockwise', () {
      const cw = [
        LatLng(46, 14),
        LatLng(46, 15),
        LatLng(45, 15),
        LatLng(45, 14)
      ];
      expect(isClockwise(cw), isTrue);
      expect(isClockwise(cw.reversed.toList()), isFalse);
      expect(isClockwise([...cw, cw.first]), isTrue);
    });

    test('degenerate', () {
      expect(isClockwise(const [LatLng(0, 0), LatLng(1, 1)]), isNull);
      expect(isClockwise(const [LatLng(0, 0), LatLng(1, 1), LatLng(2, 2)]),
          isNull);
    });

    test('across the antimeridian', () {
      const cw = [
        LatLng(-40, 179),
        LatLng(-40, -179),
        LatLng(-41, -179),
        LatLng(-41, 179),
      ];
      expect(isClockwise(cw), isTrue);
    });
  });

  group('buildBoundary', () {
    test('DP polygon', () {
      final b = buildBoundary(airspaceOf('AH FL100\n'
          'DP 46:00:00N 014:00:00E\n'
          'DP 46:00:00N 014:10:00E\n'
          'DP 45:55:00N 014:10:00E\n'
          'DP 46:00:00N 014:00:00E\n'));
      expect(b.points, hasLength(4));
      expect(b.unusedCommands, isEmpty);
      expect(b.centre!.lat, closeTo(45 + 57.5 / 60, 1e-9));
      expect(b.centre!.lon, closeTo(14 + 5 / 60, 1e-9));
    });

    test('DC circle around V X', () {
      final b =
          buildBoundary(airspaceOf('V X=50:35:36N 007:56:42E\nDC 2.00\n'));
      expect(b.hasCircle, isTrue);
      final centre = parseCoordinate('50:35:36N 007:56:42E').value!;
      expect(distanceNm(b.centre!, centre), lessThan(0.05));
    });

    test('DA and DB use V X and V D', () {
      final b = buildBoundary(airspaceOf('V X=39:29.9N 119:46.1W\n'
          'DA 10,270,290\n'
          'V D=-\n'
          'DA 5,200,270\n'
          'DB 39:36:40N 119:46:10W, 39:29:09N 119:36:10W\n'));
      expect(b.unusedCommands, isEmpty);
      expect(b.points.length, greaterThan(20));
    });

    test('arcs without a centre and bad values are unused', () {
      final b = buildBoundary(airspaceOf('DA 10,270,290\n'
          'DC 5\n'
          'V X=bad\n'
          'DP 45:00:00 014:00:00E\n'
          'V D=?\n'
          'V Q=1\n'
          'V X=45:00:00N 014:00:00E\n'
          'DC -1\n'
          'DA 10,abc,290\n'
          'DB 45:00:00N 014:00:00E\n'));
      expect(
          b.unusedCommands.map((c) => c.line), [2, 3, 4, 5, 6, 7, 9, 10, 11]);
      expect(b.isEmpty, isTrue);
      expect(b.centre, isNull);
    });

    test('LintContext.boundaryOf is computed once', () {
      final rule = Rule(
        id: 'test-boundary',
        severity: Severity.info,
        specAnchor: 'dp-polygon-point',
        description: 'd',
        explanation: 'e',
        correctExample: 'c',
        incorrectExample: 'i',
        checkAirspace: (ctx, a) {
          final b1 = ctx.boundaryOf(a);
          final b2 = ctx.boundaryOf(a);
          ctx.reportAirspace(a, identical(b1, b2) ? 'same' : 'different');
        },
      );
      final d = Linter(LintOptions(rules: [rule]))
          .lintString('AC D\nDP 45:00:00N 014:00:00E\n')
          .diagnostics;
      expect(d.single.message, 'same');
    });
  });
}
