/// Inputs that crashed the linter or made it very slow. The linter must
/// never throw and must never report `linter-internal-error`.
library;

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

import 'support/helpers.dart';

/// All diagnostics of [text] with all rules. Fails the test if a rule
/// threw an exception.
List<Diagnostic> _lintSafe(String text) {
  final d = lintAll(text);
  expect(d.where((x) => x.ruleId == internalErrorRuleId).map((x) => x.message),
      isEmpty,
      reason: text.length > 400 ? text.substring(0, 400) : text);
  return d;
}

String _nines(int n) => List.filled(n, '9').join();

void main() {
  group('no exception', () {
    test('a version number that is too large for an int', () {
      for (final v in [
        '*VERSION: ${_nines(20)}.0',
        '*version:0.${_nines(22)}.0',
      ]) {
        final d = _lintSafe('$v\n*WRITTEN_BY: test\n$validAirspace');
        expect(d.map((x) => x.ruleId), contains('header-version-invalid'),
            reason: v);
      }
      expect(VersionNumber.tryParse('${_nines(20)}.0'), isNull);
    });

    test('a repeated AH after the first DP (airspace-ac-missing)', () {
      final d = _lintSafe(withHeader('AC D\n'
          'AN Test CTR\n'
          'DP 45:00:00N 014:00:00E\n'
          'AH FL100\n'
          'AH FL100\n'
          'AL GND\n'
          'DP 45:10:00N 014:10:00E\n'
          'DP 45:00:00N 014:10:00E\n'
          'DP 45:00:00N 014:00:00E\n'));
      expect(d.map((x) => x.ruleId), isNot(contains('airspace-ac-missing')));
      expect(d.map((x) => x.ruleId), contains('airspace-ah-duplicate'));
      // The short form found by a fuzzer.
      _lintSafe(withHeader('AC\nDA\nAH\nAH\nDP\n'));
    });

    test('numbers with hundreds of digits', () {
      final big = _nines(400);
      for (final body in [
        'AH FL${_nines(320)}.5\nAL GND\nV X=46:00:00N 014:00:00E\nDC 2\n',
        'AH $big M AMSL\nAL GND\nV X=46:00:00N 014:00:00E\nDC 2\n',
        'AH FL100\nAL GND\nV X=45:00:00N 014:00:00E\nDA $big,0,90\n',
        'AH FL100\nAL GND\nV X=45:00:00N 014:00:00E\nDC $big\n',
        'AH FL100\nAL GND\nV W=$big\nDY 45:00:00N 014:00:00E\n',
        'AH FL100\nAL GND\nDP $big:00:00N 014:00:00E\n'
            'DP 45:00:00N 014:10:00E\nDP 45:00:00N 014:00:00E\n',
      ]) {
        _lintSafe(withHeader('AC D\nAN T\n$body'));
      }
      expect(parseDecimal(big), isNull);
      // A DC with an infinite radius is reported as a wrong format.
      final dc = lintRule(
          'dc-wrong-format',
          withHeader('AC D\nAN T\nAH FL100\nAL GND\nV X=45:00:00N '
              '014:00:00E\nDC $big\n'));
      expect(dc, hasLength(1));
    });
  });

  group('time', () {
    test('many interval AA commands are fast', () {
      // 20000 intervals of one hour, two hours apart. Before the fix, the
      // overlap and adjacent rules compared every pair.
      final aa = StringBuffer();
      var t = DateTime.utc(2026, 1, 1);
      String f(DateTime d) => '${d.toIso8601String().substring(0, 16)}Z';
      for (var i = 0; i < 20000; i++) {
        aa.writeln('AA ${f(t)}/${f(t.add(const Duration(hours: 1)))}');
        t = t.add(const Duration(hours: 2));
      }
      final text = withHeader('AC D\nAN T\n${aa}AH FL100\nAL GND\n'
          'V X=46:00:00N 014:00:00E\nDC 2\n');
      final sw = Stopwatch()..start();
      for (final id in ['aa-intervals-overlap', 'aa-intervals-adjacent']) {
        expect(lintRule(id, text), isEmpty);
      }
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('overlap and adjacent results are the same as before', () {
      final text = withHeader('AC D\nAN T\n'
          'AA 2026-07-04T08:00Z/2026-07-04T12:00Z\n'
          'AA 2026-07-05T08:00Z/2026-07-05T12:00Z\n'
          'AA 2026-07-04T10:00Z/2026-07-04T16:00Z\n'
          'AA 2026-07-05T12:00Z/2026-07-05T14:00Z\n'
          'AA 2026-07-04T08:00Z/2026-07-04T12:00Z\n'
          'AA NONE/2026-07-01T00:00Z\n'
          'AA 2026-06-30T00:00Z/2026-07-01T00:00Z\n'
          'AH FL100\nAL GND\nV X=46:00:00N 014:00:00E\nDC 2\n');
      // The AA commands are on the lines 5 to 11.
      final overlap = lintRule('aa-intervals-overlap', text);
      expect(overlap.map((d) => d.line), [7, 9, 11]);
      expect(overlap[0].message, contains('line 5'));
      expect(overlap[1].message, contains('line 7'));
      expect(overlap[2].message, contains('line 10'));
      final adjacent = lintRule('aa-intervals-adjacent', text);
      expect(adjacent.map((d) => d.line), [8]);
      expect(adjacent.single.message, contains('line 6'));
    });

    test('many DB arcs in one airspace are fast', () {
      final db = StringBuffer('V X=46:00:00N 014:00:00E\n');
      for (var i = 0; i < 20000; i++) {
        db.writeln(i.isEven
            ? 'DB 46:02:00N 014:00:00E, 46:00:00N 014:02:53E'
            : 'DB 46:00:00N 014:02:53E, 46:02:00N 014:00:00E');
      }
      final text = withHeader('AC D\nAN T\nAH FL100\nAL GND\n$db');
      final sw = Stopwatch()..start();
      for (final id in ['db-radius-mismatch', 'geometry-center-missing']) {
        lintRule(id, text);
      }
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('sun events', () {
    test('an event near the polar limit is found', () {
      // The end of evening civil twilight at 64° N, 81.73° W at 05:17.6Z on
      // 24 July 2026. A brute-force scan of the solar altitude gives this
      // time. It is on the local solar day 23 July (local solar time is
      // UTC - 5:27), so it is 1440 + 317.6 minutes after 00:00Z on 23 July.
      // At solar noon the sun does not reach -6°, but about 12 hours later
      // it does.
      final m = sunEventOnLocalDay(SunEvent.civilDusk,
              const CivilDate(2026, 7, 23), const LatLng(64.09, -81.73))
          .minutes;
      expect(m, isNotNull);
      expect(m!, closeTo(1440 + 317.6, 1.5));
    });
    test('an event that does not happen is still null', () {
      // Midsummer at 70° N: the sun does not set.
      final r = sunEventOnLocalDay(
          SunEvent.sunset, const CivilDate(2026, 6, 21), const LatLng(70, 20));
      expect(r.minutes, isNull);
      expect(r.allDay, SunAllDay.above);
    });
  });
}
