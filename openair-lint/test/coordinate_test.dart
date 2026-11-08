import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

List<CoordinateIssueKind> kinds(String text) =>
    parseCoordinate(text).issues.map((i) => i.kind).toList();

void main() {
  group('clean coordinates', () {
    test('DMS', () {
      final r = parseCoordinate('45:40:30N 014:18:20E');
      expect(r.isClean, isTrue);
      expect(r.notation, CoordinateNotation.dms);
      expect(r.value!.lat, closeTo(45 + 40 / 60 + 30 / 3600, 1e-12));
      expect(r.value!.lon, closeTo(14 + 18 / 60 + 20 / 3600, 1e-12));
      expect(r.end, 20);
    });

    test('DDM', () {
      final r = parseCoordinate('45:40.500N 014:18.333E');
      expect(r.isClean, isTrue);
      expect(r.notation, CoordinateNotation.ddm);
      expect(r.value!.lat, closeTo(45.675, 1e-12));
    });

    test('DDM with fewer decimals is clean (spec example 39:29.9N)', () {
      expect(parseCoordinate('39:29.9N 119:46.1W').isClean, isTrue);
    });

    test('south and west are negative', () {
      final r = parseCoordinate('33:56:00S 151:10:00W');
      expect(r.value!.lat, lessThan(0));
      expect(r.value!.lon, lessThan(0));
    });

    test('spaces at the start and the end are ignored', () {
      expect(parseCoordinate('  45:40:30N 014:18:20E  ').isClean, isTrue);
    });

    test('limits 90 and 180 are allowed', () {
      expect(parseCoordinate('90:00:00N 180:00:00W').isClean, isTrue);
    });
  });

  group('deviations (value is still computed)', () {
    test('one space before the hemisphere letter is valid', () {
      final r = parseCoordinate('45:40:30 N 014:18:20 E');
      expect(r.isClean, isTrue);
      expect(r.value, parseCoordinate('45:40:30N 014:18:20E').value);
      expect(parseCoordinate('45:40.500 N 014:18.333E').isClean, isTrue);
      expect(parseCoordinate('33:56:00 S 151:10:00 W').value!.lon, lessThan(0));
    });

    test('two blanks or a tab before the hemisphere letter', () {
      final r = parseCoordinate('45:40:30  N 014:18:20\tE');
      expect(r.isValid, isTrue);
      expect(r.issues.map((i) => (i.kind, i.offset, i.length)), [
        (CoordinateIssueKind.extraSpaceBeforeHemisphere, 8, 2),
        (CoordinateIssueKind.extraSpaceBeforeHemisphere, 21, 1),
      ]);
      expect(r.issues.first.part, CoordinatePart.latitude);
      expect(r.issues.last.part, CoordinatePart.longitude);
    });

    test('lower case hemisphere', () {
      final r = parseCoordinate('45:40:30n 014:18:20e');
      expect(r.value!.lat, greaterThan(0));
      expect(kinds('45:40:30n 014:18:20e'), [
        CoordinateIssueKind.lowerCaseHemisphere,
        CoordinateIssueKind.lowerCaseHemisphere,
      ]);
      expect(r.issues.first.offset, 8);
    });

    test('missing leading zeros', () {
      final r = parseCoordinate('45:4:30N 14:18:20E');
      expect(r.isValid, isTrue);
      expect(r.issues.map((i) => (i.kind, i.offset)), [
        (CoordinateIssueKind.missingLeadingZero, 3),
        (CoordinateIssueKind.missingLeadingZero, 9),
      ]);
    });

    test('too many digits', () {
      expect(
          kinds('045:40:30N 014:18:20E'), [CoordinateIssueKind.tooManyDigits]);
    });

    test('decimal seconds', () {
      final r = parseCoordinate('45:40:30.5N 014:18:20E');
      expect(r.value!.lat, closeTo(45 + 40 / 60 + 30.5 / 3600, 1e-12));
      expect(r.notation, CoordinateNotation.dms);
      expect(r.issues.single.kind, CoordinateIssueKind.decimalSeconds);
      expect(r.issues.single.offset, 6);
      expect(r.issues.single.length, 4);
    });

    test('seconds with a trailing dot', () {
      expect(kinds('45:40:30.N 014:18:20.W'), [
        CoordinateIssueKind.decimalSeconds,
        CoordinateIssueKind.decimalSeconds,
      ]);
    });

    test('decimal degrees', () {
      final r = parseCoordinate('45.675N 014.305E');
      expect(r.notation, CoordinateNotation.decimalDegrees);
      expect(r.value!.lat, closeTo(45.675, 1e-12));
      expect(r.issues.map((i) => i.kind), [
        CoordinateIssueKind.decimalDegrees,
        CoordinateIssueKind.decimalDegrees,
      ]);
    });

    test('missing space between latitude and longitude', () {
      final r = parseCoordinate('45:40:30N014:18:20E');
      expect(r.isValid, isTrue);
      expect(r.issues.single.kind, CoordinateIssueKind.missingSpace);
      expect(r.issues.single.offset, 9);
    });

    test('more than one space', () {
      final r = parseCoordinate('45:40:30N  014:18:20E');
      expect(r.issues.single.kind, CoordinateIssueKind.extraSpace);
      expect(r.issues.single.length, 2);
      expect(kinds('45:40:30N\t014:18:20E'), [CoordinateIssueKind.extraSpace]);
    });

    test('mixed notation', () {
      final r = parseCoordinate('45:40:30N 014:18.333E');
      expect(r.notation, isNull);
      expect(r.latitudeNotation, CoordinateNotation.dms);
      expect(r.longitudeNotation, CoordinateNotation.ddm);
      expect(
          kinds('45:40:30N 014:18.333E'), [CoordinateIssueKind.mixedNotation]);
    });

    test('trailing text', () {
      final r = parseCoordinate('45:40:30N 014:18:20E XY');
      expect(r.isValid, isTrue);
      expect(r.end, 20);
      final i = r.issues.single;
      expect(i.kind, CoordinateIssueKind.trailingText);
      expect((i.offset, i.length), (21, 2));
    });

    test('a typical messy corpus line', () {
      expect(kinds('45:40:30.5  n 14:18:20E'), [
        CoordinateIssueKind.decimalSeconds,
        CoordinateIssueKind.extraSpaceBeforeHemisphere,
        CoordinateIssueKind.lowerCaseHemisphere,
        CoordinateIssueKind.missingLeadingZero,
      ]);
    });
  });

  group('fatal problems (no value)', () {
    void fatal(String text, CoordinateIssueKind kind) {
      final r = parseCoordinate(text);
      expect(r.value, isNull, reason: text);
      expect(r.issues.map((i) => i.kind), contains(kind), reason: text);
    }

    test('empty text', () => fatal('', CoordinateIssueKind.syntax));
    test('no longitude', () => fatal('45:40:30N', CoordinateIssueKind.syntax));
    test('garbage', () => fatal('hello', CoordinateIssueKind.syntax));
    test('empty number',
        () => fatal('45::30N 014:18:20E', CoordinateIssueKind.syntax));
    test('too many parts',
        () => fatal('43:46:32N 018:018:09:07E', CoordinateIssueKind.syntax));
    test('decimals in degrees with minutes',
        () => fatal('45.5:30N 014:18:20E', CoordinateIssueKind.syntax));
    test(
        'missing hemisphere',
        () => fatal(
            '45:40:30 014:18:20E', CoordinateIssueKind.missingHemisphere));
    test(
        'missing longitude hemisphere',
        () => fatal(
            '45:40:30N 014:18:20', CoordinateIssueKind.missingHemisphere));
    test(
        'wrong hemisphere',
        () =>
            fatal('45:40:30E 014:18:20N', CoordinateIssueKind.wrongHemisphere));
    test(
        'minutes 60',
        () => fatal(
            '45:60:00N 014:18:20E', CoordinateIssueKind.minutesOutOfRange));
    test(
        'seconds 60',
        () => fatal(
            '41:08:60N 019:06:00E', CoordinateIssueKind.secondsOutOfRange));
    test(
        'latitude > 90',
        () => fatal(
            '91:00:00N 014:18:20E', CoordinateIssueKind.latitudeOutOfRange));
    test(
        'latitude 90 and 1 second',
        () => fatal(
            '90:00:01N 014:18:20E', CoordinateIssueKind.latitudeOutOfRange));
    test(
        'longitude > 180',
        () => fatal(
            '45:00:00N 181:00:00E', CoordinateIssueKind.longitudeOutOfRange));

    test('the offset points to the wrong part', () {
      final i = parseCoordinate('45:40:30N 014:61:20E')
          .issuesOf(CoordinateIssueKind.minutesOutOfRange)
          .single;
      expect((i.offset, i.length, i.part), (14, 2, CoordinatePart.longitude));
    });
  });

  group('formatCoordinate', () {
    test('DMS', () {
      expect(formatCoordinate(const LatLng(45.675, 14.30556)),
          '45:40:30N 014:18:20E');
      expect(
          formatCoordinate(const LatLng(-5.5, -0.25)), '05:30:00S 000:15:00W');
    });

    test('DDM', () {
      expect(
          formatCoordinate(
              const LatLng(45.675, 14.305555), CoordinateNotation.ddm),
          '45:40.500N 014:18.333E');
    });

    test('round trip', () {
      const text = '46:03:35N 014:10:25E';
      expect(formatCoordinate(parseCoordinate(text).value!), text);
    });
  });

  group('text helpers', () {
    test('splitParts keeps offsets', () {
      final parts = splitParts('10, 270,290', ',');
      expect(parts.map((p) => (p.text, p.offset)),
          [('10', 0), ('270', 4), ('290', 8)]);
    });

    test('splitParts with empty parts', () {
      expect(splitParts('a,,b', ',').map((p) => p.text), ['a', '', 'b']);
      expect(splitParts('', ',').single.text, '');
    });

    test('splitWords', () {
      expect(splitWords(' 1000  FT AMSL').map((p) => (p.text, p.offset)),
          [('1000', 1), ('FT', 7), ('AMSL', 10)]);
    });

    test('parseDecimal', () {
      expect(parseDecimal('10'), 10);
      expect(parseDecimal('2.5'), 2.5);
      expect(parseDecimal('.5'), 0.5);
      expect(parseDecimal('5.'), 5);
      expect(parseDecimal('-5'), isNull);
      expect(parseDecimal('-5', allowSign: true), -5);
      expect(parseDecimal('1e3'), isNull);
      expect(parseDecimal('1,5'), isNull);
      expect(parseDecimal(''), isNull);
      expect(parseDecimal('NaN'), isNull);
    });

    test('parseVariableText', () {
      final v = parseVariableText('X=45:40:30N 014:18:20E');
      expect(v.upperName, 'X');
      expect(v.value, '45:40:30N 014:18:20E');
      expect(v.valueOffset, 2);
      expect(v.isCompact, isTrue);
      final w = parseVariableText('x = -');
      expect(w.upperName, 'X');
      expect(w.value, '-');
      expect(w.valueOffset, 4);
      expect(w.isCompact, isFalse);
      final n = parseVariableText('D+');
      expect(n.hasEquals, isFalse);
    });
  });
}
