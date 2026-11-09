/// Parser for OpenAir coordinates such as `45:40:30N 014:18:20E`.
///
/// The parser is lenient. It reads many forms that real files use, and it
/// reports every difference from the specification as a [CoordinateIssue].
/// The geometry rules turn these issues into diagnostics.
library;

import '../geometry/lat_lng.dart';

/// The notation of one coordinate part.
enum CoordinateNotation {
  /// Degrees, minutes and seconds: `45:40:30N`. Allowed by the specification.
  dms('DMS'),

  /// Degrees and decimal minutes: `45:40.500N`. Allowed by the
  /// specification.
  ddm('DDM'),

  /// Decimal degrees: `45.675N`. Not allowed by the specification, but some
  /// files use it. The parser reads it and reports
  /// [CoordinateIssueKind.decimalDegrees].
  decimalDegrees('decimal degrees');

  const CoordinateNotation(this.label);

  /// A name for messages, for example `DMS`.
  final String label;
}

/// Which part of a coordinate an issue is about.
enum CoordinatePart {
  latitude,
  longitude,

  /// The whole coordinate, for example the space between the two parts.
  both,
}

/// The kinds of problems that [parseCoordinate] can find.
///
/// "Fatal" kinds mean that the parser could not compute a position:
/// [CoordinateParseResult.value] is null. The other kinds are deviations
/// from the specification; the position is still computed.
enum CoordinateIssueKind {
  /// Fatal. The text is not a coordinate, or a part is missing or has the
  /// wrong form (for example `45::30N`, `45:30:20:10N`, or no longitude).
  syntax(fatal: true),

  /// Fatal. The hemisphere letter (`N`, `S`, `E`, `W`) is missing.
  missingHemisphere(fatal: true),

  /// Fatal. The latitude has `E` or `W`, or the longitude has `N` or `S`.
  wrongHemisphere(fatal: true),

  /// Fatal. The latitude is greater than 90 degrees.
  latitudeOutOfRange(fatal: true),

  /// Fatal. The longitude is greater than 180 degrees.
  longitudeOutOfRange(fatal: true),

  /// Fatal. The minutes are 60 or more.
  minutesOutOfRange(fatal: true),

  /// Fatal. The seconds are 60 or more.
  secondsOutOfRange(fatal: true),

  /// The hemisphere letter is lower case (`n` in place of `N`).
  lowerCaseHemisphere(),

  /// There is more than one blank, or a tab, between the number and the
  /// hemisphere letter (`45:40:30  N`). One space is valid (`45:40:30 N`)
  /// and is not an issue.
  extraSpaceBeforeHemisphere(),

  /// There is no space between the latitude and the longitude
  /// (`45:40:30N014:18:20E`).
  missingSpace(),

  /// There is more than one space (or a tab) between the latitude and the
  /// longitude.
  extraSpace(),

  /// A part has fewer digits than the format needs (`14:18:20E` in place of
  /// `014:18:20E`, or `45:4:30N` in place of `45:04:30N`).
  missingLeadingZero(),

  /// A part has more digits than the format allows (`045:40:30N`).
  tooManyDigits(),

  /// DMS seconds have decimals (`45:40:30.5N`). The DMS format of the
  /// specification has whole seconds.
  decimalSeconds(),

  /// The part uses decimal degrees (`45.675N`). The specification allows
  /// only DMS and DDM.
  decimalDegrees(),

  /// The latitude and the longitude use different notations
  /// (`45:40:30N 014:18.333E`).
  mixedNotation(),

  /// There is more text after the longitude (`45:40:30N 014:18:20E X`).
  trailingText();

  const CoordinateIssueKind({this.fatal = false});

  /// True if the parser cannot compute a position when it finds this issue.
  final bool fatal;
}

/// One problem that [parseCoordinate] found.
class CoordinateIssue {
  const CoordinateIssue(
      this.kind, this.part, this.offset, this.length, this.message,
      {this.replacement});

  /// What is wrong.
  final CoordinateIssueKind kind;

  /// Which part of the coordinate is wrong.
  final CoordinatePart part;

  /// Offset of the wrong text in the parsed string (0-based).
  /// The column in the file is `command.argumentColumn + start + offset`,
  /// where `start` is the offset of the coordinate in the argument.
  final int offset;

  /// The length of the wrong text. It is at least 1.
  final int length;

  /// A short explanation in plain English, for example
  /// `The minutes must be less than 60.`.
  final String message;

  /// The text that replaces the wrong text (from [offset], with [length]),
  /// or null. It is set only when there is exactly one correct result with
  /// the same meaning, for example a leading zero. The rules use it for the
  /// automatic fix.
  final String? replacement;

  /// True if this issue means that no position could be computed.
  bool get fatal => kind.fatal;

  @override
  String toString() => '${kind.name}@$offset+$length: $message';
}

/// The result of [parseCoordinate].
class CoordinateParseResult {
  const CoordinateParseResult({
    required this.value,
    required this.latitudeNotation,
    required this.longitudeNotation,
    required this.issues,
    required this.end,
  });

  /// The position, or null if a fatal issue was found.
  final LatLng? value;

  /// The notation of the latitude, or null if it could not be read.
  final CoordinateNotation? latitudeNotation;

  /// The notation of the longitude, or null if it could not be read.
  final CoordinateNotation? longitudeNotation;

  /// All problems, in text order. Empty if the coordinate is written
  /// exactly as the specification shows.
  final List<CoordinateIssue> issues;

  /// The offset after the longitude (and its hemisphere letter). Text after
  /// this offset is reported as [CoordinateIssueKind.trailingText].
  final int end;

  /// The notation of the coordinate if both parts use the same one,
  /// otherwise null.
  CoordinateNotation? get notation =>
      latitudeNotation == longitudeNotation ? latitudeNotation : null;

  /// True if a position was computed.
  bool get isValid => value != null;

  /// True if the coordinate is written exactly as the specification shows.
  bool get isClean => value != null && issues.isEmpty;

  /// The issues of one kind.
  Iterable<CoordinateIssue> issuesOf(CoordinateIssueKind kind) =>
      issues.where((i) => i.kind == kind);

  /// True if there is at least one issue of this kind.
  bool has(CoordinateIssueKind kind) => issues.any((i) => i.kind == kind);
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isBlank(int c) => c == 0x20 || c == 0x09;

/// Parses one coordinate pair: latitude, then longitude.
///
/// Examples of accepted input:
///
/// - `45:40:30N 014:18:20E` (DMS, no issues)
/// - `45:40:30 N 014:18:20 E` (DMS with one space before the letters, no
///   issues)
/// - `45:40.500N 014:18.333E` (DDM, no issues)
/// - `45:40:30.5  n 14:18:20E` (issues: decimalSeconds,
///   extraSpaceBeforeHemisphere, lowerCaseHemisphere, missingLeadingZero)
/// - `45:40:30N014:18:20E` (issue: missingSpace)
/// - `45.675N 14.305E` (issues: decimalDegrees)
///
/// Spaces and tabs at the start and the end of [text] are ignored without
/// an issue. The caller can check them itself if needed.
///
/// It never throws.
CoordinateParseResult parseCoordinate(String text) {
  final issues = <CoordinateIssue>[];
  var pos = 0;
  final n = text.length;
  while (pos < n && _isBlank(text.codeUnitAt(pos))) {
    pos++;
  }
  final lat = _parsePart(text, pos, true, issues);
  pos = lat.end;
  if (lat.fatalSyntax) {
    return _result(lat, null, issues, pos);
  }
  // Space between the two parts.
  final gapStart = pos;
  while (pos < n && _isBlank(text.codeUnitAt(pos))) {
    pos++;
  }
  final gap = pos - gapStart;
  if (pos >= n) {
    issues.add(CoordinateIssue(CoordinateIssueKind.syntax,
        CoordinatePart.longitude, gapStart, 1, 'The longitude is missing.'));
    return _result(lat, null, issues, pos);
  }
  if (gap == 0) {
    issues.add(CoordinateIssue(
        CoordinateIssueKind.missingSpace,
        CoordinatePart.both,
        pos,
        1,
        'Write one space between the latitude and the longitude.',
        replacement: ' ${text[pos]}'));
  } else if (gap > 1 || text.substring(gapStart, pos) != ' ') {
    issues.add(CoordinateIssue(
        CoordinateIssueKind.extraSpace,
        CoordinatePart.both,
        gapStart,
        gap,
        'Write exactly one space between the latitude and the longitude.',
        replacement: ' '));
  }
  final lon = _parsePart(text, pos, false, issues);
  pos = lon.end;
  final end = pos;
  if (!lon.fatalSyntax) {
    while (pos < n && _isBlank(text.codeUnitAt(pos))) {
      pos++;
    }
    if (pos < n) {
      var tEnd = n;
      while (tEnd > pos && _isBlank(text.codeUnitAt(tEnd - 1))) {
        tEnd--;
      }
      issues.add(CoordinateIssue(
          CoordinateIssueKind.trailingText,
          CoordinatePart.both,
          pos,
          tEnd - pos,
          'Unexpected text after the coordinate: "${text.substring(pos, tEnd)}".'));
    }
  }
  if (lat.notation != null &&
      lon.notation != null &&
      lat.notation != lon.notation) {
    issues.add(CoordinateIssue(
        CoordinateIssueKind.mixedNotation,
        CoordinatePart.both,
        lat.start,
        end - lat.start,
        'The latitude uses ${lat.notation!.label} and the longitude uses '
        '${lon.notation!.label}. Use the same notation for both.'));
  }
  return _result(lat, lon, issues, end);
}

CoordinateParseResult _result(
    _Part lat, _Part? lon, List<CoordinateIssue> issues, int end) {
  issues.sort((a, b) => a.offset.compareTo(b.offset));
  final fatal = issues.any((i) => i.fatal);
  LatLng? value;
  if (!fatal && lon != null) {
    value = LatLng(lat.value, lon.value);
  }
  return CoordinateParseResult(
    value: value,
    latitudeNotation: lat.notation,
    longitudeNotation: lon?.notation,
    issues: List.unmodifiable(issues),
    end: end,
  );
}

class _Group {
  _Group(this.start, this.end, this.intDigits, this.hasDot, this.text);
  final int start;
  final int end;
  final int intDigits;
  final bool hasDot;
  final String text;
  double get value => double.parse(text.endsWith('.') ? '${text}0' : text);
}

class _Part {
  _Part(this.start, this.end);
  final int start;
  int end;
  CoordinateNotation? notation;
  double value = 0;
  bool fatalSyntax = false;
}

_Part _parsePart(
    String text, int start, bool isLat, List<CoordinateIssue> issues) {
  final n = text.length;
  final partName = isLat ? 'latitude' : 'longitude';
  final cp = isLat ? CoordinatePart.latitude : CoordinatePart.longitude;
  final part = _Part(start, start);

  // Read number groups separated by ':'.
  final groups = <_Group>[];
  var pos = start;
  while (true) {
    final gStart = pos;
    var intDigits = 0;
    while (pos < n && _isDigit(text.codeUnitAt(pos))) {
      pos++;
      intDigits++;
    }
    var hasDot = false;
    if (pos < n && text.codeUnitAt(pos) == 0x2E /* . */) {
      hasDot = true;
      pos++;
      while (pos < n && _isDigit(text.codeUnitAt(pos))) {
        pos++;
      }
    }
    if (intDigits == 0) {
      // Nothing numeric here.
      final what = groups.isEmpty
          ? 'Expected the $partName here.'
          : 'A number is missing in the $partName.';
      issues.add(
          CoordinateIssue(CoordinateIssueKind.syntax, cp, gStart, 1, what));
      part.fatalSyntax = true;
      part.end = pos;
      return part;
    }
    groups.add(
        _Group(gStart, pos, intDigits, hasDot, text.substring(gStart, pos)));
    if (pos < n && text.codeUnitAt(pos) == 0x3A /* : */) {
      pos++;
      continue;
    }
    break;
  }
  final numberEnd = pos;

  // Hemisphere letter, maybe after spaces.
  var hPos = pos;
  while (hPos < n && _isBlank(text.codeUnitAt(hPos))) {
    hPos++;
  }
  String? hemisphere;
  if (hPos < n) {
    final c = text[hPos];
    if ('NSEWnsew'.contains(c)) {
      // Only a letter that is not followed by another letter counts.
      final next = hPos + 1 < n ? text.codeUnitAt(hPos + 1) : 0;
      final nextIsLetter =
          (next >= 0x41 && next <= 0x5A) || (next >= 0x61 && next <= 0x7A);
      if (!nextIsLetter) hemisphere = c;
    }
  }
  if (hemisphere != null) {
    // One space before the letter is valid: `45:40:30 N`.
    if (hPos > numberEnd && text.substring(numberEnd, hPos) != ' ') {
      issues.add(CoordinateIssue(
          CoordinateIssueKind.extraSpaceBeforeHemisphere,
          cp,
          numberEnd,
          hPos - numberEnd,
          'Write no space or one space between the $partName and its letter '
          '"${hemisphere.toUpperCase()}".',
          replacement: ' '));
    }
    part.end = hPos + 1;
  } else {
    part.end = numberEnd;
  }

  // Notation and structure.
  if (groups.length > 3) {
    issues.add(CoordinateIssue(CoordinateIssueKind.syntax, cp, start,
        numberEnd - start, 'The $partName has too many ":" parts.'));
    part.fatalSyntax = true;
    return part;
  }
  for (var i = 0; i < groups.length - 1; i++) {
    if (groups[i].hasDot) {
      issues.add(CoordinateIssue(
          CoordinateIssueKind.syntax,
          cp,
          groups[i].start,
          groups[i].end - groups[i].start,
          'Only the last number of the $partName can have decimals.'));
      part.fatalSyntax = true;
      return part;
    }
  }
  switch (groups.length) {
    case 1:
      part.notation = CoordinateNotation.decimalDegrees;
      issues.add(CoordinateIssue(
          CoordinateIssueKind.decimalDegrees,
          cp,
          start,
          numberEnd - start,
          'The $partName uses decimal degrees. '
          'Use DMS (DD:MM:SS) or DDM (DD:MM.mmm).'));
    case 2:
      part.notation = CoordinateNotation.ddm;
    default:
      part.notation = CoordinateNotation.dms;
  }

  // Digit counts (not for decimal degrees).
  if (groups.length > 1) {
    final degDigits = isLat ? 2 : 3;
    _checkDigits(groups[0], degDigits, cp, 'degrees of the $partName', issues);
    _checkDigits(groups[1], 2, cp, 'minutes of the $partName', issues);
    if (groups.length == 3) {
      _checkDigits(groups[2], 2, cp, 'seconds of the $partName', issues);
      if (groups[2].hasDot) {
        final g = groups[2];
        issues.add(CoordinateIssue(
            CoordinateIssueKind.decimalSeconds,
            cp,
            g.start,
            g.end - g.start,
            'The seconds of the $partName have decimals. '
            'DMS uses whole seconds. Round the seconds or use DDM.'));
      }
    }
  }

  // Hemisphere checks.
  var sign = 1.0;
  if (hemisphere == null) {
    issues.add(CoordinateIssue(
        CoordinateIssueKind.missingHemisphere,
        cp,
        numberEnd < n ? numberEnd : (numberEnd > 0 ? numberEnd - 1 : 0),
        1,
        isLat
            ? 'The latitude needs the letter N or S.'
            : 'The longitude needs the letter E or W.'));
  } else {
    final upper = hemisphere.toUpperCase();
    if (hemisphere != upper) {
      issues.add(CoordinateIssue(CoordinateIssueKind.lowerCaseHemisphere, cp,
          hPos, 1, 'Write the letter "$upper" in upper case.'));
    }
    final ok =
        isLat ? (upper == 'N' || upper == 'S') : (upper == 'E' || upper == 'W');
    if (!ok) {
      issues.add(CoordinateIssue(
          CoordinateIssueKind.wrongHemisphere,
          cp,
          hPos,
          1,
          isLat
              ? 'The latitude must end with N or S, not $upper.'
              : 'The longitude must end with E or W, not $upper.'));
    }
    if (upper == 'S' || upper == 'W') sign = -1.0;
  }

  // Values and ranges.
  final deg = groups[0].value;
  var total = deg;
  if (groups.length > 1) {
    final min = groups[1].value;
    if (min >= 60) {
      final g = groups[1];
      issues.add(CoordinateIssue(CoordinateIssueKind.minutesOutOfRange, cp,
          g.start, g.end - g.start, 'The minutes must be less than 60.'));
    }
    total += min / 60;
    if (groups.length == 3) {
      final sec = groups[2].value;
      if (sec >= 60) {
        final g = groups[2];
        issues.add(CoordinateIssue(CoordinateIssueKind.secondsOutOfRange, cp,
            g.start, g.end - g.start, 'The seconds must be less than 60.'));
      }
      total += sec / 3600;
    }
  }
  final limit = isLat ? 90.0 : 180.0;
  if (total > limit + 1e-12) {
    issues.add(CoordinateIssue(
        isLat
            ? CoordinateIssueKind.latitudeOutOfRange
            : CoordinateIssueKind.longitudeOutOfRange,
        cp,
        start,
        numberEnd - start,
        'The $partName must not be greater than ${limit.toInt()} degrees.'));
  }
  part.value = sign * total;
  return part;
}

void _checkDigits(_Group g, int expected, CoordinatePart cp, String what,
    List<CoordinateIssue> issues) {
  if (g.intDigits < expected) {
    issues.add(CoordinateIssue(
        CoordinateIssueKind.missingLeadingZero,
        cp,
        g.start,
        g.end - g.start,
        'Write the $what with $expected digits '
        '(add a leading zero).',
        replacement: '${'0' * (expected - g.intDigits)}${g.text}'));
  } else if (g.intDigits > expected) {
    // Only zeros at the start can be removed without a change of the value.
    final extra = g.intDigits - expected;
    final onlyZeros = g.text.substring(0, extra) == '0' * extra;
    issues.add(CoordinateIssue(CoordinateIssueKind.tooManyDigits, cp, g.start,
        g.end - g.start, 'Write the $what with $expected digits.',
        replacement: onlyZeros ? g.text.substring(extra) : null));
  }
}

/// Writes [value] in the notation of the specification.
///
/// - DMS: `45:40:30N 014:18:20E` (seconds are rounded to whole seconds).
/// - DDM: `45:40.500N 014:18.333E` (three decimals).
/// - [CoordinateNotation.decimalDegrees] is not a spec notation; it is
///   written as DMS.
///
/// Use it in messages to show the user the correct form.
String formatCoordinate(LatLng value,
    [CoordinateNotation notation = CoordinateNotation.dms]) {
  final lat = _formatPart(value.lat.abs(), 2, notation);
  final lon = _formatPart(value.lon.abs(), 3, notation);
  final ns = value.lat < 0 ? 'S' : 'N';
  final ew = value.lon < 0 ? 'W' : 'E';
  return '$lat$ns $lon$ew';
}

String _formatPart(double v, int degDigits, CoordinateNotation notation) {
  String two(int x) => x.toString().padLeft(2, '0');
  if (notation == CoordinateNotation.ddm) {
    var thousandths = (v * 60000).round(); // minutes * 1000
    final deg = thousandths ~/ 60000;
    thousandths -= deg * 60000;
    final min = thousandths ~/ 1000;
    final frac = thousandths % 1000;
    return '${deg.toString().padLeft(degDigits, '0')}:${two(min)}.'
        '${frac.toString().padLeft(3, '0')}';
  }
  var secs = (v * 3600).round();
  final deg = secs ~/ 3600;
  secs -= deg * 3600;
  final min = secs ~/ 60;
  final sec = secs % 60;
  return '${deg.toString().padLeft(degDigits, '0')}:${two(min)}:${two(sec)}';
}
