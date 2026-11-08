import '../altitude/altitude.dart';
import '../diagnostic.dart';
import '../lint_context.dart';
import '../model/openair_file.dart';
import '../spec_version.dart';
import 'rule.dart';

/// Rules for the altitude limits AH and AL.
///
/// The values are parsed by `parseAltitude` in `lib/src/altitude/`. Each
/// command is parsed once per file (see [_parsed]), and each rule reports
/// the issues of one kind.
final List<Rule> altitudeRules = [
  _empty,
  _invalid,
  _legacyKeyword,
  _gndInAh,
  _unlInAl,
  _unitMissing,
  _unknownUnit,
  _referenceMissing,
  _unknownReference,
  _mslAlias,
  _multipleValues,
  _flightLevelInvalid,
  _flightLevelSpace,
  _unitNoSpace,
  _spacing,
  _outOfRange,
  _zeroAgl,
  _lowerNotBelowUpper,
  _unitMetres,
];

const Set<String> _altitudeKeywords = {'AH', 'AL'};

/// The parsed value of an AH or AL command, computed once per file.
AltitudeParseResult _parsed(LintContext ctx, Command c) =>
    ctx.memo(('altitude', c), () => parseAltitude(c.argument));

/// "upper" or "lower", for messages.
String _limitName(Command c) => c.upperKeyword == 'AH' ? 'upper' : 'lower';

/// Reports every issue of [kind] in the value of [c].
void _reportIssues(LintContext ctx, Command c, AltitudeIssueKind kind) {
  for (final issue in _parsed(ctx, c).issuesOf(kind)) {
    ctx.reportArgument(c, issue.message,
        offset: issue.offset, length: issue.length);
  }
}

/// A rule that reports the issues of one [AltitudeIssueKind].
Rule _issueRule({
  required String id,
  required Severity severity,
  Set<SpecVersion> versions = SpecVersion.all,
  String specAnchor = 'altitude',
  required String description,
  required String explanation,
  required String correctExample,
  required String incorrectExample,
  required AltitudeIssueKind kind,
  CommandCheck? checkCommand,
}) =>
    Rule(
      id: id,
      severity: severity,
      versions: versions,
      specAnchor: specAnchor,
      description: description,
      explanation: explanation,
      correctExample: correctExample,
      incorrectExample: incorrectExample,
      keywords: _altitudeKeywords,
      checkCommand: checkCommand ?? (ctx, c, a) => _reportIssues(ctx, c, kind),
    );

/// The "no space before the unit" issue of [c] at [offset], or null. Only
/// version 3.0 reports this issue.
AltitudeIssue? _gluedUnitAt(LintContext ctx, Command c, int offset) {
  if (!ctx.isV3) return null;
  for (final g
      in _parsed(ctx, c).issuesOf(AltitudeIssueKind.noSpaceBeforeUnit)) {
    if (g.offset == offset) return g;
  }
  return null;
}

// ---------------------------------------------------------------------------
// The form of the value.

final Rule _empty = Rule(
  id: 'altitude-empty',
  severity: Severity.error,
  specAnchor: 'a-altitude-definitions',
  description: 'AH and AL must have a value.',
  explanation: 'An AH or AL command without a value does not define a '
      'limit. Write the altitude after the command.',
  correctExample: 'AH FL95\n'
      'AL GND',
  incorrectExample: 'AH\n'
      'AL GND',
  keywords: _altitudeKeywords,
  checkCommand: (ctx, c, a) {
    if (!_parsed(ctx, c).has(AltitudeIssueKind.empty)) return;
    final example = c.upperKeyword == 'AH'
        ? '"AH FL95", "AH 5000 FT AMSL" or "AH UNL"'
        : '"AL GND", "AL 1500 FT AGL" or "AL FL65"';
    ctx.reportCommand(
        c,
        '${c.upperKeyword} has no value. Write the ${_limitName(c)} limit, '
        'for example $example.');
  },
);

final Rule _invalid = Rule(
  id: 'altitude-invalid',
  severity: Severity.error,
  specAnchor: 'altitude',
  keywords: _altitudeKeywords,
  checkCommand: (ctx, c, a) {
    final p = _parsed(ctx, c);
    // The parser does not know if the value is AH or AL. For "NOTAM", add
    // the advice that fits the command.
    final notamHint = p.text.trim().toUpperCase() != 'NOTAM'
        ? ''
        : c.upperKeyword == 'AH'
            ? ' If the airspace has no upper limit, write "UNL".'
            : ' If the airspace starts at the ground, write "GND".';
    for (final issue in p.issuesOf(AltitudeIssueKind.invalid)) {
      ctx.reportArgument(c, '${issue.message}$notamHint',
          offset: issue.offset, length: issue.length);
    }
  },
  description: 'The altitude must have one of the forms of the '
      'specification.',
  explanation: 'An altitude has one of these forms:\n'
      '\n'
      '- a flight level: "FL95",\n'
      '- a number, a unit and a reference: "1000 FT AMSL", "300 M AGL" or '
      '"9500 FT STD",\n'
      '- "GND" for a lower limit at the ground (AL only),\n'
      '- "UNL" for no upper limit (AH only).\n'
      '\n'
      'This rule reports values that do not have one of these forms, for '
      'example "NOTAM", and text after a valid altitude. A file must '
      'contain the limit itself. A reader must not need a NOTAM or other '
      'information outside the file to understand it.\n'
      '\n'
      'The rule also reports these problems:\n'
      '\n'
      '- a thousands separator in the number: write "5000", not "5,000" or '
      '"5 000",\n'
      '- a number that is not a plain number, for example "1,5",\n'
      '- a unit or a reference that is written two times,\n'
      '- other characters between the parts, for example "1000 (FT) AMSL",\n'
      '- a special space character, such as the no-break space U+00A0. '
      'Use a normal space.',
  correctExample: 'AH FL95\n'
      'AL 1000 FT AMSL',
  incorrectExample: 'AH NOTAM\n'
      'AL 1000 FT AMSL (SFC)',
);

final Rule _legacyKeyword = Rule(
  id: 'altitude-legacy-keyword',
  severity: Severity.error,
  specAnchor: 'supported-altitude-references',
  description: 'Write "GND" and "UNL", not old forms such as "SFC" or '
      '"UNLIM".',
  explanation: 'Old files use other words for the ground and for no upper '
      'limit, for example "SFC", "AGL" alone, "UNLIM" or "UNLTD". The '
      'specification defines only "GND" (AL only) and "UNL" (AH only). Some '
      'readers do not understand the other words.',
  correctExample: 'AH UNL\n'
      'AL GND',
  incorrectExample: 'AH UNLIM\n'
      'AL SFC',
  keywords: _altitudeKeywords,
  checkCommand: (ctx, c, a) {
    final p = _parsed(ctx, c);
    // "SFC" in AH and "UNLIM" in AL are reported by the rules for GND in
    // AH and UNL in AL, with a better message.
    if (c.upperKeyword == 'AH' && p.kind == AltitudeKind.ground) return;
    if (c.upperKeyword == 'AL' && p.kind == AltitudeKind.unlimited) return;
    _reportIssues(ctx, c, AltitudeIssueKind.legacyKeyword);
  },
);

final Rule _gndInAh = Rule(
  id: 'altitude-gnd-in-ah',
  severity: Severity.error,
  specAnchor: 'supported-altitude-references',
  description: 'GND is only allowed in AL, not in AH.',
  explanation: 'GND means "at the ground". It is only allowed as a lower '
      'limit (AL). An upper limit (AH) at the ground makes an airspace '
      'without height.\n'
      '\n'
      'Often the upper and lower limits are swapped, or the upper limit is a '
      'height above the ground, such as "1000 FT AGL".',
  correctExample: 'AH 1000 FT AGL\n'
      'AL GND',
  incorrectExample: 'AH GND\n'
      'AL 1000 FT AGL',
  keywords: {'AH'},
  checkCommand: (ctx, c, a) {
    final p = _parsed(ctx, c);
    if (p.kind != AltitudeKind.ground) return;
    final written = p.text.trim();
    ctx.reportArgument(
        c,
        '"$written" means the ground. It is not allowed in AH, because the '
        'upper limit must be above the ground. Check if the upper and lower '
        'limits are swapped.');
  },
);

final Rule _unlInAl = Rule(
  id: 'altitude-unl-in-al',
  severity: Severity.error,
  specAnchor: 'supported-altitude-references',
  description: 'UNL is only allowed in AH, not in AL.',
  explanation: 'UNL means "no upper limit". It is only allowed as an upper '
      'limit (AH). A lower limit (AL) cannot be unlimited.\n'
      '\n'
      'Often the upper and lower limits are swapped.',
  correctExample: 'AH UNL\n'
      'AL FL195',
  incorrectExample: 'AH FL195\n'
      'AL UNL',
  keywords: {'AL'},
  checkCommand: (ctx, c, a) {
    final p = _parsed(ctx, c);
    if (p.kind != AltitudeKind.unlimited) return;
    final written = p.text.trim();
    ctx.reportArgument(
        c,
        '"$written" means no upper limit. It is not allowed in AL. Check if '
        'the upper and lower limits are swapped.');
  },
);

final Rule _unitMissing = Rule(
  id: 'altitude-unit-missing',
  severity: Severity.error,
  specAnchor: 'altitude',
  description: 'An altitude must have the unit FT or M.',
  explanation: 'An altitude has a number, a unit and a reference. The unit '
      'is required: FT (feet) or M (metres). Feet are recommended. An '
      'altitude without a unit is not valid, for example "1000 AMSL". '
      'Without the unit, a reader does not know if the number is in feet or '
      'in metres. The meaning of a file must not depend on the settings of '
      'the reader.\n'
      '\n'
      'A flight level ("FL95") has no unit. A value of 0 also needs a '
      'unit. For "AL 0 AGL", the message says to write "AL GND", because '
      'this is the form of the specification for a lower limit at the '
      'ground.',
  keywords: _altitudeKeywords,
  checkCommand: (ctx, c, a) {
    final p = _parsed(ctx, c);
    final zero = _isZeroGroundInAl(ctx, c);
    // "AL 0 GND": the rule altitude-unknown-reference reports it, with
    // the same advice.
    if (zero && p.has(AltitudeIssueKind.unknownReference)) return;
    for (final issue in p.issuesOf(AltitudeIssueKind.unitMissing)) {
      final message = zero
          ? 'The altitude "${p.text.trim()}" has no unit. For a lower limit '
              'at the ground, write "AL GND".'
          : issue.message;
      ctx.reportArgument(c, message,
          offset: issue.offset, length: issue.length);
    }
  },
  correctExample: 'AH 3500 FT AMSL\n'
      'AL 1000 FT AGL',
  incorrectExample: 'AH 3500 AMSL\n'
      'AL 1000 AGL',
);

/// True for an AL value of 0 above the ground: `AL 0 FT AGL`, `AL 0 AGL`,
/// `AL 0 FT GND` and `AL 0 SFC`. The specification writes this as
/// `AL GND`.
///
/// Only one rule reports such a value, so that the user gets one fix:
/// altitude-unknown-reference for `GND` or `SFC` after the number, else
/// altitude-unit-missing for a value without a unit, else
/// altitude-zero-agl.
bool _isZeroGroundInAl(LintContext ctx, Command c) {
  if (c.upperKeyword != 'AL') return false;
  final p = _parsed(ctx, c);
  return p.kind == AltitudeKind.height &&
      p.reference == AltitudeReference.agl &&
      p.number == 0;
}

final Rule _unknownUnit = _issueRule(
  id: 'altitude-unknown-unit',
  severity: Severity.error,
  description: 'The unit of an altitude must be FT or M.',
  explanation: 'The specification defines two units for altitudes: FT '
      '(feet, recommended) and M (metres). Other forms, such as "F" or '
      '"FEET", are not valid.',
  correctExample: 'AH 3500 FT AMSL',
  incorrectExample: 'AH 3500 F AMSL',
  kind: AltitudeIssueKind.unknownUnit,
  checkCommand: (ctx, c, a) {
    for (final issue
        in _parsed(ctx, c).issuesOf(AltitudeIssueKind.unknownUnit)) {
      // "7000F": one message for both problems. altitude-unit-no-space
      // does not report this unit again.
      final glued = _gluedUnitAt(ctx, c, issue.offset);
      ctx.reportArgument(c,
          glued == null ? issue.message : '${issue.message} ${glued.message}',
          offset: issue.offset, length: issue.length);
    }
  },
);

final Rule _referenceMissing = _issueRule(
  id: 'altitude-reference-missing',
  severity: Severity.error,
  specAnchor: 'altitude',
  description: 'An altitude must have the reference AMSL, AGL or STD.',
  explanation: 'The format of AH and AL is "Altitude Unit AltRef": the '
      'number, the unit and the altitude reference. The reference is '
      'required. It says what the altitude is measured from:\n'
      '\n'
      '- AMSL: above mean sea level,\n'
      '- AGL: above ground level,\n'
      '- STD: standard pressure (a pressure altitude, like a flight '
      'level).\n'
      '\n'
      'An altitude without a reference is not valid, for example '
      '"1000 FT". Without the reference, readers guess. Most of them use '
      'AMSL, but this is not certain. A flight level ("FL95"), "GND" and '
      '"UNL" have no reference.',
  correctExample: 'AH 3500 FT AMSL',
  incorrectExample: 'AH 3500 FT',
  kind: AltitudeIssueKind.referenceMissing,
);

final Rule _unknownReference = Rule(
  id: 'altitude-unknown-reference',
  severity: Severity.error,
  specAnchor: 'supported-altitude-references',
  keywords: _altitudeKeywords,
  checkCommand: (ctx, c, a) {
    final p = _parsed(ctx, c);
    final zero = _isZeroGroundInAl(ctx, c);
    for (final issue in p.issuesOf(AltitudeIssueKind.unknownReference)) {
      final word = p.text.substring(issue.offset, issue.offset + issue.length);
      final message = zero
          ? '"$word" is not a valid altitude reference. For a lower limit at '
              'the ground, write "AL GND".'
          : issue.message;
      ctx.reportArgument(c, message,
          offset: issue.offset, length: issue.length);
    }
  },
  description: 'The altitude reference must be AMSL, AGL or STD.',
  explanation: 'The specification defines the altitude references AMSL, '
      'AGL and STD, and the flight level form "FL95". Old files use other '
      'words, for example "ASL" or "ALT" for AMSL, and "GND" or "SFC" for '
      'AGL. Some readers do not understand them.\n'
      '\n'
      'Note: "1000 FT GND" is a height above the ground. Write it as "1000 '
      'FT AGL". "GND" alone (without a number) is the correct form for a '
      'lower limit at the ground.\n'
      '\n'
      '"MSL" is an alias of AMSL that the specification allows. The rule '
      'altitude-msl-alias reports it.',
  correctExample: 'AH 3500 FT AMSL\n'
      'AL 1000 FT AGL',
  incorrectExample: 'AH 3500 FT ASL\n'
      'AL 1000 FT GND',
);

final Rule _mslAlias = _issueRule(
  id: 'altitude-msl-alias',
  severity: Severity.warning,
  specAnchor: 'supported-altitude-references',
  description: 'Write "AMSL", not "MSL".',
  explanation: '"MSL" is an alias of "AMSL" (above mean sea level). A reader '
      'must read "MSL" as "AMSL", so the meaning is the same. But writers '
      'should write "AMSL". openair-lint reads "MSL" as AMSL for all other '
      'checks, for example to compare the lower and the upper limit.',
  correctExample: 'AH 3500 FT AMSL',
  incorrectExample: 'AH 3500 FT MSL',
  kind: AltitudeIssueKind.mslAlias,
);

final Rule _multipleValues = _issueRule(
  id: 'altitude-multiple-values',
  severity: Severity.error,
  specAnchor: 'ah-upper-altitude-limit',
  description: 'AH and AL must have only one altitude.',
  explanation: 'Each airspace definition must include only one upper limit '
      'and only one lower limit. A value with two altitudes, for example '
      '"100 M AGL/423 M AMSL", is ambiguous and not permitted. Readers '
      'handle it in different ways.\n'
      '\n'
      'Write the one limit that applies. You can put the other value in a '
      'comment.',
  correctExample: 'AH 423 M AMSL * 100 M AGL',
  incorrectExample: 'AH 100 M AGL/423 M AMSL',
  kind: AltitudeIssueKind.multipleValues,
);

final Rule _flightLevelInvalid = _issueRule(
  id: 'altitude-flight-level-invalid',
  severity: Severity.error,
  description: 'A flight level must be "FL" and a whole number, for '
      'example "FL95".',
  explanation: 'A flight level is written as "FL" and a whole number, '
      'without a unit and without a reference. "FL95" means 9500 feet at '
      'standard pressure. Decimals ("FL95.5"), a number before "FL" '
      '("95 FL") and a unit after the flight level ("FL95 FT") are not '
      'valid.\n'
      '\n'
      'For a pressure altitude that is not a whole flight level, use STD: '
      '"9550 FT STD".',
  correctExample: 'AH FL95',
  incorrectExample: 'AH FL95.5',
  kind: AltitudeIssueKind.flightLevelInvalid,
);

final Rule _flightLevelSpace = _issueRule(
  id: 'altitude-flight-level-space',
  severity: Severity.warning,
  specAnchor: 'supported-altitude-references',
  description: 'Write a flight level without a space: "FL95", not "FL 95".',
  explanation: '"FL 145" (with a space) has the same meaning as "FL145". A '
      'reader must accept it, but writers should write "FL145", without a '
      'space. openair-lint reads "FL 145" as FL145 for all other checks.',
  correctExample: 'AH FL145',
  incorrectExample: 'AH FL 145',
  kind: AltitudeIssueKind.flightLevelSpace,
);

final Rule _unitNoSpace = _issueRule(
  id: 'altitude-unit-no-space',
  severity: Severity.error,
  versions: SpecVersion.only3,
  description: 'Write a space between the number and the unit.',
  explanation: 'In version 3.0, an altitude has a space between the number '
      'and the unit: "1000 FT", not "1000FT". Version 2.1 allowed both '
      'forms.',
  correctExample: 'AL 1000 FT AMSL',
  incorrectExample: 'AL 1000FT AMSL',
  kind: AltitudeIssueKind.noSpaceBeforeUnit,
  checkCommand: (ctx, c, a) {
    final parsed = _parsed(ctx, c);
    final unknown = {
      for (final u in parsed.issuesOf(AltitudeIssueKind.unknownUnit)) u.offset
    };
    for (final issue in parsed.issuesOf(AltitudeIssueKind.noSpaceBeforeUnit)) {
      // altitude-unknown-unit reports "7000F" with both fixes.
      if (unknown.contains(issue.offset)) continue;
      ctx.reportArgument(c, issue.message,
          offset: issue.offset, length: issue.length);
    }
  },
);

final Rule _spacing = _issueRule(
  id: 'altitude-spacing',
  severity: Severity.info,
  description: 'Use one space between the parts of an altitude.',
  explanation: 'Write exactly one space between the number, the unit and '
      'the reference. Two or more spaces, or a tab, make the file harder to '
      'read and to compare.',
  correctExample: 'AH 1000 FT AMSL',
  incorrectExample: 'AH 1000  FT   AMSL',
  kind: AltitudeIssueKind.extraSpace,
);

final Rule _unitMetres = Rule(
  id: 'altitude-unit-metres',
  severity: Severity.info,
  specAnchor: 'altitude',
  description: 'Feet (FT) are recommended for altitudes. Metres (M) are '
      'allowed.',
  explanation: 'The specification says: altitude is specified in feet FT '
      '(recommended) or in meters M. An altitude in metres is valid. This '
      'rule is info and not a warning, because the specification allows '
      'both units and only recommends one of them.\n'
      '\n'
      'Write the published value. If the published value is in metres, '
      'keep it in metres. A conversion to feet can change the limit by '
      'rounding.',
  correctExample: 'AH 5000 FT AMSL',
  incorrectExample: 'AH 1500 M AMSL',
  keywords: _altitudeKeywords,
  checkCommand: (ctx, c, a) {
    final p = _parsed(ctx, c);
    // An invalid value gets an error from another rule. Zero is the same
    // in every unit.
    if (p.kind != AltitudeKind.height || p.unit != AltitudeUnit.meters) return;
    if (p.number == 0) return;
    final ft = p.feet;
    // A very large value is not shown in feet: round() cannot give an exact
    // whole number for it. altitude-out-of-range reports such values.
    final inFeet = ft == null || !ft.isFinite || ft.abs() >= 1e15
        ? ''
        : ' (about ${ft.round()} FT)';
    ctx.reportArgument(
        c,
        'The altitude "${p.text.trim()}" is in metres$inFeet. Metres are '
        'allowed, but feet are recommended.');
  },
);

// ---------------------------------------------------------------------------
// The value itself.

/// The highest flight level of normal airspace structures (FL660).
const double _maxFeet = 66000;

/// The lowest altitude above mean sea level on land (the Dead Sea shore is
/// about -1400 ft).
const double _minAmslFeet = -1500;

final Rule _outOfRange = Rule(
  id: 'altitude-out-of-range',
  severity: Severity.warning,
  specAnchor: 'altitude',
  description: 'An altitude should be a realistic value.',
  explanation: 'This rule reports altitudes that are probably wrong:\n'
      '\n'
      '- an altitude above FL660 (66000 ft). Airspace limits are almost '
      'never that high. Files often use a value such as "FL999" to mean "no '
      'upper limit". Write "AH UNL" for this.\n'
      '- a negative height above the ground (AGL) or a negative pressure '
      'altitude (STD),\n'
      '- an altitude below 1500 ft under mean sea level (AMSL).',
  correctExample: 'AH UNL',
  incorrectExample: 'AH FL999',
  keywords: _altitudeKeywords,
  checkCommand: _checkOutOfRange,
);

String _feetText(double ft) =>
    ft == ft.roundToDouble() ? ft.toStringAsFixed(0) : ft.toStringAsFixed(1);

void _checkOutOfRange(LintContext ctx, Command c, Airspace? a) {
  final p = _parsed(ctx, c);
  if (p.kind != AltitudeKind.height && p.kind != AltitudeKind.flightLevel) {
    return;
  }
  final ft = p.feet;
  if (ft == null) return;
  final ref = p.comparableReference;
  final shown = p.text.trim();
  final inFeet = p.unit == AltitudeUnit.meters ? ' (${_feetText(ft)} ft)' : '';
  if (ft > _maxFeet) {
    final hint = c.upperKeyword == 'AH'
        ? ' If the airspace has no upper limit, write "AH UNL".'
        : '';
    ctx.reportArgument(
        c,
        'The ${_limitName(c)} limit "$shown"$inFeet is higher than FL660. '
        'Airspace limits are almost never that high. Check the value.$hint');
    return;
  }
  if (ft < 0 && ref != AltitudeReference.amsl) {
    final what = switch (ref) {
      AltitudeReference.agl => 'A height above the ground',
      _ => 'A pressure altitude (STD)',
    };
    ctx.reportArgument(
        c, 'The altitude "$shown" is negative. $what cannot be negative.');
    return;
  }
  if (ft < _minAmslFeet && ref == AltitudeReference.amsl) {
    ctx.reportArgument(
        c,
        'The altitude "$shown"$inFeet is more than 1500 ft below mean sea '
        'level. No land is that low. Check the value.');
  }
}

final Rule _zeroAgl = Rule(
  id: 'altitude-zero-agl',
  severity: Severity.warning,
  specAnchor: 'al-lower-altitude-limit',
  description: 'For a lower limit at the ground, write "AL GND".',
  explanation: 'The specification says: for areas that extend to the '
      'ground, use GND, without an altitude. "AL 0 FT AGL" means the same, '
      'but "AL GND" is the form of the specification.\n'
      '\n'
      'If the value also has an error, another rule reports it with the '
      'same advice, and this rule does not report it. "AL 0 AGL" (no unit) '
      'is reported by altitude-unit-missing. "AL 0 FT GND" and "AL 0 SFC" '
      'are reported by altitude-unknown-reference.',
  correctExample: 'AL GND',
  incorrectExample: 'AL 0 FT AGL',
  keywords: {'AL'},
  checkCommand: (ctx, c, a) {
    if (!_isZeroGroundInAl(ctx, c)) return;
    final p = _parsed(ctx, c);
    if (p.has(AltitudeIssueKind.unitMissing) ||
        p.has(AltitudeIssueKind.unknownReference)) {
      return;
    }
    ctx.reportArgument(
        c,
        '"${_parsed(ctx, c).text.trim()}" is the ground. Write "AL GND" for '
        'a lower limit at the ground.');
  },
);

// ---------------------------------------------------------------------------
// AL below AH.

final Rule _lowerNotBelowUpper = Rule(
  id: 'altitude-lower-not-below-upper',
  severity: Severity.error,
  specAnchor: 'al-lower-altitude-limit',
  description: 'The lower limit (AL) must be below the upper limit (AH).',
  explanation: 'AH is the ceiling and AL is the floor of the airspace. The '
      'floor must be below the ceiling. A lower limit equal to the upper '
      'limit is not valid, because the airspace then has no height. Often '
      'the AH and AL values are swapped.\n'
      '\n'
      'The limits can only be compared when they use the same kind of '
      'reference. openair-lint compares them when both are AMSL (MSL counts '
      'as AMSL), both are AGL (GND counts as 0 FT AGL), or both are '
      'standard pressure (FL and STD: "9500 FT STD" is the same as FL95). '
      'It converts metres to feet. It does not compare AMSL with AGL or with '
      'flight levels, because the difference depends on the terrain and on '
      'the air pressure.',
  correctExample: 'AH FL95\n'
      'AL FL65',
  incorrectExample: 'AH FL65\n'
      'AL FL95',
  checkAirspace: _checkLowerBelowUpper,
);

void _checkLowerBelowUpper(LintContext ctx, Airspace a) {
  final ahCommand = a.firstWith('AH');
  final alCommand = a.firstWith('AL');
  if (ahCommand == null || alCommand == null) return;
  final ah = _parsed(ctx, ahCommand);
  final al = _parsed(ctx, alCommand);
  // UNL in AH is above everything. GND in AH and UNL in AL have their own
  // rules. GND in AL is compared as 0 FT AGL.
  if (ah.kind == AltitudeKind.unlimited ||
      ah.kind == AltitudeKind.ground ||
      al.kind == AltitudeKind.unlimited) {
    return;
  }
  if (ah.has(AltitudeIssueKind.multipleValues) ||
      al.has(AltitudeIssueKind.multipleValues)) {
    return;
  }
  final ref = ah.comparableReference;
  if (ref == null || ref != al.comparableReference) return;
  final ahFeet = ah.feet;
  final alFeet = al.feet;
  if (ahFeet == null || alFeet == null) return;
  final diff = alFeet - ahFeet;
  if (diff.abs() < 1) {
    ctx.reportKeyword(
        alCommand,
        'The lower limit "${al.text.trim()}" is the same as the upper limit '
        '"${ah.text.trim()}" (line ${ahCommand.line}). The airspace has no '
        'height. Check the AH and AL values.');
  } else if (diff > 0) {
    ctx.reportKeyword(
        alCommand,
        'The lower limit "${al.text.trim()}" is above the upper limit '
        '"${ah.text.trim()}" (line ${ahCommand.line}). Check if AH and AL are '
        'swapped.');
  }
}
