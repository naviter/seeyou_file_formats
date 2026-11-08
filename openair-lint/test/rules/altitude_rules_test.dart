// Tests for the rules in lib/src/rules/altitude_rules.dart and the parser in
// lib/src/altitude/altitude.dart.
//
// Conformance files for this group are in openair-conformance/valid/altitude/
// and openair-conformance/invalid/altitude/.

import 'package:openair_lint/openair_lint.dart';
import 'package:openair_lint/src/altitude/altitude.dart';
import 'package:test/test.dart';

import '../support/helpers.dart';

/// A valid airspace with the given AH and AL lines. AH is on line 5 and AL
/// on line 6 (after the 2 header lines and AC, AN).
String limits(String ah, String al, {String version = '3.0'}) => withHeader(
    'AC D\n'
    'AN Test\n'
    '$ah\n'
    '$al\n'
    'DP 46:00:00N 014:00:00E\n'
    'DP 46:00:00N 014:10:00E\n'
    'DP 45:55:00N 014:10:00E\n'
    'DP 46:00:00N 014:00:00E\n',
    version: version);

/// Lints one AH line (AL GND) with only [ruleId].
List<Diagnostic> ah(String ruleId, String value, {String version = '3.0'}) =>
    lintRule(ruleId, limits('AH $value', 'AL GND', version: version));

/// Lints one AL line (AH UNL) with only [ruleId].
List<Diagnostic> al(String ruleId, String value, {String version = '3.0'}) =>
    lintRule(ruleId, limits('AH UNL', 'AL $value', version: version));

void main() {
  group('parseAltitude', () {
    test('reads the forms of the specification', () {
      final fl = parseAltitude('FL95');
      expect(fl.kind, AltitudeKind.flightLevel);
      expect(fl.feet, 9500);
      expect(fl.isClean, isTrue);

      final amsl = parseAltitude('1000 FT AMSL');
      expect(amsl.kind, AltitudeKind.height);
      expect(amsl.unit, AltitudeUnit.feet);
      expect(amsl.reference, AltitudeReference.amsl);
      expect(amsl.feet, 1000);
      expect(amsl.isClean, isTrue);

      final m = parseAltitude('300 M AGL');
      expect(m.unit, AltitudeUnit.meters);
      expect(m.feet, closeTo(984.25, 0.01));
      expect(m.isClean, isTrue);

      final std = parseAltitude('9500 FT STD');
      expect(std.comparableReference, AltitudeReference.std);
      expect(std.isClean, isTrue);

      expect(parseAltitude('GND').kind, AltitudeKind.ground);
      expect(parseAltitude('UNL').kind, AltitudeKind.unlimited);
    });

    test('reads old forms and suggests the 3.0 form', () {
      final r = parseAltitude('1000ft MSL');
      expect(r.kind, AltitudeKind.height);
      expect(r.reference, AltitudeReference.amsl);
      expect(r.suggestion, '1000 FT AMSL');
      expect(r.has(AltitudeIssueKind.noSpaceBeforeUnit), isTrue);
      expect(r.has(AltitudeIssueKind.mslAlias), isTrue);

      expect(parseAltitude('9F MSL').suggestion, '9 FT AMSL');
      expect(parseAltitude('1000 ft GND').suggestion, '1000 FT AGL');
      expect(parseAltitude('SFC').kind, AltitudeKind.ground);
      expect(parseAltitude('UNLIM').kind, AltitudeKind.unlimited);
    });

    test('ignores case', () {
      final r = parseAltitude('1000 ft amsl');
      expect(r.isClean, isTrue);
      expect(r.suggestion, '1000 FT AMSL');
    });

    test('issue offsets point into the text', () {
      final r = parseAltitude('1000 FT MSL');
      final i = r.issuesOf(AltitudeIssueKind.mslAlias).single;
      expect('1000 FT MSL'.substring(i.offset, i.offset + i.length), 'MSL');
      expect(i.replacement, 'AMSL');
    });

    test('never throws', () {
      for (final t in [
        '',
        '/',
        '-',
        '.',
        'FL',
        'FL.',
        '1.2.3',
        '--5 FT',
        'FT',
        '1000 FT AMSL AMSL',
        '1000 FT /',
        '/ 1000 FT',
        'ÄÖÜ',
        '\t',
        ' ',
        '​',
        '5,',
        '5,000,',
        ',000 FT',
        '1 000 000 FT AMSL',
        '1,5,7',
        '1000 FT FL FL',
        'FL+',
        'FL+-',
        '0 (',
        '1000 ( )',
        '1000 FT FT FT',
        '1000 AMSL AMSL FT',
        '1 000 FT AMSL',
      ]) {
        expect(() => parseAltitude(t), returnsNormally, reason: t);
      }
    });
  });

  group('altitude-empty', () {
    const id = 'altitude-empty';
    test('no diagnostic for a value', () {
      expect(ah(id, 'FL95'), isEmpty);
    });
    test('reports AH without a value', () {
      final d = lintRule(id, limits('AH', 'AL GND'));
      expect(d.single.line, 5);
      expect(d.single.message, contains('upper limit'));
    });
    test('reports AL with only spaces and a comment', () {
      final d = lintRule(id, limits('AH UNL', 'AL   * comment'));
      expect(d.single.line, 6);
      expect(d.single.message, contains('lower limit'));
    });
  });

  group('altitude-invalid', () {
    const id = 'altitude-invalid';
    test('no diagnostic for valid values', () {
      expect(ah(id, 'FL95'), isEmpty);
      expect(ah(id, '1000 FT AMSL'), isEmpty);
      expect(al(id, 'GND'), isEmpty);
    });
    test('reports NOTAM with a special message', () {
      final d = ah(id, 'NOTAM');
      expect(d.single.message, contains('not an altitude'));
      expect(d.single.column, 4);
      expect(d.single.endColumn, 9);
    });
    test('reports an unknown word', () {
      expect(ah(id, 'BCTA').single.message, contains('"BCTA" is not valid'));
    });
    test('reports text after a valid altitude', () {
      final d = ah(id, '700 FT AMSL /');
      expect(d.single.message, contains('Remove "/"'));
      expect(d.single.column, 16);
    });
    test('reports an unknown word after the number', () {
      expect(ah(id, '1000 XYZ').single.message,
          contains('"XYZ" is not a unit or an altitude reference'));
    });
    test('reports the unit after the reference', () {
      expect(ah(id, '1000 AMSL FT').single.message, contains('"1000 FT AMSL"'));
    });
    test('reports a plus sign', () {
      expect(ah(id, '+1000 FT AMSL'), hasLength(1));
    });
    test('reports a unit and a reference without a number', () {
      expect(ah(id, 'FT AMSL').single.message, contains('has no number'));
      expect(ah(id, 'AMSL').single.message, contains('has no number'));
    });
    test('GND alone is not reported', () {
      expect(al(id, 'GND'), isEmpty);
    });
    test('NOTAM in AH suggests UNL, NOTAM in AL suggests GND', () {
      final upper = ah(id, 'NOTAM').single.message;
      expect(upper, contains('"UNL"'));
      expect(upper, isNot(contains('"GND"')));
      final lower = al(id, 'NOTAM').single.message;
      expect(lower, contains('"GND"'));
      expect(lower, isNot(contains('UNL')));
    });
  });

  group('one problem gives one diagnostic', () {
    /// All altitude errors and warnings for an AH value (AL GND).
    List<String> diags(String value) => lintAll(limits('AH $value', 'AL GND'))
        .where((d) =>
            d.ruleId.startsWith('altitude-') && d.severity != Severity.info)
        .map((d) => '${d.ruleId}: ${d.message}')
        .toList();

    test('a comma as the thousands separator', () {
      final d = diags('5,000 FT AMSL');
      expect(d, hasLength(1));
      expect(d.single, startsWith('altitude-invalid'));
      expect(d.single, contains('"5000"'));
      expect(d.single, isNot(contains('"5 FT')));
    });
    test('a space or a no-break space as the thousands separator', () {
      expect(diags('1 000 FT AMSL').single, contains('"1000"'));
      expect(diags('10 000 FT AMSL').single, contains('"10000"'));
      expect(diags('1 000 FT AMSL').single, contains('"1000"'));
    });
    test('the thousands separator gives the right value', () {
      final p = parseAltitude('5,000 FT AMSL');
      expect(p.number, 5000);
      expect(p.suggestion, '5000 FT AMSL');
      final i = p.issuesOf(AltitudeIssueKind.invalid).single;
      expect(i.offset, 0);
      expect(i.length, 5);
      expect(i.replacement, '5000');
    });
    test('a no-break space between the number and the unit', () {
      final d = diags('1000 FT AMSL');
      expect(d.single, contains('U+00A0'));
      expect(parseAltitude('1000 FT AMSL').number, 1000);
    });
    test('the unit two times', () {
      final d = diags('100 FT FT AMSL');
      expect(d.single, contains('Remove "FT"'));
      expect(d.single, contains('more than one unit'));
    });
    test('the reference two times', () {
      expect(diags('100 FT AMSL AMSL').single,
          contains('more than one altitude reference'));
    });
    test('other characters around the unit', () {
      expect(
          diags('1000 (FT) AMSL').single,
          contains('Remove "(" and ")". They are not part of a valid '
              'altitude. Write "1000 FT AMSL".'));
      expect(diags('1000 - FT AMSL').single, contains('Remove "-"'));
    });
    test('a number with a decimal comma', () {
      final d = diags('1,5 FT AMSL');
      expect(d.single, contains('"1,5" is not valid'));
    });
    test('text that adds nothing still reports a missing reference', () {
      final d = diags('1000 FT /');
      expect(d, hasLength(2));
      expect(d, contains(startsWith('altitude-reference-missing')));
      expect(d, contains(contains('Remove "/"')));
    });
    test('text after a valid altitude', () {
      expect(diags('1000 FT AMSL (SFC)').single, contains('Remove "(SFC)"'));
    });
  });

  group('altitude-legacy-keyword', () {
    const id = 'altitude-legacy-keyword';
    test('no diagnostic for GND and UNL', () {
      expect(lintRule(id, limits('AH UNL', 'AL GND')), isEmpty);
    });
    test('reports SFC in AL', () {
      final d = al(id, 'SFC');
      expect(d.single.message, contains('"GND"'));
      expect(d.single.severity, Severity.error);
    });
    test('reports AGL alone in AL', () {
      expect(al(id, 'AGL').single.message, contains('"GND"'));
    });
    test('reports UNLIM and UNLTD in AH', () {
      expect(ah(id, 'UNLIM').single.message, contains('"UNL"'));
      expect(ah(id, 'UNLTD'), hasLength(1));
    });
    test('SFC in AH is reported by altitude-gnd-in-ah instead', () {
      expect(ah(id, 'SFC'), isEmpty);
      expect(ah('altitude-gnd-in-ah', 'SFC'), hasLength(1));
    });
    test('UNLIM in AL is reported by altitude-unl-in-al instead', () {
      expect(al(id, 'UNLIM'), isEmpty);
      expect(al('altitude-unl-in-al', 'UNLIM'), hasLength(1));
    });
  });

  group('altitude-gnd-in-ah', () {
    const id = 'altitude-gnd-in-ah';
    test('no diagnostic for GND in AL', () {
      expect(al(id, 'GND'), isEmpty);
    });
    test('reports GND in AH', () {
      final d = ah(id, 'GND');
      expect(d.single.line, 5);
      expect(d.single.message, contains('swapped'));
    });
  });

  group('altitude-unl-in-al', () {
    const id = 'altitude-unl-in-al';
    test('no diagnostic for UNL in AH', () {
      expect(ah(id, 'UNL'), isEmpty);
    });
    test('reports UNL in AL', () {
      expect(al(id, 'UNL').single.line, 6);
    });
  });

  group('altitude-unit-missing', () {
    const id = 'altitude-unit-missing';
    test('no diagnostic with a unit, or for a flight level', () {
      expect(ah(id, '1000 FT AMSL'), isEmpty);
      expect(ah(id, '300 M AGL'), isEmpty);
      expect(ah(id, 'FL95'), isEmpty);
    });
    test('reports a number without a unit', () {
      final d = ah(id, '1000 AMSL');
      expect(d.single.message, contains('"1000 FT AMSL"'));
      expect(d.single.column, 4);
      expect(d.single.endColumn, 8);
    });
    test('reports "1000MSL" and suggests AMSL', () {
      expect(ah(id, '1000MSL').single.message, contains('"1000 FT AMSL"'));
    });
    test('reports a number alone', () {
      expect(ah(id, '1000'), hasLength(1));
    });
    test('reports AL 0 AGL as an error and says to write AL GND', () {
      final d = al(id, '0 AGL');
      expect(d.single.severity, Severity.error);
      expect(d.single.message, contains('"AL GND"'));
      expect(al('altitude-zero-agl', '0 AGL'), isEmpty);
    });
    test('AL 0 AGL is still an error with --min-severity error', () {
      final d = lintString(limits('AH UNL', 'AL 0 AGL'),
              const LintOptions(minSeverity: Severity.error))
          .where((d) => d.ruleId.startsWith('altitude-'));
      expect(d.map((d) => d.ruleId), ['altitude-unit-missing']);
    });
    test('AH 0 AGL is still reported', () {
      expect(ah(id, '0 AGL'), hasLength(1));
    });
    test('AL 0 GND is reported by altitude-unknown-reference only', () {
      expect(al(id, '0 GND'), isEmpty);
    });
    test('uses the number without separators in the example', () {
      expect(ah(id, '5,000 AMSL').single.message, contains('"5000 FT AMSL"'));
    });
  });

  group('altitude-unknown-unit', () {
    const id = 'altitude-unknown-unit';
    test('no diagnostic for FT and M', () {
      expect(ah(id, '1000 FT AMSL'), isEmpty);
      expect(ah(id, '1000 M AMSL'), isEmpty);
    });
    test('reports F and FEET', () {
      expect(ah(id, '1000 F AMSL').single.message, contains('Write "FT"'));
      expect(ah(id, '1000 FEET AMSL').single.message, contains('Write "FT"'));
      expect(ah(id, '300 METERS AMSL').single.message, contains('Write "M"'));
    });
  });

  group('altitude-reference-missing', () {
    const id = 'altitude-reference-missing';
    test('no diagnostic with a reference', () {
      expect(ah(id, '1000 FT AMSL'), isEmpty);
      expect(ah(id, 'FL95'), isEmpty);
    });
    test('reports a value without a reference', () {
      final d = ah(id, '1000 FT');
      expect(d.single.message, contains('"1000 FT AMSL"'));
      // The position is after the unit, where the reference must be added.
      expect(d.single.column, 11);
    });
    test('reports in version 2.1 too', () {
      expect(ah(id, '1000ft', version: '2.1'), hasLength(1));
    });
  });

  group('altitude-unknown-reference', () {
    const id = 'altitude-unknown-reference';
    test('no diagnostic for AMSL, AGL and STD', () {
      expect(ah(id, '1000 FT AMSL'), isEmpty);
      expect(ah(id, '1000 FT AGL'), isEmpty);
      expect(ah(id, '9500 FT STD'), isEmpty);
    });
    test('reports ALT and ASL', () {
      expect(ah(id, '1000 FT ALT').single.message, contains('Write "AMSL"'));
      expect(ah(id, '1000 FT ASL').single.message, contains('Write "AMSL"'));
    });
    test('MSL is left to altitude-msl-alias', () {
      expect(ah(id, '1000 FT MSL'), isEmpty);
      expect(ah(id, '1000 ft msl'), isEmpty);
    });
    test('reports GND after a number', () {
      final d = ah(id, '1000 FT GND');
      expect(d.single.message, contains('Write "AGL"'));
      expect(d.single.column, 12);
    });
    test('reports an unknown word after the unit', () {
      expect(ah(id, '1000 FT XYZ').single.message, contains('AMSL, AGL'));
    });
  });

  group('altitude-msl-alias', () {
    const id = 'altitude-msl-alias';
    test('no diagnostic for AMSL', () {
      expect(ah(id, '1000 FT AMSL'), isEmpty);
    });
    test('reports MSL as a warning', () {
      final d = ah(id, '1000 FT MSL').single;
      expect(d.severity, Severity.warning);
      expect(d.line, 5);
      expect(d.column, 4 + '1000 FT '.length);
      expect(d.endColumn, 4 + '1000 FT MSL'.length);
      expect(d.message, contains('alias of "AMSL"'));
      expect(d.message, contains('should write "AMSL"'));
    });
    test('MSL is read as AMSL by the other rules', () {
      final text = limits('AH 3000 FT MSL', 'AL 1000 FT AMSL');
      expect(expectedFormat(lintAll(text)), ['5 altitude-msl-alias']);
      expect(
          linesOf('altitude-lower-not-below-upper',
              limits('AH 1000 FT MSL', 'AL 1000 FT AMSL')),
          [6]);
    });
    test('applies to version 2.1 too', () {
      expect(ah(id, '1000 FT MSL', version: '2.1'), hasLength(1));
    });
  });

  group('altitude-multiple-values', () {
    const id = 'altitude-multiple-values';
    test('no diagnostic for one value', () {
      expect(ah(id, '423 M AMSL'), isEmpty);
    });
    test('reports two values', () {
      final d = ah(id, '100 M AGL/423 M AMSL');
      expect(d.single.line, 5);
      expect(d.single.column, 4);
      expect(d.single.endColumn, 24);
    });
    test('a lone slash at the end is not a second value', () {
      expect(ah(id, '700 FT AMSL /'), isEmpty);
    });
  });

  group('altitude-flight-level-invalid', () {
    const id = 'altitude-flight-level-invalid';
    test('no diagnostic for FL95 and FL095', () {
      expect(ah(id, 'FL95'), isEmpty);
      expect(ah(id, 'FL095'), isEmpty);
    });
    test('reports decimals', () {
      expect(ah(id, 'FL95.5').single.message, contains('whole number'));
    });
    test('reports FL without a number', () {
      expect(ah(id, 'FL').single.message, contains('has no number'));
    });
    test('reports a plus sign after FL', () {
      final m = ah(id, 'FL+95').single.message;
      expect(m, isNot(contains('has no number')));
      expect(m, contains('Remove "+"'));
      expect(m, contains('"FL95"'));
    });
    test('reports a word after FL', () {
      expect(ah(id, 'FL XX').single.message, contains('not a whole number'));
    });
    test('reports FL after a number and a unit', () {
      final d = ah(id, '1000 FT FL');
      expect(d.single.message, contains('"FL10"'));
      expect(d.single.message, contains('"1000 FT STD"'));
      expect(ah('altitude-unknown-reference', '1000 FT FL'), isEmpty);
      expect(ah(id, '950 FT FL').single.message, contains('"950 FT STD"'));
    });
    test('reports a number before FL', () {
      expect(ah(id, '95 FL').single.message, contains('"FL95"'));
    });
    test('reports a unit after the flight level', () {
      expect(ah(id, 'FL95 FT').single.message, contains('Remove "FT"'));
    });
  });

  group('altitude-flight-level-space', () {
    const id = 'altitude-flight-level-space';
    test('no diagnostic for FL95', () {
      expect(ah(id, 'FL95'), isEmpty);
    });
    test('reports FL 95 as a warning', () {
      final d = ah(id, 'FL 95');
      expect(d.single.severity, Severity.warning);
      expect(d.single.message, contains('"FL95"'));
    });
    test('FL 95 has the same meaning as FL95 for the other rules', () {
      expect(expectedFormat(lintAll(limits('AH FL 95', 'AL FL65'))),
          ['5 altitude-flight-level-space']);
      expect(
          linesOf('altitude-lower-not-below-upper',
              limits('AH FL 95', 'AL 9500 FT STD')),
          [6]);
    });
  });

  group('altitude-unit-no-space', () {
    const id = 'altitude-unit-no-space';
    test('no diagnostic with a space', () {
      expect(ah(id, '1000 FT AMSL'), isEmpty);
    });
    test('reports 1000FT in version 3.0', () {
      final d = ah(id, '1000FT AMSL');
      expect(d.single.column, 8);
      expect(d.single.message, contains('"1000 FT"'));
    });
    test('allows 1000ft in version 2.1', () {
      expect(ah(id, '1000ft AMSL', version: '2.1'), isEmpty);
    });
  });

  group('altitude-spacing', () {
    const id = 'altitude-spacing';
    test('no diagnostic with one space', () {
      expect(ah(id, '1000 FT AMSL'), isEmpty);
    });
    test('reports two spaces and a tab as info', () {
      final d = ah(id, '1000  FT\tAMSL');
      expect(d, hasLength(2));
      expect(d.first.severity, Severity.info);
    });
  });

  group('altitude-out-of-range', () {
    const id = 'altitude-out-of-range';
    test('no diagnostic for normal values', () {
      expect(ah(id, 'FL660'), isEmpty);
      expect(ah(id, '66000 FT STD'), isEmpty);
      expect(al(id, '-1000 FT AMSL'), isEmpty);
      expect(ah(id, 'UNL'), isEmpty);
    });
    test('reports FL999 and suggests UNL', () {
      final d = ah(id, 'FL999');
      expect(d.single.severity, Severity.warning);
      expect(d.single.message, contains('"AH UNL"'));
    });
    test('reports a high value in metres', () {
      expect(ah(id, '30000 M AMSL').single.message, contains('ft)'));
    });
    test('reports negative AGL and STD values', () {
      expect(al(id, '-100 FT AGL'), hasLength(1));
      expect(al(id, '-32805 FT STD'), hasLength(1));
    });
    test('reports a very low AMSL value', () {
      expect(al(id, '-2000 FT AMSL'), hasLength(1));
    });
  });

  group('altitude-zero-agl', () {
    const id = 'altitude-zero-agl';
    test('no diagnostic for GND or a height', () {
      expect(al(id, 'GND'), isEmpty);
      expect(al(id, '500 FT AGL'), isEmpty);
      expect(al(id, '0 FT AMSL'), isEmpty);
    });
    test('reports AL 0 FT AGL', () {
      final d = al(id, '0 FT AGL');
      expect(d.single.severity, Severity.warning);
      expect(d.single.message, contains('"AL GND"'));
    });
    test('does not report AH', () {
      expect(ah(id, '0 FT AGL'), isEmpty);
    });
    test('AL 0 GND, AL 0 FT GND and AL 0 SFC get one diagnostic', () {
      for (final v in ['0 GND', '0 FT GND', '0 SFC']) {
        final d = lintAll(limits('AH UNL', 'AL $v'))
            .where((d) => d.ruleId.startsWith('altitude-'))
            .toList();
        expect(d, hasLength(1), reason: v);
        expect(d.single.ruleId, 'altitude-unknown-reference', reason: v);
        expect(d.single.severity, Severity.error, reason: v);
        expect(d.single.message, contains('"AL GND"'), reason: v);
      }
    });
  });

  group('altitude-unit-metres', () {
    const id = 'altitude-unit-metres';
    test('no diagnostic for feet, flight levels and zero', () {
      expect(ah(id, '1000 FT AMSL'), isEmpty);
      expect(ah(id, 'FL95'), isEmpty);
      expect(al(id, '0 M AMSL'), isEmpty);
    });
    test('reports metres as info', () {
      final d = ah(id, '1500 M AMSL');
      expect(d.single.severity, Severity.info);
      expect(d.single.message, contains('about 4921 FT'));
    });
    test('does not report an invalid value', () {
      expect(ah(id, '300 M FL'), isEmpty);
    });
  });

  group('altitude-lower-not-below-upper', () {
    const id = 'altitude-lower-not-below-upper';
    List<int> lines(String ah, String al) => linesOf(id, limits(ah, al));

    test('no diagnostic when AL is below AH', () {
      expect(lines('AH FL95', 'AL FL65'), isEmpty);
      expect(lines('AH 3000 FT AMSL', 'AL 1000 FT AMSL'), isEmpty);
      expect(lines('AH 1000 FT AGL', 'AL GND'), isEmpty);
      expect(lines('AH UNL', 'AL FL195'), isEmpty);
    });
    test('reports AL above AH', () {
      final d = lintRule(id, limits('AH FL65', 'AL FL95'));
      expect(d.single.line, 6);
      expect(d.single.message, contains('swapped'));
    });
    test('reports AL equal to AH', () {
      final d = lintRule(id, limits('AH 1000 FT AGL', 'AL 1000 FT AGL'));
      expect(d.single.message, contains('the same'));
    });
    test('compares FL with STD', () {
      expect(lines('AH 9000 FT STD', 'AL FL95'), [6]);
      expect(lines('AH FL95', 'AL 9500 FT STD'), [6]);
    });
    test('converts metres to feet', () {
      expect(lines('AH 300 M AMSL', 'AL 1000 FT AMSL'), [6]);
      expect(lines('AH 400 M AMSL', 'AL 1000 FT AMSL'), isEmpty);
    });
    test('GND is 0 FT AGL', () {
      expect(lines('AH 0 FT AGL', 'AL GND'), [6]);
      expect(lines('AH 0 AGL', 'AL GND'), [6]);
    });
    test('does not compare different references', () {
      expect(lines('AH 3000 FT AMSL', 'AL FL95'), isEmpty);
      expect(lines('AH 1000 FT AGL', 'AL 5000 FT AMSL'), isEmpty);
      expect(lines('AH 1000 FT AMSL', 'AL GND'), isEmpty);
    });
    test('uses old forms with a clear meaning', () {
      expect(lines('AH 1000ft MSL', 'AL 2000 FT AMSL'), [6]);
    });
    test('MSL is AMSL', () {
      expect(lines('AH 2000 FT MSL', 'AL 1000 FT AMSL'), isEmpty);
      expect(lines('AH 1000 FT AMSL', 'AL 1000 FT MSL'), [6]);
    });
    test('9500 FT STD is the same as FL95', () {
      expect(lines('AH FL95', 'AL 9500 FT STD'), [6]);
      expect(lines('AH 9500 FT STD', 'AL FL94'), isEmpty);
      expect(lines('AH FL96', 'AL 9500 FT STD'), isEmpty);
    });
    test('is an error', () {
      expect(lintRule(id, limits('AH FL65', 'AL FL95')).single.severity,
          Severity.error);
    });
    test('does not compare a value without a unit', () {
      expect(lines('AH 1000 AMSL', 'AL 2000 AMSL'), isEmpty);
    });
  });

  group('valid airspace has no altitude diagnostics', () {
    test('all rules of the group', () {
      final ids = {for (final r in allRules) r.id};
      final diags = lintAll(withHeader(validAirspace))
          .where((d) => d.ruleId.startsWith('altitude-'));
      expect(diags, isEmpty);
      expect(ids.where((id) => id.startsWith('altitude-')).length, 19);
    });
  });

  group('the altitude examples of the specification', () {
    // The table "Supported Altitude References" and the section
    // "Altitude" of the specification.
    test('every example is valid', () {
      for (final (ah, al) in [
        ('AH 1500 FT AMSL', 'AL GND'),
        ('AH 1500 FT AMSL', 'AL 300 M AGL'),
        ('AH 9500 FT STD', 'AL 1500 FT AMSL'),
        ('AH FL95', 'AL GND'),
        ('AH UNL', 'AL FL95'),
        ('AH UNL', 'AL 9500 FT STD'),
        ('AH FL100', 'AL GND'),
        ('AH 4500 FT AMSL', 'AL 1000 FT AGL'),
      ]) {
        expect(expectedFormat(lintAll(limits(ah, al))), isEmpty,
            reason: '$ah / $al');
      }
    });
    test('the invalid examples are errors', () {
      expect(linesOf('altitude-unit-missing', limits('AH 1000 AMSL', 'AL GND')),
          [5]);
      expect(
          linesOf('altitude-reference-missing', limits('AH 1000 FT', 'AL GND')),
          [5]);
      expect(findRule('altitude-unit-missing')!.severity, Severity.error);
      expect(findRule('altitude-reference-missing')!.severity, Severity.error);
    });
  });

  group('review fixes', () {
    test('a glued unknown unit is reported once, with both fixes', () {
      expect(ah('altitude-unit-no-space', '7000F AMSL'), isEmpty);
      final d = ah('altitude-unknown-unit', '7000F AMSL').single;
      expect(d.message, contains('Write "FT"'));
      expect(d.message, contains('"7000 FT"'));
      // Version 2.1 allows "7000FT", so it does not ask for a space.
      expect(
          ah('altitude-unknown-unit', '7000F AMSL', version: '2.1')
              .single
              .message,
          isNot(contains('"7000 FT"')));
    });
    test('a glued lower case unit is reported only by altitude-unit-no-space',
        () {
      expect(ah('case-not-upper-case', '4500ft AMSL'), isEmpty);
      expect(ah('altitude-unit-no-space', '4500ft AMSL').single.message,
          contains('"4500 FT"'));
      // Other lower case text on the line is still reported.
      expect(ah('case-not-upper-case', '4500ft amsl').single.message,
          contains('"amsl"'));
    });
    test('numbers that are too large do not crash the rules', () {
      final big = List.filled(400, '9').join();
      for (final v in ['FL$big.5', '$big M AMSL', 'FL$big']) {
        final all = lintAll(withHeader('AC D\nAN T\nAH $v\nAL GND\n'
            'V X=46:00:00N 014:00:00E\nDC 2\n'));
        expect(all.where((d) => d.ruleId == 'linter-internal-error'), isEmpty,
            reason: v);
      }
      expect(
          ah('altitude-unit-metres', '10000000000000000000000000 M AMSL')
              .single
              .message,
          isNot(contains('9223372036854775807')));
    });
  });
}
