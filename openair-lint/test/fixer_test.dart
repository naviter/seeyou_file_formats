import 'dart:convert';

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

/// A valid airspace without a header, for the tests below.
const String _body = 'AC D\n'
    'AN Test CTR\n'
    'AH 4500 FT AMSL\n'
    'AL GND\n'
    'DP 46:00:00N 014:00:00E\n'
    'DP 46:00:00N 014:10:00E\n'
    'DP 45:55:00N 014:10:00E\n'
    'DP 45:55:00N 014:00:00E\n'
    'DP 46:00:00N 014:00:00E\n';

const String _header = '*VERSION: 2.1\n*WRITTEN_BY: test\n';

/// Fixes [text] with all rules (or only [rules]) and returns the fixed text.
String fix(String text,
    {List<String>? rules, SpecVersion? target, Severity? minSeverity}) {
  final linter = Linter(LintOptions(
    target: target,
    rules: rules?.map((id) => findRule(id)!).toList(),
    minSeverity: minSeverity ?? Severity.info,
  ));
  return fixString(linter, text).$1;
}

FixResult fixResult(List<int> bytes, {List<String>? rules}) => fixBytes(
    Linter(LintOptions(rules: rules?.map((id) => findRule(id)!).toList())),
    bytes);

void main() {
  group('fixBytes', () {
    test('a clean file does not change', () {
      final text = '$_header$_body';
      final r = fixResult(utf8.encode(text));
      expect(r.changed, isFalse);
      expect(r.fixedCount, 0);
      expect(r.unifiedDiff('x'), isEmpty);
    });

    test('lines without a fix stay the same, byte by byte', () {
      // CRLF, a comment with odd spacing, and no line ending at the end.
      final text =
          '$_header* a   comment\t\r\n${_body.replaceAll('\n', '\r\n')}'
          'AC D\r\nAN Two\r\nAH 1000 FT MSL\r\nAL GND\r\n'
          'DP 46:00:00N 015:00:00E\r\nDP 46:00:00N 015:10:00E\r\n'
          'DP 45:55:00N 015:10:00E\r\nDP 46:00:00N 015:00:00E';
      final fixed = fix(text, rules: ['altitude-msl-alias']);
      expect(fixed, text.replaceFirst('1000 FT MSL', '1000 FT AMSL'));
    });

    test('fixes on the same text are applied in the next pass', () {
      // The case fix and the space fix change the same text.
      final text = '*VERSION: 3.0\n*WRITTEN_BY: test\n'
          '${_body.replaceFirst('AH 4500 FT AMSL', 'ah 4500ft msl')}';
      final r = fixResult(utf8.encode(text));
      final fixed = utf8.decode(r.bytes);
      expect(fixed, contains('\nAH 4500 FT AMSL\n'));
      expect(r.fixedByRule['case-not-upper-case'], 1);
      expect(r.fixedByRule['altitude-unit-no-space'], 1);
      expect(r.fixedByRule['altitude-msl-alias'], 1);
      // A second run finds nothing more to fix.
      expect(fixResult(r.bytes).changed, isFalse);
    });

    test('only the rules that run are fixed', () {
      final text = '$_header${_body.replaceFirst('AMSL', 'MSL')}';
      expect(
          fix(text, rules: ['altitude-msl-alias'], minSeverity: Severity.error),
          text);
      expect(fix(text, rules: ['altitude-spacing']), text);
      expect(fix(text, rules: ['altitude-msl-alias']), '$_header$_body');
    });

    test('a file with invalid UTF-8 is not fixed', () {
      final bytes = [
        ...utf8.encode('$_header${_body.replaceFirst('AMSL', 'MSL')}'),
        ...utf8.encode('* M'),
        0xFC,
        ...utf8.encode('nchen\n'),
      ];
      final r = fixResult(bytes);
      expect(r.changed, isFalse);
      expect(r.notFixedReason, contains('not valid UTF-8'));
      expect(r.bytes, bytes);
      // The problems are still reported.
      expect(r.result.diagnostics.map((d) => d.ruleId),
          contains('altitude-msl-alias'));
    });

    test('a UTF-16 file stays UTF-16 when file-not-utf8 is not used', () {
      final text = '$_header${_body.replaceFirst('AMSL', 'MSL')}';
      final bytes = [
        0xFF, 0xFE, //
        for (final u in text.codeUnits) ...[u & 0xFF, u >> 8],
      ];
      final r = fixResult(bytes, rules: ['altitude-msl-alias']);
      expect(r.bytes.sublist(0, 2), [0xFF, 0xFE]);
      final fixedText = String.fromCharCodes([
        for (var i = 2; i < r.bytes.length; i += 2)
          r.bytes[i] | (r.bytes[i + 1] << 8)
      ]);
      expect(fixedText, '$_header$_body');
    });

    test('file-not-utf8 saves a UTF-16 file as UTF-8', () {
      final text = '$_header$_body';
      final bytes = [
        0xFF, 0xFE, //
        for (final u in text.codeUnits) ...[u & 0xFF, u >> 8],
      ];
      final r = fixResult(bytes, rules: ['file-not-utf8']);
      expect(r.bytes, utf8.encode(text));
      expect(r.fileChanges.single, contains('UTF-8'));
    });

    test('file-bom removes only the byte order mark', () {
      final text = '$_header$_body';
      final r = fixResult([0xEF, 0xBB, 0xBF, ...utf8.encode(text)],
          rules: ['file-bom']);
      expect(r.bytes, utf8.encode(text));
      expect(r.fileChanges, ['Removed the byte order mark (BOM).']);
      // Without the rule, the byte order mark stays.
      final keep = fixResult([0xEF, 0xBB, 0xBF, ...utf8.encode(text)],
          rules: ['altitude-msl-alias']);
      expect(keep.changed, isFalse);
    });

    test('file-mixed-line-endings uses the most frequent line ending', () {
      final text = '$_header$_body'.replaceAll('\n', '\r\n');
      final mixed = text.replaceFirst('AN Test CTR\r\n', 'AN Test CTR\n');
      final r =
          fixResult(utf8.encode(mixed), rules: ['file-mixed-line-endings']);
      expect(utf8.decode(r.bytes), text);
      expect(r.fileChanges, ['Changed the line endings to CRLF.']);
      expect(r.unifiedDiff('x'), isEmpty);
    });

    test('a removed last line keeps "no line ending at the end"', () {
      final text = '$_header$_body'
          'AA NONE\n'
          'AA NONE';
      final fixed = fix(text, rules: ['aa-duplicate']);
      expect(fixed, '$_header${_body}AA NONE');
    });

    test('a new line after the last line gets a line ending', () {
      final open = '$_header${_body.substring(0, _body.length - 24)}';
      expect(open.endsWith('DP 45:55:00N 014:00:00E\n'), isTrue);
      final noEnd = open.substring(0, open.length - 1);
      expect(fix(noEnd, rules: ['geometry-polygon-not-closed']),
          '${open}DP 46:00:00N 014:00:00E');
      final crlf = open.replaceAll('\n', '\r\n');
      expect(fix(crlf, rules: ['geometry-polygon-not-closed']),
          '${crlf}DP 46:00:00N 014:00:00E\r\n');
    });

    test('unifiedDiff shows the changed lines with context', () {
      final text = '$_header${_body.replaceFirst('AMSL', 'MSL')}';
      final r = fixResult(utf8.encode(text), rules: ['altitude-msl-alias']);
      expect(
          r.unifiedDiff('a.openair'),
          '--- a.openair\n'
          '+++ a.openair (fixed)\n'
          '@@ -3,5 +3,5 @@\n'
          ' AC D\n'
          ' AN Test CTR\n'
          '-AH 4500 FT MSL\n'
          '+AH 4500 FT AMSL\n'
          ' AL GND\n'
          ' DP 46:00:00N 014:00:00E\n');
    });

    test('unifiedDiff shows removed and added lines', () {
      final dup = '$_header'
          '${_body.replaceFirst('DP 46:00:00N 014:10:00E\n', 'DP 46:00:00N 014:10:00E\nDP 46:00:00N 014:10:00E\n')}';
      final r = fixResult(utf8.encode(dup), rules: ['dp-duplicate-point']);
      expect(r.unifiedDiff('a', context: 0),
          '--- a\n+++ a (fixed)\n@@ -9 +8,0 @@\n-DP 46:00:00N 014:10:00E\n');
    });
  });

  group('fixes of the rules', () {
    // One case per fix. Each line is (rule, before, after). The text is a
    // line of the airspace in _body or a header line.
    final cases = <(String, String, String, SpecVersion)>[
      ('case-not-upper-case', 'ac d', 'AC D', SpecVersion.v3_0),
      (
        'case-not-upper-case',
        'an Name * a comment',
        'AN Name * a comment',
        SpecVersion.v3_0
      ),
      (
        'case-not-upper-case',
        'AH 4500 ft amsl * keep this',
        'AH 4500 FT AMSL * keep this',
        SpecVersion.v3_0
      ),
      (
        'header-field-format',
        '* version = 2.1',
        '*VERSION: 2.1',
        SpecVersion.v2_1
      ),
      (
        'header-version-unknown',
        '*VERSION: 2.1.0',
        '*VERSION: 2.1',
        SpecVersion.v2_1
      ),
      (
        'header-version-invalid',
        '*VERSION: V2.1',
        '*VERSION: 2.1',
        SpecVersion.v2_1
      ),
      (
        'header-version-invalid',
        '*VERSION: 2,1',
        '*VERSION: 2.1',
        SpecVersion.v2_1
      ),
      ('altitude-legacy-keyword', 'AL SFC', 'AL GND', SpecVersion.v2_1),
      ('altitude-legacy-keyword', 'AH UNLIM', 'AH UNL', SpecVersion.v2_1),
      (
        'altitude-unknown-unit',
        'AH 4500 FEET AMSL',
        'AH 4500 FT AMSL',
        SpecVersion.v2_1
      ),
      (
        'altitude-unknown-reference',
        'AH 4500 FT ASL',
        'AH 4500 FT AMSL',
        SpecVersion.v2_1
      ),
      ('altitude-unknown-reference', 'AL 0 FT SFC', 'AL GND', SpecVersion.v2_1),
      ('altitude-unit-missing', 'AL 0 AGL', 'AL GND', SpecVersion.v2_1),
      ('altitude-zero-agl', 'AL 0 FT AGL', 'AL GND', SpecVersion.v2_1),
      (
        'altitude-msl-alias',
        'AH 4500 FT MSL',
        'AH 4500 FT AMSL',
        SpecVersion.v2_1
      ),
      ('altitude-flight-level-space', 'AH FL 95', 'AH FL95', SpecVersion.v2_1),
      (
        'altitude-flight-level-invalid',
        'AH 95 FL',
        'AH FL95',
        SpecVersion.v2_1
      ),
      (
        'altitude-flight-level-invalid',
        'AH FL95 FT',
        'AH FL95',
        SpecVersion.v2_1
      ),
      (
        'altitude-unit-no-space',
        'AH 4500FT AMSL',
        'AH 4500 FT AMSL',
        SpecVersion.v3_0
      ),
      (
        'altitude-spacing',
        'AH 4500  FT\tAMSL',
        'AH 4500 FT AMSL',
        SpecVersion.v2_1
      ),
      (
        'altitude-invalid',
        'AH 4,500 FT AMSL',
        'AH 4500 FT AMSL',
        SpecVersion.v2_1
      ),
      (
        'altitude-invalid',
        'AH 4500 FT AMSL',
        'AH 4500 FT AMSL',
        SpecVersion.v2_1
      ),
      ('ac-unknown-class', 'AC UNCLASSIFIED', 'AC UNC', SpecVersion.v2_1),
      ('ay-unknown-type', 'AY RESTRICTED', 'AY R', SpecVersion.v2_1),
      ('af-invalid-format', 'AF 123,300', 'AF 123.300', SpecVersion.v2_1),
      ('af-invalid-format', 'AF 123.300 MHz', 'AF 123.300', SpecVersion.v2_1),
      ('af-not-three-decimals', 'AF 123.3', 'AF 123.300', SpecVersion.v3_0),
      ('af-not-three-decimals', 'AF 123.3000', 'AF 123.300', SpecVersion.v3_0),
      ('aa-none-none', 'AA NONE/NONE', 'AA NONE', SpecVersion.v3_0),
      (
        'aa-invalid-syntax',
        'AA MON 07:00Z-15:00Z',
        'AA MON 07:00Z/15:00Z',
        SpecVersion.v3_0
      ),
      (
        'aa-invalid-syntax',
        'AA MON 07:00Z / 15:00Z',
        'AA MON 07:00Z/15:00Z',
        SpecVersion.v3_0
      ),
      (
        'aa-invalid-syntax',
        'AA MON–FRI 07:00Z/15:00Z',
        'AA MON-FRI 07:00Z/15:00Z',
        SpecVersion.v3_0
      ),
      (
        'aa-weekday-list-has-spaces',
        'AA MON, WED 07:00Z/15:00Z',
        'AA MON,WED 07:00Z/15:00Z',
        SpecVersion.v3_0
      ),
      (
        'aa-weekday-every-day',
        'AA MON-SUN 07:00Z/15:00Z',
        'AA 07:00Z/15:00Z',
        SpecVersion.v3_0
      ),
      (
        'aa-value-form-not-allowed',
        'AA 20260705T0800Z/2026-07-05T10:00Z',
        'AA 2026-07-05T08:00Z/2026-07-05T10:00Z',
        SpecVersion.v3_0
      ),
      (
        'aa-interval-form-not-allowed',
        'AA 2026-07-05T08:00Z/PT2H',
        'AA 2026-07-05T08:00Z/2026-07-05T10:00Z',
        SpecVersion.v3_0
      ),
      (
        'aa-time-zone-not-z',
        'AA 2026-09-14T06:00UTC/2026-09-18T14:00Z',
        'AA 2026-09-14T06:00Z/2026-09-18T14:00Z',
        SpecVersion.v3_0
      ),
      (
        'aa-time-zone-not-z',
        'AA MON 07:00GMT/15:00+00:00',
        'AA MON 07:00Z/15:00Z',
        SpecVersion.v3_0
      ),
      (
        'v-space-around-equals',
        'V X = 46:00:00N 014:05:00E',
        'V X=46:00:00N 014:05:00E',
        SpecVersion.v2_1
      ),
      (
        'coordinate-space-between-parts',
        'DP 46:00:00N014:00:00E',
        'DP 46:00:00N 014:00:00E',
        SpecVersion.v2_1
      ),
      (
        'coordinate-space-between-parts',
        'DP 46:00:00N \t014:00:00E',
        'DP 46:00:00N 014:00:00E',
        SpecVersion.v2_1
      ),
      (
        'coordinate-space-between-parts',
        'DP 46:00:00  N 014:00:00E',
        'DP 46:00:00 N 014:00:00E',
        SpecVersion.v2_1
      ),
      (
        'coordinate-digit-count',
        'DP 46:0:0N 14:00:00E',
        'DP 46:00:00N 014:00:00E',
        SpecVersion.v2_1
      ),
      (
        'coordinate-digit-count',
        'DP 046:00:00N 014:00:00E',
        'DP 46:00:00N 014:00:00E',
        SpecVersion.v2_1
      ),
    ];

    test('a coordinate with a 60 is not changed at all', () {
      // A 60 is a typing error, and only a person can find the correct
      // value. The missing zero of the longitude is not added either: a
      // coordinate with an error gets no fix.
      final file = _replaceLine(_header + _body, 'DP 45:59:60 N 14:00:00 E');
      expect(
          fix(file,
              rules: ['coordinate-out-of-range', 'coordinate-digit-count']),
          file);
    });
    for (final (id, before, after, version) in cases) {
      test('$id: "$before"', () {
        final header = '*VERSION: ${version.label}\n*WRITTEN_BY: test\n';
        final file = _replaceLine(header + _body, before);
        final fixed = fix(file, rules: [id], target: version);
        expect(fixed, _replaceLine(header + _body, after));
      });
    }

    // Problems without a safe fix: the file does not change.
    final noFix = <(String, String, SpecVersion)>[
      ('altitude-unit-missing', 'AH 4500 AMSL', SpecVersion.v2_1),
      ('altitude-reference-missing', 'AH 4500 FT', SpecVersion.v2_1),
      ('altitude-unknown-reference', 'AH 4500 FT XYZ', SpecVersion.v2_1),
      ('altitude-flight-level-invalid', 'AH FL95 AMSL', SpecVersion.v2_1),
      ('altitude-flight-level-invalid', 'AH 95.5 FL', SpecVersion.v2_1),
      ('altitude-legacy-keyword', 'AH UNLIM 1000', SpecVersion.v2_1),
      (
        'header-version-invalid',
        '*VERSION: 2.1 (2026-01-01)',
        SpecVersion.v2_1
      ),
      ('ay-unknown-type', 'AY MILITARY', SpecVersion.v2_1),
      ('ay-unknown-type', 'AY UNCLASSIFIED', SpecVersion.v2_1),
      ('ac-unknown-class', 'AC R', SpecVersion.v2_1),
      ('af-invalid-format', 'AF 123.300 / 124.500', SpecVersion.v2_1),
      ('af-invalid-format', 'AF 123300 kHz', SpecVersion.v2_1),
      ('af-not-three-decimals', 'AF 118.0083', SpecVersion.v3_0),
      (
        'aa-weekday-list-has-spaces',
        'AA MON FRI 07:00Z/15:00Z',
        SpecVersion.v3_0
      ),
      (
        'aa-value-form-not-allowed',
        'AA 2026-07-05T08:00:00.5Z/NONE',
        SpecVersion.v3_0
      ),
      ('aa-time-missing-z', 'AA MON 07:00/15:00', SpecVersion.v3_0),
      ('aa-time-zone-not-z', 'AA MON 08:00+01:00/15:00Z', SpecVersion.v3_0),
      ('aa-time-zone-not-z', 'AA MON 08:00LT/15:00Z', SpecVersion.v3_0),
      ('aa-time-zone-not-z', 'AA MON 08:00CET/15:00Z', SpecVersion.v3_0),
      ('coordinate-digit-count', 'DP 46:0:00N 014:00:00', SpecVersion.v2_1),
      ('coordinate-out-of-range', 'DP 46:00:61N 014:00:00E', SpecVersion.v2_1),
      ('coordinate-out-of-range', 'DP 91:00:00N 014:00:00E', SpecVersion.v2_1),
      ('coordinate-out-of-range', 'DP 90:00:60N 014:00:00E', SpecVersion.v2_1),
      ('coordinate-out-of-range', 'DP 46:00:60N 014:00:00', SpecVersion.v2_1),
      (
        'coordinate-decimal-seconds',
        'DP 46:00:00.5N 014:00:00E',
        SpecVersion.v2_1
      ),
      ('ax-not-four-digits', 'AX 424', SpecVersion.v2_1),
    ];
    for (final (id, line, version) in noFix) {
      test('$id: no fix for "$line"', () {
        final header = '*VERSION: ${version.label}\n*WRITTEN_BY: test\n';
        final file = _replaceLine(header + _body, line);
        final found =
            Linter(LintOptions(target: version, rules: [findRule(id)!]))
                .lintString(file)
                .diagnostics;
        expect(found, isNotEmpty, reason: 'the problem must be reported');
        expect(fix(file, rules: [id], target: version), file);
      });
    }

    test('header-field-duplicate removes only a copy with the same value', () {
      const same = '*VERSION: 2.1\n*WRITTEN_BY: test\n*WRITTEN_BY: test\n';
      expect(fix('$same$_body', rules: ['header-field-duplicate']),
          '$_header$_body');
      const other = '*VERSION: 2.1\n*WRITTEN_BY: test\n*WRITTEN_BY: other\n';
      expect(fix('$other$_body', rules: ['header-field-duplicate']),
          '$other$_body');
    });

    test('dp-duplicate-point keeps a line with a comment', () {
      final dup = _body.replaceFirst('DP 46:00:00N 014:10:00E\n',
          'DP 46:00:00N 014:10:00E\nDP 46:00:00N 014:10:00E\n');
      expect(
          fix('$_header$dup', rules: ['dp-duplicate-point']), '$_header$_body');
      final withComment = _body.replaceFirst('DP 46:00:00N 014:10:00E\n',
          'DP 46:00:00N 014:10:00E\nDP 46:00:00N 014:10:00E * keep\n');
      expect(fix('$_header$withComment', rules: ['dp-duplicate-point']),
          '$_header$withComment');
      // The same position in another notation is the same point.
      final ddm = _body.replaceFirst('DP 46:00:00N 014:10:00E\n',
          'DP 46:00:00N 014:10:00E\nDP 46:00.000N 014:10.000E\n');
      expect(
          fix('$_header$ddm', rules: ['dp-duplicate-point']), '$_header$_body');
      // A point 0.001 seconds away is reported (it is within the tolerance),
      // but it is not removed, because the polygon would change.
      final near = _body.replaceFirst('DP 46:00:00N 014:10:00E\n',
          'DP 46:00:00N 014:10:00E\nDP 46:00:00N 014:10:00.001E\n');
      final found =
          Linter(LintOptions(rules: [findRule('dp-duplicate-point')!]))
              .lintString('$_header$near')
              .diagnostics;
      expect(found, hasLength(1));
      expect(
          fix('$_header$near', rules: ['dp-duplicate-point']), '$_header$near');
    });

    test('aa-duplicate keeps a line with a comment', () {
      const two = 'AA MON 07:00Z/15:00Z\nAA MON 07:00Z/15:00Z * keep\n';
      final file = '$_header${_body.replaceFirst('AL GND\n', 'AL GND\n$two')}';
      expect(fix(file, rules: ['aa-duplicate']), file);
    });

    test('geometry-polygon-not-closed adds the first point', () {
      final open = _body.substring(0, _body.length - 24);
      expect(fix('$_header$open', rules: ['geometry-polygon-not-closed']),
          '$_header$_body');
      // A gap below 0.1 NM is probably a typing error: no fix.
      final near = '${open}DP 46:00:01N 014:00:00E\n';
      expect(fix('$_header$near', rules: ['geometry-polygon-not-closed']),
          '$_header$near');
    });

    group('geometry-polygon-counter-clockwise', () {
      const head = '*VERSION: 2.1\n*WRITTEN_BY: test\n'
          'AC D\nAN Test CTR\nAH 4500 FT AMSL\nAL GND\n';
      // _body clockwise, and the same points counter-clockwise. The DDM
      // point keeps its exact text.
      const cw = 'DP 46:00:00N 014:00:00E\n'
          'DP 46:00:00N 014:10:00E\n'
          'DP 45:55.000N 014:10:00E\n'
          'DP 45:55:00N 014:00:00E\n'
          'DP 46:00:00N 014:00:00E\n';
      const ccw = 'DP 46:00:00N 014:00:00E\n'
          'DP 45:55:00N 014:00:00E\n'
          'DP 45:55.000N 014:10:00E\n'
          'DP 46:00:00N 014:10:00E\n'
          'DP 46:00:00N 014:00:00E\n';
      const id = 'geometry-polygon-counter-clockwise';

      test('writes the DP points in the opposite order', () {
        expect(fix('$head$ccw', rules: [id]), '$head$cw');
        // Empty lines stay where they are.
        final gap = ccw.replaceFirst(
            '014:00:00E\nDP 45:55.000N', '014:00:00E\n\nDP 45:55.000N');
        expect(fix('$head$gap', rules: [id]),
            '$head${cw.replaceFirst('014:10:00E\nDP 45:55.000N', '014:10:00E\n\nDP 45:55.000N')}');
      });

      test('the fix is stable and gives a clean file', () {
        final r = fixBytes(Linter(), utf8.encode('$head$ccw'));
        expect(utf8.decode(r.bytes), '$head$cw');
        expect(r.result.diagnostics.map((d) => d.ruleId), isNot(contains(id)));
      });

      test('an open polygon is closed first, then reversed', () {
        final open = ccw.substring(0, ccw.length - 24);
        final fixed =
            fix('$head$open', rules: [id, 'geometry-polygon-not-closed']);
        expect(fixed, '$head$cw');
      });

      test('no fix with a comment, a comment line or other commands', () {
        for (final text in [
          ccw.replaceFirst('014:10:00E\n', '014:10:00E * river\n'),
          ccw.replaceFirst('DP 45:55.000N', '* border\nDP 45:55.000N'),
          ccw.replaceFirst('DP 45:55.000N', 'AF 123.500\nDP 45:55.000N'),
        ]) {
          expect(
              Linter(LintOptions(rules: [findRule(id)!]))
                  .lintString('$head$text')
                  .diagnostics,
              hasLength(1));
          expect(fix('$head$text', rules: [id]), '$head$text');
        }
      });

      test('no fix for a boundary with an arc', () {
        const arc = 'V X=46:00:00N 014:05:00E\n'
            'DP 46:00:00N 014:00:00E\n'
            'DP 45:55:00N 014:00:00E\n'
            'DP 45:55:00N 014:10:00E\n'
            'DP 46:00:00N 014:10:00E\n'
            'V D=-\n'
            'DB 46:00:00N 014:10:00E, 46:00:00N 014:00:00E\n';
        final found = Linter(LintOptions(rules: [findRule(id)!]))
            .lintString('$head$arc')
            .diagnostics;
        expect(found, hasLength(1));
        expect(found.single.fixable, isFalse);
      });
    });
  });

  test('only rules with a fix description give fixes', () {
    // LintContext.report checks this with an assert. This test makes sure
    // that the examples of all rules run with the assert.
    for (final rule in allRules) {
      for (final example in [rule.correctExample, rule.incorrectExample]) {
        final file = '$_header$example\n';
        for (final d in lintString(file)) {
          if (d.fixable) {
            expect(findRule(d.ruleId)!.fixable, isTrue, reason: d.ruleId);
          }
          expect(d.ruleId, isNot(internalErrorRuleId), reason: d.message);
        }
      }
    }
  });
}

/// [file] with the line that has the same keyword (or header key) as
/// [line] replaced by [line]. If no line has the keyword, [line] is added
/// after "AL GND".
String _replaceLine(String file, String line) {
  final lines = file.split('\n');
  String key(String l) {
    final t = l.trimLeft();
    if (t.startsWith('*')) {
      return t
          .substring(1)
          .trimLeft()
          .split(RegExp(r'[\s:=]'))
          .first
          .toUpperCase();
    }
    return t.split(RegExp(r'\s')).first.toUpperCase();
  }

  final k = key(line);
  final index = lines.indexWhere((l) => l.isNotEmpty && key(l) == k);
  if (index >= 0) {
    lines[index] = line;
  } else {
    lines.insert(lines.indexOf('AL GND') + 1, line);
  }
  return lines.join('\n');
}
