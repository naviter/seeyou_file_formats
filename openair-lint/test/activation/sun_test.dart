// Tests for lib/src/activation/sun.dart.
//
// The reference values are from the sunrise-sunset.org API (which uses the
// same definitions: 0°50' for sunrise and sunset, 6° for civil twilight)
// and from published sunrise tables. The specification accepts differences
// of about one minute; the tests allow 2 minutes.

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

const london = LatLng(51.5074, -0.1278);
const ljubljana = LatLng(46.0569, 14.5058);
const tromso = LatLng(69.6492, 18.9553);
const suva = LatLng(-18.1416, 178.4419);
const sydney = LatLng(-33.8688, 151.2093);

/// Minutes after 00:00Z for `hh:mm`.
double hm(String t) {
  final p = t.split(':');
  return int.parse(p[0]) * 60 + double.parse(p[1]);
}

void expectEvent(SunEvent e, CivilDate d, LatLng p, String expected) {
  final m = sunEventMinutes(e, d, p);
  expect(m, isNotNull, reason: '${e.keyword} $d');
  expect((m! - hm(expected)).abs(), lessThanOrEqualTo(2),
      reason: '${e.keyword} $d: got ${formatMinutes(m)}, expected $expected');
}

void main() {
  test('London, winter solstice', () {
    const d = CivilDate(2026, 12, 21);
    expectEvent(SunEvent.sunrise, d, london, '08:04');
    expectEvent(SunEvent.sunset, d, london, '15:53');
    expectEvent(SunEvent.civilDawn, d, london, '07:23');
    expectEvent(SunEvent.civilDusk, d, london, '16:34');
  });

  test('London, summer solstice', () {
    const d = CivilDate(2026, 6, 21);
    expectEvent(SunEvent.sunrise, d, london, '03:43');
    expectEvent(SunEvent.sunset, d, london, '20:21');
  });

  test('Ljubljana, summer solstice', () {
    const d = CivilDate(2026, 6, 21);
    expectEvent(SunEvent.sunrise, d, ljubljana, '03:11');
    expectEvent(SunEvent.sunset, d, ljubljana, '18:57');
    expectEvent(SunEvent.civilDawn, d, ljubljana, '02:32');
    expectEvent(SunEvent.civilDusk, d, ljubljana, '19:35');
  });

  test('Sydney (east of Greenwich, events on the UTC day)', () {
    const d = CivilDate(2026, 12, 21);
    // 05:41 and 20:05 local time (UTC+11).
    expectEvent(SunEvent.sunrise, d, sydney, '18:41');
    expectEvent(SunEvent.sunset, d, sydney, '09:05');
  });

  test('Suva, near the antimeridian: the sunrise on the UTC day', () {
    // The local sunrise of 21 June is at 18:37Z on 20 June. The sunrise
    // that happens on the UTC day 21 June is the local sunrise of 22 June.
    const d = CivilDate(2026, 6, 21);
    expectEvent(SunEvent.sunrise, d, suva, '18:37');
    expectEvent(SunEvent.sunset, d, suva, '05:39');
    final m = sunEventMinutes(SunEvent.sunrise, d, suva)!;
    expect(m, inInclusiveRange(0, 1440));
  });

  test('Tromsø: polar day and polar night', () {
    expect(
        sunEventMinutes(SunEvent.sunset, const CivilDate(2026, 6, 21), tromso),
        isNull);
    expect(
        sunEventMinutes(
            SunEvent.sunrise, const CivilDate(2026, 12, 21), tromso),
        isNull);
    // Civil twilight still happens in the polar night.
    expectEvent(
        SunEvent.civilDawn, const CivilDate(2026, 12, 21), tromso, '08:31');
    expectEvent(
        SunEvent.civilDusk, const CivilDate(2026, 12, 21), tromso, '12:53');
  });

  test('poles do not crash', () {
    expect(
        sunEventMinutes(
            SunEvent.sunrise, const CivilDate(2026, 3, 1), const LatLng(90, 0)),
        isNull);
    expect(
        sunEventMinutes(
            SunEvent.sunset, const CivilDate(2026, 3, 1), const LatLng(-90, 0)),
        isNull);
  });

  test('fromKeyword ignores case', () {
    expect(SunEvent.fromKeyword('sr'), SunEvent.sunrise);
    expect(SunEvent.fromKeyword('EECT'), SunEvent.civilDusk);
    expect(SunEvent.fromKeyword('XX'), isNull);
  });
}
