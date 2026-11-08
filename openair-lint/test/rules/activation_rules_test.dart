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
        'PT8H/PT2H',
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

  group('aa-invalid-duration', () {
    test('fires for invalid durations', () {
      expect(fires('aa-invalid-duration', ['2026-07-04T08:00Z/P8H']), [5]);
      expect(fires('aa-invalid-duration', ['2026-07-04T08:00Z/PT']), [5]);
    });
    test('does not fire for valid durations', () {
      expect(fires('aa-invalid-duration', ['2026-07-04T08:00Z/PT8H']), isEmpty);
      expect(
          fires('aa-invalid-duration',
              ['2026-07-04T08:00Z/P0000-00-01T00:00:00']),
          isEmpty);
    });
    test('fires on the AA line for a very long duration', () {
      for (final v in [
        '2026-07-04T08:00Z/PT99999999999999999999H',
        '2026-07-04T08:00Z/P99999999999999999999D',
        '2026-07-04T08:00Z/P9000Y',
        'P3000Y/2026-07-04T08:00Z',
      ]) {
        final all = lintAll(aa([v]));
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

  group('aa-value-not-recommended-form', () {
    test('fires for other ISO 8601 forms', () {
      for (final v in [
        '20260704T0800Z/2026-07-04T16:00Z',
        '2026-07-04T08:00:00Z/2026-07-04T16:00Z',
        '2026-W27-6T08:00Z/2026-07-04T16:00Z',
        '2026-185T08:00Z/2026-07-04T16:00Z',
        'MON 0900Z/11:00Z',
        'MON 09Z/11:00Z',
        'EXCEPT 20261225',
      ]) {
        expect(fires('aa-value-not-recommended-form', [v]), [5], reason: v);
      }
    });
    test('does not fire for the recommended forms', () {
      expect(
          fires('aa-value-not-recommended-form', [
            '2026-07-04T08:00Z/2026-07-04T16:00Z',
            'MON 09:00Z/11:00Z 2026-01-01/2026-12-31',
            'EXCEPT 2026-12-25',
          ]),
          isEmpty);
    });
    test('the message gives the recommended form', () {
      expect(
          messages('aa-value-not-recommended-form', ['EXCEPT 2026-W52-5'])
              .single,
          contains('"2026-12-25"'));
    });
    test('is a warning, because the specification says "should"', () {
      expect(findRule('aa-value-not-recommended-form')!.severity,
          Severity.warning);
      expect(findRule('aa-interval-not-recommended-form')!.severity,
          Severity.warning);
    });
    test('version 2.1 has no recommended form', () {
      expect(
          fires('aa-value-not-recommended-form',
              ['2026-07-04T08:00:00Z/2026-07-04T16:00Z'],
              version: '2.1'),
          isEmpty);
      expect(
          fires('aa-interval-not-recommended-form', ['2026-07-04T08:00Z/PT8H'],
              version: '2.1'),
          isEmpty);
    });
    test('a fraction is cut, not rounded up to the next day', () {
      expect(
          messages('aa-value-not-recommended-form',
              ['MON 23:59:59.9999Z/24:00Z']).single,
          contains('"23:59:59Z"'));
      expect(
          fires('aa-interval-end-before-start',
              ['2026-07-04T23:59:59.9999Z/2026-07-05T00:00Z']),
          isEmpty);
      expect(
          fires('aa-time-24-as-start', ['MON 23:59:59.9999Z/24:00Z']), isEmpty);
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

  group('aa-interval-not-recommended-form', () {
    test('fires for durations and short ends', () {
      expect(
          fires('aa-interval-not-recommended-form', ['2026-07-04T08:00Z/PT8H']),
          [5]);
      expect(
          fires('aa-interval-not-recommended-form', ['PT8H/2026-07-04T16:00Z']),
          [5]);
      expect(
          fires(
              'aa-interval-not-recommended-form', ['2026-07-04T08:00Z/16:00Z']),
          [5]);
      expect(
          messages('aa-interval-not-recommended-form',
              ['2026-07-04T08:00Z/PT8H']).single,
          contains('2026-07-04T08:00Z/2026-07-04T16:00Z'));
    });
    test('fires for other ISO 8601 interval forms, which are not errors', () {
      for (final (v, full) in [
        ('2026-07-04T08:00Z/07-05T16:00Z', '2026-07-05T16:00Z'),
        ('2026-07-04T08:00Z/05T16:00Z', '2026-07-05T16:00Z'),
        ('20260704T0800Z/0705T1600Z', '2026-07-05T16:00Z'),
        ('2026-07-04T08:00Z/P0000-00-01T00:00:00', '2026-07-05T08:00Z'),
      ]) {
        final all = lintAll(aa([v]));
        // Only the two "recommended form" rules report these forms, as
        // warnings. They are not errors.
        expect(
            all
                .where((d) => d.ruleId.startsWith('aa-'))
                .where((d) => d.severity != Severity.info)
                .where((d) => !const {
                      'aa-interval-not-recommended-form',
                      'aa-value-not-recommended-form',
                    }.contains(d.ruleId)),
            isEmpty,
            reason: v);
        expect(
            all.where((d) =>
                d.severity == Severity.error && d.ruleId.startsWith('aa-')),
            isEmpty,
            reason: v);
        expect(messages('aa-interval-not-recommended-form', [v]).single,
            contains(full),
            reason: v);
      }
    });
    test('a short end with a date that does not exist is an error', () {
      expect(fires('aa-invalid-date', ['2026-07-04T08:00Z/07-32T16:00Z']), [5]);
      expect(
          messages('aa-invalid-date', ['2026-07-04T08:00Z/07-32T16:00Z'])
              .single,
          contains('from the start (2026-07-04)'));
    });
    test('does not fire for StartDateTime/EndDateTime', () {
      expect(
          fires('aa-interval-not-recommended-form',
              ['2026-07-04T08:00Z/2026-07-04T16:00Z']),
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
    // Positions where a sun event crosses 00:00Z during the year.
    const texas = 'AH 4500 FT AMSL\nAL GND\nV X=30:00:00N 097:00:00W\nDC 5\n';
    const myanmar = 'AH 4500 FT AMSL\nAL GND\nV X=20:00:00N 096:00:00E\nDC 5\n';

    test('fires when sunrise moves across a fixed time', () {
      // In Ljubljana, sunrise is between 03:10Z and 06:45Z during the year.
      expect(fires('aa-sun-event-order-changes', ['06:00Z/SR']), [5]);
      final m = messages(
              'aa-sun-event-order-changes', ['06:00Z/SR 2026-01-01/2026-12-31'])
          .single;
      expect(m, contains('length of the window changes by about 24 hours'));
      expect(m, contains('SR (sunrise)'));
      expect(m, contains('Thursday 2026-02-19'));
      expect(
          m, contains('of 365 checked days the window ends on the next day'));
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
    test('names the days of the change, with dates on the times', () {
      // Sunset in Ljubljana is before 17:00Z until about 9 March.
      final m = messages(
              'aa-sun-event-order-changes', ['17:00Z/SS 2026-03-01/2026-03-31'])
          .single;
      expect(m, contains('On Sunday 2026-03-08 the window is from'));
      expect(m, contains('On Monday 2026-03-09 it is from 2026-03-09T17:00Z'));
      expect(m, contains('On 8 of 31 checked days'));
    });
    test('shows seconds when the start and the end are in one minute', () {
      final m = messages(
              'aa-sun-event-order-changes', ['17:00Z/SS 2026-03-01/2026-03-31'])
          .single;
      expect(m, matches(RegExp(r'at 2026-03-09T16:59:\d\dZ')));
    });
    test('does not fire when only the end crosses 00:00Z', () {
      // In Texas, sunset is before 00:00Z in winter and after it in summer.
      // The window always ends at sunset, so nothing changes.
      for (final v in [
        'SR/SS',
        'MON-FRI 14:00Z/SS 2026-01-01/2026-12-31',
        'BCMT/EECT 2026-01-01/2026-12-31',
        'MON-FRI 07:00Z/SS 2026-04-01/2026-09-30',
      ]) {
        expect(fires('aa-sun-event-order-changes', [v], geo: texas), isEmpty,
            reason: v);
      }
      // In Myanmar, sunrise is just before or just after 00:00Z.
      expect(
          fires('aa-sun-event-order-changes', ['SS/SR 2026-01-01/2026-12-31'],
              geo: myanmar),
          isEmpty);
    });
    test('fires when the start crosses 00:00Z', () {
      expect(
          fires('aa-sun-event-start-crosses-midnight', ['SR/SS'], geo: myanmar),
          [5]);
      final m = messages('aa-sun-event-start-crosses-midnight', ['SR/SS'],
              geo: myanmar)
          .single;
      expect(m, contains('The start SR (sunrise) crosses 00:00Z'));
      expect(m, contains('moves by about 24 hours'));
      expect(m, matches(RegExp(r'SR \(sunrise\) at \d{4}-\d\d-\d\dT23:5\dZ')));
      // In Texas, sunset as the start crosses 00:00Z.
      expect(
          fires('aa-sun-event-start-crosses-midnight', ['SS/SR'], geo: texas),
          [5]);
    });
    test('the result does not depend on the date of the run', () {
      // Without a date range, the days 2026 to 2029 are checked.
      final m = messages('aa-sun-event-start-crosses-midnight', ['SR/SS'],
              geo: myanmar)
          .single;
      expect(m, contains('Monday 2026-02-23'));
      // An open end that starts long ago is checked from 2026.
      expect(
          messages('aa-sun-event-start-crosses-midnight',
                  ['SR/SS 2020-01-01/NONE'],
                  geo: myanmar)
              .single,
          m);
      // An open end in the future is checked from its start.
      expect(
          messages('aa-sun-event-start-crosses-midnight',
                  ['SR/SS 2031-01-01/NONE'],
                  geo: myanmar)
              .single,
          contains('2031-'));
      // An open start is checked for the four years before the end.
      expect(
          messages('aa-sun-event-start-crosses-midnight',
                  ['SR/SS NONE/2022-12-31'],
                  geo: myanmar)
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
  });

  group('aa-sun-event-start-crosses-midnight', () {
    test('does not fire when the order changes', () {
      // aa-sun-event-order-changes reports this command.
      expect(
          fires('aa-sun-event-start-crosses-midnight', ['06:00Z/SR']), isEmpty);
    });
    test('does not fire at 14° E', () {
      expect(fires('aa-sun-event-start-crosses-midnight', ['SR/SS', 'SS/SR']),
          isEmpty);
    });
  });

  group('aa-sun-event-near-fixed-time', () {
    test('fires when the times are less than 2 minutes apart', () {
      expect(
          fires('aa-sun-event-near-fixed-time',
              ['03:12Z/SR 2026-06-20/2026-06-22']),
          [5]);
      expect(
          messages('aa-sun-event-near-fixed-time',
              ['03:12Z/SR 2026-06-20/2026-06-22']).single,
          contains('less than 2 minutes apart'));
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

  group('aa-sun-event-missing-day', () {
    const tromso = 'AH 4500 FT AMSL\nAL GND\nV X=69:39:00N 018:57:00E\nDC 5\n';
    test('fires in polar regions', () {
      expect(
          fires('aa-sun-event-missing-day', ['SR/SS 2026-06-01/2026-06-30'],
              geo: tromso),
          [5]);
    });
    test('does not fire at 46° N', () {
      expect(fires('aa-sun-event-missing-day', ['SR/SS']), isEmpty);
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

  group('aa-none-combined', () {
    test('fires for AA NONE with other AA commands', () {
      expect(
          fires('aa-none-combined',
              ['NONE', '2026-07-04T08:00Z/2026-07-04T16:00Z']),
          [5]);
      expect(fires('aa-none-combined', ['MON 09:00Z/10:00Z', 'NONE']), [6]);
    });
    test('does not fire for AA NONE alone', () {
      expect(fires('aa-none-combined', ['NONE']), isEmpty);
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
        ['NONE'],
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
