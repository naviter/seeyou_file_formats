// Tests for the rules in lib/src/rules/geometry_rules.dart.
//
// Conformance files for this group are in openair-conformance/valid/geometry/
// and openair-conformance/invalid/geometry/.

import 'package:openair_lint/openair_lint.dart';
import 'package:openair_lint/src/rules/geometry_rules_support.dart';
import 'package:test/test.dart';

import '../support/helpers.dart';

/// The IDs of all rules of the geometry group.
final Set<String> geometryIds = {
  for (final g in ruleGroups)
    if (g.name == 'geometry') ...g.rules.map((r) => r.id)
};

/// A file with one airspace. The geometry [lines] start at line 7.
String airspace(List<String> lines, {String version = '3.0'}) => withHeader(
    'AC D\n'
    'AN Test\n'
    'AH 4500 FT AMSL\n'
    'AL GND\n'
    '${lines.join('\n')}\n',
    version: version);

/// A closed, clockwise square (lines 7 to 11).
const List<String> square = [
  'DP 46:00:00N 014:00:00E',
  'DP 46:00:00N 014:10:00E',
  'DP 45:55:00N 014:10:00E',
  'DP 45:55:00N 014:00:00E',
  'DP 46:00:00N 014:00:00E',
];

/// The lines where rule [id] fires in a file with the geometry [lines].
List<int> at(String id, List<String> lines) => linesOf(id, airspace(lines));

/// The messages of rule [id] for the geometry [lines].
List<String> messages(String id, List<String> lines) =>
    [for (final d in lintRule(id, airspace(lines))) d.message];

void main() {
  test('a valid file has no geometry diagnostics', () {
    final text = withHeader('$validAirspace'
        'AC C\n'
        'AN Circle\n'
        'AH FL95\n'
        'AL 4500 FT AMSL\n'
        'V X=46:30:00N 014:30:00E\n'
        'DC 5\n'
        'AC C\n'
        'AN Arcs\n'
        'AH FL95\n'
        'AL 4500 FT AMSL\n'
        'DP 46:10:00N 014:00:00E\n'
        'V X=46:00:00N 014:00:00E\n'
        'DB 46:10:00N 014:00:00E, 46:00:00N 014:14:24E\n'
        'DP 46:00:00N 014:00:00E\n'
        'DP 46:10:00N 014:00:00E\n');
    final d = lintAll(text).where((d) => geometryIds.contains(d.ruleId));
    expect(d, isEmpty);
  });

  test('all rules apply to 2.1 and 3.0, except the rules with a 2.1 part', () {
    // Version 3.0 says "must" for the DB radius and for DC as the only
    // geometry. Version 2.1 does not, so 2.1 files get a warning.
    const versionRules = {
      'db-radius-mismatch': SpecVersion.only3,
      'db-radius-mismatch-v21': SpecVersion.only21,
      'dc-mixed-with-other-geometry': SpecVersion.only3,
      'dc-mixed-with-other-geometry-v21': SpecVersion.only21,
    };
    for (final g in ruleGroups.where((g) => g.name == 'geometry')) {
      for (final r in g.rules) {
        expect(r.versions, versionRules[r.id] ?? SpecVersion.all, reason: r.id);
      }
    }
  });

  test('a file of the 2.1 version is checked the same way', () {
    final text = airspace(
        ['DP 46:00:00N 014:00:00E', 'DP 91:00:00N 014:00:00E'],
        version: '2.1');
    expect(linesOf('coordinate-out-of-range', text), [8]);
  });

  // -------------------------------------------------------------------------
  // Coordinates
  // -------------------------------------------------------------------------

  group('coordinate-syntax', () {
    const id = 'coordinate-syntax';
    test('clean coordinates', () => expect(at(id, square), isEmpty));
    test('missing longitude', () {
      expect(at(id, ['DP 46:00:00N']), [7]);
    });
    test('empty DP and empty point in V X', () {
      expect(at(id, ['DP']), [7]);
      expect(messages(id, ['DP']).single, contains('The point is missing'));
    });
    test('too many parts, in DP, DB and V X', () {
      expect(
          at(id, [
            'DP 46:00:00:00N 014:00:00E',
            'V X=46::00N 014:00:00E',
            'DB 46:00:00N 014:00:00E, 46:00:00N',
          ]),
          [7, 8, 9]);
    });
    test('column points to the wrong part', () {
      final d = lintRule(id, airspace(['DP 46:00:00N 014:00:00:00E'])).single;
      expect(d.column, 'DP 46:00:00N '.length + 1);
    });
  });

  group('coordinate-hemisphere-invalid', () {
    const id = 'coordinate-hemisphere-invalid';
    test('valid', () => expect(at(id, square), isEmpty));
    test('missing letters', () {
      expect(at(id, ['DP 46:00:00 014:00:00']), [7, 7]);
    });
    test('wrong letters', () {
      expect(at(id, ['DP 46:00:00E 014:00:00N']), [7, 7]);
    });
    test('lower case is not reported here', () {
      expect(at(id, ['DP 46:00:00n 014:00:00e']), isEmpty);
    });
    test('an unknown letter gives one diagnostic, also from other rules', () {
      for (final line in [
        'DP 46:00:00Q 014:00:00E',
        'V X=46:00:00Q 014:00:00E',
      ]) {
        final d = lintAll(airspace([line]))
            .where((d) => geometryIds.contains(d.ruleId))
            .where((d) => d.line == 7 && d.severity != Severity.info)
            .toList();
        expect(d.map((d) => d.ruleId), [id], reason: line);
        expect(d.single.message, 'The latitude must end with N or S, not "Q".');
      }
    });
    test('an unknown letter at the end of the longitude', () {
      final d = lintAll(airspace(['DP 46:00:00N 014:00:00X']))
          .where((d) => geometryIds.contains(d.ruleId) && d.line == 7);
      expect(d.map((d) => d.ruleId), [id]);
      expect(d.single.message, 'The longitude must end with E or W, not "X".');
    });
    test('a word in place of the letter', () {
      expect(messages(id, ['DP 46:00:00N 014:00:00EAST']).single,
          'The longitude must end with one letter, E or W, not "EAST".');
    });
    test('two blanks after a missing letter are still reported', () {
      expect(
          linesOf('coordinate-space-between-parts',
              airspace(['DP 46:00:00  014:00:00E'])),
          [7]);
    });
    test('a missing letter keeps the plain message', () {
      expect(messages(id, ['DP 46:00:00 014:00:00E']).single,
          'The latitude needs the letter N or S.');
    });
  });

  group('coordinate-out-of-range', () {
    const id = 'coordinate-out-of-range';
    test('valid limits', () {
      expect(at(id, ['DP 90:00:00N 180:00:00W', 'DP 00:59:59S 000:00:00E']),
          isEmpty);
    });
    test('latitude, longitude, minutes and seconds', () {
      expect(
          at(id, [
            'DP 91:00:00N 014:00:00E',
            'DP 46:00:00N 181:00:00E',
            'DP 46:60:00N 014:00:00E',
            'DP 46:00:00N 014:00:61E',
          ]),
          [7, 8, 9, 10]);
    });
    test('a value of 60 is a typing error, with no suggested value', () {
      for (final line in [
        'DP 41:08:60 N 019:06:00 E',
        'DP 41:00:00N 019:06:60.0000E',
        'DP 45:60.000N 014:00.000E',
      ]) {
        final message = messages(id, [line]).single;
        expect(message, contains('This is probably a typing error.'));
        expect(message, contains('source data'));
        expect(message, isNot(contains('in place of')), reason: line);
      }
    });
    test('the shape rules still check a polygon with a 60', () {
      // An open bow tie. The last point is 014:10:00E, written with 60.
      final lines = [
        'DP 46:00:00N 014:00:00E',
        'DP 46:00:00N 014:10:00E',
        'DP 45:55:00N 014:00:00E',
        'DP 45:55:00N 014:09:60E',
      ];
      final d = lintAll(airspace(lines))
          .where((d) => geometryIds.contains(d.ruleId))
          .map((d) => '${d.line} ${d.ruleId}');
      expect(
          d,
          unorderedEquals([
            '10 coordinate-out-of-range',
            '10 geometry-polygon-not-closed',
            '10 geometry-polygon-self-intersection',
          ]));
    });
  });

  group('carriedPosition', () {
    LatLng? carried(String text) =>
        carriedPosition(text, parseCoordinate(text));
    LatLng? value(String text) => parseCoordinate(text).value;
    void same(String sixty, String clean) {
      final a = carried(sixty);
      expect(a, isNotNull, reason: sixty);
      expect(a!.closeTo(value(clean)!, toleranceDeg: 1e-9), isTrue,
          reason: '$sixty -> $clean');
    }

    test('a clean value is returned as it is', () {
      expect(carried('46:00:00N 014:00:00E'), value('46:00:00N 014:00:00E'));
    });
    test('seconds and minutes of 60 are carried', () {
      same('41:08:60N 019:06:00E', '41:09:00N 019:06:00E');
      same('41:59:60N 019:59:60E', '42:00:00N 020:00:00E');
      same('45:60.000N 014:00.000E', '46:00.000N 014:00.000E');
      same('89:59:60N 014:00:00E', '90:00:00N 014:00:00E');
    });
    test('south and west stay correct', () {
      same('33:51:60S 151:12:60W', '33:52:00S 151:13:00W');
      same('00:00:60S 000:00:60W', '00:01:00S 000:01:00W');
    });
    test('no value for other problems', () {
      expect(carried('41:08:61N 019:06:00E'), isNull);
      expect(carried('41:08:60.5N 019:06:00E'), isNull);
      expect(carried('41:08:60N 019:06:00'), isNull);
      expect(carried('90:00:60N 014:00:00E'), isNull);
      expect(carried('46:00:00N 180:00:60E'), isNull);
    });
  });

  group('coordinate-decimal-degrees', () {
    const id = 'coordinate-decimal-degrees';
    test('DMS and DDM are fine', () {
      expect(at(id, ['DP 46:00:00N 014:00:00E', 'DP 46:00.000N 014:00.000E']),
          isEmpty);
    });
    test('one diagnostic per command', () {
      final d = lintRule(id, airspace(['DP 46.5N 14.25E']));
      expect(d.map((d) => d.line), [7]);
      expect(d.single.column, 4);
      expect(d.single.endColumn, 'DP 46.5N 14.25'.length + 1);
      expect(
          d.single.message,
          'The coordinate uses decimal degrees. Use DMS (DD:MM:SS) or DDM '
          '(DD:MM.mmm). For example "46:30:00N 014:15:00E".');
    });
    test('whole degrees: the minutes are missing', () {
      expect(
          messages(id, ['DP 46N 014E']).single,
          'The coordinate has only degrees. The minutes are missing. Write '
          'DD:MM:SS or DD:MM.mmm. For example "46:00:00N 014:00:00E".');
      expect(messages(id, ['DP 46N 014:10:00E']).single,
          startsWith('The latitude has only degrees.'));
      expect(messages(id, ['DP 46:00:00N 014.5E']).single,
          startsWith('The longitude uses decimal degrees.'));
    });
  });

  group('coordinate-trailing-text', () {
    const id = 'coordinate-trailing-text';
    test('a comment is fine', () {
      expect(at(id, ['DP 46:00:00N 014:00:00E * river']), isEmpty);
    });
    test('text after the point', () {
      expect(at(id, ['DP 46:00:00N 014:00:00E river']), [7]);
    });
  });

  group('one space before the letter N, S, E or W', () {
    // The specification allows "45:40:30 N 014:18:20 E". It has the same
    // meaning as "45:40:30N 014:18:20E".
    const spaced = [
      'DP 46:00:00 N 014:00:00 E',
      'DP 46:00:00 N 014:10:00 E',
      'DP 45:55:00N 014:10:00 E',
      'DP 45:55:00 N 014:00:00E',
      'DP 46:00:00 N 014:00:00 E',
    ];
    // All diagnostics, also info, except the note that 3.0 is a draft.
    List<Diagnostic> all(List<String> lines) => [
          for (final d in lintAll(airspace(lines)))
            if (d.ruleId != 'header-version-draft') d
        ];
    test('no rule reports it', () {
      expect(all(spaced), isEmpty);
      expect(
          all([
            'V X=46:00:00 N 014:00:00 E',
            'DB 46:10:00 N 014:00:00 E, 46:00:00 N 014:14:24 E',
          ]),
          isEmpty);
      expect(all(['V X=46:00.000 N 014:00.000 E', 'DC 2']), isEmpty);
    });
    test('the rule coordinate-space-before-hemisphere does not exist', () {
      expect(findRule('coordinate-space-before-hemisphere'), isNull);
    });
    test('it is the same point as without the space', () {
      // The closing point has the space, the first point has none.
      expect(at('geometry-polygon-not-closed', [...square.take(4), spaced[0]]),
          isEmpty);
      expect(at('dp-duplicate-point', [square[0], spaced[0]]), [8]);
    });
  });

  group('coordinate-space-between-parts', () {
    const id = 'coordinate-space-between-parts';
    test('valid', () => expect(at(id, square), isEmpty));
    test('missing, double and tab', () {
      expect(
          at(id, [
            'DP 46:00:00N014:00:00E',
            'DP 46:00:00N  014:00:00E',
            'DP 46:00:00N\t014:00:00E',
          ]),
          [7, 8, 9]);
    });
    test('one space before the letter is fine', () {
      expect(at(id, ['DP 46:00:00 N 014:00:00 E']), isEmpty);
    });
    test('two blanks or a tab before the letter', () {
      expect(
          at(id, [
            'DP 46:00:00  N 014:00:00E',
            'DP 46:00:00N 014:00:00\tE',
          ]),
          [7, 8]);
      expect(
          messages(id, ['DP 46:00:00  N 014:00:00E']).single,
          'Write no space or one space between the latitude and its letter '
          '"N".');
    });
  });

  group('coordinate-digit-count', () {
    const id = 'coordinate-digit-count';
    test('valid', () => expect(at(id, square), isEmpty));
    test('missing leading zeros and too many digits', () {
      expect(at(id, ['DP 46:00:00N 14:00:00E', 'DP 046:00:00N 014:0:00E']),
          [7, 8]);
    });
    test('two problems in one command give one diagnostic', () {
      expect(messages(id, ['DP 46:0:00N 14:00:00E']).single,
          contains('leading zeros'));
    });
  });

  group('coordinate-decimal-seconds', () {
    const id = 'coordinate-decimal-seconds';
    test('whole seconds and DDM are fine', () {
      expect(at(id, ['DP 46:00:00N 014:00:00E', 'DP 46:00.123N 014:00.5E']),
          isEmpty);
    });
    test('decimal seconds', () {
      expect(at(id, ['DP 46:00:00.5N 014:00:00.25E']), [7]);
    });
  });

  group('coordinate-mixed-notation', () {
    const id = 'coordinate-mixed-notation';
    test('valid', () => expect(at(id, square), isEmpty));
    test('DMS latitude and DDM longitude', () {
      expect(at(id, ['DP 46:00:00N 014:00.000E']), [7]);
    });
    test('a part with decimal degrees is not reported here', () {
      expect(at(id, ['DP 46N 014:10:00E', 'DP 46:00.000N 014.5E']), isEmpty);
    });
    const dbLines = [
      'DP 46:00:00N 014:00:00E',
      'V X=46:00:00N 014:00:00E',
      'DB 46:10:00N 014:00:00E, 46:00.000N 014:14.400E',
      'DP 46:00:00N 014:00:00E',
    ];
    test('the two points of a DB use different notations', () {
      expect(at(id, dbLines), [9]);
      expect(
          messages(id, dbLines).single,
          'The two points of this DB use DMS and DDM. Use the same notation '
          'for both.');
    });
    test('the file rule does not report the same DB again', () {
      final d = lintAll(airspace(dbLines))
          .where((d) => geometryIds.contains(d.ruleId))
          .map((d) => '${d.line} ${d.ruleId}');
      expect(d, ['9 $id']);
    });
    test('a DB with one notation is fine', () {
      expect(
          at(id, [
            'V X=46:00:00N 014:00:00E',
            'DB 46:10.000N 014:00.000E, 46:00.000N 014:14.400E',
          ]),
          isEmpty);
    });
  });

  group('coordinate-file-mixed-notation', () {
    const id = 'coordinate-file-mixed-notation';
    test('one notation', () {
      expect(at(id, square), isEmpty);
      expect(at(id, ['DP 46:00.000N 014:00.000E', 'DP 46:10.000N 014:00.000E']),
          isEmpty);
    });
    test('reported once at the first change', () {
      expect(
          at(id, [
            'DP 46:00:00N 014:00:00E',
            'DP 46:10.000N 014:00.000E',
            'DP 46:10.000N 014:10.000E',
          ]),
          [8]);
    });
    test('over several airspaces and in V X', () {
      final text = withHeader('$validAirspace'
          'AC D\n'
          'AN Circle\n'
          'AH FL95\n'
          'AL GND\n'
          'V X=46:30.000N 014:30.000E\n'
          'DC 5\n');
      expect(linesOf(id, text), [17]);
    });
    test('decimal degrees and mixed points are ignored', () {
      expect(
          at(id, [
            'DP 46:00:00N 014:00:00E',
            'DP 46.5N 14.5E',
            'DP 46:00:00N 014:00.000E',
          ]),
          isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Polygon
  // -------------------------------------------------------------------------

  group('geometry-polygon-too-few-points', () {
    const id = 'geometry-polygon-too-few-points';
    test('valid', () => expect(at(id, square), isEmpty));
    test('two points', () {
      expect(
          at(id, [
            'DP 46:00:00N 014:00:00E',
            'DP 46:00:00N 014:10:00E',
            'DP 46:00:00N 014:00:00E',
          ]),
          [7]);
    });
    test('points on one line', () {
      final m = messages(id, [
        'DP 46:00:00N 014:00:00E',
        'DP 46:00:00N 014:10:00E',
        'DP 46:00:00N 014:20:00E',
      ]);
      expect(m.single, contains('one line'));
    });
    test('a circle or a single arc is fine', () {
      expect(at(id, ['V X=46:00:00N 014:00:00E', 'DC 5']), isEmpty);
      expect(at(id, ['V X=46:00:00N 014:00:00E', 'DA 5, 0, 90']), isEmpty);
    });
    test('not checked when a point is wrong', () {
      expect(at(id, ['DP 46:00:00N 014:00:00E', 'DP 99:00:00N 014:10:00E']),
          isEmpty);
    });
  });

  group('geometry-polygon-not-closed', () {
    const id = 'geometry-polygon-not-closed';
    test('closed', () => expect(at(id, square), isEmpty));
    test('open polygon is reported at the last point', () {
      expect(at(id, square.sublist(0, 4)), [10]);
      expect(messages(id, square.sublist(0, 4)).single,
          contains('Add "DP 46:00:00N 014:00:00E" as the last point.'));
    });
    test('one digit differs: probably a typing error', () {
      final m =
          messages(id, [...square.sublist(0, 4), 'DP 46:00:01N 014:00:00E']);
      expect(m.single, contains('differs from the first point in one digit'));
      expect(m.single, contains('probably a typing error'));
    });
    test('a close point with more than one different digit', () {
      final m =
          messages(id, [...square.sublist(0, 4), 'DP 46:00:05N 014:00:03E']);
      expect(m.single, contains('Add "DP 46:00:00N 014:00:00E"'));
    });
    test('closed by a DB arc', () {
      expect(
          at(id, [
            'DP 46:00:00N 014:00:00E',
            'DP 46:10:00N 014:00:00E',
            'V X=46:00:00N 014:00:00E',
            'DB 46:10:00N 014:00:00E, 46:00:00N 014:14:24E',
            'DP 46:00:00N 014:00:00E',
          ]),
          isEmpty);
    });
    test('a boundary that ends with a DA arc is not checked', () {
      expect(
          at(id, [
            'DP 46:00:00N 014:00:00E',
            'V X=46:00:00N 014:00:00E',
            'DA 10, 0, 90',
          ]),
          isEmpty);
    });
    test('a boundary that is only one DB arc is not checked', () {
      // The DB example of the specification, and the same for one DA.
      expect(
          at(id, [
            'V X=39:13:00N 118:13:00W',
            'DB 39:36:40N 119:46:10W, 39:29:09N 119:36:10W',
          ]),
          isEmpty);
      expect(at(id, ['V X=39:13:00N 118:13:00W', 'DA 10, 270, 290']), isEmpty);
    });
    test('a boundary of only DB arcs is not checked (no DP points)', () {
      final lines = [
        'V X=46:00:00N 014:00:00E',
        'DB 46:10:00N 014:00:00E, 46:00:00N 014:14:24E',
        'DB 45:50:00N 014:00:00E, 46:00:00N 013:45:36E',
      ];
      expect(at(id, lines), isEmpty);
    });
    test('a DB arc and DP points that do not meet are reported', () {
      final lines = [
        'DP 46:10:00N 013:50:00E',
        'V X=46:00:00N 014:00:00E',
        'DB 46:10:00N 014:00:00E, 46:00:00N 014:14:24E',
        'DP 45:50:00N 014:00:00E',
        'DB 45:50:00N 014:00:00E, 46:00:00N 013:45:36E',
      ];
      expect(at(id, lines), [11]);
      expect(messages(id, lines).single, contains('(line 7)'));
    });
  });

  group('dp-duplicate-point', () {
    const id = 'dp-duplicate-point';
    test('valid', () => expect(at(id, square), isEmpty));
    test('the same point twice', () {
      expect(
          at(id, [square[0], square[1], square[1], ...square.sublist(2)]), [9]);
    });
    test('same value, other text', () {
      expect(
          at(id,
              [square[0], 'DP 46:00.000N 014:00.000E', ...square.sublist(1)]),
          [8]);
    });
    test('not after another geometry command', () {
      expect(
          at(id, [
            'DP 46:10:00N 014:00:00E',
            'V X=46:00:00N 014:00:00E',
            'DB 46:10:00N 014:00:00E, 46:00:00N 014:14:24E',
            'DP 46:00:00N 014:14:24E',
          ]),
          isEmpty);
    });
  });

  group('geometry-polygon-counter-clockwise', () {
    const id = 'geometry-polygon-counter-clockwise';
    test('clockwise', () => expect(at(id, square), isEmpty));
    test('counter-clockwise', () {
      expect(at(id, square.reversed.toList()), [7]);
    });
    test('the severity is warning (the specification says "expected")', () {
      expect(findRule(id)!.severity, Severity.warning);
    });
  });

  group('geometry-polygon-self-intersection', () {
    const id = 'geometry-polygon-self-intersection';
    test('valid', () => expect(at(id, square), isEmpty));
    test('bow tie', () {
      final lines = [
        'DP 46:00:00N 014:00:00E',
        'DP 46:00:00N 014:10:00E',
        'DP 45:55:00N 014:00:00E',
        'DP 45:55:00N 014:10:00E',
        'DP 46:00:00N 014:00:00E',
      ];
      expect(at(id, lines), [11]);
      expect(
          messages(id, lines).single,
          contains('the edge to the point on line 11 crosses the edge to the '
              'point on line 9'));
    });
    test('open bow tie is reported at the closing edge', () {
      expect(
          at(id, [
            'DP 46:00:00N 014:00:00E',
            'DP 46:00:00N 014:10:00E',
            'DP 45:55:00N 014:00:00E',
            'DP 45:55:00N 014:10:00E',
          ]),
          [10]);
    });
    test('an arc with the wrong direction', () {
      final lines = [
        'DP 46:05:00N 014:00:00E',
        'DP 46:05:00N 014:20:00E',
        'DP 46:00:00N 014:20:00E',
        'V D=-',
        'V X=46:00:00N 014:10:00E',
        'DB 46:00:00N 014:20:00E, 46:00:00N 014:00:00E',
        'DP 46:00:00N 014:00:00E',
        'DP 46:05:00N 014:00:00E',
      ];
      expect(at(id, lines), [12]);
      expect(messages(id, lines).single, contains('direction of the arc'));
    });
    test('a very thin loop is not reported', () {
      // The point on line 9 is 1 second (about 20 m) past the edge.
      expect(
          at(id, [
            'DP 46:00:00N 014:00:00E',
            'DP 46:00:00N 014:10:00E',
            'DP 45:55:00N 014:10:00E',
            'DP 45:55:00N 014:05:00E',
            'DP 45:55:01N 014:05:01E',
            'DP 45:54:59N 014:05:02E',
            'DP 45:55:00N 014:00:00E',
            'DP 46:00:00N 014:00:00E',
          ]),
          isEmpty);
    });
    test('a polygon across the antimeridian', () {
      expect(
          at(id, [
            'DP 10:00:00N 179:50:00E',
            'DP 10:00:00N 179:50:00W',
            'DP 09:50:00N 179:50:00W',
            'DP 09:50:00N 179:50:00E',
            'DP 10:00:00N 179:50:00E',
          ]),
          isEmpty);
    });
    test('the severity is warning (the specification says "should")', () {
      expect(findRule(id)!.severity, Severity.warning);
      expect(findRule(id)!.specAnchor, 'd-geometric-definitions');
    });
    test('a figure-eight with two crossing edges', () {
      // The west loop is clockwise, the east loop is counter-clockwise. The
      // edges to the points on lines 9 and 13 cross near 46:05N 014:10E.
      final lines = [
        'DP 46:10:00N 014:00:00E',
        'DP 46:10:00N 014:05:00E',
        'DP 46:00:00N 014:15:00E',
        'DP 46:00:00N 014:20:00E',
        'DP 46:10:00N 014:20:00E',
        'DP 46:10:00N 014:15:00E',
        'DP 46:00:00N 014:05:00E',
        'DP 46:00:00N 014:00:00E',
        'DP 46:10:00N 014:00:00E',
      ];
      expect(at(id, lines), [13]);
      expect(messages(id, lines).single,
          contains('crosses itself near 46:05:00N 014:10:00E'));
    });
  });

  group('a boundary that touches itself', () {
    const id = 'geometry-polygon-self-intersection';
    // A ring-shaped airspace with an empty area inside: the outer ring
    // (clockwise), a connecting line, the inner ring (counter-clockwise)
    // and the same connecting line back (lines 18 to 23).
    const ringFile = 'AC UNC\n'
        'AY CUSTOM\n'
        'AN Outside competition area\n'
        'AH FL95\n'
        'AL GND\n'
        'DP 46:30:00N 013:40:00E\n'
        'DP 46:32:00N 014:20:00E\n'
        'DP 46:10:00N 014:35:00E\n'
        'DP 45:50:00N 014:20:00E\n'
        'DP 45:48:00N 013:45:00E\n'
        'DP 46:30:00N 013:40:00E\n'
        'DP 46:15:00N 013:55:00E\n'
        'DP 46:00:00N 013:55:00E\n'
        'DP 46:00:00N 014:15:00E\n'
        'DP 46:15:00N 014:15:00E\n'
        'DP 46:15:00N 013:55:00E\n'
        'DP 46:30:00N 013:40:00E\n';

    test('a ring-shaped airspace has no error and no warning', () {
      final text = withHeader(ringFile);
      final d = lintAll(text).where((d) => d.severity != Severity.info);
      expect(d, isEmpty);
    });

    test('the shape rules check the ring', () {
      // The same ring in the opposite direction: the outer ring is
      // counter-clockwise. The direction rule reports it, so the ring is
      // checked as one boundary without a crossing.
      final lines = ringFile.trim().split('\n');
      final reversed = [...lines.take(5), ...lines.skip(5).toList().reversed];
      final text = withHeader('${reversed.join('\n')}\n');
      expect(linesOf('geometry-polygon-counter-clockwise', text), [8]);
      expect(linesOf(id, text), isEmpty);
    });

    test('findCrossings finds no crossing in the ring', () {
      final file = parseOpenAir(withHeader(ringFile));
      final ring = PolygonRing(
          [
            for (final c in file.airspaces.single.commands)
              if (c.upperKeyword == 'DP') parseCoordinate(c.argument).value!
          ]..removeLast(),
          List.filled(11, file.airspaces.single.commands.last),
          file.airspaces.single.commands.last,
          explicitlyClosed: true);
      final r = findCrossings(ring);
      expect(r.count, 0);
      expect(r.limitReached, isFalse);
    });

    test('a ring-shaped airspace made of DB arcs', () {
      final text = withHeader('AC UNC\n'
          'AY CUSTOM\n'
          'AN Outside competition circle\n'
          'AH FL95\n'
          'AL GND\n'
          'V X=46:10:00N 014:10:00E\n'
          'DB 46:30:00N 014:10:00E, 45:50:00N 014:10:00E\n'
          'DB 45:50:00N 014:10:00E, 46:30:00N 014:10:00E\n'
          'DP 46:20:00N 014:10:00E\n'
          'V D=-\n'
          'DB 46:20:00N 014:10:00E, 46:00:00N 014:10:00E\n'
          'DB 46:00:00N 014:10:00E, 46:20:00N 014:10:00E\n'
          'DP 46:30:00N 014:10:00E\n');
      expect(lintAll(text).where((d) => d.severity != Severity.info), isEmpty);
    });

    test('a connecting line in the middle of an edge', () {
      // The connecting line starts in the middle of the south edge of the
      // outer square and goes to the inner square.
      expect(
          at(id, [
            'DP 46:00:00N 014:00:00E',
            'DP 46:00:00N 014:20:00E',
            'DP 45:40:00N 014:20:00E',
            'DP 45:40:00N 014:10:00E',
            'DP 45:45:00N 014:10:00E',
            'DP 45:45:00N 014:15:00E',
            'DP 45:55:00N 014:15:00E',
            'DP 45:55:00N 014:05:00E',
            'DP 45:45:00N 014:05:00E',
            'DP 45:45:00N 014:10:00E',
            'DP 45:40:00N 014:10:00E',
            'DP 45:40:00N 014:00:00E',
            'DP 46:00:00N 014:00:00E',
          ]),
          isEmpty);
    });

    test('two loops that touch at one point', () {
      // Both loops are clockwise. They touch at 46:05N 014:10E.
      final lines = [
        'DP 46:05:00N 014:10:00E',
        'DP 46:00:00N 014:00:00E',
        'DP 46:10:00N 014:00:00E',
        'DP 46:05:00N 014:10:00E',
        'DP 46:10:00N 014:20:00E',
        'DP 46:00:00N 014:20:00E',
        'DP 46:05:00N 014:10:00E',
      ];
      final d =
          lintAll(airspace(lines)).where((d) => d.severity != Severity.info);
      expect(d, isEmpty);
    });

    test('a figure-eight that crosses at a point it passes twice', () {
      // The west loop is clockwise, the east loop is counter-clockwise.
      final lines = [
        'DP 46:05:00N 014:10:00E',
        'DP 46:00:00N 014:00:00E',
        'DP 46:10:00N 014:00:00E',
        'DP 46:05:00N 014:10:00E',
        'DP 46:00:00N 014:20:00E',
        'DP 46:10:00N 014:20:00E',
        'DP 46:05:00N 014:10:00E',
      ];
      expect(at(id, lines), [10]);
      expect(
          messages(id, lines).single,
          'The boundary of "Test" (line 3) crosses itself near 46:05:00N '
          '014:10:00E: the boundary passes this point on line 7 and again on '
          'line 10, and there it goes from one side of itself to the other '
          'side.');
      // No other warning hides it: the direction is not checked.
      expect(at('geometry-polygon-counter-clockwise', lines), isEmpty);
    });

    test('a spike: a line drawn out and back', () {
      expect(
          at(id, [
            'DP 46:00:00N 014:00:00E',
            'DP 46:00:00N 014:10:00E',
            'DP 46:05:00N 014:15:00E',
            'DP 46:00:00N 014:10:00E',
            'DP 45:55:00N 014:10:00E',
            'DP 45:55:00N 014:00:00E',
            'DP 46:00:00N 014:00:00E',
          ]),
          isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Centre, DA, DB, DC
  // -------------------------------------------------------------------------

  group('geometry-center-missing', () {
    const id = 'geometry-center-missing';
    test('valid', () {
      expect(at(id, ['V X=46:00:00N 014:00:00E', 'DC 5']), isEmpty);
    });
    test('DA, DB and DC without a centre', () {
      expect(
          at(id, [
            'DA 5, 0, 90',
            'DB 46:05:00N 014:00:00E, 46:00:00N 014:07:12E',
            'DC 5',
          ]),
          [7, 8, 9]);
    });
    test('centre after the command', () {
      expect(messages(id, ['DC 5', 'V X=46:00:00N 014:00:00E']).single,
          contains('comes after this command'));
    });
    test('the centre of an earlier airspace is not used', () {
      final text = withHeader('AC D\n'
          'AN A\n'
          'AH FL95\n'
          'AL GND\n'
          'V X=46:00:00N 014:00:00E\n'
          'DC 5\n'
          'AC D\n'
          'AN B\n'
          'AH FL95\n'
          'AL GND\n'
          'DC 3\n');
      final d = lintRule(id, text);
      expect(d.map((d) => d.line), [13]);
      expect(
          d.single.message,
          'DC needs a centre. Write "V X=<point>" before it in the same '
          'airspace. The V values are reset at every AC. The centre on line 7 '
          'is in an earlier part of the file, so it is not used here.');
      expect(findRule(id)!.specAnchor, 'v-variable-assignment');
    });
    test('a centre before the first AC is not used', () {
      final text = withHeader('V X=46:00:00N 014:00:00E\n'
          'AC D\n'
          'AN A\n'
          'AH FL95\n'
          'AL GND\n'
          'DC 5\n');
      expect(linesOf(id, text), [8]);
    });
    test('the message always says that the values are reset', () {
      expect(messages(id, ['DC 5']).single,
          contains('values are reset at every AC'));
    });
    test('a wrong centre counts as a centre', () {
      expect(at(id, ['V X=99:00:00N 014:00:00E', 'DC 5']), isEmpty);
    });
  });

  group('da-wrong-format', () {
    const id = 'da-wrong-format';
    test('valid', () {
      expect(at(id, ['V X=46:00:00N 014:00:00E', 'DA 10, 270, 290']), isEmpty);
      expect(at(id, ['V X=46:00:00N 014:00:00E', 'DA 7,290,320']), isEmpty);
    });
    test('no commas', () {
      expect(at(id, ['V X=46:00:00N 014:00:00E', 'DA 10 270 290']), [8]);
    });
    test('a unit', () {
      final m = messages(id, ['V X=46:00:00N 014:00:00E', 'DA 10NM, 270, 290']);
      expect(m.single, contains('without a unit'));
    });
    test('a decimal comma', () {
      final m = messages(id, [
        'V X=46:00:00N 014:00:00E',
        'DA 2,5, 270, 290',
        'DA 10, 270,5, 290',
      ]);
      expect(m, hasLength(2));
      for (final s in m) {
        expect(s, endsWith('Use a point (.) as the decimal separator.'));
      }
      expect(messages(id, ['DA 10, 270, 290, 5']).single,
          isNot(contains('decimal separator')));
    });
    test('a missing value', () {
      expect(messages(id, ['DA 10, , 290']).single,
          'The start bearing is missing.');
    });
  });

  group('da-radius-not-positive', () {
    const id = 'da-radius-not-positive';
    test('valid', () => expect(at(id, ['DA 0.5, 0, 90']), isEmpty));
    test('zero and negative', () {
      expect(at(id, ['DA 0, 0, 90', 'DA -2, 0, 90']), [7, 8]);
    });
  });

  group('da-bearing-out-of-range', () {
    const id = 'da-bearing-out-of-range';
    test('valid', () => expect(at(id, ['DA 5, 0, 360']), isEmpty));
    test('negative and above 360', () {
      expect(at(id, ['DA 5, -90, 380']), [7, 7]);
    });
  });

  group('da-combined-with-dp', () {
    const id = 'da-combined-with-dp';
    test('DA alone is fine', () {
      expect(at(id, ['V X=46:00:00N 014:00:00E', 'DA 5, 0, 90']), isEmpty);
    });
    test('DA with DP, once per airspace', () {
      expect(
          at(id, [
            'DP 46:00:00N 014:00:00E',
            'V X=46:00:00N 014:00:00E',
            'DA 5, 0, 90',
            'DA 5, 90, 180',
          ]),
          [9]);
    });
  });

  group('db-wrong-format', () {
    const id = 'db-wrong-format';
    test('valid', () {
      expect(
          at(id, ['DB 46:05:00N 014:00:00E, 46:00:00N 014:07:12E']), isEmpty);
    });
    test('one point', () {
      expect(messages(id, ['DB 46:05:00N 014:00:00E']).single,
          contains('only one point'));
    });
    test('missing comma', () {
      expect(
          messages(id, ['DB 46:05:00N 014:00:00E 46:00:00N 014:07:12E']).single,
          contains('comma between the two points is missing'));
    });
    test('empty second point', () {
      expect(messages(id, ['DB 46:05:00N 014:00:00E,']).single,
          'The second point is missing.');
    });
    test('three points', () {
      expect(at(id, ['DB 46:05:00N 014:00:00E, 46:00:00N 014:07:12E, 1']), [7]);
    });
  });

  group('db-radius-mismatch', () {
    const id = 'db-radius-mismatch';
    test('equal distances', () {
      expect(
          at(id, [
            'V X=46:00:00N 014:00:00E',
            'DB 46:10:00N 014:00:00E, 46:00:00N 014:14:24E',
          ]),
          isEmpty);
    });
    test('small difference from rounding', () {
      expect(
          at(id, [
            'V X=46:00:00N 014:00:00E',
            'DB 46:10:00N 014:00:00E, 46:00:00N 014:14:30E',
          ]),
          isEmpty);
    });
    test('large difference', () {
      final lines = [
        'V X=46:00:00N 014:00:00E',
        'DB 46:10:00N 014:00:00E, 46:00:00N 014:20:00E',
      ];
      expect(at(id, lines), [8]);
      expect(messages(id, lines).single, contains('(line 7)'));
    });
    test('the DB example of the specification', () {
      // Both points are 10 NM from the centre.
      final lines = [
        'V X=46:00:00N 014:00:00E',
        'DB 46:10:00N 014:00:00E, 46:00:00N 014:14:24E',
      ];
      expect(lintAll(airspace(lines)).where((d) => d.severity != Severity.info),
          isEmpty);
    });
    test('no centre: not checked here', () {
      expect(
          at(id, ['DB 46:10:00N 014:00:00E, 46:00:00N 014:20:00E']), isEmpty);
    });
    test('an error in 3.0, a warning (other rule) in 2.1', () {
      const lines = [
        'V X=46:00:00N 014:00:00E',
        'DB 46:10:00N 014:00:00E, 46:00:00N 014:20:00E',
      ];
      final v30 = lintAll(airspace(lines))
          .where((d) => d.ruleId.startsWith('db-radius'))
          .toList();
      expect(v30.map((d) => d.ruleId), ['db-radius-mismatch']);
      expect(v30.single.severity, Severity.error);
      final v21 = lintAll(airspace(lines, version: '2.1'))
          .where((d) => d.ruleId.startsWith('db-radius'))
          .toList();
      expect(v21.map((d) => d.ruleId), ['db-radius-mismatch-v21']);
      expect(v21.single.severity, Severity.warning);
      expect(v21.single.message, v30.single.message);
    });
  });

  group('dc-wrong-format', () {
    const id = 'dc-wrong-format';
    test('valid', () => expect(at(id, ['DC 2.00', 'DC 5', 'DC .5']), isEmpty));
    test('a unit, a comma and nothing', () {
      expect(at(id, ['DC 2 NM', 'DC 2,5', 'DC']), [7, 8, 9]);
      expect(messages(id, ['DC 2,5']).single, contains('decimal separator'));
    });
  });

  group('dc-radius-not-positive', () {
    const id = 'dc-radius-not-positive';
    test('valid', () => expect(at(id, ['DC 0.1']), isEmpty));
    test('zero and negative', () {
      expect(at(id, ['DC 0', 'DC -1']), [7, 8]);
    });
  });

  group('dc-mixed-with-other-geometry', () {
    const id = 'dc-mixed-with-other-geometry';
    test('a circle alone', () {
      expect(at(id, ['V X=46:00:00N 014:00:00E', 'V D=-', 'DC 5']), isEmpty);
    });
    test('a circle and points', () {
      expect(
          at(id,
              ['V X=46:00:00N 014:00:00E', 'DC 5', 'DP 46:00:00N 014:00:00E']),
          [8]);
    });
    test('two circles', () {
      expect(
          at(id, [
            'V X=46:00:00N 014:00:00E',
            'DC 5',
            'V X=46:10:00N 014:00:00E',
            'DC 5',
          ]),
          [10]);
    });
    test('every other geometry command is an error', () {
      for (final other in [
        'DP 46:00:00N 014:00:00E',
        'DA 5, 0, 90',
        'DB 46:05:00N 014:00:00E, 46:00:00N 014:07:12E',
        'DY 46:00:00N 014:00:00E',
      ]) {
        final d = lintRule(
            id, airspace(['V X=46:00:00N 014:00:00E', 'V W=2', 'DC 5', other]));
        expect(d.map((d) => d.line), [9], reason: other);
        expect(d.single.severity, Severity.error);
        expect(
            d.single.message,
            startsWith(
                'DC must be the only geometry command of its airspace.'));
      }
    });
    test('the DC example of the specification', () {
      final text = withHeader('AC UNC\n'
          'AY Q\n'
          'AN PARA Ailertchen EDGA\n'
          'AH FL100\n'
          'AL GND\n'
          'V X=50:35:36N 007:56:42E\n'
          'DC 2.00\n');
      expect(lintAll(text).where((d) => d.severity != Severity.info), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // DY
  // -------------------------------------------------------------------------

  group('dy-deprecated', () {
    const id = 'dy-deprecated';
    test('DP airway is fine', () => expect(at(id, square), isEmpty));
    test('once per airspace', () {
      expect(
          at(id, [
            'V W=4',
            'DY 46:00:00N 014:00:00E',
            'DY 46:00:00N 015:00:00E',
          ]),
          [8]);
    });
  });

  group('dy-width-missing', () {
    const id = 'dy-width-missing';
    test('width before', () {
      expect(at(id, ['V W=4', 'DY 46:00:00N 014:00:00E']), isEmpty);
    });
    test('no width', () {
      expect(
          at(id, ['DY 46:00:00N 014:00:00E', 'DY 46:00:00N 015:00:00E']), [7]);
    });
    test('width after the DY', () {
      expect(messages(id, ['DY 46:00:00N 014:00:00E', 'V W=4']).single,
          contains('comes after it'));
    });
    test('the width of an earlier airspace is not used', () {
      final text = withHeader('AC D\n'
          'AN A\n'
          'AH FL95\n'
          'AL GND\n'
          'V W=4\n'
          'DY 46:00:00N 014:00:00E\n'
          'DY 46:00:00N 015:00:00E\n'
          'AC D\n'
          'AN B\n'
          'AH FL95\n'
          'AL GND\n'
          'DY 46:10:00N 014:00:00E\n'
          'DY 46:10:00N 015:00:00E\n');
      final d = lintRule(id, text);
      expect(d.map((d) => d.line), [14]);
      expect(
          d.single.message,
          'DY needs an airway width. Write "V W=<width in NM>" before it in '
          'the same airspace. The V values are reset at every AC. The width '
          'on line 7 is in an earlier part of the file, so it is not used '
          'here.');
      expect(findRule(id)!.severity, Severity.error);
    });
    test('the DY example of the specification is fine', () {
      final lines = [
        'V W=5',
        'DY 46:00:00N 014:00:00E',
        'DY 46:30:00N 014:30:00E',
      ];
      final d = lintAll(airspace(lines))
          .where((d) => geometryIds.contains(d.ruleId))
          .map((d) => d.ruleId);
      // DY itself is not recommended. Nothing else is reported.
      expect(d, ['dy-deprecated']);
    });
  });

  group('V values are reset at every AC', () {
    test('the direction of an earlier airspace is not used', () {
      // The first airspace sets V D=-. The second airspace has the same arc
      // without V D=, so its arc is clockwise and does not cross the edges.
      const arc = [
        'DP 46:05:00N 014:00:00E',
        'DP 46:05:00N 014:20:00E',
        'DP 46:00:00N 014:20:00E',
        'V X=46:00:00N 014:10:00E',
        'DB 46:00:00N 014:20:00E, 46:00:00N 014:00:00E',
        'DP 46:00:00N 014:00:00E',
        'DP 46:05:00N 014:00:00E',
      ];
      final text = withHeader('AC D\n'
          'AN A\n'
          'AH FL95\n'
          'AL GND\n'
          'V D=-\n'
          'V X=46:30:00N 014:00:00E\n'
          'DC 5\n'
          'AC D\n'
          'AN B\n'
          'AH FL95\n'
          'AL GND\n'
          '${arc.join('\n')}\n');
      expect(linesOf('geometry-polygon-self-intersection', text), isEmpty);
      expect(linesOf('geometry-polygon-counter-clockwise', text), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // V
  // -------------------------------------------------------------------------

  group('v-wrong-format', () {
    const id = 'v-wrong-format';
    test('valid', () {
      expect(at(id, ['V X=46:00:00N 014:00:00E', 'V D=-', 'V W=2']), isEmpty);
    });
    test('no "=", no name, no value', () {
      expect(at(id, ['V X 46:00:00N 014:00:00E', 'V =-', 'V D=', 'V']),
          [7, 8, 9, 10]);
    });
  });

  group('v-space-around-equals', () {
    const id = 'v-space-around-equals';
    test('valid', () {
      expect(at(id, ['V X=46:00:00N 014:00:00E', 'V D=-', 'V W=2', 'V d=+']),
          isEmpty);
    });
    test('blanks before, after and around "="', () {
      expect(
          at(id, [
            'V X =46:00:00N 014:00:00E',
            'V X= 46:00:00N 014:00:00E',
            'V D = -',
            'V W=\t2',
          ]),
          [7, 8, 9, 10]);
    });
    test('the message and the columns', () {
      final d = lintRule(id, airspace(['V X = 46:00:00N 014:00:00E'])).single;
      expect(d.message,
          'Do not write blanks around "=". Write "V X=46:00:00N 014:00:00E".');
      expect(d.column, 'V X'.length + 1);
      expect(d.endColumn, 'V X = '.length + 1);
    });
    test('a missing name or value is left to v-wrong-format', () {
      expect(at(id, ['V = -', 'V D = ', 'V X 46:00:00N 014:00:00E']), isEmpty);
    });
  });

  group('v-unknown-variable', () {
    const id = 'v-unknown-variable';
    test('X, D and W are known', () {
      expect(at(id, ['V X=46:00:00N 014:00:00E', 'V d=+', 'V W=2']), isEmpty);
    });
    test('unknown name', () {
      expect(at(id, ['V T=1']), [7]);
    });
  });

  group('v-invalid-direction', () {
    const id = 'v-invalid-direction';
    test('valid', () => expect(at(id, ['V D=+', 'V D = -']), isEmpty));
    test('other values', () {
      expect(at(id, ['V D=CCW', 'V D=-;']), [7, 8]);
    });
  });

  group('v-invalid-width', () {
    const id = 'v-invalid-width';
    test('valid', () => expect(at(id, ['V W=4', 'V W=0.5']), isEmpty));
    test('zero, unit, not a number', () {
      expect(at(id, ['V W=0', 'V W=4NM', 'V W=wide']), [7, 8, 9]);
    });
  });

  group('v-width-without-airway', () {
    const id = 'v-width-without-airway';
    test('with DY', () {
      expect(at(id, ['V W=4', 'DY 46:00:00N 014:00:00E']), isEmpty);
    });
    test('without DY', () {
      expect(at(id, ['V W=4', ...square]), [7]);
    });
  });

  group('v-center-unused', () {
    const id = 'v-center-unused';
    test('used', () {
      expect(at(id, ['V X=46:00:00N 014:00:00E', 'DC 5']), isEmpty);
    });
    test('not used, and replaced before use', () {
      expect(
          at(id, [
            'V X=46:00:00N 014:00:00E',
            'V X=46:10:00N 014:00:00E',
            'DC 5',
            'V X=46:20:00N 014:00:00E',
            ...square,
          ]),
          [7, 10]);
    });
  });

  // -------------------------------------------------------------------------
  // Support code
  // -------------------------------------------------------------------------

  group('findCrossings', () {
    test('a large polygon is fast and has no crossings', () {
      // A circle with 20000 corners.
      final shape = StringBuffer();
      for (var i = 0; i <= 20000; i++) {
        final b = 360.0 * i / 20000;
        final p = destinationPoint(const LatLng(46, 14), b, 20);
        shape.writeln('DP ${formatCoordinate(p, CoordinateNotation.ddm)}');
      }
      final text = withHeader('AC D\nAN Big\nAH FL95\nAL GND\n$shape');
      final sw = Stopwatch()..start();
      final d = lintRule('geometry-polygon-self-intersection', text);
      expect(d, isEmpty);
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('loop width filter keeps real crossings', () {
      expect(minLoopWidthMetres, greaterThan(0));
    });

    // A ring from points, for direct calls of findCrossings.
    final command = parseOpenAir('AC D\nDP 46:00:00N 014:00:00E\n')
        .airspaces
        .single
        .commands
        .last;
    PolygonRing ringOf(List<LatLng> points) =>
        PolygonRing(points, List.filled(points.length, command), command,
            explicitlyClosed: false);

    // A zigzag that does not cross itself: the points alternate between two
    // longitudes and go north in small steps, then the ring goes back on a
    // third longitude.
    List<LatLng> zigzag(int n, {bool diagonal = false}) {
      const step = 2 / 3600; // 2 seconds
      const half = 0.5; // degrees
      return [
        for (var i = 0; i < n; i++)
          diagonal
              ? LatLng(40 + i * step + (i.isEven ? half : -half),
                  10 + i * step + (i.isEven ? -half : half))
              : LatLng(40 + i * step, i.isEven ? 10 : 11),
        if (diagonal) ...[
          LatLng(40 + (n - 1) * step - 1, 10 + (n - 1) * step + 1),
          const LatLng(39, 11),
        ] else ...[
          LatLng(40 + (n - 1) * step, 9.5),
          const LatLng(40, 9.5),
        ],
      ];
    }

    test('a long and narrow ring is fast (sweep along the latitude)', () {
      final sw = Stopwatch()..start();
      final r = findCrossings(ringOf(zigzag(40000)));
      expect(r.count, 0);
      expect(r.limitReached, isFalse);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('the search stops at the work limit', () {
      final ring = ringOf(zigzag(4000, diagonal: true));
      final full = findCrossings(ring);
      expect(full.count, 0);
      expect(full.limitReached, isFalse);
      final cut = findCrossings(ring, workLimit: 1000);
      expect(cut.count, 0);
      expect(cut.limitReached, isTrue);
    });

    test('many thin crossings count as work and stop at the work limit', () {
      // A zigzag of about 1.85 m along 45° N, and a straight line back that
      // crosses every zigzag edge. All loops are thin, so no crossing is
      // counted, but each loop width costs time.
      const amp = 1 / 60000; // 1/1000 minute
      List<LatLng> thin(int n) => [
            const LatLng(45, 14),
            for (var k = 1; k < n - 1; k++)
              LatLng(45 + (k.isOdd ? amp : -amp), 14 + k * 0.0005),
            LatLng(45, 14 + (n - 1) * 0.0005),
          ];
      final small = findCrossings(ringOf(thin(2001)));
      expect(small.count, 0);
      expect(small.limitReached, isFalse);
      final sw = Stopwatch()..start();
      final big = findCrossings(ringOf(thin(60001)));
      expect(big.count, 0);
      expect(big.limitReached, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('a crossing is found on both sweep axes', () {
      // A bow tie that is wide (sweep along the longitude) and one that is
      // tall (sweep along the latitude).
      const wide = [
        LatLng(46, 14),
        LatLng(46, 15),
        LatLng(45.9, 14),
        LatLng(45.9, 15),
      ];
      const tall = [
        LatLng(46, 14),
        LatLng(46, 14.1),
        LatLng(45, 14),
        LatLng(45, 14.1),
      ];
      expect(findCrossings(ringOf(wide)).count, 1);
      expect(findCrossings(ringOf(tall)).count, 1);
    });
  });

  test('the cache gives the same result for repeated files', () {
    final text = airspace(['DP 46:00:00 N 014:00:00E', ...square]);
    final a = lintAll(text);
    final b = lintAll(text);
    expect(expectedFormat(a), expectedFormat(b));
  });

  test('the cache belongs to one file', () {
    // The same commands in two files, linted in turns. A cache that is
    // shared between files would give the wrong result for the second one.
    final open = airspace(square.sublist(0, 4));
    final closed = airspace(square);
    const id = 'geometry-polygon-not-closed';
    expect(linesOf(id, open), [10]);
    expect(linesOf(id, closed), isEmpty);
    expect(linesOf(id, open), [10]);
  });

  group('review fixes', () {
    test('a ring around a pole on one latitude has an area', () {
      const ring = [
        'DP 80:00:00N 000:00:00E',
        'DP 80:00:00N 090:00:00E',
        'DP 80:00:00N 180:00:00E',
        'DP 80:00:00N 090:00:00W',
        'DP 80:00:00N 000:00:00E',
      ];
      expect(at('geometry-polygon-too-few-points', ring), isEmpty);
      expect(at('geometry-polygon-counter-clockwise', ring), isEmpty);
    });
    test('da-not-recommended reports DA only without DP points', () {
      const daOnly = [
        'V X=46:00:00N 014:00:00E',
        'DA 10, 0, 90',
        'DA 10, 90, 0',
      ];
      expect(at('da-not-recommended', daOnly), [8]);
      expect(at('da-combined-with-dp', daOnly), isEmpty);
      const mixed = [
        'DP 46:10:00N 014:00:00E',
        'V X=46:00:00N 014:00:00E',
        'DA 10, 0, 90',
        'DP 46:10:00N 014:00:00E',
      ];
      expect(at('da-not-recommended', mixed), isEmpty);
      expect(findRule('da-not-recommended')!.severity, Severity.info);
    });
    test('dc-mixed-with-other-geometry is an error (the spec says "must")', () {
      expect(
          findRule('dc-mixed-with-other-geometry')!.severity, Severity.error);
    });
    test('warning and info descriptions do not say "must"', () {
      for (final r in allRules) {
        if (r.severity == Severity.error) continue;
        expect(r.description.toLowerCase(), isNot(contains('must')),
            reason: r.id);
      }
    });
  });
}
