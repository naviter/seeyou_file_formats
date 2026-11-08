// Tests for lib/src/activation/sun.dart and sun_window.dart.
//
// The reference values are from the sunrise-sunset.org API (which uses the
// same definitions: 0°50' for sunrise and sunset, 6° for civil twilight)
// and from published sunrise tables. The specification accepts differences
// of about one minute; the tests allow 2 minutes.
//
// A sun event belongs to a local solar day: local solar time is UTC plus
// the longitude divided by 15 hours. The reference values are UTC date and
// times; the test converts them to minutes after 00:00Z of the date of the
// local solar day.

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

const london = LatLng(51.5074, -0.1278);
const ljubljana = LatLng(46.0569, 14.5058);
const tromso = LatLng(69.6492, 18.9553);
const suva = LatLng(-18.1416, 178.4419);
const sydney = LatLng(-33.8688, 151.2093);
const sanAngelo = LatLng(31.4638, -100.437); // Texas

const june21 = CivilDate(2026, 6, 21);
const dec21 = CivilDate(2026, 12, 21);

/// Minutes after 00:00Z of [day] for the UTC date and time [utc]
/// (`YYYY-MM-DDThh:mm` or `hh:mm` on [day]).
double minutesOf(CivilDate day, String utc) {
  var date = day;
  var time = utc;
  if (utc.contains('T')) {
    final p = utc.split('T');
    final d = p[0].split('-').map(int.parse).toList();
    date = CivilDate(d[0], d[1], d[2]);
    time = p[1];
  }
  final t = time.split(':');
  return (date.dayNumber - day.dayNumber) * 1440 +
      int.parse(t[0]) * 60 +
      double.parse(t[1]);
}

void expectEvent(SunEvent e, CivilDate day, LatLng p, String expected) {
  final r = sunEventOnLocalDay(e, day, p);
  expect(r.minutes, isNotNull, reason: '${e.keyword} $day');
  final want = minutesOf(day, expected);
  expect((r.minutes! - want).abs(), lessThanOrEqualTo(2),
      reason: '${e.keyword} $day: got ${r.minutes}, expected $want');
  // The event is inside the local solar day.
  final start = localDayStartMinutes(p.lon);
  expect(r.minutes, inInclusiveRange(start, start + 1440),
      reason: '${e.keyword} $day is inside the local solar day');
}

void expectMissing(SunEvent e, CivilDate day, LatLng p, SunAllDay allDay) {
  final r = sunEventOnLocalDay(e, day, p);
  expect(r.minutes, isNull, reason: '${e.keyword} $day');
  expect(r.allDay, allDay, reason: '${e.keyword} $day');
}

const AaTimeOfDay sr = AaTimeOfDay.sun(SunEvent.sunrise);
const AaTimeOfDay ss = AaTimeOfDay.sun(SunEvent.sunset);
const AaTimeOfDay bcmt = AaTimeOfDay.sun(SunEvent.civilDawn);
const AaTimeOfDay eect = AaTimeOfDay.sun(SunEvent.civilDusk);
AaTimeOfDay fixed(int h, [int m = 0]) =>
    AaTimeOfDay.fixed(h * 3600000 + m * 60000);

SunWindowDay window(AaTimeOfDay s, AaTimeOfDay e, CivilDate d, LatLng p) =>
    sunWindowOnDay(s, e, d, p.lon, (ev, day) => sunEventOnLocalDay(ev, day, p));

void main() {
  group('local solar time', () {
    test('the day starts at 00:00Z minus 4 minutes per degree east', () {
      expect(localDayStartMinutes(15), -60);
      expect(localDayStartMinutes(-120), 480);
      expect(localDayStartMinutes(0), 0);
    });

    test('each UTC time of day happens once in the local solar day', () {
      // At 15° E the day is from 23:00Z (day before) to 23:00Z.
      expect(placeInLocalDay(7 * 60, 15), 420);
      expect(placeInLocalDay(23 * 60, 15), -60);
      expect(placeInLocalDay(22 * 60 + 59, 15), 1379);
      // 24:00Z is the same time of day as 00:00Z.
      expect(placeInLocalDay(1440, 15), 0);
      // At 100° W the day is from 06:40Z to 06:40Z of the next day.
      expect(placeInLocalDay(7 * 60, -100), 420);
      expect(placeInLocalDay(0, -100), 1440);
      expect(placeInLocalDay(6 * 60, -100), 1800);
      // At 178° E the day is from 12:08Z (day before) to 12:08Z.
      expect(placeInLocalDay(18 * 60, 178), 1080 - 1440);
    });
  });

  group('sun events on the local solar day', () {
    test('London', () {
      expectEvent(SunEvent.sunrise, dec21, london, '08:04');
      expectEvent(SunEvent.sunset, dec21, london, '15:53');
      expectEvent(SunEvent.civilDawn, dec21, london, '07:23');
      expectEvent(SunEvent.civilDusk, dec21, london, '16:34');
      expectEvent(SunEvent.sunrise, june21, london, '03:43');
      expectEvent(SunEvent.sunset, june21, london, '20:21');
    });

    test('Ljubljana (14.5° E), June and December', () {
      expectEvent(SunEvent.sunrise, june21, ljubljana, '03:11');
      expectEvent(SunEvent.sunset, june21, ljubljana, '18:57');
      expectEvent(SunEvent.civilDawn, june21, ljubljana, '02:32');
      expectEvent(SunEvent.civilDusk, june21, ljubljana, '19:35');
      expectEvent(SunEvent.sunrise, dec21, ljubljana, '06:41');
      expectEvent(SunEvent.sunset, dec21, ljubljana, '15:19');
      expectEvent(SunEvent.civilDawn, dec21, ljubljana, '06:06');
      expectEvent(SunEvent.civilDusk, dec21, ljubljana, '15:54');
    });

    test('Texas (100.4° W): the evening events are on the next UTC day', () {
      // The local solar day 21 June is from 06:42Z on 21 June to 06:42Z on
      // 22 June. Sunset is on the UTC day 22 June.
      expectEvent(SunEvent.sunrise, june21, sanAngelo, '11:38');
      expectEvent(SunEvent.sunset, june21, sanAngelo, '2026-06-22T01:50');
      expectEvent(SunEvent.civilDawn, june21, sanAngelo, '11:10');
      expectEvent(SunEvent.civilDusk, june21, sanAngelo, '2026-06-22T02:18');
      // In December sunset is before 00:00Z, civil twilight ends after.
      expectEvent(SunEvent.sunrise, dec21, sanAngelo, '13:37');
      expectEvent(SunEvent.sunset, dec21, sanAngelo, '23:43');
      expectEvent(SunEvent.civilDusk, dec21, sanAngelo, '2026-12-22T00:10');
    });

    test('Fiji (178.4° E): the morning events are on the UTC day before', () {
      // The local solar day 21 June is from 12:06Z on 20 June to 12:06Z on
      // 21 June.
      expectEvent(SunEvent.sunrise, june21, suva, '2026-06-20T18:37');
      expectEvent(SunEvent.sunset, june21, suva, '05:39');
      expectEvent(SunEvent.civilDawn, june21, suva, '2026-06-20T18:13');
      expectEvent(SunEvent.civilDusk, june21, suva, '06:03');
      expectEvent(SunEvent.sunrise, dec21, suva, '2026-12-20T17:27');
      expectEvent(SunEvent.sunset, dec21, suva, '06:41');
    });

    test('Sydney (151.2° E)', () {
      // 05:41 and 20:05 local time (UTC+11).
      expectEvent(SunEvent.sunrise, dec21, sydney, '2026-12-20T18:41');
      expectEvent(SunEvent.sunset, dec21, sydney, '09:05');
    });

    test('Tromsø (69.6° N): polar day and polar night', () {
      expectMissing(SunEvent.sunrise, june21, tromso, SunAllDay.above);
      expectMissing(SunEvent.sunset, june21, tromso, SunAllDay.above);
      expectMissing(SunEvent.civilDawn, june21, tromso, SunAllDay.above);
      expectMissing(SunEvent.civilDusk, june21, tromso, SunAllDay.above);
      expectMissing(SunEvent.sunrise, dec21, tromso, SunAllDay.below);
      expectMissing(SunEvent.sunset, dec21, tromso, SunAllDay.below);
      // Civil twilight still happens in the polar night.
      expectEvent(SunEvent.civilDawn, dec21, tromso, '08:31');
      expectEvent(SunEvent.civilDusk, dec21, tromso, '12:53');
    });

    test('poles do not crash', () {
      expectMissing(SunEvent.sunrise, const CivilDate(2026, 6, 1),
          const LatLng(90, 0), SunAllDay.above);
      expectMissing(SunEvent.sunset, const CivilDate(2026, 6, 1),
          const LatLng(-90, 0), SunAllDay.below);
    });

    test('every day of a year has its event inside the local solar day', () {
      for (final p in [ljubljana, sanAngelo, suva, sydney, london]) {
        final start = localDayStartMinutes(p.lon);
        for (var i = 0; i < 366; i++) {
          final d = const CivilDate(2026, 1, 1).addDays(i);
          for (final e in SunEvent.values) {
            final m = sunEventOnLocalDay(e, d, p).minutes!;
            expect(m, inInclusiveRange(start, start + 1440),
                reason: '${e.keyword} $d at $p');
          }
        }
      }
    });
  });

  group('windows on the local solar day', () {
    test('SR/SS in Texas ends at sunset, also after 00:00Z', () {
      final w = window(sr, ss, june21, sanAngelo);
      expect(w.isNormal, isTrue);
      expect(w.endsNextDay, isFalse);
      expect(
          (w.end! - minutesOf(june21, '2026-06-22T01:50')).abs(), lessThan(2));
    });

    test('SS/SR ends at sunrise of the next local solar day', () {
      final w = window(ss, sr, june21, ljubljana);
      expect(w.endsNextDay, isTrue);
      expect(
          (w.end! - minutesOf(june21, '2026-06-22T03:11')).abs(), lessThan(2));
    });

    test('a fixed time is the UTC time inside the local solar day', () {
      // Fiji: the local solar day 21 June starts at 12:06Z on 20 June.
      // 20:00Z is on 20 June, before sunset on 21 June at 05:39Z.
      final w = window(fixed(20), ss, june21, suva);
      expect(w.start, minutesOf(june21, '2026-06-20T20:00'));
      expect(w.endsNextDay, isFalse);
      // Texas: 03:00Z is at the end of the local solar day (22 June).
      final t = window(sr, fixed(3), june21, sanAngelo);
      expect(t.end, minutesOf(june21, '2026-06-22T03:00'));
      expect(t.endsNextDay, isFalse);
    });

    test('06:00Z/SR ends on the next day when sunrise is earlier', () {
      expect(window(fixed(6), sr, june21, ljubljana).endsNextDay, isTrue);
      expect(window(fixed(6), sr, dec21, ljubljana).endsNextDay, isFalse);
    });

    group('polar regions (the table of the specification)', () {
      test('morning to evening', () {
        final summer = window(sr, ss, june21, tromso);
        expect(summer.polar, SunPolarOutcome.wholeDay);
        expect(summer.end! - summer.start!, 1440);
        expect(summer.start, localDayStartMinutes(tromso.lon));
        expect(summer.missingEvents, [SunEvent.sunrise, SunEvent.sunset]);
        final winter = window(sr, ss, dec21, tromso);
        expect(winter.polar, SunPolarOutcome.notActive);
        expect(winter.isActive, isFalse);
        expect(
            window(bcmt, eect, june21, tromso).polar, SunPolarOutcome.wholeDay);
      });

      test('evening to morning', () {
        expect(window(ss, sr, june21, tromso).polar, SunPolarOutcome.notActive);
        final winter = window(ss, sr, dec21, tromso);
        expect(winter.polar, SunPolarOutcome.wholeDay);
        expect(winter.end! - winter.start!, 1440);
      });

      test('a sun event and a fixed time', () {
        final dayStart = localDayStartMinutes(tromso.lon);
        final end = window(fixed(7), ss, june21, tromso);
        expect(end.polar, SunPolarOutcome.endsAtDayEnd);
        expect(end.start, 420);
        expect(end.end, dayStart + 1440);
        final start = window(sr, fixed(15), june21, tromso);
        expect(start.polar, SunPolarOutcome.startsAtDayStart);
        expect(start.start, dayStart);
        expect(start.end, 900);
        expect(window(fixed(7), ss, dec21, tromso).polar,
            SunPolarOutcome.notActive);
        expect(window(sr, fixed(15), dec21, tromso).polar,
            SunPolarOutcome.notActive);
      });

      test('one event happens, the other does not', () {
        // In the polar night civil twilight happens, sunset does not.
        expect(
            window(bcmt, ss, dec21, tromso).polar, SunPolarOutcome.notActive);
        // The night from EECT to SR: SR does not happen, the sun is below.
        expect(window(eect, sr, dec21, tromso).polar, SunPolarOutcome.wholeDay);
      });
    });
  });

  test('fromKeyword ignores case', () {
    expect(SunEvent.fromKeyword('sr'), SunEvent.sunrise);
    expect(SunEvent.fromKeyword('EECT'), SunEvent.civilDusk);
    expect(SunEvent.fromKeyword('XX'), isNull);
  });
}
