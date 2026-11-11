// Tests for the rules in lib/src/rules/activation_rules.dart.
//
// Conformance files for this group are in openair-conformance/valid/activation/
// and openair-conformance/invalid/activation/.

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

import '../support/helpers.dart';

/// The geometry of the test airspace (Ljubljana area, about 46° N 14.5° E).
const String geometry = 'AH 4500 FT AMSL\n'
    'AL GND\n'
    'DP 46:00:00N 014:00:00E\n'
    'DP 46:00:00N 014:10:00E\n'
    'DP 45:55:00N 014:10:00E\n'
    'DP 45:55:00N 014:00:00E\n'
    'DP 46:00:00N 014:00:00E\n';

/// A file with one airspace and these AA lines. The first AA line is
/// line 5.
String aa(List<String> aaLines,
        {String version = '3.0', String geo = geometry}) =>
    withHeader(
        'AC D\n'
        'AN Test\n'
        '${aaLines.map((l) => 'AA $l\n').join()}'
        '$geo',
        version: version);

/// The lines where [ruleId] fires for these AA lines.
List<int> fires(String ruleId, List<String> aaLines,
        {String version = '3.0', String geo = geometry}) =>
    linesOf(ruleId, aa(aaLines, version: version, geo: geo));

/// The messages of [ruleId] for these AA lines.
List<String> messages(String ruleId, List<String> aaLines,
        {String version = '3.0', String geo = geometry}) =>
    [
      for (final d in lintRule(ruleId, aa(aaLines, version: version, geo: geo)))
        d.message
    ];

/// True for an error or a warning of an activation rule.
bool aaProblem(Diagnostic d) =>
    d.ruleId.startsWith('aa-') && d.severity != Severity.info;

void main() {
  group('parseAa', () {
    test('interval', () {
      final c = parseAa('2026-07-04T08:00Z/2026-07-04T16:00Z');
      expect(c, isA<AaIntervalCommand>());
      c as AaIntervalCommand;
      expect(c.isUsable, isTrue);
      expect(formatInstant(c.start!), '2026-07-04T08:00Z');
      expect(formatInstant(c.end!), '2026-07-04T16:00Z');
    });

    test('interval with NONE', () {
      final c = parseAa('NONE/2026-07-04T16:00Z') as AaIntervalCommand;
      expect(c.startIsNone, isTrue);
      expect(c.start, isNull);
      expect(c.isUsable, isTrue);
    });

    test('weekday command', () {
      final c =
          parseAa('MON-FRI,SUN 07:00Z/SS 2026-04-01/NONE') as AaWeekdayCommand;
      expect(c.isUsable, isTrue);
      expect(c.weekdays, {1, 2, 3, 4, 5, 7});
      expect(c.weekdaysGiven, isTrue);
      expect(c.startTime, const AaTimeOfDay.fixed(7 * 3600000));
      expect(c.endTime, const AaTimeOfDay.sun(SunEvent.sunset));
      expect(c.fromDate, const CivilDate(2026, 4, 1));
      expect(c.toDate, isNull);
      expect(c.usesSunEvent, isTrue);
    });

    test('wrapping weekday range', () {
      final c = parseAa('FRI-MON 22:00Z/02:00Z') as AaWeekdayCommand;
      expect(c.weekdays, {5, 6, 7, 1});
    });

    test('weekday command without weekdays', () {
      final c = parseAa('SS/SR') as AaWeekdayCommand;
      expect(c.weekdays.length, 7);
      expect(c.weekdaysGiven, isFalse);
    });

    test('lower case is read (case is checked by the header group)', () {
      expect(parseAa('mon-fri 07:00z/ss').isUsable, isTrue);
      expect(parseAa('except 2026-12-25'), isA<AaExceptCommand>());
      expect(parseAa('none'), isA<AaNoneCommand>());
    });

    test('exception', () {
      final c = parseAa('EXCEPT 2026-12-31/2027-01-01') as AaExceptCommand;
      expect(c.contains(const CivilDate(2027, 1, 1)), isTrue);
      expect(c.contains(const CivilDate(2027, 1, 2)), isFalse);
      final one = parseAa('EXCEPT 2026-12-25') as AaExceptCommand;
      expect(one.fromDate, one.toDate);
    });

    test('unknown', () {
      expect(parseAa('H24'), isA<AaUnknownCommand>());
      expect(parseAa('').issues.single.kind, AaIssueKind.missingValue);
    });
  });

  group('aa-missing-value', () {
    test('fires for AA without a value', () {
      expect(fires('aa-missing-value', ['']), [5]);
    });
    test('does not fire for AA NONE', () {
      expect(fires('aa-missing-value', ['NONE']), isEmpty);
    });
  });

  group('aa-invalid-syntax', () {
    test('fires for forms that do not exist', () {
      for (final v in [
        'H24',
        'HJ',
        '2026-07-04 08:00Z/2026-07-04 16:00Z',
        '2026-07-04T08:00Z-2026-07-04T16:00Z',
        '2026-07-04T08:00Z/2026-07-04T16:00Z extra',
        'R5/2026-07-04T08:00Z/P1D',
        '2026-07-04/2026-07-05',
        'MON',
        '09:00Z/11:00Z MON',
        'MON 09:00Z/11:00Z 2026-03-29',
        'EXCEPT',
        'EXCEPT 2026-12-25,2026-12-26',
        'NONE extra',
        '2026-07-04T08:00Z/2026-07-04T16:00Z/2026-07-04T18:00Z',
      ]) {
        expect(fires('aa-invalid-syntax', [v]), [5], reason: v);
      }
    });
    test('does not fire for valid forms', () {
      for (final v in [
        '2026-07-04T08:00Z/2026-07-04T16:00Z',
        'MON-FRI 07:00Z/15:00Z 2026-03-29/2026-10-24',
        'EXCEPT 2026-12-25',
        'NONE',
        'SR/SS',
      ]) {
        expect(fires('aa-invalid-syntax', [v]), isEmpty, reason: v);
      }
    });
    test('H24 gives advice', () {
      expect(messages('aa-invalid-syntax', ['H24']).single,
          contains('always active'));
    });
  });

  group('common typing errors give one clear message', () {
    /// The AA diagnostics (all severities) for one AA command.
    /// aa-except-without-weekday is left out: a single AA EXCEPT command
    /// always has it.
    List<Diagnostic> aaDiags(String v) => [
          for (final d in lintAll(aa([v])))
            if (d.ruleId.startsWith('aa-') &&
                d.ruleId != 'aa-except-without-weekday')
              d
        ];

    test('spaces around "/"', () {
      for (final (v, write, column) in [
        ('MON-FRI 07:00Z /15:00Z', '"07:00Z/15:00Z"', 18),
        ('MON-FRI 07:00Z/ 15:00Z', '"07:00Z/15:00Z"', 18),
        (
          '2026-07-04T08:00Z / 2026-07-04T16:00Z',
          '"2026-07-04T08:00Z/2026-07-04T16:00Z"',
          21
        ),
        ('MON 07:00Z/15:00Z 2026-01-01 /NONE', '"2026-01-01/NONE"', 32),
        ('EXCEPT 2026-12-31 / 2027-01-01', '"2026-12-31/2027-01-01"', 21),
      ]) {
        final d = aaDiags(v).single;
        expect(d.ruleId, 'aa-invalid-syntax', reason: v);
        expect(d.message, 'Remove the spaces around "/". Write $write.',
            reason: v);
        expect(d.column, column, reason: v);
      }
    });

    test('the other issues still point to the right place', () {
      final d = lintRule('aa-invalid-time', aa(['MON 07:00Z / 25:00Z'])).single;
      expect(d.column, 17);
      expect(d.endColumn, 23);
    });

    test('the kind of command is kept, so other rules do not misfire', () {
      final c = parseAa('MON-FRI 07:00Z /15:00Z');
      expect(c, isA<AaWeekdayCommand>());
      expect(c.isUsable, isFalse);
      expect(c.text, 'MON-FRI 07:00Z /15:00Z');
      expect(
          fires('aa-except-without-weekday',
              ['MON-FRI 07:00Z /15:00Z', 'EXCEPT 2026-12-25']),
          isEmpty);
    });

    test('a schedule code after the weekdays', () {
      for (final (v, advice) in [
        ('MON-FRI HJ', 'Write AA MON-FRI SR/SS.'),
        ('SAT,SUN HN', 'Write AA SAT,SUN SS/SR.'),
        ('MON-FRI H24', 'write AA MON-FRI 00:00Z/24:00Z.'),
        ('MON-FRI PH 07:00Z/15:00Z', 'Write each holiday as AA EXCEPT Date.'),
        ('EXCEPT PH', 'Write each holiday as AA EXCEPT Date.'),
      ]) {
        final d = aaDiags(v).where((d) => d.severity != Severity.info);
        expect(d.length, 1, reason: '$v: $d');
        expect(d.single.ruleId, 'aa-invalid-syntax', reason: v);
        expect(d.single.message, endsWith(advice), reason: v);
      }
    });

    test('"-" in place of "/" in a weekday time window', () {
      for (final (v, write) in [
        ('MON-FRI 07:00Z-15:00Z', '"07:00Z/15:00Z"'),
        ('MON 0700Z-1500Z', '"0700Z/1500Z"'),
        ('SAT 07:00Z-SS', '"07:00Z/SS"'),
      ]) {
        final d = aaDiags(v).single;
        expect(
            d.message,
            'Use "/" between the start time and the end time, not "-". '
            'Write $write.',
            reason: v);
      }
    });

    test('an en dash or an em dash', () {
      for (final dash in [0x2013, 0x2014, 0x2212]) {
        final c = String.fromCharCode(dash);
        final d = aaDiags('MON${c}FRI 07:00Z/15:00Z').single;
        expect(d.ruleId, 'aa-invalid-syntax');
        expect(d.message, 'Use "-" (hyphen), not "$c".');
        expect(d.column, 7);
      }
    });
  });

  group('aa-invalid-date', () {
    test('fires for dates that do not exist', () {
      expect(fires('aa-invalid-date', ['EXCEPT 2026-02-30']), [5]);
      expect(fires('aa-invalid-date', ['2026-13-01T08:00Z/NONE']), [5]);
      expect(
          fires('aa-invalid-date', ['MON 09:00Z/11:00Z 2026-02-29/NONE']), [5]);
    });
    test('fires for a date with a time in a date range', () {
      expect(
          fires(
              'aa-invalid-date', ['MON 09:00Z/11:00Z 2026-03-29T00:00Z/NONE']),
          [5]);
    });
    test('does not fire for leap days', () {
      expect(fires('aa-invalid-date', ['EXCEPT 2028-02-29']), isEmpty);
    });
    test('points to the date', () {
      final d = lintRule('aa-invalid-date', aa(['EXCEPT 2026-02-30'])).single;
      expect(d.column, 11);
      expect(d.endColumn, 21);
    });
  });

  group('aa-invalid-time', () {
    test('fires for invalid times', () {
      expect(fires('aa-invalid-time', ['MON 09:00Z/25:00Z']), [5]);
      expect(fires('aa-invalid-time', ['9:00Z/11:00Z']), [5]);
      expect(fires('aa-invalid-time', ['2026-07-04/2026-07-04T10:00Z']), [5]);
      expect(fires('aa-invalid-time', ['2026-07-04T0800Z/NONE']), [5]);
      expect(fires('aa-invalid-time', ['MON 2026-07-04T08:00Z/10:00Z']), [5]);
    });
    test('does not fire for valid times', () {
      expect(fires('aa-invalid-time', ['MON 00:00Z/24:00Z']), isEmpty);
    });
  });

  group('aa-invalid-duration (version 2.1)', () {
    test('fires for invalid durations', () {
      expect(
          fires('aa-invalid-duration', ['2026-07-04T08:00Z/P8H'],
              version: '2.1'),
          [5]);
      expect(
          fires('aa-invalid-duration', ['2026-07-04T08:00Z/PT'],
              version: '2.1'),
          [5]);
      expect(fires('aa-invalid-duration', ['PT8H/PT2H'], version: '2.1'), [5]);
      expect(fires('aa-invalid-duration', ['PT8H/NONE'], version: '2.1'), [5]);
    });
    test('does not fire for valid durations', () {
      expect(
          fires('aa-invalid-duration', ['2026-07-04T08:00Z/PT8H'],
              version: '2.1'),
          isEmpty);
      expect(
          fires(
              'aa-invalid-duration', ['2026-07-04T08:00Z/P0000-00-01T00:00:00'],
              version: '2.1'),
          isEmpty);
    });
    test('does not apply to version 3.0 (durations are not allowed)', () {
      expect(fires('aa-invalid-duration', ['2026-07-04T08:00Z/P8H']), isEmpty);
      for (final v in ['2026-07-04T08:00Z/P8H', 'PT8H/PT2H', 'PT8H/NONE']) {
        expect(fires('aa-interval-form-not-allowed', [v]), [5], reason: v);
      }
    });
    test('fires on the AA line for a very long duration', () {
      for (final v in [
        '2026-07-04T08:00Z/PT99999999999999999999H',
        '2026-07-04T08:00Z/P99999999999999999999D',
        '2026-07-04T08:00Z/P9000Y',
        'P3000Y/2026-07-04T08:00Z',
      ]) {
        final all = lintAll(aa([v], version: '2.1'));
        expect(all.where((d) => d.ruleId == 'linter-internal-error'), isEmpty,
            reason: v);
        final d = all.where((d) => d.ruleId == 'aa-invalid-duration').single;
        expect(d.line, 5, reason: v);
        expect(d.message, contains('too long'), reason: v);
      }
    });
  });

  group('aa-time-missing-z', () {
    test('fires for times without Z', () {
      expect(fires('aa-time-missing-z', ['MON 09:00/11:00Z']), [5]);
      expect(lintRule('aa-time-missing-z', aa(['MON 09:00/11:00'])).length, 2);
      expect(fires('aa-time-missing-z', ['2026-07-04T08:00/NONE']), [5]);
    });
    test('does not fire for Z', () {
      expect(fires('aa-time-missing-z', ['MON 09:00Z/11:00Z']), isEmpty);
    });
  });

  group('aa-time-zone-not-z', () {
    test('fires for offsets and zone names', () {
      expect(fires('aa-time-zone-not-z', ['MON 09:00+01:00/11:00Z']), [5]);
      expect(
          fires(
              'aa-time-zone-not-z', ['2026-09-14T06:00UTC/2026-09-18T14:00Z']),
          [5]);
      expect(fires('aa-time-zone-not-z', ['MON 09:00LT/11:00Z']), [5]);
    });
    test('does not fire for Z', () {
      expect(fires('aa-time-zone-not-z', ['MON 09:00Z/11:00Z']), isEmpty);
    });
  });

  group('aa-time-24-as-start', () {
    test('fires for 24:00Z as a start', () {
      expect(fires('aa-time-24-as-start', ['24:00Z/06:00Z']), [5]);
      expect(
          fires('aa-time-24-as-start', ['2026-07-04T24:00Z/2026-07-05T06:00Z']),
          [5]);
    });
    test('does not fire for 24:00Z as an end', () {
      expect(fires('aa-time-24-as-start', ['18:00Z/24:00Z']), isEmpty);
      expect(
          fires('aa-time-24-as-start', ['2024-12-17T00:00Z/2024-12-17T24:00Z']),
          isEmpty);
    });
  });

  group('aa-value-form-not-allowed', () {
    test('fires for ISO 8601 forms that are not allowed', () {
      for (final v in [
        '20260704T0800Z/2026-07-04T16:00Z',
        '2026-W27-6T08:00Z/2026-07-04T16:00Z',
        '2026-185T08:00Z/2026-07-04T16:00Z',
        '2026-07-04T08:00:00.5Z/2026-07-04T16:00Z',
        '2026-07-04T08Z/2026-07-04T16:00Z',
        'MON 0900Z/11:00Z',
        'MON 09Z/11:00Z',
        'MON T09:00Z/11:00Z',
        'MON 09:00:00,5Z/11:00Z',
        'MON 09:00Z/11:00Z 20260101/2026-12-31',
        'EXCEPT 20261225',
        'EXCEPT 2026-W52-5',
        'EXCEPT 2026-359',
      ]) {
        expect(fires('aa-value-form-not-allowed', [v]), [5], reason: v);
      }
    });
    test('does not fire for the allowed forms, also with seconds', () {
      expect(
          fires('aa-value-form-not-allowed', [
            '2026-07-04T08:00Z/2026-07-04T16:00Z',
            '2026-07-05T08:00:00Z/2026-07-05T16:00:30Z',
            'MON 09:00Z/11:00Z 2026-01-01/2026-12-31',
            'TUE 09:00:00Z/24:00:00Z',
            'EXCEPT 2026-12-25',
          ]),
          isEmpty);
    });
    test('the message names the allowed forms and gives the value', () {
      expect(
          messages('aa-value-form-not-allowed', ['EXCEPT 2026-W52-5']).single,
          '"2026-W52-5" uses a week date. This form is not allowed. Write it '
          'as YYYY-MM-DD: "2026-12-25".');
      expect(
          messages('aa-value-form-not-allowed',
              ['20260704T0800Z/2026-07-04T16:00Z']).single,
          contains('YYYY-MM-DDThh:mmZ or YYYY-MM-DDThh:mm:ssZ: '
              '"2026-07-04T08:00Z"'));
      expect(messages('aa-value-form-not-allowed', ['MON 09Z/11:00Z']).single,
          contains('hh:mmZ or hh:mm:ssZ: "09:00Z"'));
    });
    test('is an error, because the specification says "not allowed"', () {
      expect(findRule('aa-value-form-not-allowed')!.severity, Severity.error);
      expect(
          findRule('aa-interval-form-not-allowed')!.severity, Severity.error);
    });
    test('the value is still known, so other rules use the command', () {
      final c = parseAa('20260704T0800Z/20260704T1600Z') as AaIntervalCommand;
      expect(c.isUsable, isTrue);
      expect(formatInstant(c.start!), '2026-07-04T08:00Z');
      expect(
          fires('aa-intervals-overlap', [
            '20260704T0800Z/20260704T1600Z',
            '2026-07-04T10:00Z/2026-07-04T18:00Z',
          ]),
          [6]);
    });
    test('a fraction is cut, not rounded up to the next day', () {
      expect(
          messages('aa-value-form-not-allowed', ['MON 23:59:59.9999Z/24:00Z'])
              .single,
          contains('"23:59:59Z"'));
      expect(
          fires('aa-interval-end-before-start',
              ['2026-07-04T23:59:59.9999Z/2026-07-05T00:00Z']),
          isEmpty);
      expect(
          fires('aa-time-24-as-start', ['MON 23:59:59.9999Z/24:00Z']), isEmpty);
    });
  });

  group('aa-value-form-not-allowed-v21', () {
    test('is a warning in version 2.1 that names version 3.0', () {
      final d = lintRule(
              'aa-value-form-not-allowed-v21',
              aa(['20260704T0800Z/2026-07-04T16:00Z', 'EXCEPT 2026-W52-5'],
                  version: '2.1'))
          .toList();
      expect([for (final x in d) x.line], [5, 6]);
      expect(d.first.message, contains('not allowed in version 3.0'));
      expect(findRule('aa-value-form-not-allowed-v21')!.severity,
          Severity.warning);
    });
    test('the 3.0 rule does not apply to version 2.1, and the reverse', () {
      expect(
          fires(
              'aa-value-form-not-allowed', ['20260704T0800Z/2026-07-04T16:00Z'],
              version: '2.1'),
          isEmpty);
      expect(
          fires('aa-value-form-not-allowed-v21',
              ['20260704T0800Z/2026-07-04T16:00Z']),
          isEmpty);
    });
    test('does not fire for the allowed forms', () {
      expect(
          fires('aa-value-form-not-allowed-v21',
              ['2026-07-04T08:00:00Z/2026-07-04T16:00Z'],
              version: '2.1'),
          isEmpty);
    });
  });

  group('aa-none-not-allowed', () {
    test('fires for NONE in weekday times and in AA EXCEPT', () {
      expect(fires('aa-none-not-allowed', ['MON 09:00Z/NONE']), [5]);
      expect(fires('aa-none-not-allowed', ['NONE/09:00Z']), [5]);
      expect(fires('aa-none-not-allowed', ['EXCEPT NONE']), [5]);
      expect(fires('aa-none-not-allowed', ['EXCEPT 2026-12-25/NONE']), [5]);
    });
    test('does not fire where NONE is allowed', () {
      expect(
          fires('aa-none-not-allowed', [
            '2026-07-04T08:00Z/NONE',
            'MON 09:00Z/11:00Z 2026-04-01/NONE',
          ]),
          isEmpty);
      expect(fires('aa-none-not-allowed', ['NONE']), isEmpty);
    });
  });

  group('aa-none-none', () {
    test('fires for NONE/NONE', () {
      expect(fires('aa-none-none', ['NONE/NONE']), [5]);
    });
    test('does not fire for AA NONE', () {
      expect(fires('aa-none-none', ['NONE']), isEmpty);
    });
    test('the message in version 3.0 does not suggest AA NONE', () {
      final d = lintRule('aa-none-none', aa(['NONE/NONE']));
      expect(d.single.message, isNot(contains('Write AA NONE')));
      expect(d.single.fix, isNull);
    });
    test('version 2.1 suggests AA NONE and has a fix', () {
      final d = lintRule('aa-none-none', aa(['NONE/NONE'], version: '2.1'));
      expect(d.single.message, contains('Write AA NONE'));
      expect(d.single.fix, isNotNull);
    });
  });

  group('aa-none-removed', () {
    test('fires for AA NONE in version 3.0', () {
      expect(fires('aa-none-removed', ['NONE']), [5]);
      expect(fires('aa-none-removed', ['MON 09:00Z/10:00Z', 'NONE']), [6]);
    });
    test('does not fire for NONE on one side of an interval', () {
      expect(
          fires('aa-none-removed',
              ['2026-07-04T08:00Z/NONE', 'NONE/2026-07-05T08:00Z']),
          isEmpty);
    });
    test('does not apply to version 2.1', () {
      expect(fires('aa-none-removed', ['NONE'], version: '2.1'), isEmpty);
    });
  });

  group('schedule codes', () {
    test('NOTAM suggests AS NOTAM in version 3.0', () {
      final d = lintRule('aa-invalid-syntax', aa(['NOTAM']));
      expect(d.single.message, contains('AS NOTAM'));
      expect(d.single.message, isNot(contains('AA NONE')));
    });
    test('NOTAM suggests AA NONE in version 2.1', () {
      final d = lintRule('aa-invalid-syntax', aa(['NOTAM'], version: '2.1'));
      expect(d.single.message, contains('AA NONE'));
    });
    test('HX does not suggest AA NONE in version 3.0', () {
      for (final v in ['HX', 'MON-FRI HX', 'EXCEPT HX']) {
        final d = lintRule('aa-invalid-syntax', aa([v]));
        expect(d.single.message, isNot(contains('AA NONE')), reason: v);
      }
    });
  });

  group('aa-interval-end-before-start', () {
    test('fires when the end is before or equal to the start', () {
      expect(
          fires('aa-interval-end-before-start',
              ['2026-07-04T16:00Z/2026-07-04T08:00Z']),
          [5]);
      expect(
          fires('aa-interval-end-before-start',
              ['2026-07-04T08:00Z/2026-07-04T08:00Z']),
          [5]);
      expect(fires('aa-interval-end-before-start', ['2026-07-04T08:00Z/PT0H']),
          [5]);
      expect(
          fires('aa-interval-end-before-start', ['2026-07-04T16:00Z/08:00Z']),
          [5]);
    });
    test('does not fire for a correct interval', () {
      expect(
          fires('aa-interval-end-before-start',
              ['2026-07-04T08:00Z/2026-07-04T16:00Z']),
          isEmpty);
    });
  });

  group('aa-interval-form-not-allowed', () {
    test('fires for durations and short ends, with the corrected value', () {
      for (final (v, fixed) in [
        ('2026-07-04T08:00Z/PT8H', '2026-07-04T08:00Z/2026-07-04T16:00Z'),
        ('PT8H/2026-07-04T16:00Z', '2026-07-04T08:00Z/2026-07-04T16:00Z'),
        ('2026-07-04T08:00Z/16:00Z', '2026-07-04T08:00Z/2026-07-04T16:00Z'),
        (
          '2026-07-04T08:00Z/07-05T16:00Z',
          '2026-07-04T08:00Z/2026-07-05T16:00Z'
        ),
        ('2026-07-04T08:00Z/05T16:00Z', '2026-07-04T08:00Z/2026-07-05T16:00Z'),
        (
          '2026-07-04T08:00Z/P0000-00-01T00:00:00',
          '2026-07-04T08:00Z/2026-07-05T08:00Z'
        ),
      ]) {
        expect(fires('aa-interval-form-not-allowed', [v]), [5], reason: v);
        expect(messages('aa-interval-form-not-allowed', [v]).single,
            contains('"$fixed"'),
            reason: v);
      }
    });
    test('the message says what is wrong', () {
      expect(
          messages('aa-interval-form-not-allowed', ['2026-07-04T08:00Z/PT8H'])
              .single,
          '"PT8H" is a duration. A duration in an interval is not allowed. '
          'Write the interval as StartDateTime/EndDateTime: '
          '"2026-07-04T08:00Z/2026-07-04T16:00Z".');
      expect(
          messages('aa-interval-form-not-allowed', ['2026-07-04T08:00Z/16:00Z'])
              .single,
          startsWith('The end "16:00Z" has no date.'));
      expect(
          messages('aa-interval-form-not-allowed',
              ['2026-07-04T08:00Z/07-05T16:00Z']).single,
          startsWith('The end "07-05T16:00Z" has no year.'));
    });
    test('an invalid duration has no corrected value', () {
      expect(
          messages('aa-interval-form-not-allowed', ['2026-07-04T08:00Z/P8H'])
              .single,
          contains('for example 2026-07-04T08:00Z/2026-07-04T16:00Z'));
    });
    test('a short end with a date that does not exist is an error', () {
      expect(fires('aa-invalid-date', ['2026-07-04T08:00Z/07-32T16:00Z']), [5]);
      expect(
          messages('aa-invalid-date', ['2026-07-04T08:00Z/07-32T16:00Z'])
              .single,
          contains('from the start (2026-07-04)'));
    });
    test('does not fire for StartDateTime/EndDateTime and the NONE forms', () {
      expect(
          fires('aa-interval-form-not-allowed', [
            '2026-07-04T08:00Z/2026-07-04T16:00Z',
            '2026-07-05T08:00Z/NONE',
            'NONE/2026-07-03T08:00Z',
          ]),
          isEmpty);
    });
  });

  group('aa-interval-form-not-allowed-v21', () {
    test('is a warning in version 2.1 that names version 3.0', () {
      final d = lintRule('aa-interval-form-not-allowed-v21',
              aa(['2026-07-04T08:00Z/PT8H'], version: '2.1'))
          .single;
      expect(d.message, contains('not allowed in version 3.0'));
      expect(d.message, contains('"2026-07-04T08:00Z/2026-07-04T16:00Z"'));
      expect(findRule('aa-interval-form-not-allowed-v21')!.severity,
          Severity.warning);
    });
    test('the 3.0 rule does not apply to version 2.1', () {
      expect(
          fires('aa-interval-form-not-allowed', ['2026-07-04T08:00Z/PT8H'],
              version: '2.1'),
          isEmpty);
    });
  });

  group('aa-intervals-overlap', () {
    test('fires for overlapping intervals', () {
      expect(
          fires('aa-intervals-overlap', [
            '2026-07-04T08:00Z/2026-07-04T12:00Z',
            '2026-07-04T10:00Z/2026-07-04T16:00Z',
          ]),
          [6]);
      expect(
          fires('aa-intervals-overlap', [
            'NONE/2026-07-05T00:00Z',
            '2026-07-04T10:00Z/2026-07-04T16:00Z',
          ]),
          [6]);
    });
    test('does not fire for separate or touching intervals', () {
      expect(
          fires('aa-intervals-overlap', [
            '2026-07-04T08:00Z/2026-07-04T12:00Z',
            '2026-07-04T12:00Z/2026-07-04T16:00Z',
            '2026-07-05T08:00Z/NONE',
          ]),
          isEmpty);
    });
    test('does not fire for exact duplicates (aa-duplicate reports them)', () {
      expect(
          fires('aa-intervals-overlap', [
            '2026-07-04T08:00Z/2026-07-04T12:00Z',
            '2026-07-04T08:00Z/2026-07-04T12:00Z',
          ]),
          isEmpty);
    });
  });

  group('aa-intervals-adjacent', () {
    test('fires for touching intervals', () {
      expect(
          fires('aa-intervals-adjacent', [
            '2026-07-04T08:00Z/2026-07-04T12:00Z',
            '2026-07-04T12:00Z/2026-07-04T16:00Z',
          ]),
          [6]);
      expect(
          messages('aa-intervals-adjacent', [
            '2026-07-04T08:00Z/2026-07-04T12:00Z',
            '2026-07-04T12:00Z/2026-07-04T16:00Z',
          ]).single,
          contains('AA 2026-07-04T08:00Z/2026-07-04T16:00Z'));
    });
    test('does not fire with a gap', () {
      expect(
          fires('aa-intervals-adjacent', [
            'NONE/2026-03-18T23:59Z',
            '2026-03-19T00:00Z/NONE',
          ]),
          isEmpty);
    });
  });

  group('aa-intervals-not-sorted', () {
    test('fires when an interval starts before an earlier one', () {
      expect(
          fires('aa-intervals-not-sorted', [
            '2026-07-05T08:00Z/2026-07-05T12:00Z',
            '2026-07-04T08:00Z/2026-07-04T12:00Z',
            '2026-07-06T08:00Z/2026-07-06T12:00Z',
          ]),
          [6]);
      expect(
          fires('aa-intervals-not-sorted', [
            '2026-07-05T08:00Z/2026-07-05T12:00Z',
            'NONE/2026-07-04T12:00Z',
          ]),
          [6]);
    });
    test('does not fire for sorted intervals', () {
      expect(
          fires('aa-intervals-not-sorted', [
            '2026-07-04T08:00Z/2026-07-04T12:00Z',
            '2026-07-05T08:00Z/2026-07-05T12:00Z',
            'MON 09:00Z/10:00Z',
          ]),
          isEmpty);
    });
    test('does not apply to version 2.1 (aa-intervals-not-sorted-v21 does)',
        () {
      expect(
          fires(
              'aa-intervals-not-sorted',
              [
                '2026-07-05T08:00Z/2026-07-05T12:00Z',
                '2026-07-04T08:00Z/2026-07-04T12:00Z',
              ],
              version: '2.1'),
          isEmpty);
    });
  });

  group('aa-intervals-not-sorted-v21', () {
    const unsorted = [
      '2026-07-05T08:00Z/2026-07-05T12:00Z',
      '2026-07-04T08:00Z/2026-07-04T12:00Z',
    ];
    test('is an error in version 2.1', () {
      final d = lintRule('aa-intervals-not-sorted-v21',
              aa(unsorted.toList(), version: '2.1'))
          .single;
      expect(d.line, 6);
      expect(d.severity, Severity.error);
      expect(d.message, contains('Version 2.1 requires'));
    });
    test('applies to version 2.0 (checked as 2.1) and to --target 2.1', () {
      expect(
          fires('aa-intervals-not-sorted-v21', unsorted.toList(),
              version: '2.0'),
          [6]);
      expect(
          linesOf('aa-intervals-not-sorted-v21', aa(unsorted.toList()),
              target: SpecVersion.v2_1),
          [6]);
    });
    test('does not apply to version 3.0', () {
      expect(fires('aa-intervals-not-sorted-v21', unsorted.toList()), isEmpty);
    });
    test('does not fire for sorted intervals', () {
      expect(
          fires(
              'aa-intervals-not-sorted-v21',
              [
                'NONE/2026-07-04T00:00Z',
                '2026-07-04T08:00Z/2026-07-04T12:00Z',
                '2026-07-05T08:00Z/NONE',
              ],
              version: '2.1'),
          isEmpty);
    });
  });

  group('aa-weekday-invalid-name', () {
    test('fires for wrong names', () {
      for (final v in [
        'MO-FR 09:00Z/11:00Z',
        'MONDAY 09:00Z/11:00Z',
        'MON-FRI,PH 09:00Z/11:00Z',
        'MON,,FRI 09:00Z/11:00Z',
        'MON-WED-FRI 09:00Z/11:00Z',
        'MON- 09:00Z/11:00Z',
        'SR 09:00Z/11:00Z',
      ]) {
        expect(fires('aa-weekday-invalid-name', [v]), isNotEmpty, reason: v);
      }
      expect(messages('aa-weekday-invalid-name', ['MONDAY 09:00Z/11:00Z']),
          [contains('"MON"')]);
    });
    test('points to the wrong name', () {
      final d =
          lintRule('aa-weekday-invalid-name', aa(['MON,TUX,FRI 09:00Z/11:00Z']))
              .single;
      expect(d.column, 8);
      expect(d.endColumn, 11);
    });
    test('does not fire for valid names', () {
      expect(fires('aa-weekday-invalid-name', ['MON-FRI,SUN 09:00Z/11:00Z']),
          isEmpty);
    });
  });

  group('aa-weekday-range-same-day', () {
    test('fires for MON-MON', () {
      expect(
          fires('aa-weekday-range-same-day', ['MON-MON 09:00Z/11:00Z']), [5]);
      expect(fires('aa-weekday-range-same-day', ['TUE,SUN-SUN 09:00Z/11:00Z']),
          [5]);
    });
    test('does not fire for a single day or a real range', () {
      expect(
          fires('aa-weekday-range-same-day',
              ['MON 09:00Z/11:00Z', 'SUN-MON 09:00Z/11:00Z']),
          isEmpty);
    });
  });

  group('aa-weekday-list-has-spaces', () {
    test('fires for spaces in the list', () {
      expect(
          fires('aa-weekday-list-has-spaces', ['MON, WED 09:00Z/11:00Z']), [5]);
      expect(fires('aa-weekday-list-has-spaces', ['MON - FRI 09:00Z/11:00Z']),
          [5]);
      expect(
          fires('aa-weekday-list-has-spaces', ['MON WED 09:00Z/11:00Z']), [5]);
    });
    test('the list is still read', () {
      final c = parseAa('MON, WED 09:00Z/11:00Z') as AaWeekdayCommand;
      expect(c.weekdays, {1, 3});
    });
    test('does not fire without spaces', () {
      expect(fires('aa-weekday-list-has-spaces', ['MON,WED 09:00Z/11:00Z']),
          isEmpty);
    });
  });

  group('aa-weekday-duplicate-day', () {
    test('fires for a day in the list twice', () {
      expect(fires('aa-weekday-duplicate-day', ['MON-FRI,WED 09:00Z/11:00Z']),
          [5]);
    });
    test('does not fire without duplicates', () {
      expect(fires('aa-weekday-duplicate-day', ['MON-FRI,SUN 09:00Z/11:00Z']),
          isEmpty);
    });
  });

  group('aa-weekday-every-day', () {
    test('fires for all seven days', () {
      expect(fires('aa-weekday-every-day', ['MON-SUN 09:00Z/11:00Z']), [5]);
      expect(fires('aa-weekday-every-day', ['SAT-FRI 09:00Z/11:00Z']), [5]);
    });
    test('does not fire for six days', () {
      expect(fires('aa-weekday-every-day', ['MON-SAT 09:00Z/11:00Z']), isEmpty);
    });
    test('fires also when the command has another info', () {
      expect(fires('aa-weekday-every-day', ['MON-SUN 06:00:00Z/20:00Z']), [5]);
    });
    test('does not fire when the command cannot be read', () {
      expect(fires('aa-weekday-every-day', ['MON-SUN 06:00Z/25:00Z']), isEmpty);
    });
  });

  group('aa-date-range-end-before-start', () {
    test('fires when the end date is before the start date', () {
      expect(
          fires('aa-date-range-end-before-start',
              ['MON 09:00Z/11:00Z 2026-10-24/2026-03-29']),
          [5]);
    });
    test('does not fire for the same date', () {
      expect(
          fires('aa-date-range-end-before-start',
              ['MON 09:00Z/11:00Z 2026-07-06/2026-07-06']),
          isEmpty);
    });
  });

  group('aa-date-range-none-none', () {
    test('fires for NONE/NONE', () {
      expect(fires('aa-date-range-none-none', ['MON 09:00Z/11:00Z NONE/NONE']),
          [5]);
    });
    test('does not fire for one open end', () {
      expect(
          fires(
              'aa-date-range-none-none', ['MON 09:00Z/11:00Z NONE/2026-10-31']),
          isEmpty);
    });
  });

  group('aa-weekday-never-active', () {
    test('fires when no weekday is in the date range', () {
      expect(
          fires('aa-weekday-never-active',
              ['SAT,SUN 08:00Z/18:00Z 2026-07-06/2026-07-10']),
          [5]);
    });
    test('fires when AA EXCEPT removes every day', () {
      expect(
          fires('aa-weekday-never-active', [
            'MON 08:00Z/18:00Z 2026-07-06/2026-07-13',
            'EXCEPT 2026-07-06/2026-07-13',
          ]),
          [5]);
    });
    test('does not fire when a day is left', () {
      expect(
          fires('aa-weekday-never-active', [
            'SAT,SUN 08:00Z/18:00Z 2026-07-04/2026-07-05',
            'EXCEPT 2026-07-04',
          ]),
          isEmpty);
    });
    test('overlapping and touching AA EXCEPT ranges are joined', () {
      // The Mondays are 07-06, 07-13, 07-20 and 07-27.
      expect(
          fires('aa-weekday-never-active', [
            'MON 08:00Z/18:00Z 2026-07-06/2026-07-27',
            'EXCEPT 2026-07-15/2026-07-27',
            'EXCEPT 2026-07-06/2026-07-10',
            'EXCEPT 2026-07-11/2026-07-20',
          ]),
          [5]);
      expect(
          fires('aa-weekday-never-active', [
            'MON 08:00Z/18:00Z 2026-07-06/2026-07-27',
            'EXCEPT 2026-07-21/2026-07-27',
            'EXCEPT 2026-07-06/2026-07-19',
          ]),
          isEmpty);
    });
  });

  group('aa-except-end-before-start', () {
    test('fires for a reversed range', () {
      expect(
          fires('aa-except-end-before-start', ['EXCEPT 2027-01-01/2026-12-31']),
          [5]);
    });
    test('does not fire for a correct range', () {
      expect(
          fires('aa-except-end-before-start', ['EXCEPT 2026-12-31/2027-01-01']),
          isEmpty);
    });
  });

  group('aa-except-without-weekday', () {
    test('fires without a weekday command', () {
      expect(
          fires('aa-except-without-weekday', [
            '2026-12-24T07:00Z/2026-12-26T15:00Z',
            'EXCEPT 2026-12-25',
          ]),
          [6]);
      expect(fires('aa-except-without-weekday', ['EXCEPT 2026-12-25']), [5]);
    });
    test('does not fire with a weekday command after it', () {
      expect(
          fires('aa-except-without-weekday', [
            'EXCEPT 2026-12-25',
            'MON-FRI 07:00Z/15:00Z',
          ]),
          isEmpty);
    });
  });

  group('aa-except-no-effect', () {
    test('fires for a date outside every date range', () {
      expect(
          fires('aa-except-no-effect', [
            'MON-FRI 07:00Z/15:00Z 2026-03-29/2026-10-24',
            'EXCEPT 2026-12-25',
          ]),
          [6]);
    });
    test('fires for a date without a scheduled weekday', () {
      expect(
          fires('aa-except-no-effect', [
            'MON-FRI 07:00Z/15:00Z',
            'EXCEPT 2026-12-26',
          ]),
          [6]);
      expect(
          messages('aa-except-no-effect', [
            'MON-FRI 07:00Z/15:00Z',
            'EXCEPT 2026-12-26/2026-12-27',
          ]).single,
          contains('2026-12-26 to 2026-12-27'));
    });
    test('does not fire when a window is removed', () {
      expect(
          fires('aa-except-no-effect', [
            'MON-FRI 07:00Z/15:00Z',
            'EXCEPT 2026-12-25',
            'EXCEPT 2026-12-26/2026-12-28',
          ]),
          isEmpty);
    });
    test('does not fire when a weekday command cannot be read', () {
      expect(
          fires('aa-except-no-effect', [
            'MO-FR 07:00Z/15:00Z',
            'EXCEPT 2026-12-26',
          ]),
          isEmpty);
    });
  });

  group('aa-sun-event-not-allowed', () {
    test('fires for sun events in intervals and dates', () {
      expect(fires('aa-sun-event-not-allowed', ['2026-07-04T08:00Z/SS']), [5]);
      expect(fires('aa-sun-event-not-allowed', ['SR/2026-07-04T20:00Z']), [5]);
      expect(fires('aa-sun-event-not-allowed', ['2026-07-04TSR/NONE']), [5]);
      expect(fires('aa-sun-event-not-allowed', ['EXCEPT SR']), [5]);
    });
    test('does not fire in weekday commands', () {
      expect(fires('aa-sun-event-not-allowed', ['SR/SS', 'MON BCMT/EECT']),
          isEmpty);
    });
  });

  group('aa-sun-event-order-changes', () {
    // Positions far from Greenwich. A sun event can be on another UTC day
    // than its local solar day.
    const texas = 'AH 4500 FT AMSL\nAL GND\nV X=30:00:00N 097:00:00W\nDC 5\n';
    const myanmar = 'AH 4500 FT AMSL\nAL GND\nV X=20:00:00N 096:00:00E\nDC 5\n';

    test('fires when sunrise moves across a fixed time', () {
      // In Ljubljana, sunrise is between 03:10Z and 06:45Z during the year.
      expect(fires('aa-sun-event-order-changes', ['06:00Z/SR']), [5]);
      final m = messages(
              'aa-sun-event-order-changes', ['06:00Z/SR 2026-01-01/2026-12-31'])
          .single;
      expect(m, contains('SR (sunrise)'));
      expect(m, contains('local solar day Thursday 2026-02-19'));
      expect(m, contains('This happens 2 times'));
      expect(
          m,
          contains('of 365 checked days the window ends on the next local '
              'solar day'));
      expect(m, contains('To fix it, split the command with date ranges'));
    });
    test('is an error, because the specification says "must"', () {
      expect(findRule('aa-sun-event-order-changes')!.severity, Severity.error);
    });
    test('does not fire when the times are less than 2 minutes apart', () {
      expect(
          fires('aa-sun-event-order-changes',
              ['03:12Z/SR 2026-06-20/2026-06-22']),
          isEmpty);
    });
    test('names the days of the change and the times of that day', () {
      // Sunset in Ljubljana is before 17:00Z until about 9 March.
      final m = messages(
              'aa-sun-event-order-changes', ['17:00Z/SS 2026-03-01/2026-03-31'])
          .single;
      expect(
          m,
          contains('On the local solar day Sunday 2026-03-08 the start is '
              '2026-03-08T17:00'));
      expect(m, contains('so the window ends on the next local solar day'));
      expect(
          m,
          contains('On Monday 2026-03-09 the start is 2026-03-09T17:00Z and '
              'the end is SS (sunset) at 2026-03-09T17:0'));
      expect(m, contains('On 8 of 31 checked days'));
    });
    test('shows seconds when the start and the end are in one minute', () {
      final m = messages(
              'aa-sun-event-order-changes', ['17:00Z/SS 2026-03-01/2026-03-31'])
          .single;
      expect(m, matches(RegExp(r'at 2026-03-08T16:59:\d\dZ')));
    });
    test('does not fire far from Greenwich: the day is local', () {
      // In Texas, sunset is before 00:00Z in winter and after it in summer.
      // In Myanmar, sunrise is just before or just after 00:00Z. On the
      // local solar day, the order does not change.
      for (final v in [
        'SR/SS',
        'SS/SR 2026-01-01/2026-12-31',
        'MON-FRI 14:00Z/SS 2026-01-01/2026-12-31',
        'BCMT/EECT 2026-01-01/2026-12-31',
        'MON-FRI 07:00Z/SS 2026-04-01/2026-09-30',
        'SS/03:00Z',
      ]) {
        expect(fires('aa-sun-event-order-changes', [v], geo: texas), isEmpty,
            reason: v);
        expect(lintAll(aa([v], geo: texas)).where(aaProblem), isEmpty,
            reason: 'Texas $v');
      }
      for (final v in ['SR/SS', 'SS/SR', 'SR/12:00Z', '20:00Z/SS']) {
        expect(lintAll(aa([v], geo: myanmar)).where(aaProblem), isEmpty,
            reason: 'Myanmar $v');
      }
    });
    test('the result does not depend on the date of the run', () {
      // Without a date range, the days 2026 to 2029 are checked.
      final m = messages('aa-sun-event-order-changes', ['06:00Z/SR']).single;
      expect(m, contains('Thursday 2026-02-19'));
      // An open end that starts long ago is checked from 2026.
      expect(
          messages('aa-sun-event-order-changes', ['06:00Z/SR 2020-01-01/NONE'])
              .single,
          m);
      // An open end in the future is checked from its start.
      expect(
          messages('aa-sun-event-order-changes', ['06:00Z/SR 2031-01-01/NONE'])
              .single,
          contains('2031-'));
      // An open start is checked for the four years before the end.
      expect(
          messages('aa-sun-event-order-changes', ['06:00Z/SR NONE/2022-12-31'])
              .single,
          contains('2019-'));
    });
    test('the excepted days are not checked', () {
      expect(
          fires('aa-sun-event-order-changes', [
            '17:00Z/SS 2026-03-01/2026-03-31',
            'EXCEPT 2026-03-01/2026-03-15',
          ]),
          isEmpty);
    });
    test('does not fire when the order is the same every day', () {
      expect(
          fires('aa-sun-event-order-changes', [
            'MON-FRI 07:00Z/SS 2026-04-01/2026-09-30',
            'SR/SS',
            'SS/SR',
            '12:00Z/SS',
            'SS/02:00Z',
          ]),
          isEmpty);
    });
    test('days without the sun event are not compared', () {
      const tromso =
          'AH 4500 FT AMSL\nAL GND\nV X=69:39:00N 018:57:00E\nDC 5\n';
      expect(fires('aa-sun-event-order-changes', ['07:00Z/SS'], geo: tromso),
          isEmpty);
    });
  });

  group('aa-sun-event-near-fixed-time', () {
    test('fires when the times are less than 5 minutes apart', () {
      // Sunrise in Ljubljana on 20-22 June is at about 03:13Z.
      for (final v in ['03:12Z', '03:09Z', '03:17Z']) {
        expect(
            fires('aa-sun-event-near-fixed-time',
                ['$v/SR 2026-06-20/2026-06-22']),
            [5],
            reason: v);
      }
      final m = messages('aa-sun-event-near-fixed-time',
          ['03:09Z/SR 2026-06-20/2026-06-22']).single;
      expect(m, contains('less than 5 minutes apart'));
      expect(m, contains('differ by a few minutes'));
      expect(m, contains('Use a fixed time that is further'));
      expect(m, isNot(contains('one minute')));
      expect(
          fires('aa-sun-event-near-fixed-time',
              ['03:05Z/SR 2026-06-20/2026-06-22']),
          isEmpty);
    });
    test('the texts say "a few minutes", as the specification', () {
      final r = findRule('aa-sun-event-near-fixed-time')!;
      expect(r.explanation, contains('a few minutes'));
      expect(r.explanation, isNot(contains('one minute')));
    });
    test('does not fire when the order changes', () {
      expect(fires('aa-sun-event-near-fixed-time', ['06:00Z/SR']), isEmpty);
    });
    test('does not fire when the times are far apart', () {
      expect(
          fires('aa-sun-event-near-fixed-time',
              ['02:00Z/SR 2026-06-20/2026-06-22', 'SR/SS']),
          isEmpty);
    });
  });

  group('aa-sun-event-fixed-start-near-day-start', () {
    // At 15° E the local solar day starts at 23:00Z.
    const at15 = 'AH 4500 FT AMSL\nAL GND\nV X=46:00:00N 015:00:00E\nDC 5\n';
    test('fires for a fixed start at the start of the local solar day', () {
      expect(
          fires('aa-sun-event-fixed-start-near-day-start', ['23:00Z/SS'],
              geo: at15),
          [5]);
      expect(
          fires('aa-sun-event-fixed-start-near-day-start', ['22:59Z/SS'],
              geo: at15),
          [5]);
      final m = messages(
              'aa-sun-event-fixed-start-near-day-start', ['23:00Z/SS'],
              geo: at15)
          .single;
      expect(m, contains('(15.00° E) the local solar day starts at 23:00Z'));
      expect(
          m,
          contains('Use a start time that is at least 2 minutes from '
              '23:00Z'));
      expect(findRule('aa-sun-event-fixed-start-near-day-start')!.severity,
          Severity.warning);
    });
    test('does not fire for other times or for a fixed end', () {
      for (final v in ['23:05Z/SS', '05:00Z/SS', 'SR/23:00Z', 'SR/SS']) {
        expect(fires('aa-sun-event-fixed-start-near-day-start', [v], geo: at15),
            isEmpty,
            reason: v);
      }
      // 00:00Z at 14° E is not near the start of the day (23:04Z).
      expect(fires('aa-sun-event-fixed-start-near-day-start', ['00:00Z/SS']),
          isEmpty);
    });
  });

  group('aa-sun-event-missing-day', () {
    const tromso = 'AH 4500 FT AMSL\nAL GND\nV X=69:39:00N 018:57:00E\nDC 5\n';
    test('fires in polar regions', () {
      expect(
          fires('aa-sun-event-missing-day', ['SR/SS 2026-06-01/2026-06-30'],
              geo: tromso),
          [5]);
    });
    test('the message says what the window means (the table)', () {
      String m(String v) =>
          messages('aa-sun-event-missing-day', [v], geo: tromso).single;
      final summer = m('SR/SS 2026-06-10/2026-06-20');
      expect(summer, contains('On 11 of 11 checked days'));
      expect(summer, contains('SR (sunrise) and SS (sunset) do not happen'));
      expect(summer, contains('higher than 0°50′ below the horizon'));
      expect(summer,
          contains('the window is active for the whole local solar day'));
      expect(m('SR/SS 2026-12-10/2026-12-20'),
          contains('the window is not active'));
      expect(m('SS/SR 2026-06-10/2026-06-20'),
          contains('the window is not active'));
      expect(m('SS/SR 2026-12-10/2026-12-20'),
          contains('the window is active for the whole local solar day'));
      expect(m('07:00Z/SS 2026-06-10/2026-06-20'),
          contains('the window ends at the end of the local solar day'));
      expect(m('SR/15:00Z 2026-06-10/2026-06-20'),
          contains('the window starts at the start of the local solar day'));
      expect(m('07:00Z/SS 2026-12-10/2026-12-20'),
          contains('the window is not active'));
      final twilight = m('BCMT/EECT 2026-06-10/2026-06-20');
      expect(twilight, contains('higher than 6° below the horizon'));
    });
    test('lists the days above and the days below the horizon', () {
      final m =
          messages('aa-sun-event-missing-day', ['SR/SS'], geo: tromso).single;
      expect(m, contains('lower than'));
      expect(m, contains('higher than'));
    });
    test('groups the days by the events that do not happen', () {
      // On 18 May 2026 only the sunset is missing. On 19 and 20 May both
      // events are missing.
      final m = messages(
              'aa-sun-event-missing-day', ['SS/SR 2026-05-18/2026-05-20'],
              geo: tromso)
          .single;
      expect(
          m,
          contains('On 1 of 3 checked days (the first is Monday 2026-05-18) '
              'SS (sunset) does not happen'));
      expect(
          m,
          contains('On 2 of 3 checked days (the first is Tuesday 2026-05-19) '
              'SR (sunrise) and SS (sunset) do not happen'));
    });
    test('the night after the polar day ends at the next sunrise', () {
      // 25 July 2026: the sun sets at 22:38Z and rises at 23:04Z.
      for (final id in [
        'aa-weekday-never-active',
        'aa-sun-event-missing-day'
      ]) {
        expect(fires(id, ['SS/SR 2026-07-25/2026-07-25'], geo: tromso), isEmpty,
            reason: id);
      }
      expect(
          fires('aa-weekday-never-active', ['EECT/BCMT 2026-06-28/2026-06-28'],
              geo: 'AH 4500 FT AMSL\nAL GND\nV X=60:45:00N 000:00:00E\nDC 5\n'),
          isEmpty);
    });
    test('the explanation separates the specification and openair-lint', () {
      final e = findRule('aa-sun-event-missing-day')!.explanation;
      expect(e, contains('AA SR/SS means active for the whole day in summer'));
      expect(e, contains('openair-lint uses these choices'));
      expect(e, isNot(contains('The specification defines the meaning')));
    });
    test('does not fire at 46° N', () {
      expect(fires('aa-sun-event-missing-day', ['SR/SS']), isEmpty);
    });
    test('is an info', () {
      expect(findRule('aa-sun-event-missing-day')!.severity, Severity.info);
    });
  });

  group('dates without a time of day', () {
    test('a week date pair also gets aa-value-form-not-allowed', () {
      final text = aa(['2026-W27-6/2026-W27-7']);
      final forms = lintRule('aa-value-form-not-allowed', text);
      expect([
        for (final d in forms) d.message
      ], [
        contains('"2026-W27-6" uses a week date'),
        contains('"2026-W27-7" uses a week date'),
      ]);
      expect(forms.first.message, contains('"2026-07-04"'));
      final syntax = lintRule('aa-invalid-syntax', text).single.message;
      // The examples use the dates of the command.
      expect(syntax, contains('2026-07-04T00:00Z/2026-07-06T00:00Z'));
      expect(syntax, contains('00:00Z/24:00Z 2026-07-04/2026-07-05'));
    });
    test('plain dates get only aa-invalid-syntax', () {
      final text = aa(['2026-07-04/2026-07-05']);
      expect(lintRule('aa-value-form-not-allowed', text), isEmpty);
      expect(lintRule('aa-invalid-syntax', text).single.message,
          contains('2026-07-04T00:00Z/2026-07-06T00:00Z'));
    });
  });

  group('aa-sun-event-near-date-line', () {
    String geo(String lon) =>
        'AH 4500 FT AMSL\nAL GND\nV X=17:00:00S $lon\nDC 5\n';
    const across = 'AH 4500 FT AMSL\nAL GND\n'
        'DP 17:00:00S 179:50:00E\n'
        'DP 17:00:00S 179:50:00W\n'
        'DP 17:10:00S 179:50:00W\n'
        'DP 17:10:00S 179:50:00E\n'
        'DP 17:00:00S 179:50:00E\n';
    test('fires for every sun window near longitude 180°', () {
      expect(
          fires('aa-sun-event-near-date-line',
              ['SAT SR/SS 2026-07-04/2026-07-04', 'SUN 12:01Z/SS'],
              geo: across),
          [5, 6]);
      expect(
          fires('aa-sun-event-near-date-line', ['SR/SS'],
              geo: geo('179:45:00W')),
          [5]);
      expect(
          findRule('aa-sun-event-near-date-line')!.severity, Severity.warning);
    });
    test('the fixed start rule does not report the same command', () {
      expect(
          fires('aa-sun-event-fixed-start-near-day-start', ['SUN 12:01Z/SS'],
              geo: across),
          isEmpty);
    });
    test('does not fire away from longitude 180° or without a sun event', () {
      expect(
          fires('aa-sun-event-near-date-line', ['SR/SS'],
              geo: geo('179:00:00E')),
          isEmpty);
      expect(
          fires('aa-sun-event-near-date-line', ['MON 18:00Z/06:00Z'],
              geo: across),
          isEmpty);
    });
  });

  group('sun event rules in version 2.1 files', () {
    // aa-needs-version-3 reports the command, and a 2.1 reader ignores all
    // AA commands of the airspace. The sun event rules do not add more.
    const tromso = 'AH 4500 FT AMSL\nAL GND\nV X=69:39:00N 018:57:00E\nDC 5\n';
    test('only aa-needs-version-3 is reported', () {
      for (final (v, geo) in [
        ('06:00Z/SR', geometry),
        ('03:12Z/SR 2026-06-20/2026-06-22', geometry),
        ('SR/SS 2026-12-01/2026-12-31', tromso),
      ]) {
        final ids = {
          for (final d in lintAll(aa([v], version: '2.1', geo: geo)))
            if (d.ruleId.startsWith('aa-')) d.ruleId
        };
        expect(ids, {'aa-needs-version-3'}, reason: v);
      }
    });
  });

  group('messages for sun windows name the local day', () {
    const east170 = 'AH 4500 FT AMSL\nAL GND\nV X=46:00:00N 170:00:00E\nDC 5\n';
    test('aa-except-no-effect', () {
      final m = messages(
              'aa-except-no-effect', ['MON SR/SS', 'EXCEPT 2026-07-05'],
              geo: east170)
          .single;
      expect(
          m,
          contains('No weekday command has a window on Sunday '
              '2026-07-05 (the local day at the airspace)'));
      expect(m, isNot(contains('starts on')));
      final mixed = messages('aa-except-no-effect',
              ['MON SR/SS', 'TUE 08:00Z/10:00Z', 'EXCEPT 2026-07-05'],
              geo: east170)
          .single;
      expect(
          mixed,
          contains('A window with a sun event belongs to the '
              'local day at the airspace'));
    });
    test('aa-weekday-never-active', () {
      final m = messages(
              'aa-weekday-never-active', ['MON SR/SS 2026-07-07/2026-07-12'],
              geo: east170)
          .single;
      expect(m, contains('This command has no window in the date range'));
      expect(m, contains('mean the local day at the airspace'));
      expect(m, isNot(contains('starts in')));
    });
  });

  group('sun windows and local solar days', () {
    // Fiji: the local solar day starts at about 12:06Z of the UTC day
    // before.
    const fiji = 'AH 4500 FT AMSL\nAL GND\nV X=18:00:00S 178:30:00E\nDC 5\n';
    test('the weekday and the date range refer to the local solar day', () {
      // 2026-06-21 is a Sunday. The window of this local solar day starts
      // at 20:00Z on Saturday 2026-06-20 (UTC).
      expect(
          lintAll(aa(['SUN 20:00Z/SS 2026-06-21/2026-06-21'], geo: fiji))
              .where(aaProblem),
          isEmpty);
      expect(
          fires('aa-weekday-never-active',
              ['SAT 20:00Z/SS 2026-06-21/2026-06-21'],
              geo: fiji),
          [5]);
    });
    test('AA EXCEPT dates are local solar days', () {
      expect(
          fires('aa-weekday-never-active',
              ['SUN SR/SS 2026-06-21/2026-06-21', 'EXCEPT 2026-06-21'],
              geo: fiji),
          [5]);
      expect(
          fires('aa-except-no-effect',
              ['SUN SR/SS 2026-06-21/2026-06-21', 'EXCEPT 2026-06-21'],
              geo: fiji),
          isEmpty);
    });
  });

  group('aa-sun-event-no-position', () {
    test('fires without geometry', () {
      expect(
          fires('aa-sun-event-no-position', ['SR/SS'],
              geo: 'AH 4500 FT AMSL\nAL GND\nDC 5\n'),
          [5]);
    });
    test('does not fire with geometry', () {
      expect(fires('aa-sun-event-no-position', ['SR/SS']), isEmpty);
    });
  });

  group('aa-none-combined (version 2.1)', () {
    test('fires for AA NONE with other AA commands', () {
      expect(
          fires('aa-none-combined',
              ['NONE', '2026-07-04T08:00Z/2026-07-04T16:00Z'],
              version: '2.1'),
          [5]);
      expect(
          fires('aa-none-combined',
              ['2026-07-04T08:00Z/2026-07-04T16:00Z', 'NONE'],
              version: '2.1'),
          [6]);
    });
    test('does not fire for AA NONE alone', () {
      expect(fires('aa-none-combined', ['NONE'], version: '2.1'), isEmpty);
    });
    test('does not apply to version 3.0 (aa-none-removed reports AA NONE)', () {
      expect(
          fires('aa-none-combined',
              ['NONE', '2026-07-04T08:00Z/2026-07-04T16:00Z']),
          isEmpty);
    });
  });

  group('aa-duplicate', () {
    test('fires for the same meaning', () {
      expect(
          fires('aa-duplicate',
              ['MON-FRI 07:00Z/15:00Z', 'MON-FRI 07:00Z/15:00Z']),
          [6]);
      expect(
          fires('aa-duplicate', [
            '2026-07-04T08:00Z/2026-07-04T16:00Z',
            '20260704T0800Z/20260704T1600Z',
          ]),
          [6]);
      expect(
          fires('aa-duplicate',
              ['FRI,MON-THU 07:00Z/15:00Z', 'MON-FRI 07:00Z/15:00Z']),
          [6]);
      expect(fires('aa-duplicate', ['NONE', 'NONE']), [6]);
    });
    test('does not fire for different commands', () {
      expect(
          fires('aa-duplicate',
              ['MON-FRI 07:00Z/15:00Z', 'MON-FRI 07:00Z/16:00Z']),
          isEmpty);
    });
  });

  group('aa-order-not-recommended', () {
    test('fires for the wrong kind order', () {
      expect(
          fires('aa-order-not-recommended', [
            'EXCEPT 2026-12-25',
            'MON-FRI 06:00Z/14:00Z',
            '2026-07-04T08:00Z/2026-07-04T16:00Z',
          ]),
          [6, 7]);
    });
    test('fires for unsorted weekday commands and exceptions', () {
      expect(
          fires('aa-order-not-recommended', [
            'MON-FRI 07:00Z/15:00Z 2026-10-25/2027-03-27',
            'MON-FRI 06:00Z/14:00Z 2026-03-29/2026-10-24',
          ]),
          [6]);
      expect(
          fires('aa-order-not-recommended', [
            'MON-FRI 07:00Z/15:00Z 2026-10-25/2027-03-27',
            'SAT 07:00Z/15:00Z',
          ]),
          [6]);
      expect(
          fires('aa-order-not-recommended', [
            'MON-FRI 07:00Z/15:00Z',
            'EXCEPT 2026-12-25',
            'EXCEPT 2026-05-01',
          ]),
          [7]);
    });
    test('does not fire for the recommended order', () {
      expect(
          fires('aa-order-not-recommended', [
            '2026-07-04T08:00Z/2026-07-04T16:00Z',
            'SAT 07:00Z/15:00Z',
            'MON-FRI 06:00Z/14:00Z 2026-03-29/2026-10-24',
            'MON-FRI 07:00Z/15:00Z 2026-10-25/2027-03-27',
            'EXCEPT 2026-12-25',
            'EXCEPT 2026-12-31/2027-01-01',
          ]),
          isEmpty);
    });
    test('does not report unsorted intervals (another rule does)', () {
      expect(
          fires('aa-order-not-recommended', [
            '2026-07-05T08:00Z/2026-07-05T16:00Z',
            '2026-07-04T08:00Z/2026-07-04T16:00Z',
          ]),
          isEmpty);
    });
  });

  group('aa-needs-version-3', () {
    test('fires for 3.0 features in version 2.1', () {
      expect(
          fires(
              'aa-needs-version-3',
              [
                'MON-FRI 07:00Z/15:00Z',
                'EXCEPT 2026-12-25',
                'SR/SS',
              ],
              version: '2.1'),
          [5, 6, 7]);
      expect(messages('aa-needs-version-3', ['SR/SS'], version: '2.1').single,
          contains('sun events'));
    });
    test('fires for version 2.0 (checked as 2.1)', () {
      expect(fires('aa-needs-version-3', ['MON 07:00Z/15:00Z'], version: '2.0'),
          [5]);
    });
    test('does not fire for intervals in 2.1', () {
      expect(
          fires('aa-needs-version-3',
              ['2026-07-04T08:00Z/2026-07-04T16:00Z', 'NONE/2026-07-05T00:00Z'],
              version: '2.1'),
          isEmpty);
    });
    test('does not fire in version 3.0', () {
      expect(fires('aa-needs-version-3', ['MON-FRI 07:00Z/15:00Z']), isEmpty);
    });
    test('--target 2.1 wins over the header', () {
      expect(
          linesOf('aa-needs-version-3', aa(['MON 07:00Z/15:00Z']),
              target: SpecVersion.v2_1),
          [5]);
    });
  });

  group('all activation rules', () {
    test('the spec examples have no errors or warnings', () {
      final examples = [
        [
          '2023-12-16T12:00Z/2023-12-16T13:00Z   * Active from 12:00 to 13:00',
          '2024-12-17T00:00Z/2024-12-17T24:00Z   * Active for the entire day',
        ],
        ['2024-12-17T00:00Z/NONE'],
        ['NONE/2024-12-18T00:00Z'],
        ['MON 09:00Z/11:30Z'],
        ['MON-FRI 07:00Z/15:00Z'],
        ['SAT,SUN 08:00Z/18:00Z'],
        ['06:00Z/20:00Z'],
        ['FRI 22:00Z/02:00Z'],
        ['MON-FRI 06:00Z/14:00Z 2026-03-29/2026-10-24'],
        ['SR/SS'],
        ['SS/SR'],
        ['SAT,SUN BCMT/EECT'],
        ['MON-FRI 07:00Z/SS 2026-04-01/2026-09-30'],
        [
          'MON-FRI 06:00Z/14:00Z 2026-03-29/2026-10-24 * 08:00-16:00 CEST',
          'MON-FRI 07:00Z/15:00Z 2026-10-25/2027-03-27 * 08:00-16:00 CET',
        ],
        [
          'MON-FRI 07:00Z/15:00Z',
          'EXCEPT 2026-12-25',
          'EXCEPT 2026-12-31/2027-01-01',
        ],
        [
          '2026-07-04T08:00Z/2026-07-04T16:00Z',
          'MON-FRI 06:00Z/14:00Z 2026-03-29/2026-10-24',
          'MON-FRI 07:00Z/15:00Z 2026-10-25/2027-03-27',
          'EXCEPT 2026-12-25',
        ],
      ];
      final rules = [
        for (final g in ruleGroups)
          if (g.name == 'activation') ...g.rules
      ];
      final linter = Linter(LintOptions(rules: rules));
      for (final e in examples) {
        final bad = linter
            .lintString(aa(e))
            .diagnostics
            .where((d) => d.severity != Severity.info)
            .toList();
        expect(bad, isEmpty, reason: e.join('\n'));
      }
    });

    test('every rule example: the incorrect example fires the rule', () {
      // Wrap the AA lines of each example in an airspace and check that the
      // rule fires on the incorrect example and not on the correct one.
      final group = ruleGroups.firstWhere((g) => g.name == 'activation');
      for (final rule in group.rules) {
        String build(String example) {
          final v21 = example.contains('*VERSION: 2.1');
          final lines = [
            for (final l in example.split('\n'))
              if (l.startsWith('AA ')) l.substring(3) else if (l == 'AA') ''
          ];
          if (rule.id == 'aa-sun-event-missing-day') {
            final polar = example.contains('70°');
            return aa(lines,
                geo: 'AH 4500 FT AMSL\nAL GND\n'
                    'V X=${polar ? '70:00:00N' : '46:00:00N'} 014:00:00E\n'
                    'DC 5\n');
          }
          if (rule.id == 'aa-sun-event-no-position' &&
              !example.contains('V X=')) {
            return aa(lines, geo: 'AH 4500 FT AMSL\nAL GND\nDC 5\n');
          }
          if (example.contains('V X=')) {
            // The example has its own geometry.
            final geo = [
              for (final l in example.split('\n'))
                if (l.startsWith('V ') || l.startsWith('DC ')) l
            ];
            return aa(lines,
                geo: 'AH 4500 FT AMSL\nAL GND\n${geo.join('\n')}\n');
          }
          return aa(lines, version: v21 ? '2.1' : '3.0');
        }

        expect(lintRule(rule.id, build(rule.incorrectExample)), isNotEmpty,
            reason: '${rule.id}: incorrect example');
        expect(lintRule(rule.id, build(rule.correctExample)), isEmpty,
            reason: '${rule.id}: correct example');
      }
    });

    test('commands before the first AC are checked', () {
      final text = withHeader('AA MON-MON 09:00Z/10:00Z\n$validAirspace');
      expect(linesOf('aa-weekday-range-same-day', text), [3]);
    });

    test('nothing crashes on strange input', () {
      final strange = [
        '/',
        '//',
        '/NONE',
        'NONE/',
        'T/T',
        'P/P',
        '-',
        ',',
        'MON,',
        '-MON 09:00Z/10:00Z',
        'EXCEPT /',
        'EXCEPT 2026-01-01/',
        'éé',
        '2026-07-04T/2026-07-04T',
        'MON 09:00Z/10:00Z /',
        '99999999T9999Z/NONE',
        'P99999Y/2026-01-01T00:00Z',
        '2026-07-04T08:00Z/PT99999999999999999999H',
        '2026-07-04T08:00Z/P99999999999999999999D',
        '2026-07-04T08:00Z/PT99999999999999999999.5S',
        'P99999999999999999999W/2026-07-04T08:00Z',
        '2026-07-04T08:00Z/P9999-12-30T24:00:00',
        '2026-07-04T08:00Z/99999999999T16:00Z',
        '2026-07-04T08:00Z/99T16:00Z',
        '9999-12-31T23:00Z/PT2H',
        'MON 99999999999999999999Z/10:00Z',
        'MON 09:00Z/10:00Z 99999999999999999999/NONE',
        'EXCEPT 99999999999999999999',
        ' / ',
        '/ /',
        'MON / / 10:00Z',
        '${String.fromCharCode(0x2013)} / ${String.fromCharCode(0x2014)}',
      ];
      for (final s in strange) {
        final diags = lintAll(aa([s]));
        expect(diags.where((d) => d.ruleId == 'linter-internal-error'), isEmpty,
            reason: s);
      }
    });
  });
}
