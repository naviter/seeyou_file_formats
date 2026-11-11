// Tests for the rules in lib/src/rules/attribute_rules.dart and the helpers
// in lib/src/attributes/attribute_values.dart.
//
// Conformance files for this group are in openair-conformance/valid/attributes/
// and openair-conformance/invalid/attributes/.

import 'dart:io';

import 'package:openair_lint/openair_lint.dart';
import 'package:openair_lint/src/attributes/attribute_values.dart';
import 'package:test/test.dart';

import '../support/helpers.dart';

/// A valid airspace with [attributes] after the AC line. The AC line is
/// line 3, the first attribute is line 4.
String airspace(String attributes, {String ac = 'AC D', String? version}) =>
    withHeader(
        '$ac\n$attributes'
        'AH 4500 FT AMSL\n'
        'AL GND\n'
        'DP 46:00:00N 014:00:00E\n'
        'DP 46:00:00N 014:10:00E\n'
        'DP 45:55:00N 014:10:00E\n'
        'DP 46:00:00N 014:00:00E\n',
        version: version ?? '3.0');

Diagnostic single(String id, String text, {SpecVersion? target}) {
  final d = lintRule(id, text, target: target);
  expect(d, hasLength(1), reason: d.join('\n'));
  return d.single;
}

void main() {
  test('the base airspace has no attribute diagnostics', () {
    final ids = attributeIds();
    final d = lintAll(airspace('AY CTR\nAN Test\nAF 118.480\nAG Test Tower\n'
            'AS AIP+NOTAM\nAX 7000\n'))
        .where((d) => ids.contains(d.ruleId))
        .toList();
    expect(d, isEmpty);
  });

  test('every attribute rule has metadata and a spec URL', () {
    for (final id in attributeIds()) {
      final r = findRule(id)!;
      expect(r.specUrl, startsWith('https://github.com/naviter/'));
    }
    expect(attributeIds(), hasLength(26));
  });

  test('the tables match the specification', () {
    expect(airspaceTypes.toSet(), specTable('#### AY'));
    expect(airspaceClasses.toSet(), specTable('#### AC'));
    expect(airspaceSources.toSet(), specTable('#### AS'));
  });

  group('ac-class-missing', () {
    const id = 'ac-class-missing';
    test('valid class', () => expect(lintRule(id, airspace('')), isEmpty));
    test('empty AC', () {
      final d = single(id, airspace('', ac: 'AC'));
      expect(d.line, 3);
      expect(d.column, 1);
      expect(d.severity, Severity.error);
    });
    test('AC with only a comment', () {
      expect(linesOf(id, airspace('', ac: 'AC * no class')), [3]);
    });
  });

  group('ac-unknown-class', () {
    const id = 'ac-unknown-class';
    test('all classes are valid', () {
      for (final c in airspaceClasses) {
        expect(lintRule(id, airspace('', ac: 'AC $c')), isEmpty, reason: c);
      }
    });
    test('lower case class is not unknown', () {
      expect(lintRule(id, airspace('', ac: 'AC d')), isEmpty);
    });
    test('empty AC is reported by ac-class-missing only', () {
      expect(lintRule(id, airspace('', ac: 'AC')), isEmpty);
    });
    test('old type in AC: suggests AC UNC and AY', () {
      final d = single(id, airspace('', ac: 'AC R'));
      expect(d.line, 3);
      expect(d.column, 4);
      expect(d.endColumn, 5);
      expect(d.message, contains('"R" is an airspace type, not a class'));
      expect(d.message, contains('"AC UNC"'));
      expect(d.message, contains('"AY R"'));
    });
    test('long old names are mapped to the AY type', () {
      expect(single(id, airspace('', ac: 'AC RESTRICTED')).message,
          contains('"AY R"'));
      expect(single(id, airspace('', ac: 'AC DANGER')).message,
          contains('"AY Q"'));
      expect(single(id, airspace('', ac: 'AC OVERFLIGHT_RESTRICTION')).message,
          contains('"AY OFR"'));
    });
    test('unclassified aliases suggest AC UNC', () {
      for (final v in ['UNCLASSIFIED', 'UKN', 'UNKNOWN']) {
        final d = single(id, airspace('', ac: 'AC $v'));
        expect(d.message, contains('write "AC UNC"'), reason: v);
        expect(d.message, isNot(contains('AY')), reason: v);
      }
    });
    test('uncertain old values give the closest type', () {
      final d = single(id, airspace('', ac: 'AC W'));
      expect(d.message, contains('probably "AY GSEC"'));
    });
    test('unknown value without a hint lists the classes', () {
      final d = single(id, airspace('', ac: 'AC XYZ'));
      expect(d.message, contains('A, B, C, D, E, F, G and UNC'));
    });
    test('an existing AY is mentioned', () {
      final d = single(id, airspace('AY CTR\n', ac: 'AC CTR'));
      expect(d.message, contains('already in "AY CTR"'));
    });
    test('an AY synonym of the same type is the same type', () {
      final d = single(id, airspace('AY RESTRICTED\n', ac: 'AC R'));
      expect(d.message, contains('already in "AY RESTRICTED"'));
    });
    test('a different type in AY is mentioned', () {
      final d = single(id, airspace('AY Q\n', ac: 'AC R'));
      expect(d.message, contains('It means "AY R"'));
      expect(d.message, contains('"AY Q" on line 4 gives a different type'));
      expect(d.message, isNot(contains('already')));
    });
    test('two classes in one AC', () {
      for (final (v, first) in [('D E', 'D'), ('C/D', 'C'), ('D,E', 'D')]) {
        final d = single(id, airspace('', ac: 'AC $v'));
        expect(d.message, contains('"$v" has more than one class'), reason: v);
        expect(d.message, contains('"AC $first"'), reason: v);
        expect(d.message, isNot(contains('Old files')), reason: v);
      }
    });
    test('applies to version 2.1', () {
      expect(linesOf(id, airspace('', ac: 'AC Q', version: '2.1')), [3]);
    });
    test('the comment after the class is not part of the class', () {
      expect(lintRule(id, airspace('', ac: 'AC D * class D')), isEmpty);
    });
  });

  group('ay-type-missing', () {
    const id = 'ay-type-missing';
    test('valid', () => expect(lintRule(id, airspace('AY CTR\n')), isEmpty));
    test('empty AY', () => expect(linesOf(id, airspace('AY\n')), [4]));
  });

  group('ay-unknown-type', () {
    const id = 'ay-unknown-type';
    test('all types from the table are valid', () {
      for (final t in airspaceTypes) {
        expect(lintRule(id, airspace('AY $t\n')), isEmpty, reason: t);
      }
    });
    test('synonym', () {
      final d = single(id, airspace('AY RESTRICTED\n'));
      expect(d.line, 4);
      expect(d.column, 4);
      expect(d.message, contains('Write "AY R"'));
    });
    test('class letter in AY', () {
      expect(single(id, airspace('AY D\n')).message,
          contains('"D" is an airspace class'));
    });
    test('UNCLASSIFIED in AY suggests NONE', () {
      expect(single(id, airspace('AY UNCLASSIFIED\n')).message,
          contains('"AY NONE"'));
    });
    test('guess', () {
      expect(single(id, airspace('AY MRT\n')).message,
          contains('probably "AY MTR"'));
    });
    test('unknown without hint', () {
      expect(single(id, airspace('AY FOO\n')).message,
          contains('Use a type from the table'));
    });
    test('lower case type is not unknown', () {
      expect(lintRule(id, airspace('AY ctr\n')), isEmpty);
    });
  });

  group('ay-not-after-ac', () {
    const id = 'ay-not-after-ac';
    test('directly after AC', () {
      expect(lintRule(id, airspace('AY CTR\nAN Test\n')), isEmpty);
    });
    test('after AN', () {
      final d = single(id, airspace('AN Test\nAY CTR\n'));
      expect(d.line, 5);
      expect(d.severity, Severity.info);
    });
    test('comment lines between AC and AY do not matter', () {
      expect(lintRule(id, airspace('* comment\nAY CTR\n')), isEmpty);
    });
    test('no AY', () => expect(lintRule(id, airspace('AN Test\n')), isEmpty));
  });

  group('an-name-empty', () {
    const id = 'an-name-empty';
    test('valid', () => expect(lintRule(id, airspace('AN Test\n')), isEmpty));
    test('empty', () => expect(linesOf(id, airspace('AN\n')), [4]));
    test('only spaces', () => expect(linesOf(id, airspace('AN   \n')), [4]));
  });

  group('an-name-too-long', () {
    const id = 'an-name-too-long';
    test('100 characters is fine', () {
      expect(lintRule(id, airspace('AN ${'x' * 100}\n')), isEmpty);
    });
    test('101 characters', () {
      final d = single(id, airspace('AN ${'x' * 101}\n'));
      expect(d.message, contains('101 characters'));
      expect(d.severity, Severity.info);
    });
  });

  group('names with special characters', () {
    // The file is UTF-8, so a name can use any character except "*". A
    // correct name gets no message, also not from file-garbled-text.
    for (final name in [
      'CTR PORTOROŽ',
      'CTR München',
      'Úštěk',
      'NÍŽINA',
      'ТМА',
    ]) {
      test(name, () {
        final found = lintString(airspace('AN $name\n'))
            .where((d) => d.ruleId != 'header-version-draft');
        expect(found.map((d) => '${d.ruleId}: ${d.message}'), isEmpty);
      });
    }
  });

  group('an-contains-asterisk', () {
    const id = 'an-contains-asterisk';
    test('a name without "*"', () {
      expect(lintRule(id, airspace('AN EKR664 ZONE 1 (NOTAM)\n')), isEmpty);
    });
    test('a comment on its own line is allowed', () {
      expect(
          lintRule(id, airspace('* part in France\nAN TRA AREA\n')), isEmpty);
    });
    test('a comment after the name is an error', () {
      final d = single(id, airspace('AN TRA AREA * part in France\n'));
      expect(d.severity, Severity.error);
      expect(d.line, 4);
      expect(d.column, 4 + 'TRA AREA '.length);
      expect(d.endColumn, 4 + 'TRA AREA * part in France'.length);
      expect(d.message, contains('the name ends before the "*"'));
      expect(d.message, contains('only the name "TRA AREA"'));
      expect(d.message, contains('not allowed on the same line as AN'));
      expect(d.message, contains('own line: "* part in France"'));
    });
    test('every "*" is reported, also decoration and a "*" alone', () {
      expect(linesOf(id, airspace('AN TRA AREA   ** note\n')), [4]);
      expect(linesOf(id, airspace('AN TRA AREA *\n')), [4]);
      expect(single(id, airspace('AN TRA AREA *\n')).message,
          endsWith('Remove the "*".'));
      expect(linesOf(id, airspace('AN TRA AREA (EAST) * note\n')), [4]);
      expect(
          linesOf(id, airspace('AN Wien CTR * source: AIP *AMDT 3*\n')), [4]);
    });
    test('a word in stars: the fix removes the stars', () {
      final d = single(id, airspace('AN EKR664 ZONE 1 (*NOTAM*)\n'));
      expect(d.column, 4 + 'EKR664 ZONE 1 ('.length);
      expect(d.endColumn, 4 + 'EKR664 ZONE 1 (*NOTAM*)'.length);
      expect(d.message, contains('only the name "EKR664 ZONE 1 ("'));
      expect(d.message, contains('"AN EKR664 ZONE 1 (NOTAM)"'));
    });
    test('no blank before the star', () {
      final d =
          single(id, airspace('AN XX-MTA ALPHA* MTA ALPHAVILLE FL140/GND\n'));
      expect(d.message, contains('only the name "XX-MTA ALPHA"'));
      expect(d.message, contains('"AN XX-MTA ALPHA MTA ALPHAVILLE FL140/GND"'));
    });
    test('a second star later in the line', () {
      final d = single(
          id,
          airspace(
              'AN EXAMPLE/FIELD 118.7 *TWR HRS-SEE AIP* XX (XXXX) CERT\n'));
      expect(d.message, contains('only the name "EXAMPLE/FIELD 118.7"'));
      expect(
          d.message,
          contains('"AN EXAMPLE/FIELD 118.7 TWR HRS-SEE AIP XX (XXXX) '
              'CERT"'));
    });
    test('an unclosed bracket before the star', () {
      expect(single(id, airspace('AN TRA AREA (* NOTAM)\n')).message,
          contains('"AN TRA AREA ( NOTAM)"'));
      expect(linesOf(id, airspace('AN TRA AREA [ * EAST]\n')), [4]);
    });
    test('an empty name', () {
      final d = single(id, airspace('AN *NOTAM*\n'));
      expect(d.message, contains('readers show an empty name'));
      expect(d.message, contains('"AN NOTAM"'));
      expect(linesOf('an-name-empty', airspace('AN *NOTAM*\n')), [4]);
    });
    test('applies only to version 3.0', () {
      expect(linesOf(id, airspace('AN A * B\n', version: '2.1')), isEmpty);
      expect(linesOf(id, airspace('AN A * B\n'), target: SpecVersion.v2_1),
          isEmpty);
    });
  });

  group('ag-contains-asterisk', () {
    const id = 'ag-contains-asterisk';
    test('a station name without "*"', () {
      expect(lintRule(id, airspace('AG Langen Information\n')), isEmpty);
    });
    test('a comment after the station name is an error', () {
      final d = single(id, airspace('AG Langen Information * FIS\n'));
      expect(d.severity, Severity.error);
      expect(d.message, contains('only the station name "Langen Information"'));
      expect(d.message, contains('not allowed on the same line as AG'));
      expect(d.message, contains('own line: "* FIS"'));
    });
    test('a word in stars', () {
      final d = single(id, airspace('AG Langen Information (*FIS*)\n'));
      expect(d.message, contains('only the station name'));
      expect(d.message, contains('"AG Langen Information (FIS)"'));
    });
    test('AN is not checked by the AG rule', () {
      expect(lintRule(id, airspace('AN A (*B*)\n')), isEmpty);
    });
  });

  group('af-invalid-format', () {
    const id = 'af-invalid-format';
    test('valid', () {
      expect(lintRule(id, airspace('AF 123.300\n')), isEmpty);
      expect(lintRule(id, airspace('AF 123.3\n')), isEmpty);
    });
    test('empty', () {
      expect(single(id, airspace('AF\n')).message, contains('no frequency'));
    });
    test('comma', () {
      final d = single(id, airspace('AF 123,300\n'));
      expect(d.message, contains('"AF 123.300"'));
      expect(d.column, 4);
    });
    test('unit', () {
      expect(single(id, airspace('AF 123.300 MHz\n')).message,
          contains('without a unit: "AF 123.300"'));
    });
    test('two frequencies', () {
      for (final v in [
        '123.300/124.500',
        '123.300 124.500',
        '123.300,124.500',
        '123,3 124,5',
      ]) {
        final d = single(id, airspace('AF $v\n'));
        expect(d.message, contains('more than one'), reason: v);
        expect(d.message, contains('"AF 123.3'), reason: v);
        expect(d.message, contains('one AF command for each frequency'),
            reason: v);
        expect(d.message, contains('and "AF 124.5'), reason: v);
        expect(d.message, isNot(contains('main frequency')), reason: v);
      }
    });
    test('three frequencies', () {
      final d = single(id, airspace('AF 123.500 124.000 125.000\n'));
      expect(
          d.message,
          endsWith('Write one AF command for each frequency: "AF 123.500", '
              '"AF 124.000" and "AF 125.000".'));
    });
    test('one frequency and other text', () {
      final d = single(id, airspace('AF 122.100 INFO\n'));
      expect(d.message, contains('also has other text'));
      expect(d.message, contains('"AF 122.100"'));
    });
    test('a number in scientific notation is one value, not two', () {
      final d = single(id, airspace('AF 1.23E2\n'));
      expect(d.message, contains('is not a frequency'));
      expect(d.message, isNot(contains('more than one')));
    });
    test('text', () {
      expect(single(id, airspace('AF Langen Information\n')).message,
          contains('is not a frequency'));
    });
  });

  group('af-outside-air-band', () {
    const id = 'af-outside-air-band';
    test('band edges', () {
      expect(lintRule(id, airspace('AF 118.000\n')), isEmpty);
      expect(lintRule(id, airspace('AF 136.990\n')), isEmpty);
    });
    test('below', () {
      final d = single(id, airspace('AF 114.880\n'));
      expect(d.severity, Severity.error);
      expect(d.message, contains('outside the VHF air band'));
    });
    test('above', () {
      expect(linesOf(id, airspace('AF 137.000\n')), [4]);
      expect(linesOf(id, airspace('AF 243.000\n')), [4]);
    });
    test('kHz value', () {
      expect(single(id, airspace('AF 123300\n')).message,
          contains('"AF 123.300"'));
    });
    test('bad format is left to af-invalid-format', () {
      expect(lintRule(id, airspace('AF 99,5\n')), isEmpty);
    });
  });

  group('af-invalid-channel', () {
    const id = 'af-invalid-channel';
    test('25 kHz and 8.33 kHz channel names', () {
      for (final f in [
        '118.000',
        '118.005',
        '118.010',
        '118.015',
        '118.025',
        '123.455',
        '136.990',
        '126.1',
        '120.53'
      ]) {
        expect(lintRule(id, airspace('AF $f\n')), isEmpty, reason: f);
      }
    });
    test('not a channel', () {
      final d = single(id, airspace('AF 123.456\n'));
      expect(d.message, contains('123.455 and 123.460'));
    });
    test('ending 20', () => expect(linesOf(id, airspace('AF 118.020\n')), [4]));
    test('the examples of the specification', () {
      expect(lintRule(id, airspace('AF 123.505\n')), isEmpty);
      expect(lintRule(id, airspace('AF 123.300\n')), isEmpty);
      expect(lintRule(id, airspace('AF 118.005\n')), isEmpty);
      expect(linesOf(id, airspace('AF 123.520\n')), [4]);
      expect(linesOf(id, airspace('AF 123.456\n')), [4]);
    });
    test('two decimals that lost the last digit', () {
      expect(single(id, airspace('AF 122.47\n')).message,
          contains('"AF 122.475"'));
    });
    test('outside the band is left to af-outside-air-band', () {
      expect(lintRule(id, airspace('AF 114.123\n')), isEmpty);
    });
    test('more than three decimals: zeros at the end are ignored', () {
      expect(lintRule(id, airspace('AF 122.4750\n')), isEmpty);
      expect(linesOf(id, airspace('AF 118.02000\n')), [4]);
    });
    test('more than three decimals: the real frequency of a channel', () {
      // 118.0083 is the real frequency of the 8.33 kHz channel 118.010.
      expect(lintRule(id, airspace('AF 118.0083\n')), isEmpty);
      expect(lintRule(id, airspace('AF 118.01667\n')), isEmpty);
      expect(lintRule(id, airspace('AF 122.4751\n')), isEmpty);
    });
    test('more than three decimals: not near a channel', () {
      final d = single(id, airspace('AF 123.4567\n'));
      expect(d.severity, Severity.error);
      expect(d.message, contains('The nearest channel name is 123.460'));
    });
  });

  group('af-not-three-decimals', () {
    const id = 'af-not-three-decimals';
    test('three decimals', () {
      expect(lintRule(id, airspace('AF 126.100\n')), isEmpty);
    });
    test('one decimal', () {
      final d = single(id, airspace('AF 126.1\n'));
      expect(d.severity, Severity.error);
      expect(d.message, contains('"AF 126.100"'));
    });
    test('no decimals', () {
      expect(
          single(id, airspace('AF 126\n')).message, contains('"AF 126.000"'));
    });
    test('four decimals: the real frequency of a channel', () {
      final d = single(id, airspace('AF 118.0083\n'));
      expect(d.message, contains('channel 118.010'));
      expect(d.message, contains('"AF 118.010"'));
    });
    test('four decimals: one zero too many', () {
      expect(single(id, airspace('AF 122.4750\n')).message,
          contains('"AF 122.475"'));
    });
    test('a value that is not a channel is left to af-invalid-channel', () {
      // The padded value 122.470 is not a channel name, so this rule would
      // suggest a wrong fix.
      expect(lintRule(id, airspace('AF 122.47\n')), isEmpty);
      expect(lintRule(id, airspace('AF 122.42\n')), isEmpty);
      expect(lintRule(id, airspace('AF 123.4567\n')), isEmpty);
    });
    test('one diagnostic for each wrong value', () {
      for (final v in ['122.47', '123.4567', '118.0083', '122.4750']) {
        final d = lintAll(airspace('AF $v\n'))
            .where((d) => d.ruleId.startsWith('af-'))
            .toList();
        expect(d, hasLength(1), reason: '$v: ${d.join('\n')}');
        expect(d.single.severity, Severity.error, reason: v);
      }
    });
    test('applies only to version 3.0', () {
      expect(lintRule(id, airspace('AF 126.1\n', version: '2.1')), isEmpty);
    });
  });

  group('ag-station-empty', () {
    const id = 'ag-station-empty';
    test('valid', () => expect(lintRule(id, airspace('AG Tower\n')), isEmpty));
    test('empty', () => expect(linesOf(id, airspace('AG\n')), [4]));
  });

  group('ag-station-is-frequency', () {
    const id = 'ag-station-is-frequency';
    test('name', () {
      expect(lintRule(id, airspace('AG Langen Radar 2\n')), isEmpty);
    });
    test('frequency', () {
      final d = single(id, airspace('AG 118.655\n'));
      expect(d.severity, Severity.warning);
      expect(d.message, contains('Put the frequency in AF'));
    });
  });

  group('airspaceSourceCorrection', () {
    test('gives the value for the right sources in a wrong form', () {
      for (final (value, correct) in [
        ('AIP + NOTAM', 'AIP+NOTAM'),
        ('AIP,NOTAM', 'AIP+NOTAM'),
        ('AIP NOTAM', 'AIP+NOTAM'),
        ('NOTAM+AIP', 'AIP+NOTAM'),
        ('notam/aip', 'AIP+NOTAM'),
        ('AIP+NOTAM+AIP', 'AIP+NOTAM'),
        ('AIP+', 'AIP'),
        (' CUSTOM+', 'CUSTOM'),
      ]) {
        expect(airspaceSourceCorrection(value), correct, reason: value);
      }
    });
    test('is null for a correct value or no single correct value', () {
      for (final value in [
        'AIP',
        'AIP+NOTAM',
        'aip+notam',
        'NOTAM+CUSTOM',
        'AIP+NOTAM+CUSTOM',
        'AIC',
        '',
      ]) {
        expect(airspaceSourceCorrection(value), isNull, reason: value);
      }
    });
  });

  group('as-source-missing', () {
    const id = 'as-source-missing';
    test('fires for AS without a value', () {
      final d = single(id, airspace('AS\n'));
      expect(d.line, 4);
      expect(d.severity, Severity.error);
    });
    test('fires for AS with only a separator', () {
      expect(linesOf(id, airspace('AS +\n')), [4]);
      expect(lintRule('as-unknown-source', airspace('AS +\n')), isEmpty);
    });
    test('does not fire for a source', () {
      expect(lintRule(id, airspace('AS NOTAM\n')), isEmpty);
    });
  });

  group('as-unknown-source', () {
    const id = 'as-unknown-source';
    test('valid values', () {
      for (final v in ['AIP', 'NOTAM', 'AIP+NOTAM', 'CUSTOM']) {
        expect(lintRule(id, airspace('AS $v\n')), isEmpty, reason: v);
      }
    });
    test('lower case is left to case-not-upper-case', () {
      final text = airspace('AS aip+notam\n');
      expect(lintRule(id, text), isEmpty);
      expect(linesOf('case-not-upper-case', text), [4]);
    });
    test('the right sources in a wrong form have a fix', () {
      for (final v in ['AIP + NOTAM', 'NOTAM+AIP', 'AIP,NOTAM', 'AIP+']) {
        final d = single(id, airspace('AS $v\n'));
        expect(d.fix, isNotNull, reason: v);
        expect(d.message, contains('Write "AS '), reason: v);
      }
    });
    test('other combinations are not allowed', () {
      for (final v in ['NOTAM+CUSTOM', 'AIP+CUSTOM', 'AIP+NOTAM+CUSTOM']) {
        final d = single(id, airspace('AS $v\n'));
        expect(d.fix, isNull, reason: v);
        expect(d.message, contains('The only combination is AIP+NOTAM'),
            reason: v);
      }
    });
    test('an unknown word has a hint and no fix', () {
      final d = single(id, airspace('AS AIP-SUP\n'));
      expect(d.message, contains('write "AIP"'));
      expect(d.fix, isNull);
      expect(single(id, airspace('AS AIC\n')).message,
          contains('"AIC" is not a value of AS'));
    });
  });

  group('as-needs-version-3', () {
    const id = 'as-needs-version-3';
    test('fires for AS in a file of version 2.1', () {
      final text = airspace('AS NOTAM\n', version: '2.1');
      final d = single(id, text);
      expect(d.line, 4);
      expect(d.severity, Severity.error);
      expect(linesOf('command-unknown', text), isEmpty);
    });
    test('does not fire in a file of version 3.0', () {
      expect(lintRule(id, airspace('AS NOTAM\n')), isEmpty);
    });
  });

  group('AS in other rules', () {
    test('two AS commands are a duplicate attribute', () {
      expect(
          linesOf(
              'airspace-attribute-duplicate', airspace('AS AIP\nAS NOTAM\n')),
          [5]);
    });
    test('two AS commands in version 2.1 are reported only as AS', () {
      final text = airspace('AS AIP\nAS NOTAM\n', version: '2.1');
      expect(linesOf('airspace-attribute-duplicate-v21', text), isEmpty);
      expect(linesOf('as-needs-version-3', text), [4, 5]);
    });
    test('AS is not an unknown command', () {
      expect(linesOf('command-unknown', airspace('AS NOTAM\n')), isEmpty);
    });
  });

  group('ax-not-four-digits', () {
    const id = 'ax-not-four-digits';
    test('valid', () {
      expect(lintRule(id, airspace('AX 7000\n')), isEmpty);
      expect(lintRule(id, airspace('AX 0424\n')), isEmpty);
    });
    test('empty', () {
      expect(single(id, airspace('AX\n')).message, contains('no transponder'));
    });
    test('three digits suggests the zero', () {
      expect(single(id, airspace('AX 424\n')).message, contains('"AX 0424"'));
    });
    test('no zeros are suggested when the digit 8 or 9 is in the code', () {
      final d = single(id, airspace('AX 488\n'));
      expect(d.message, isNot(contains('"AX 0488"')));
      expect(d.message, contains('only the digits 0 to 7'));
    });
    test('five digits', () => expect(linesOf(id, airspace('AX 70000\n')), [4]));
    test('other characters', () {
      expect(single(id, airspace('AX A7000\n')).message,
          contains('other characters'));
    });
  });

  group('ax-not-octal', () {
    const id = 'ax-not-octal';
    test('octal', () => expect(lintRule(id, airspace('AX 7777\n')), isEmpty));
    test('8 and 9', () {
      expect(linesOf(id, airspace('AX 4810\n')), [4]);
      expect(linesOf(id, airspace('AX 0009\n')), [4]);
    });
    test('is an error: transponder codes are octal', () {
      expect(single(id, airspace('AX 4810\n')).severity, Severity.error);
    });
    test('wrong length is left to ax-not-four-digits', () {
      expect(lintRule(id, airspace('AX 89\n')), isEmpty);
    });
  });

  group('ax-emergency-code', () {
    const id = 'ax-emergency-code';
    test('normal code', () {
      expect(lintRule(id, airspace('AX 7000\n')), isEmpty);
    });
    test('emergency codes', () {
      for (final c in ['7500', '7600', '7700']) {
        expect(linesOf(id, airspace('AX $c\n')), [4], reason: c);
      }
    });
  });

  group('helpers', () {
    test('parseFrequency', () {
      final f = parseFrequency('123.45')!;
      expect(f.khz, 123450);
      expect(f.decimals, 2);
      expect(f.threeDecimals, '123.450');
      expect(parseFrequency('123,45'), isNull);
      expect(parseFrequency('118.0083')!.khz, isNull);
      final zeros = parseFrequency('122.4750')!;
      expect(zeros.khz, 122475);
      expect(zeros.decimals, 4);
      expect(zeros.channelKhz, 122475);
    });
    test('channelKhz', () {
      expect(parseFrequency('118.005')!.channelKhz, 118005);
      expect(parseFrequency('118.020')!.channelKhz, isNull);
      expect(parseFrequency('118.0083')!.channelKhz, 118010);
      expect(parseFrequency('118.0167')!.channelKhz, 118015);
      expect(parseFrequency('118.0249')!.channelKhz, 118025);
      expect(parseFrequency('123.4567')!.channelKhz, isNull);
    });
    test('nearestChannelByFrequency', () {
      expect(nearestChannelByFrequency(118008.33).$1, 118010);
      expect(nearestChannelByFrequency(118016.67).$1, 118015);
      expect(nearestChannelByFrequency(118049.9).$1, 118050);
      expect(nearestChannelByFrequency(123456.7).$1, 123460);
      expect(nearestChannelByFrequency(123456.7).$2, closeTo(1.63, 0.01));
    });
    test('nearestChannelNames', () {
      expect(nearestChannelNames(118020), (118015, 118025));
      expect(nearestChannelNames(118045), (118040, 118050));
    });
    test('frequencyFormatProblem', () {
      expect(frequencyFormatProblem('123.300'), isNull);
      expect(frequencyFormatProblem('1.23E2'), contains('is not a frequency'));
      expect(
          frequencyFormatProblem('123.300/124.500'), contains('more than one'));
    });
    test('isValidAttributeValue', () {
      expect(isValidAttributeValue('AC', 'D'), isTrue);
      expect(isValidAttributeValue('AC', 'R'), isFalse);
      expect(isValidAttributeValue('AY', 'CTR'), isTrue);
      expect(isValidAttributeValue('AY', 'RESTRICTED'), isFalse);
      expect(isValidAttributeValue('AF', '123.300'), isTrue);
      expect(isValidAttributeValue('AF', '123.300MHZ'), isFalse);
      expect(isValidAttributeValue('AX', '7000'), isTrue);
      expect(isValidAttributeValue('AX', '7000 SQUAWK'), isFalse);
      expect(isValidAttributeValue('AN', 'anything'), isTrue);
    });
    test('typeHintFor', () {
      expect(typeHintFor('CTR')!.type, 'CTR');
      expect(typeHintFor('DANGER')!.certain, isTrue);
      expect(typeHintFor('W')!.certain, isFalse);
      expect(typeHintFor('X'), isNull);
    });
    test('findDoubleEncoding: Windows-1252', () {
      final d = findDoubleEncoding('AUGUSTÃ“W')!;
      expect(d.repaired, 'AUGUSTÓW');
      expect(d.offset, 6);
      expect(d.end, 8);
    });
    test('findDoubleEncoding: Latin-1 and three byte characters', () {
      expect(findDoubleEncoding('DÃ¼BENDORF')!.repaired, 'DüBENDORF');
      // "–" (E2 80 93) read as Windows-1252 is "â€“".
      expect(findDoubleEncoding('A â€“ B')!.repaired, 'A – B');
    });
    test('findDoubleEncoding: normal names', () {
      for (final name in [
        'SÃO PAULO',
        'Tromsø TMA',
        'Ørland',
        'Århus',
        'Úštěk',
        'NÍŽINA',
        'ÚŽINA',
        'Í–X',
        'Ý‘A',
        'Ü€',
        'ß–',
      ]) {
        expect(findDoubleEncoding(name), isNull, reason: name);
      }
    });
    test('findDoubleEncoding: common garbled text is still found', () {
      expect(findDoubleEncoding('VÃ–SLAU')!.repaired, 'VÖSLAU');
      expect(findDoubleEncoding('WÃ¢NSWERT')!.repaired, 'WâNSWERT');
      expect(findDoubleEncoding('Å IAULIAI')!.repaired, 'ŠIAULIAI');
      expect(findDoubleEncoding('45Â°N')!.repaired, '45°N');
    });
    test('isPlausibleRepairedChar', () {
      expect(isPlausibleRepairedChar('Ö'.runes.first), isTrue);
      expect(isPlausibleRepairedChar('Ж'.runes.first), isTrue);
      expect(isPlausibleRepairedChar(0x2013), isTrue);
      expect(isPlausibleRepairedChar(0x069A), isFalse); // Arabic
      expect(isPlausibleRepairedChar(0x034E), isFalse); // combining mark
      expect(isPlausibleRepairedChar(0x0085), isFalse); // control character
    });
  });

  group('version 3.0 case', () {
    test('lower case values are left to case-not-upper-case', () {
      final text = airspace('AY ctr\nAN Test\nAF 118.480\n', ac: 'AC d');
      final ids = attributeIds();
      expect(lintAll(text).where((d) => ids.contains(d.ruleId)), isEmpty);
      expect(linesOf('case-not-upper-case', text), [3, 4]);
    });
    test('a unit after AF is reported only by af-invalid-format', () {
      final text = airspace('AF 123.500 MHz\nAX 7000 mode s\n');
      expect(linesOf('af-invalid-format', text), [4]);
      expect(linesOf('ax-not-four-digits', text), [5]);
      expect(linesOf('case-not-upper-case', text), isEmpty);
      // A valid value in lower case is still reported.
      expect(linesOf('case-not-upper-case', airspace('AY ctr\n')), [4]);
    });
  });

  group('version 2.1 parts (-v21)', () {
    String v21(String attributes) => airspace(attributes, version: '2.1');

    test('"*" in AN and AG is a warning in version 2.1', () {
      final text = v21('AN TMA *TWR* 118.7\nAG Station * note\n');
      final an = single('an-contains-asterisk-v21', text);
      expect(an.severity, Severity.warning);
      expect(an.line, 4);
      expect(an.message, contains('only the name "TMA"'));
      // The 2.1 text does not forbid a comment after AN.
      expect(an.message, isNot(contains('not allowed')));
      expect(an.specUrl, contains('v2.1.5'));
      final ag = single('ag-contains-asterisk-v21', text);
      expect(ag.severity, Severity.warning);
      expect(ag.line, 5);
      expect(linesOf('an-contains-asterisk', text), isEmpty);
      expect(linesOf('ag-contains-asterisk', text), isEmpty);
    });
    test('the -v21 rules do not check version 3.0 files', () {
      final text = airspace('AN TMA *TWR*\nAG Station * note\n');
      expect(linesOf('an-contains-asterisk', text), [4]);
      expect(linesOf('an-contains-asterisk-v21', text), isEmpty);
      expect(linesOf('ag-contains-asterisk-v21', text), isEmpty);
    });
    test('AF and AX values are warnings in version 2.1', () {
      final text = v21('AF 123.520\nAF 140.000\nAX 7778\n');
      for (final (id, line) in [
        ('af-invalid-channel-v21', 4),
        ('af-outside-air-band-v21', 5),
        ('ax-not-octal-v21', 6),
      ]) {
        final d = single(id, text);
        expect(d.severity, Severity.warning, reason: id);
        expect(d.line, line, reason: id);
        expect(d.message, endsWith('In version 3.0 this is an error.'),
            reason: id);
        final base = id.replaceFirst('-v21', '');
        expect(lintRule(base, text), isEmpty, reason: base);
        expect(lintRule(id, airspace('AF 123.520\nAF 140.000\nAX 7778\n')),
            isEmpty,
            reason: '$id in a 3.0 file');
      }
    });
    test('AF with one or two decimals is not checked in version 2.1', () {
      expect(lintRule('af-not-three-decimals', v21('AF 123.5\n')), isEmpty);
    });
    test('every -v21 rule checks only version 2.1', () {
      for (final r in allRules.where((r) => r.id.endsWith('-v21'))) {
        expect(r.versions, SpecVersion.only21, reason: r.id);
        final base = findRule(r.id.replaceFirst(RegExp(r'-v21$'), ''));
        expect(base, isNotNull, reason: r.id);
        expect(base!.versions, SpecVersion.only3, reason: base.id);
      }
    });
  });
}

/// The IDs of all rules in the attributes group.
Set<String> attributeIds() => {
      for (final g in ruleGroups)
        if (g.name == 'attributes') ...g.rules.map((r) => r.id)
    };

/// The first column of the table in the spec section that starts with
/// [heading] (for example `#### AY`).
Set<String> specTable(String heading) {
  final lines = File('../OpenAir_File_Format_Support.md').readAsLinesSync();
  final start = lines.indexWhere((l) => l.startsWith(heading));
  final result = <String>{};
  for (final l in lines.skip(start + 1)) {
    if (l.startsWith('#')) break;
    final m = RegExp(r'^\|\s*([A-Z+]+)\s*\|').firstMatch(l);
    if (m != null) result.add(m.group(1)!);
  }
  return result;
}
