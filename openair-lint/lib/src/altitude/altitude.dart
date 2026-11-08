/// A parser for the altitude values of the `AH` and `AL` commands.
///
/// The parser is lenient. It reads the forms of the specification and the
/// old forms that real files use (`SFC`, `MSL`, `1000ft`, `UNLIM` and more).
/// It returns the meaning of the value and a list of issues. It never
/// throws. The rules in `altitude_rules.dart` turn the issues into
/// diagnostics.
///
/// The parser ignores case: `1000 ft msl` is read like `1000 FT MSL`. The
/// upper case rule of version 3.0 is the rule `case-not-upper-case` of the
/// header group, so that one problem is reported only once.
///
/// Forms of version 3.0:
///
/// ```
/// GND               (AL only)
/// UNL               (AH only)
/// FL95              flight level
/// 1000 FT AMSL      above mean sea level
/// 300 M AGL         above ground level
/// 9500 FT STD       pressure altitude (standard pressure, 1013.25 hPa)
/// ```
library;

import '../values/text_parts.dart';

/// What kind of altitude a value is.
enum AltitudeKind {
  /// `GND`: the ground (lower limit only).
  ground,

  /// `UNL`: no upper limit (upper limit only).
  unlimited,

  /// `FL95`: a flight level.
  flightLevel,

  /// A number with a unit and a reference, for example `1000 FT AMSL`.
  height,

  /// The value cannot be read.
  invalid,
}

/// The unit of an altitude.
enum AltitudeUnit {
  /// Feet, written `FT`.
  feet('FT'),

  /// Metres, written `M`.
  meters('M');

  const AltitudeUnit(this.label);

  /// The unit as the specification writes it.
  final String label;
}

/// The reference of an altitude.
enum AltitudeReference {
  /// Above mean sea level.
  amsl('AMSL'),

  /// Above ground level.
  agl('AGL'),

  /// Standard pressure (1013.25 hPa). A flight level also uses this
  /// reference.
  std('STD');

  const AltitudeReference(this.label);

  /// The reference as the specification writes it.
  final String label;
}

/// The kinds of problems that [parseAltitude] finds.
enum AltitudeIssueKind {
  /// The value is empty.
  empty,

  /// The value (or a part of it) cannot be read.
  invalid,

  /// An old keyword such as `SFC` or `UNLIM` in place of `GND` or `UNL`.
  legacyKeyword,

  /// A number without the unit `FT` or `M`.
  unitMissing,

  /// A unit that the specification does not define, for example `F`.
  unknownUnit,

  /// A number and unit without a reference such as `AMSL`.
  referenceMissing,

  /// A reference that the specification does not define, for example `MSL`.
  unknownReference,

  /// More than one altitude, for example `100 M AGL/423 M AMSL`.
  multipleValues,

  /// A flight level in a wrong form, for example `FL95.5` or `95 FL`.
  flightLevelInvalid,

  /// A space between `FL` and the number, for example `FL 95`.
  flightLevelSpace,

  /// No space between the number and the unit, for example `1000FT`.
  noSpaceBeforeUnit,

  /// More than one space, or a tab, between the parts of the value.
  extraSpace,
}

/// One problem in an altitude value.
class AltitudeIssue {
  const AltitudeIssue(
    this.kind,
    this.offset,
    this.length,
    this.message, {
    this.replacement,
  });

  /// The kind of problem.
  final AltitudeIssueKind kind;

  /// The position of the problem in the parsed text (0-based).
  final int offset;

  /// The length of the problem (at least 1).
  final int length;

  /// A plain English message that says what is wrong and how to fix it.
  final String message;

  /// The text that should replace the wrong part, if it is known.
  final String? replacement;

  @override
  String toString() => 'AltitudeIssue($kind at $offset+$length: $message)';
}

/// The result of [parseAltitude].
class AltitudeParseResult {
  const AltitudeParseResult({
    required this.text,
    required this.kind,
    this.number,
    this.numberText,
    this.unit,
    this.reference,
    this.issues = const [],
    this.suggestion,
  });

  /// The text that was parsed.
  final String text;

  /// The kind of the value. It is [AltitudeKind.invalid] if the value
  /// cannot be read.
  final AltitudeKind kind;

  /// The number: the altitude for [AltitudeKind.height] or the flight level
  /// for [AltitudeKind.flightLevel]. Null for the other kinds.
  final double? number;

  /// The number as written.
  final String? numberText;

  /// The unit, also if it was written in an old form such as `F`. Null if
  /// the value has no unit, or for a flight level.
  final AltitudeUnit? unit;

  /// The reference, also if it was written in an old form such as `MSL`.
  /// It is [AltitudeReference.std] for a flight level. Null if the value
  /// has no reference.
  final AltitudeReference? reference;

  /// The problems, sorted by position.
  final List<AltitudeIssue> issues;

  /// The value in the form of the specification (version 3.0), if it can be
  /// made from the text, for example `1000 FT AMSL` for `1000ft MSL`.
  final String? suggestion;

  /// True if the value has no issues.
  bool get isClean => issues.isEmpty;

  /// True if the value has an issue of this kind.
  bool has(AltitudeIssueKind kind) => issues.any((i) => i.kind == kind);

  /// All issues of this kind.
  Iterable<AltitudeIssue> issuesOf(AltitudeIssueKind kind) =>
      issues.where((i) => i.kind == kind);

  /// The altitude in feet, or null if it is not known. GND is 0 (above
  /// ground), UNL is infinity. A flight level is 100 ft per level.
  double? get feet {
    switch (kind) {
      case AltitudeKind.ground:
        return 0;
      case AltitudeKind.unlimited:
        return double.infinity;
      case AltitudeKind.flightLevel:
        return number! * 100;
      case AltitudeKind.height:
        final n = number;
        final u = unit;
        if (n == 0) return 0; // 0 is 0 in every unit.
        if (n == null || u == null) return null;
        return u == AltitudeUnit.feet ? n : n / feetToMeters;
      case AltitudeKind.invalid:
        return null;
    }
  }

  /// The reference for a comparison with another altitude. GND is
  /// [AltitudeReference.agl], a flight level is [AltitudeReference.std].
  /// Null for UNL, for an invalid value and for a value without a
  /// reference.
  AltitudeReference? get comparableReference => switch (kind) {
        AltitudeKind.ground => AltitudeReference.agl,
        AltitudeKind.flightLevel => AltitudeReference.std,
        AltitudeKind.height => reference,
        _ => null,
      };

  /// A short text of the value for messages, for example `FL95` or
  /// `1000 FT AMSL`. It is the [suggestion] if there is one, or else the
  /// text as written.
  String get display => suggestion ?? text;

  @override
  String toString() => 'AltitudeParseResult("$text", $kind, $issues)';
}

/// One foot in metres.
const double feetToMeters = 0.3048;

/// Words that mean `GND` in old files.
const Map<String, String> _groundWords = {
  'SFC': 'SFC',
  'ASFC': 'ASFC',
  'AGL': 'AGL',
  'GROUND': 'GROUND',
};

/// Words that mean `UNL` in old files.
const Set<String> _unlimitedWords = {
  'UNLIM',
  'UNLTD',
  'UNLIMITED',
  'UNLMTD',
  'INF',
};

/// Old unit words and the unit that they mean.
const Map<String, AltitudeUnit> _legacyUnits = {
  'F': AltitudeUnit.feet,
  'FEET': AltitudeUnit.feet,
  'FOOT': AltitudeUnit.feet,
  'FTS': AltitudeUnit.feet,
  'MT': AltitudeUnit.meters,
  'MTR': AltitudeUnit.meters,
  'MTRS': AltitudeUnit.meters,
  'METER': AltitudeUnit.meters,
  'METERS': AltitudeUnit.meters,
  'METRE': AltitudeUnit.meters,
  'METRES': AltitudeUnit.meters,
};

/// Old reference words and the reference that they mean.
const Map<String, AltitudeReference> _legacyReferences = {
  'MSL': AltitudeReference.amsl,
  'ASL': AltitudeReference.amsl,
  'ALT': AltitudeReference.amsl,
  'QNH': AltitudeReference.amsl,
  'GND': AltitudeReference.agl,
  'SFC': AltitudeReference.agl,
  'ASFC': AltitudeReference.agl,
  'QNE': AltitudeReference.std,
};

/// The meaning of each reference, for messages.
const Map<AltitudeReference, String> _referenceMeaning = {
  AltitudeReference.amsl: 'above mean sea level',
  AltitudeReference.agl: 'above ground level',
  AltitudeReference.std: 'standard pressure',
};

final RegExp _numberPattern = RegExp(r'^-?\d+(\.\d+)?$');

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
bool _isNumberChar(int c) => _isDigit(c) || c == 0x2E || c == 0x2D;

enum _SegType { number, word, other }

/// One part of a word: a number, a word of letters, or other characters.
class _Seg {
  _Seg(this.text, this.offset, this.type, {required this.joined});

  final String text;
  final int offset;
  final _SegType type;

  /// True if there is no space between this part and the part before it.
  final bool joined;

  String get upper => text.toUpperCase();
  int get end => offset + text.length;
  bool get isUpperCase => text == upper;
}

List<_Seg> _segments(String text) {
  final result = <_Seg>[];
  for (final word in splitWords(text)) {
    final w = word.text;
    var i = 0;
    var first = true;
    while (i < w.length) {
      final c = w.codeUnitAt(i);
      final start = i;
      _SegType type;
      if (_isLetter(c)) {
        type = _SegType.word;
        while (i < w.length && _isLetter(w.codeUnitAt(i))) {
          i++;
        }
      } else if (_isNumberChar(c)) {
        type = _SegType.number;
        i++;
        while (i < w.length && _isNumberChar(w.codeUnitAt(i))) {
          i++;
        }
      } else {
        type = _SegType.other;
        i++;
        while (i < w.length &&
            !_isLetter(w.codeUnitAt(i)) &&
            !_isNumberChar(w.codeUnitAt(i))) {
          i++;
        }
      }
      result.add(_Seg(w.substring(start, i), word.offset + start, type,
          joined: !first));
      first = false;
    }
  }
  return result;
}

/// Parses the value of an `AH` or `AL` command, for example `FL95`,
/// `1000 FT AMSL` or `GND`.
///
/// [text] is the argument of the command, without the comment. Spaces at
/// the start and the end are ignored. The offsets of the issues are
/// positions in [text].
///
/// The parser does not know if the value is an upper or a lower limit, and
/// it does not know the spec version. The rules decide which issues matter.
AltitudeParseResult parseAltitude(String text) {
  if (text.trim().isEmpty) {
    return AltitudeParseResult(
      text: text,
      kind: AltitudeKind.invalid,
      issues: [
        AltitudeIssue(AltitudeIssueKind.empty, 0, 1, 'The altitude is empty.')
      ],
    );
  }

  // Two or more values: "100 M AGL/423 M AMSL".
  final slash = text.indexOf('/');
  if (slash >= 0) {
    final before = text.substring(0, slash).trim();
    final after = text.substring(slash + 1).trim();
    if (before.isNotEmpty && after.isNotEmpty) {
      final start = text.length - text.trimLeft().length;
      final end = text.trimRight().length;
      return AltitudeParseResult(
        text: text,
        kind: AltitudeKind.invalid,
        issues: [
          AltitudeIssue(
              AltitudeIssueKind.multipleValues,
              start,
              end - start,
              'The value "${text.trim()}" has more than one altitude. '
              'Write only one altitude.')
        ],
      );
    }
  }

  // Special space characters, for example the no-break space U+00A0. Each
  // one is one UTF-16 unit, so a normal space in its place keeps all the
  // offsets. The parser then reads the value as if it had normal spaces.
  final specialSpaces = <AltitudeIssue>[];
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (_isSpecialSpace(c)) {
      final code = c.toRadixString(16).toUpperCase().padLeft(4, '0');
      specialSpaces.add(AltitudeIssue(
          AltitudeIssueKind.invalid,
          i,
          1,
          'The altitude has a special space character (U+$code). Use a '
          'normal space.',
          replacement: ' '));
      buffer.writeCharCode(0x20);
    } else {
      buffer.writeCharCode(c);
    }
  }
  final normalized = buffer.toString();
  if (normalized.trim().isEmpty) {
    return AltitudeParseResult(
      text: text,
      kind: AltitudeKind.invalid,
      issues: [
        AltitudeIssue(AltitudeIssueKind.empty, 0, 1, 'The altitude is empty.')
      ],
    );
  }

  final segs = _segments(normalized);
  return _Parser(text, normalized, segs, specialSpaces).parse();
}

/// Space characters that look like a normal space, but are not one.
bool _isSpecialSpace(int c) =>
    c == 0x00A0 ||
    (c >= 0x2000 && c <= 0x200B) ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF;

/// A number with thousands separators: "5,000", "10'000" or "1 000" (the
/// blank is read from the normalized text, so a no-break space counts).
final RegExp _thousandsPattern = RegExp(r"^-?\d{1,3}([,'’]\d{3})+$");
final RegExp _thousandsSeparator = RegExp(r"[,'’]");
final RegExp _threeDigits = RegExp(r'^\d{3}$');
final RegExp _oneOrTwoDigits = RegExp(r'^-?\d{1,2}$');

/// `"a"`, `"a" and "b"`, `"a", "b" and "c"`.
String _joinList(List<String> items) {
  if (items.length <= 1) return items.join();
  return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

class _Parser {
  _Parser(this.text, this.norm, this.segs, this.specialSpaces)
      : issues = [...specialSpaces];

  /// The text as written. Messages show parts of this text.
  final String text;

  /// [text] with a normal space in place of each special space character.
  final String norm;
  final List<_Seg> segs;

  /// The issues for special space characters.
  final List<AltitudeIssue> specialSpaces;
  final List<AltitudeIssue> issues;

  AltitudeKind kind = AltitudeKind.invalid;
  double? number;
  String? numberText;
  AltitudeUnit? unit;
  AltitudeReference? reference;
  String? suggestion;

  AltitudeParseResult parse() {
    final first = segs.first;
    if (first.type == _SegType.word && first.upper == 'FL') {
      _flightLevel();
    } else if (first.type == _SegType.word) {
      _keyword();
    } else if (first.type == _SegType.number) {
      _height();
    } else {
      _invalidFrom(0);
    }
    _checkSpaces();
    issues.sort((a, b) => a.offset.compareTo(b.offset));
    return AltitudeParseResult(
      text: text,
      kind: kind,
      number: number,
      numberText: numberText,
      unit: unit,
      reference: reference,
      issues: List.unmodifiable(issues),
      suggestion: suggestion,
    );
  }

  String get _trimmed => text.trim();

  void _add(AltitudeIssueKind k, int offset, int length, String message,
      {String? replacement}) {
    issues.add(AltitudeIssue(k, offset, length < 1 ? 1 : length, message,
        replacement: replacement));
  }

  /// Reports the whole value as invalid.
  void _invalidAll([String? message]) {
    final start = segs.first.offset;
    final end = segs.last.end;
    kind = AltitudeKind.invalid;
    _add(
        AltitudeIssueKind.invalid,
        start,
        end - start,
        message ??
            'The altitude "$_trimmed" is not valid. Use one of these forms: '
                '"FL95", "1000 FT AMSL", "300 M AGL", "GND" (AL only) or '
                '"UNL" (AH only).');
  }

  /// Reports the text from segment [index] to the end as text that does
  /// not belong to the altitude.
  void _invalidFrom(int index) {
    if (index == 0) {
      _invalidAll();
      return;
    }
    final start = segs[index].offset;
    final end = segs.last.end;
    final extra = text.substring(start, end);
    _add(AltitudeIssueKind.invalid, start, end - start,
        'Remove "$extra". It is not part of a valid altitude.');
  }

  // GND, UNL and their old forms. NOTAM and other words are invalid.
  void _keyword() {
    final first = segs.first;
    final up = first.upper;
    final isUnitOrReference = up == 'FT' ||
        up == 'M' ||
        _legacyUnits.containsKey(up) ||
        (_reference(up) != null &&
            up != 'GND' &&
            !_groundWords.containsKey(up));
    if (isUnitOrReference && segs.every((s) => s.type == _SegType.word)) {
      // "FT AMSL": the number is missing.
      _invalidAll('The altitude "$_trimmed" has no number. Write the number '
          'before the unit, for example "1000 FT AMSL".');
      return;
    }
    if (segs.length > 1) {
      if (up == 'GND' || up == 'UNL' || _unlimitedWords.contains(up)) {
        // "GND 1000 FT" and similar.
        _setKeyword(first, up);
        _invalidFrom(1);
        return;
      }
      _invalidAll();
      return;
    }
    if (up == 'NOTAM') {
      // The parser does not know if this is AH or AL. The rule adds the
      // advice for UNL or GND.
      _invalidAll('"$_trimmed" is not an altitude. The file must contain '
          'the limit itself. Write the published limit, for example "FL95" '
          'or "1000 FT AMSL".');
      return;
    }
    _setKeyword(first, up);
    if (kind == AltitudeKind.invalid) _invalidAll();
  }

  void _setKeyword(_Seg seg, String up) {
    if (up == 'GND') {
      kind = AltitudeKind.ground;
      suggestion = 'GND';
    } else if (up == 'UNL') {
      kind = AltitudeKind.unlimited;
      suggestion = 'UNL';
    } else if (_groundWords.containsKey(up)) {
      kind = AltitudeKind.ground;
      suggestion = 'GND';
      _add(
          AltitudeIssueKind.legacyKeyword,
          seg.offset,
          seg.text.length,
          '"${seg.text}" is not a valid altitude. For a limit at the ground, '
          'write "GND".',
          replacement: 'GND');
    } else if (_unlimitedWords.contains(up)) {
      kind = AltitudeKind.unlimited;
      suggestion = 'UNL';
      _add(
          AltitudeIssueKind.legacyKeyword,
          seg.offset,
          seg.text.length,
          '"${seg.text}" is not a valid altitude. For no upper limit, '
          'write "UNL".',
          replacement: 'UNL');
    }
  }

  // FL95, FL 95, FL95.5, FL, FL95 FT.
  void _flightLevel() {
    final fl = segs.first;
    if (segs.length == 1) {
      kind = AltitudeKind.invalid;
      _add(
          AltitudeIssueKind.flightLevelInvalid,
          fl.offset,
          fl.text.length,
          'The flight level has no number. Write the flight level as "FL" '
          'and a whole number, for example "FL95".');
      return;
    }
    if (segs[1].type != _SegType.number) {
      // "FL+95", "FL#95", "FL XX".
      kind = AltitudeKind.invalid;
      final bad = segs[1];
      final next = segs.length > 2 ? segs[2] : null;
      final String message;
      if (bad.type == _SegType.other &&
          next != null &&
          next.joined &&
          next.type == _SegType.number &&
          RegExp(r'^\d+$').hasMatch(next.text)) {
        message = 'Remove "${text.substring(bad.offset, bad.end)}". Write the '
            'flight level as "FL" and a whole number: "FL${next.text}".';
      } else {
        message = 'The text after "FL" is not a whole number. Write the '
            'flight level as "FL" and a whole number, for example "FL95".';
      }
      _add(AltitudeIssueKind.flightLevelInvalid, fl.offset,
          segs.last.end - fl.offset, message);
      return;
    }
    final n = segs[1];
    if (!n.joined) {
      _add(AltitudeIssueKind.flightLevelSpace, fl.end, n.offset - fl.end,
          'Write the flight level without a space: "FL${n.text}".',
          replacement: 'FL${n.text}');
    }
    var value = _numberPattern.hasMatch(n.text) ? double.parse(n.text) : null;
    // A number with hundreds of digits is Infinity as a double.
    if (value != null && !value.isFinite) value = null;
    if (value == null || n.text.contains('.')) {
      final example = value == null || value.abs() >= 1e15
          ? 'FL95'
          : 'FL${value.truncate().abs().toString()}';
      kind = AltitudeKind.invalid;
      _add(
          AltitudeIssueKind.flightLevelInvalid,
          fl.offset,
          n.end - fl.offset,
          'The flight level "${text.substring(fl.offset, n.end)}" is not '
          'valid. A flight level is a whole number of hundreds of feet, '
          'for example "$example".');
      if (segs.length > 2) _invalidFrom(2);
      return;
    }
    kind = AltitudeKind.flightLevel;
    number = value;
    numberText = n.text;
    reference = AltitudeReference.std;
    suggestion = 'FL${n.text}';
    if (segs.length > 2) {
      // "FL95 FT", "FL95 STD", "FL95 AMSL".
      final rest = segs[2];
      final up = rest.upper;
      final isUnitOrRef = rest.type == _SegType.word &&
          (up == 'FT' ||
              up == 'M' ||
              _legacyUnits.containsKey(up) ||
              AltitudeReference.values.any((r) => r.label == up) ||
              _legacyReferences.containsKey(up));
      if (isUnitOrRef) {
        final start = rest.offset;
        final end = segs.last.end;
        _add(
            AltitudeIssueKind.flightLevelInvalid,
            start,
            end - start,
            'A flight level has no unit and no reference. Remove '
            '"${text.substring(start, end)}" and write only "FL${n.text}".',
            replacement: '');
      } else {
        _invalidFrom(2);
      }
    }
  }

  // 1000 FT AMSL and its variants.
  void _height() {
    final n = segs.first;
    if (!_numberPattern.hasMatch(n.text)) {
      _invalidAll();
      return;
    }

    // Parts without a space after the number belong to the number token:
    // "5,000", "1,5", "1000(".
    var i = 1;
    while (i < segs.length && segs[i].joined && segs[i].type != _SegType.word) {
      i++;
    }
    var numEnd = segs[i - 1].end;
    var numText = n.text;
    var numberValid = true;
    if (i > 1) {
      final token = norm.substring(n.offset, numEnd);
      if (_thousandsPattern.hasMatch(token)) {
        numText = token.replaceAll(_thousandsSeparator, '');
        _thousands(n.offset, numEnd, numText);
      } else if (segs.sublist(1, i).any((s) => s.type == _SegType.number)) {
        // "1,5", "1.000,5", "10:00".
        numberValid = false;
        _add(
            AltitudeIssueKind.invalid,
            n.offset,
            numEnd - n.offset,
            'The number "${text.substring(n.offset, numEnd)}" is not valid. '
            'A number has only digits, and a point for decimals.');
      } else {
        // "1000(FT)": the other characters are reported below.
        i = 1;
        numEnd = n.end;
      }
    } else if (_oneOrTwoDigits.hasMatch(n.text)) {
      // "1 000" and "10 000": a space as the thousands separator.
      var j = 1;
      while (j < segs.length &&
          !segs[j].joined &&
          segs[j].type == _SegType.number &&
          _threeDigits.hasMatch(segs[j].text) &&
          norm.substring(segs[j - 1].end, segs[j].offset) == ' ') {
        j++;
      }
      if (j > 1) {
        i = j;
        numEnd = segs[j - 1].end;
        numText = segs.sublist(0, j).map((s) => s.text).join();
        _thousands(n.offset, numEnd, numText);
      }
    }
    if (numberValid && !double.parse(numText).isFinite) {
      // A number with hundreds of digits is Infinity as a double.
      numberValid = false;
      _add(
          AltitudeIssueKind.invalid,
          n.offset,
          numEnd - n.offset,
          'The number "${text.substring(n.offset, numEnd)}" is too large. '
          'Write a realistic altitude.');
    }
    if (numberValid) {
      number = double.parse(numText);
      numberText = numText;
    }
    // A number for the examples in messages.
    final exampleNumber = numberValid ? numText : '1000';

    final firstAfterNumber = i;
    _Seg? unitSeg;
    _Seg? refSeg;
    String? unitText; // the unit as the spec writes it
    String? refText; // the reference as the spec writes it
    for (; i < segs.length; i++) {
      final s = segs[i];
      if (s.type != _SegType.word) break;
      final up = s.upper;
      if (up == 'FL' && i == firstAfterNumber) {
        // "95 FL"
        kind = AltitudeKind.invalid;
        final example =
            !numberValid || numText.contains('.') || numText.startsWith('-')
                ? 'FL95'
                : 'FL$numText';
        _add(
            AltitudeIssueKind.flightLevelInvalid,
            n.offset,
            segs.last.end - n.offset,
            'Write a flight level as "FL" and the number: "$example".',
            replacement: example);
        return;
      }
      if (up == 'FL' && unitSeg != null && refSeg == null) {
        // "1000 FT FL": FL is a reference, but the specification writes a
        // flight level as "FL10".
        kind = AltitudeKind.invalid;
        final value = number;
        final std = '$exampleNumber ${unitText ?? 'FT'} STD';
        final String message;
        if (unit == AltitudeUnit.feet &&
            value != null &&
            value > 0 &&
            value % 100 == 0) {
          message = 'Write a flight level as "FL" and the number, for '
              'example "FL${(value / 100).toStringAsFixed(0)}". Or use STD '
              'for a pressure altitude: "$std".';
        } else {
          message = 'Write a flight level as "FL" and a whole number, for '
              'example "FL95". For a pressure altitude, use STD: "$std".';
        }
        _add(AltitudeIssueKind.flightLevelInvalid, n.offset,
            segs.last.end - n.offset, message);
        return;
      }
      if (unitSeg == null && refSeg == null) {
        final u = _unitOf(up);
        if (u != null) {
          unitSeg = s;
          unit = u;
          unitText = u.label;
          if (u.label != up) {
            _add(
                AltitudeIssueKind.unknownUnit,
                s.offset,
                s.text.length,
                '"${s.text}" is not a valid unit. Write "${u.label}". '
                'The units are FT (feet) and M (metres).',
                replacement: u.label);
          }
          continue;
        }
      }
      if (unitSeg != null && _unitOf(up) != null) {
        // "100 FT FT AMSL"
        _add(AltitudeIssueKind.invalid, s.offset, s.text.length,
            'Remove "${s.text}". The altitude has more than one unit.');
        continue;
      }
      final ref = _reference(up);
      if (ref != null && refSeg != null) {
        // "1000 FT AMSL AMSL"
        _add(
            AltitudeIssueKind.invalid,
            s.offset,
            s.text.length,
            'Remove "${s.text}". The altitude has more than one altitude '
            'reference.');
        continue;
      }
      if (ref != null) {
        refSeg = s;
        reference = ref;
        refText = ref.label;
        if (ref.label != up) {
          final groundNote =
              up == 'GND' ? ' Use "GND" only alone, as "AL GND".' : '';
          _add(
              AltitudeIssueKind.unknownReference,
              s.offset,
              s.text.length,
              '"${s.text}" is not a valid altitude reference. Write '
              '"${ref.label}" (${_referenceMeaning[ref]}).$groundNote',
              replacement: ref.label);
        }
        continue;
      }
      break;
    }

    kind = numberValid ? AltitudeKind.height : AltitudeKind.invalid;
    // A wrong number is reported alone. The user fixes it first.
    var unitMissing = numberValid && unitSeg == null;
    var refMissing = numberValid && refSeg == null;
    if (i < segs.length) {
      final s = segs[i];
      final lastWord = s.type == _SegType.word && i == segs.length - 1;
      if (lastWord && unitSeg == null && refSeg == null) {
        // "1000 XYZ": one unknown word. Its message says what is missing.
        unitMissing = false;
        refMissing = false;
        _add(
            AltitudeIssueKind.invalid,
            s.offset,
            s.text.length,
            '"${s.text}" is not a unit or an altitude reference. Write the '
            'unit FT or M and the reference AMSL, AGL or STD, for example '
            '"$exampleNumber FT AMSL".');
      } else if (lastWord &&
          unitSeg == null &&
          (s.upper == 'FT' || s.upper == 'M')) {
        // "1000 AMSL FT": the unit is after the reference.
        unitMissing = false;
        refMissing = false;
        unit = s.upper == 'FT' ? AltitudeUnit.feet : AltitudeUnit.meters;
        _add(
            AltitudeIssueKind.invalid,
            refSeg!.offset,
            s.end - refSeg.offset,
            'Write the unit before the reference: '
            '"$exampleNumber ${s.upper} ${refText ?? refSeg.upper}".');
      } else if (lastWord && unitSeg != null && refSeg == null) {
        // "1000 FT XYZ": the reference is present, but it is not known.
        refMissing = false;
        _add(
            AltitudeIssueKind.unknownReference,
            s.offset,
            s.text.length,
            '"${s.text}" is not a valid altitude reference. Use AMSL, AGL '
            'or STD.');
      } else {
        // Other text: "1000 FT AMSL (SFC)", "1000 (FT) AMSL", "1000 - FT".
        final rest = segs.sublist(i);
        _Seg? restUnit;
        _Seg? restRef;
        for (final r in rest) {
          if (r.type != _SegType.word) continue;
          if (unitSeg == null && restUnit == null && _unitOf(r.upper) != null) {
            restUnit = r;
          } else if (refSeg == null &&
              restRef == null &&
              _reference(r.upper) != null) {
            restRef = r;
          }
        }
        if (restUnit == null && restRef == null) {
          // The text adds nothing that the altitude needs.
          _invalidFrom(i);
        } else {
          // The unit or the reference is there, with other text around it.
          if (restUnit != null) {
            final u = _unitOf(restUnit.upper)!;
            unit = u;
            unitText = u.label;
            unitMissing = false;
          }
          if (restRef != null) {
            final r = _reference(restRef.upper)!;
            reference = r;
            refText = r.label;
            refMissing = false;
          }
          final bad = <String>[];
          for (final r in rest) {
            if (identical(r, restUnit) || identical(r, restRef)) continue;
            final shown = '"${text.substring(r.offset, r.end)}"';
            if (!bad.contains(shown)) bad.add(shown);
          }
          final full = numberValid && unitText != null && refText != null
              ? '$numText $unitText $refText'
              : null;
          if (full != null) suggestion = full;
          final start = rest.first.offset;
          _add(
              AltitudeIssueKind.invalid,
              start,
              rest.last.end - start,
              'Remove ${_joinList(bad)}. '
              '${bad.length == 1 ? 'It is' : 'They are'} not part of a valid '
              'altitude.${full == null ? '' : ' Write "$full".'}');
        }
      }
    }
    if (unitMissing) {
      final refExample = reference?.label ?? 'AMSL';
      _add(
          AltitudeIssueKind.unitMissing,
          n.offset,
          numEnd - n.offset,
          'The altitude "$_trimmed" has no unit. Write FT (feet) or M '
          '(metres) after the number, for example "$numText FT $refExample".');
    }
    if (refMissing) {
      final unitExample = unit?.label ?? 'FT';
      // The reference is missing after the value. The problem is at the
      // end of the value, where the reference must be added.
      final end = unitSeg?.end ?? numEnd;
      _add(
          AltitudeIssueKind.referenceMissing,
          end,
          1,
          'The altitude "$_trimmed" has no reference. Add AMSL, AGL or STD, '
          'for example "$numText $unitExample AMSL".');
    }
    if (unitSeg != null && unitSeg.joined) {
      _add(
          AltitudeIssueKind.noSpaceBeforeUnit,
          unitSeg.offset,
          unitSeg.text.length,
          'Write a space between the number and the unit: '
          '"$exampleNumber ${unitText ?? unitSeg.upper}".',
          replacement: ' ${unitSeg.text}');
    }
    if (numberValid &&
        unitText != null &&
        refText != null &&
        i == segs.length) {
      suggestion = '$numText $unitText $refText';
    }
  }

  /// Reports a number with thousands separators, for example "5,000".
  void _thousands(int start, int end, String joined) {
    // A special space inside the number is part of this issue.
    issues.removeWhere((x) =>
        specialSpaces.contains(x) && x.offset >= start && x.offset < end);
    _add(
        AltitudeIssueKind.invalid,
        start,
        end - start,
        'Write the number without a thousands separator: "$joined", not '
        '"${text.substring(start, end)}".',
        replacement: joined);
  }

  /// The unit for a unit word, also for an old form such as `F`.
  AltitudeUnit? _unitOf(String up) {
    if (up == 'FT') return AltitudeUnit.feet;
    if (up == 'M') return AltitudeUnit.meters;
    return _legacyUnits[up];
  }

  AltitudeReference? _reference(String up) {
    for (final r in AltitudeReference.values) {
      if (r.label == up) return r;
    }
    return _legacyReferences[up];
  }

  // One space between the parts. Two or more spaces, or a tab, is a style
  // problem.
  void _checkSpaces() {
    for (var i = 1; i < segs.length; i++) {
      final s = segs[i];
      if (s.joined) continue;
      final prev = segs[i - 1];
      final gap = norm.substring(prev.end, s.offset);
      if (gap != ' ') {
        _add(AltitudeIssueKind.extraSpace, prev.end, gap.length,
            'Use exactly one space between "${prev.text}" and "${s.text}".');
      }
    }
  }
}
