// Tests for lib/src/activation/iso8601.dart and civil_date.dart.

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

CivilDate? date(String text, [List<AaIssue>? issues]) =>
    parseIsoDate(text, 0, issues ?? []).value;

int? time(String text, {bool isEnd = false, List<AaIssue>? issues}) =>
    parseIsoTime(text, 0, issues ?? [], isEnd: isEnd).value;

int? dateTime(String text, {bool isEnd = false, List<AaIssue>? issues}) =>
    parseIsoDateTime(text, 0, issues ?? [], isEnd: isEnd).value;

List<String> kinds(List<AaIssue> issues) =>
    [for (final i in issues) i.kind.ruleId];

const int h = 3600000;

void main() {
  group('CivilDate', () {
    test('day numbers and weekdays', () {
      expect(const CivilDate(1970, 1, 1).dayNumber, 0);
      expect(const CivilDate(2026, 7, 4).weekday, DateTime.saturday);
      expect(const CivilDate(2026, 12, 25).weekday, DateTime.friday);
      for (final n in [-1000, -1, 0, 1, 20000, 30000]) {
        expect(CivilDate.fromDayNumber(n).dayNumber, n);
      }
      expect(CivilDate.fromDayNumber(const CivilDate(2024, 2, 29).dayNumber),
          const CivilDate(2024, 2, 29));
    });

    test('addMonths keeps the day or uses the last day', () {
      expect(const CivilDate(2026, 1, 31).addMonths(1),
          const CivilDate(2026, 2, 28));
      expect(const CivilDate(2024, 1, 31).addMonths(1),
          const CivilDate(2024, 2, 29));
      expect(const CivilDate(2026, 12, 15).addMonths(1),
          const CivilDate(2027, 1, 15));
      expect(const CivilDate(2026, 1, 15).addMonths(-1),
          const CivilDate(2025, 12, 15));
    });

    test('ISO weeks per year', () {
      expect(isoWeeksInYear(2026), 53);
      expect(isoWeeksInYear(2025), 52);
      expect(isoWeeksInYear(2020), 53);
    });

    test('formatting', () {
      expect(formatTimeOfDay(9 * h), '09:00Z');
      expect(formatTimeOfDay(24 * h), '24:00Z');
      expect(formatTimeOfDay(9 * h + 30000), '09:00:30Z');
      expect(formatInstant(const CivilDate(2026, 7, 4).startInstant + 8 * h),
          '2026-07-04T08:00Z');
      expect(formatMinutes(359.6), '06:00Z');
    });
  });

  group('Date', () {
    test('allowed form', () {
      final r = parseIsoDate('2026-07-04', 0, []);
      expect(r.value, const CivilDate(2026, 7, 4));
      expect(r.formNote, isNull);
    });

    test('other ISO 8601 forms have a form note', () {
      for (final t in [
        '20260704',
        '2026-W27-6',
        '2026W276',
        '2026-185',
        '2026185'
      ]) {
        final r = parseIsoDate(t, 0, []);
        expect(r.value, const CivilDate(2026, 7, 4), reason: t);
        expect(r.formNote, isNotNull, reason: t);
      }
      // Week 1 of 2026 starts on Monday 2025-12-29.
      expect(date('2026-W01-1'), const CivilDate(2025, 12, 29));
      expect(date('2024-366'), const CivilDate(2024, 12, 31));
    });

    test('invalid dates', () {
      for (final t in [
        '2026-02-30',
        '2026-13-01',
        '2026-00-10',
        '2026-W54-1',
        '2026-W10-8',
        '2026-366',
        '2026-7-4',
        '04.07.2026',
        '2026-07',
        '2026',
        'today',
        '',
      ]) {
        final issues = <AaIssue>[];
        expect(date(t, issues), isNull, reason: t);
        expect(kinds(issues), ['aa-invalid-date'], reason: t);
      }
    });

    test('messages are specific', () {
      final issues = <AaIssue>[];
      date('2026-02-30', issues);
      expect(issues.single.message, contains('February 2026 has 28 days'));
      issues.clear();
      date('04.07.2026', issues);
      expect(issues.single.message, contains('year first'));
    });

    test('offsets use the base', () {
      final issues = <AaIssue>[];
      parseIsoDate('2026-02-30', 7, issues);
      expect(issues.single.offset, 7);
      expect(issues.single.length, 10);
    });
  });

  group('Time', () {
    test('allowed forms: hh:mmZ and hh:mm:ssZ', () {
      final r = parseIsoTime('09:30Z', 0, [], isEnd: false);
      expect(r.value, 9 * h + 30 * 60000);
      expect(r.formNote, isNull);
      final s = parseIsoTime('09:30:15Z', 0, [], isEnd: false);
      expect(s.value, 9 * h + 30 * 60000 + 15000);
      expect(s.formNote, isNull);
      expect(parseIsoTime('24:00:00Z', 0, [], isEnd: true).formNote, isNull);
    });

    test('lower case z is read (case is checked by another rule)', () {
      expect(time('09:30z'), 9 * h + 30 * 60000);
    });

    test('other ISO 8601 forms have a form note', () {
      final cases = {
        '09:30:15.5Z': 9 * h + 30 * 60000 + 15500,
        '09:30,5Z': 9 * h + 30 * 60000 + 30000,
        '0930Z': 9 * h + 30 * 60000,
        '093015Z': 9 * h + 30 * 60000 + 15000,
        '09Z': 9 * h,
        'T09:30Z': 9 * h + 30 * 60000,
      };
      cases.forEach((t, ms) {
        final r = parseIsoTime(t, 0, [], isEnd: false);
        expect(r.value, ms, reason: t);
        expect(r.formNote, isNotNull, reason: t);
      });
    });

    test('24:00Z only as an end', () {
      expect(time('24:00Z', isEnd: true), 24 * h);
      expect(time('24:00:00Z', isEnd: true), 24 * h);
      final issues = <AaIssue>[];
      expect(time('24:00Z', issues: issues), isNull);
      expect(kinds(issues), ['aa-time-24-as-start']);
      issues.clear();
      expect(time('24:30Z', isEnd: true, issues: issues), isNull);
      expect(kinds(issues), ['aa-invalid-time']);
      issues.clear();
      expect(time('24:00:01Z', isEnd: true, issues: issues), isNull);
      expect(kinds(issues), ['aa-invalid-time']);
      // The specification allows 24:00Z and 24:00:00Z.
      expect(issues.single.message,
          contains('only 24:00Z or 24:00:00Z is allowed'));
    });

    test('a missing Z is an error', () {
      final issues = <AaIssue>[];
      expect(time('09:00', issues: issues), isNull);
      expect(kinds(issues), ['aa-time-missing-z']);
      expect(issues.single.message, contains('09:00Z'));
    });

    test('offsets and zone names are errors', () {
      for (final t in [
        '09:00+01:00',
        '09:00+0100',
        '09:00+01',
        '09:00-05:00',
        '09:00+00:00',
        '09:00UTC',
        '09:00GMT',
        '09:00LT',
        '09:00CET',
      ]) {
        final issues = <AaIssue>[];
        expect(time(t, issues: issues), isNull, reason: t);
        expect(kinds(issues), ['aa-time-zone-not-z'], reason: t);
      }
    });

    test('an offset message gives the UTC time', () {
      final issues = <AaIssue>[];
      time('09:00+02:00', issues: issues);
      expect(issues.single.message, contains('07:00Z'));
      issues.clear();
      time('01:00+02:00', issues: issues);
      expect(issues.single.message, contains('23:00Z on the previous day'));
      // The issue points to the offset.
      expect(issues.single.offset, 5);
      expect(issues.single.length, 6);
    });

    test('invalid times', () {
      for (final t in [
        '25:00Z',
        '09:60Z',
        '09:00:60Z',
        '9:00Z',
        '09:0Z',
        '090Z',
        '09:00Zx',
        'nine',
        '',
      ]) {
        final issues = <AaIssue>[];
        expect(time(t, issues: issues), isNull, reason: t);
        expect(kinds(issues), contains('aa-invalid-time'), reason: t);
      }
    });
  });

  group('DateTime', () {
    final jul4 = const CivilDate(2026, 7, 4).startInstant;

    test('recommended form and other forms', () {
      expect(dateTime('2026-07-04T08:00Z'), jul4 + 8 * h);
      expect(dateTime('20260704T0800Z'), jul4 + 8 * h);
      expect(dateTime('2026-07-04T08:00:00Z'), jul4 + 8 * h);
      expect(dateTime('2026-W27-6T08:00Z'), jul4 + 8 * h);
      expect(dateTime('2026-185T08:00Z'), jul4 + 8 * h);
      expect(dateTime('2026-07-04t08:00z'), jul4 + 8 * h);
      expect(
          parseIsoDateTime('2026-07-04T08:00Z', 0, [], isEnd: false).formNote,
          isNull);
      expect(
          parseIsoDateTime('2026-07-04T08:00:00Z', 0, [], isEnd: false)
              .formNote,
          isNull);
      for (final t in [
        '20260704T0800Z',
        '2026-W27-6T08:00Z',
        '2026-185T08:00Z',
        '2026-07-04T08Z',
        '2026-07-04T08:00:00.5Z',
      ]) {
        expect(parseIsoDateTime(t, 0, [], isEnd: false).formNote, isNotNull,
            reason: t);
      }
    });

    test('24:00 is the start of the next day, only as an end', () {
      expect(dateTime('2026-07-04T24:00Z', isEnd: true), jul4 + 24 * h);
      final issues = <AaIssue>[];
      expect(dateTime('2026-07-04T24:00Z', issues: issues), isNull);
      expect(kinds(issues), ['aa-time-24-as-start']);
      expect(issues.single.message, contains('2026-07-05T00:00Z'));
    });

    test('mixed basic and extended format is an error', () {
      final issues = <AaIssue>[];
      expect(dateTime('2026-07-04T0800Z', issues: issues), isNull);
      expect(kinds(issues), ['aa-invalid-time']);
      expect(issues.single.message, contains('mixes'));
    });

    test('a date without a time is an error', () {
      final issues = <AaIssue>[];
      expect(dateTime('2026-07-04', issues: issues), isNull);
      expect(issues.single.message, contains('no time of day'));
    });

    test('errors in the date and the time', () {
      final issues = <AaIssue>[];
      expect(dateTime('2026-02-30T08:00Z', issues: issues), isNull);
      expect(kinds(issues), ['aa-invalid-date']);
      issues.clear();
      expect(dateTime('2026-07-04T08:00', issues: issues), isNull);
      expect(kinds(issues), ['aa-time-missing-z']);
      expect(issues.single.offset, 11);
    });

    test('a sun event in a date is an error', () {
      final issues = <AaIssue>[];
      expect(dateTime('2026-07-04TSR', issues: issues), isNull);
      expect(kinds(issues), ['aa-sun-event-not-allowed']);
    });
  });

  group('Duration', () {
    IsoDuration? dur(String t, [List<AaIssue>? issues]) =>
        parseIsoDuration(t, 0, issues ?? []).value;
    final start = const CivilDate(2026, 1, 31).startInstant + 8 * h;

    test('valid durations', () {
      expect(dur('PT8H')!.ms, 8 * h);
      expect(dur('PT1H30M')!.ms, 90 * 60000);
      expect(dur('PT0.5H')!.ms, 30 * 60000);
      expect(dur('PT1,5H')!.ms, 90 * 60000);
      expect(dur('P1D')!.days, 1);
      expect(dur('P2W')!.days, 14);
      expect(dur('P1DT12H')!.days, 1);
      expect(dur('P1DT12H')!.ms, 12 * h);
      expect(dur('P1Y2M')!.months, 2);
      expect(dur('pt8h')!.ms, 8 * h);
    });

    test('calendar arithmetic', () {
      expect(formatInstant(dur('P1M')!.addTo(start)), '2026-02-28T08:00Z');
      expect(formatInstant(dur('P1D')!.addTo(start)), '2026-02-01T08:00Z');
      expect(formatInstant(dur('PT20H')!.addTo(start)), '2026-02-01T04:00Z');
      expect(
          formatInstant(dur('PT8H')!.subtractFrom(start)), '2026-01-31T00:00Z');
    });

    test('invalid durations', () {
      for (final t in [
        'P',
        'PT',
        'P8H',
        'PT8D',
        'P1.5DT2H',
        'P0.5M',
        'PT1H2H',
        'PM1',
        'P1DT',
        'P0000-13-00',
        'P0000-00-31',
        'P0000-00-00T25:00:00',
        'P0000-00-01T00:00',
        'P0000-01',
      ]) {
        final issues = <AaIssue>[];
        expect(dur(t, issues), isNull, reason: t);
        expect(kinds(issues), ['aa-invalid-duration'], reason: t);
      }
    });

    test('the alternative format', () {
      final d = parseIsoDuration('P0001-02-03T04:05:06', 0, []);
      expect(d.value!.years, 1);
      expect(d.value!.months, 2);
      expect(d.value!.days, 3);
      expect(d.value!.ms, 4 * h + 5 * 60000 + 6000);
      expect(d.formNote, 'the alternative format');
      expect(dur('P00000001T000000')!.days, 1);
      expect(dur('P0000-00-01')!.days, 1);
    });

    test('very long values are an error, not an exception', () {
      for (final t in [
        'PT99999999999999999999H',
        'P99999999999999999999D',
        'P1000000000Y',
        'P10001Y',
        'P3700000D',
        'PT90000000000H',
      ]) {
        final issues = <AaIssue>[];
        expect(dur(t, issues), isNull, reason: t);
        expect(kinds(issues), ['aa-invalid-duration'], reason: t);
        expect(issues.single.message, contains('too long'), reason: t);
      }
      expect(dur('P0000000000001D')!.days, 1);
      expect(dur('P9000Y')!.years, 9000);
    });
  });

  group('short interval end', () {
    const start = CivilDate(2026, 7, 4);
    int? end(String t, [List<AaIssue>? issues]) =>
        parseShortEndDateTime(t, 0, issues ?? [], start)?.value;

    test('the missing parts come from the start', () {
      expect(formatInstant(end('05T16:00Z')!), '2026-07-05T16:00Z');
      expect(formatInstant(end('08-01T16:00Z')!), '2026-08-01T16:00Z');
      expect(formatInstant(end('0801T1600Z')!), '2026-08-01T16:00Z');
      expect(formatInstant(end('05T24:00Z')!), '2026-07-06T00:00Z');
    });

    test('a full date is not a short end', () {
      expect(parseShortEndDateTime('2026-07-05T16:00Z', 0, [], start), isNull);
      expect(parseShortEndDateTime('16:00Z', 0, [], start), isNull);
    });

    test('errors', () {
      for (final (t, kind) in [
        ('32T16:00Z', 'aa-invalid-date'),
        ('02-30T16:00Z', 'aa-invalid-date'),
        ('13-01T16:00Z', 'aa-invalid-date'),
        ('05T16:00', 'aa-time-missing-z'),
        ('08-01T1600Z', 'aa-invalid-time'),
        ('05TSS', 'aa-sun-event-not-allowed'),
      ]) {
        final issues = <AaIssue>[];
        expect(end(t, issues), isNull, reason: t);
        expect(kinds(issues), [kind], reason: t);
      }
    });
  });
}
