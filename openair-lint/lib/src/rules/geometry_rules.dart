import '../diagnostic.dart';
import '../geometry/boundary.dart' show isClockwise;
import '../geometry/geo_math.dart';
import '../lint_context.dart';
import '../model/openair_file.dart';
import '../spec_version.dart';
import '../values/coordinate.dart';
import '../values/text_parts.dart';
import '../values/variable.dart';
import 'geometry_rules_support.dart';
import 'rule.dart';

/// Rules for the geometry commands DP, DA, DB, DC, DY and V, and for
/// coordinates and polygons.
///
/// The geometry is the same in version 2.1 and 3.0, so all rules apply to
/// both versions. Keywords and variable names are compared in upper case.
/// The header group reports the wrong case.
final List<Rule> geometryRules = [
  // Coordinates.
  _coordinateSyntax,
  _coordinateHemisphere,
  _coordinateOutOfRange,
  _coordinateDecimalDegrees,
  _coordinateTrailingText,
  _coordinateSpaceBetweenParts,
  _coordinateDigitCount,
  _coordinateDecimalSeconds,
  _coordinateMixedNotation,
  _coordinateFileMixedNotation,
  // Polygon.
  _polygonTooFewPoints,
  _polygonNotClosed,
  _dpDuplicatePoint,
  _polygonCounterClockwise,
  _polygonSelfIntersection,
  // Centre, arcs and circles.
  _centerMissing,
  _daWrongFormat,
  _daRadiusNotPositive,
  _daBearingOutOfRange,
  _daCombinedWithDp,
  _daNotRecommended,
  _dbWrongFormat,
  _dbRadiusMismatch,
  _dbRadiusMismatchV21,
  _dcWrongFormat,
  _dcRadiusNotPositive,
  _dcMixedWithOtherGeometry,
  _dcMixedWithOtherGeometryV21,
  // Airways.
  _dyDeprecated,
  _dyWidthMissing,
  // Variables.
  _vWrongFormat,
  _vSpaceAroundEquals,
  _vUnknownVariable,
  _vInvalidDirection,
  _vInvalidWidth,
  _vWidthWithoutAirway,
  _vCenterUnused,
];

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// The commands that contain coordinates.
const Set<String> _coordinateKeywords = {'DP', 'DB', 'DY', 'V'};

const String _dpExample = 'AC D\n'
    'AN Example CTR\n'
    'AH 4500 FT AMSL\n'
    'AL GND\n'
    'DP 46:00:00N 014:00:00E\n'
    'DP 46:00:00N 014:10:00E\n'
    'DP 45:55:00N 014:10:00E\n'
    'DP 45:55:00N 014:00:00E\n'
    'DP 46:00:00N 014:00:00E';

/// The commands of the scope of [airspace]: the airspace itself, or the
/// commands before the first `AC` if [airspace] is null.
List<Command> _scope(LintContext ctx, Airspace? airspace) =>
    airspace?.commands ?? ctx.file.commandsOutsideAirspace;

/// The last `V <name>=` command before [command] in its scope, or null.
///
/// The result for every command of the scope is calculated in one pass and
/// kept (memo), so an airspace with many arcs stays fast.
Command? _previousVariable(
    LintContext ctx, Command command, Airspace? airspace, String upperName) {
  final scope = _scope(ctx, airspace);
  final before = ctx.memo(('geometry-previous-variable', scope, upperName), () {
    final result = Map<Command, Command?>.identity();
    Command? last;
    for (final c in scope) {
      result[c] = last;
      if (c.upperKeyword == 'V' && parseVariable(c).upperName == upperName) {
        last = c;
      }
    }
    return result;
  });
  return before[command];
}

/// The last `V <name>=` command in the file before [line], in any scope.
Command? _variableBeforeLine(LintContext ctx, int line, String upperName) {
  final all = ctx.memo(('geometry-variables', upperName), () {
    return [
      for (final c in ctx.file.allCommands)
        if (c.upperKeyword == 'V' && parseVariable(c).upperName == upperName) c
    ];
  });
  // Binary search: the commands are in line order.
  var lo = 0;
  var hi = all.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (all[mid].line < line) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo == 0 ? null : all[lo - 1];
}

/// The sentence that the specification gives for the scope of `V` values.
const String _resetNote = 'The V values are reset at every AC.';

/// A sentence that says that a value from an earlier airspace is not used.
String _earlierScopeNote(LintContext ctx, Airspace? airspace, String what,
    String upperName, int line) {
  final start = airspace?.startLine ?? 1;
  final earlier = _variableBeforeLine(ctx, start, upperName);
  if (earlier == null) return '';
  return ' The $what on line ${earlier.line} is in an earlier part of the '
      'file, so it is not used here.';
}

String _ordinal(int i) => const ['first', 'second', 'third'][i];

/// A hint when a number has a unit, for example `10NM` or `5 km`, or a
/// decimal comma (`2,5`). This works for `DC` and `V W=`. A `DA` argument
/// is split at commas first; `da-wrong-format` has its own hint.
String _unitHint(String text) {
  if (RegExp(r'^[+-]?\d+(\.\d*)?\s*[A-Za-z]+$').hasMatch(text)) {
    return ' Write the number without a unit. The unit is always NM.';
  }
  if (RegExp(r'^[+-]?\d+,\d+$').hasMatch(text)) {
    return ' Use a point (.) as the decimal separator.';
  }
  return '';
}

// ---------------------------------------------------------------------------
// Coordinates
// ---------------------------------------------------------------------------

/// One coordinate issue together with its coordinate.
typedef _Found = (CommandCoordinate, CoordinateIssue);

/// The issue kinds that the parser reports after a hemisphere letter that
/// it does not know. For `46:00:00Q 014:00:00E` the parser stops at `Q`.
/// It reports the missing letter, a missing space and a missing longitude,
/// all at the offset of `Q`. For `014:00:00X` it reports the missing letter
/// and the trailing text `X`. Only the first one helps the user.
///
/// Two blanks after a missing letter (`46:00:00  014:00:00E`) are a real
/// second problem, so `extraSpace` is not in this set.
const Set<CoordinateIssueKind> _followOnKinds = {
  CoordinateIssueKind.missingSpace,
  CoordinateIssueKind.syntax,
  CoordinateIssueKind.trailingText,
};

/// True if [issue] is only a result of a wrong hemisphere letter at the same
/// place (see [_followOnKinds]).
bool _isFollowOn(CoordinateParseResult result, CoordinateIssue issue) {
  if (!_followOnKinds.contains(issue.kind)) return false;
  for (final o in result.issues) {
    if (o.kind == CoordinateIssueKind.missingHemisphere &&
        o.offset == issue.offset) {
      return true;
    }
  }
  return false;
}

/// A rule that reports [CoordinateIssue]s of some kinds.
///
/// If [groupMessage] is null, each issue is reported on its own. Otherwise
/// all matching issues of one command are reported as one diagnostic; if
/// there is more than one, the diagnostic covers all of them and uses the
/// text of [groupMessage].
///
/// [include] can skip issues that another rule reports better.
///
/// [extraCheck] runs after the issues are reported. It can report more
/// problems of the same rule.
Rule _coordinateRule({
  required String id,
  required Severity severity,
  required Set<CoordinateIssueKind> kinds,
  required String description,
  required String explanation,
  required String correctExample,
  required String incorrectExample,
  String Function(List<_Found> found)? groupMessage,
  String Function(CommandCoordinate coordinate, CoordinateIssue issue)? message,
  bool Function(CommandCoordinate coordinate, CoordinateIssue issue)? include,
  void Function(LintContext ctx, Command c, List<CommandCoordinate> coords)?
      extraCheck,
}) {
  return Rule(
    id: id,
    severity: severity,
    versions: SpecVersion.all,
    specAnchor: 'geographic-position',
    description: description,
    explanation: explanation,
    correctExample: correctExample,
    incorrectExample: incorrectExample,
    keywords: _coordinateKeywords,
    checkCommand: (ctx, c, a) {
      final coords = coordinatesOf(ctx, c, a);
      final found = <_Found>[];
      for (final cc in coords) {
        for (final issue in cc.result.issues) {
          if (kinds.contains(issue.kind) &&
              !_isFollowOn(cc.result, issue) &&
              (include == null || include(cc, issue))) {
            found.add((cc, issue));
          }
        }
      }
      if (found.isNotEmpty) _reportFound(ctx, c, found, groupMessage, message);
      if (extraCheck != null) extraCheck(ctx, c, coords);
    },
  );
}

void _reportFound(
  LintContext ctx,
  Command c,
  List<_Found> found,
  String Function(List<_Found> found)? groupMessage,
  String Function(CommandCoordinate coordinate, CoordinateIssue issue)? message,
) {
  String text(CommandCoordinate cc, CoordinateIssue i) =>
      message == null ? i.message : message(cc, i);
  if (groupMessage == null || found.length == 1) {
    for (final (cc, i) in found) {
      ctx.reportArgument(c, text(cc, i),
          offset: cc.offset + i.offset, length: i.length);
    }
    return;
  }
  final start = found.first.$1.offset + found.first.$2.offset;
  final last = found.last;
  final end = last.$1.offset + last.$2.offset + last.$2.length;
  ctx.reportArgument(c, groupMessage(found),
      offset: start, length: end - start);
}

/// The text of [issue] in its coordinate.
String _issueText(CommandCoordinate cc, CoordinateIssue issue) {
  final end = issue.offset + issue.length;
  if (issue.offset < 0 || end > cc.text.length) return '';
  return cc.text.substring(issue.offset, end);
}

final Rule _coordinateSyntax = _coordinateRule(
  id: 'coordinate-syntax',
  severity: Severity.error,
  kinds: {CoordinateIssueKind.syntax},
  description: 'A coordinate must have the form DD:MM:SS[N|S] DDD:MM:SS[E|W] '
      'or DD:MM.mmm[N|S] DDD:MM.mmm[E|W].',
  explanation: 'A coordinate has a latitude and a longitude, separated by a '
      'space. Each part has degrees and minutes, separated by ":". DMS adds '
      'the seconds after another ":". DDM writes the minutes with decimals. '
      'Each part ends with its letter: N or S for the latitude, E or W for '
      'the longitude.\n'
      '\n'
      'This rule reports text that is not a coordinate, for example a '
      'missing number, a missing longitude or too many ":" parts. A reader '
      'cannot read such a point. It can skip the point or the whole '
      'airspace.',
  correctExample: 'DP 45:40:30N 014:18:20E\n'
      'DP 45:40.500N 014:18.333E',
  incorrectExample: 'DP 45:40:30N\n'
      'DP 45::30N 014:18:20E\n'
      'DP 45:40:30:10N 014:18:20E',
  message: (cc, i) {
    if (cc.text.isEmpty) {
      return 'The point is missing. Write a coordinate, for example '
          '"${cc.command.upperKeyword} 45:40:30N 014:18:20E".';
    }
    return i.message;
  },
);

final Rule _coordinateHemisphere = _coordinateRule(
  id: 'coordinate-hemisphere-invalid',
  severity: Severity.error,
  kinds: {
    CoordinateIssueKind.missingHemisphere,
    CoordinateIssueKind.wrongHemisphere,
  },
  description: 'The latitude must end with N or S, and the longitude with E '
      'or W.',
  explanation: 'The letter after each part of a coordinate gives the '
      'hemisphere. The latitude ends with N (north) or S (south). The '
      'longitude ends with E (east) or W (west). Without the letter, or with '
      'the wrong letter, the position is not known. Numbers with a sign (for '
      'example -45:40:30) are not allowed.',
  correctExample: 'DP 45:40:30N 014:18:20E\n'
      'DP 33:51:35S 151:12:40E',
  incorrectExample: 'DP 45:40:30 014:18:20\n'
      'DP 45:40:30E 014:18:20N\n'
      'DP 45:40:30Q 014:18:20E',
  message: (cc, i) {
    if (i.kind != CoordinateIssueKind.missingHemisphere) return i.message;
    // Letters that the parser does not read as the hemisphere, for example
    // `46:00:00Q` or `014:00:00EAST`.
    final word =
        RegExp(r'[A-Za-z]+').matchAsPrefix(cc.text, i.offset)?.group(0);
    if (word == null) return i.message;
    final letters = i.part == CoordinatePart.latitude ? 'N or S' : 'E or W';
    final what = i.part == CoordinatePart.latitude ? 'latitude' : 'longitude';
    return word.length == 1
        ? 'The $what must end with $letters, not "$word".'
        : 'The $what must end with one letter, $letters, not "$word".';
  },
);

/// A fix for minutes or seconds that are exactly 60, for example
/// `41:08:60` -> `41:09:00`. Returns null if there is no simple fix.
String? _carryFix(CommandCoordinate cc, CoordinateIssue issue) {
  final text = cc.text;
  bool isPartChar(int c) => (c >= 0x30 && c <= 0x39) || c == 0x3A || c == 0x2E;
  var s = issue.offset;
  while (s > 0 && isPartChar(text.codeUnitAt(s - 1))) {
    s--;
  }
  var e = issue.offset + issue.length;
  while (e < text.length && isPartChar(text.codeUnitAt(e))) {
    e++;
  }
  final part = text.substring(s, e);
  final groups = part.split(':');
  if (groups.length < 2 || groups.any((g) => g.isEmpty)) return null;
  final isSeconds = issue.kind == CoordinateIssueKind.secondsOutOfRange;
  final index = isSeconds ? 2 : 1;
  if (index >= groups.length) return null;
  final bad = double.tryParse(groups[index]);
  if (bad != 60) return null;
  String zero(String g) => g.replaceAll(RegExp(r'\d'), '0');
  String plusOne(String g, int width) {
    final dot = g.indexOf('.');
    final intText = dot < 0 ? g : g.substring(0, dot);
    final frac = dot < 0 ? '' : g.substring(dot);
    final v = int.tryParse(intText);
    if (v == null) return g;
    return '${(v + 1).toString().padLeft(width, '0')}$frac';
  }

  final out = [...groups];
  // DMS seconds are whole numbers (see coordinate-decimal-seconds). So the
  // fix drops a fraction of the seconds, which is all zeros here: 60.0000
  // becomes 00.
  out[index] =
      isSeconds ? zero(groups[index].split('.').first) : zero(groups[index]);
  var carry = index - 1;
  while (carry >= 0) {
    final g = out[carry];
    final next = plusOne(g, g.split('.').first.length);
    if (carry > 0 && (double.tryParse(next) ?? 0) >= 60) {
      out[carry] = zero(g);
      carry--;
      continue;
    }
    out[carry] = next;
    break;
  }
  return 'Write "${out.join(':')}" in place of "$part".';
}

final Rule _coordinateOutOfRange = _coordinateRule(
  id: 'coordinate-out-of-range',
  severity: Severity.error,
  kinds: {
    CoordinateIssueKind.latitudeOutOfRange,
    CoordinateIssueKind.longitudeOutOfRange,
    CoordinateIssueKind.minutesOutOfRange,
    CoordinateIssueKind.secondsOutOfRange,
  },
  description: 'The latitude must be at most 90 degrees, the longitude at '
      'most 180 degrees, and minutes and seconds must be less than 60.',
  explanation: 'A latitude greater than 90 degrees or a longitude greater '
      'than 180 degrees is not a position on the earth. Minutes and seconds '
      'go from 0 to 59. The value 60 is not allowed: write the next minute '
      'or degree in its place. For example, write 41:09:00N, not 41:08:60N.\n'
      '\n'
      'The value 60 often comes from a program that rounds the seconds '
      'without carrying them to the minutes. Fix the program that writes '
      'the file.',
  correctExample: 'DP 41:09:00N 019:06:00E',
  incorrectExample: 'DP 41:08:60N 019:06:00E\n'
      'DP 91:00:00N 019:06:00E',
  message: (cc, i) {
    if (i.kind == CoordinateIssueKind.minutesOutOfRange ||
        i.kind == CoordinateIssueKind.secondsOutOfRange) {
      final fix = _carryFix(cc, i);
      if (fix != null) return '${i.message} $fix';
    }
    return i.message;
  },
);

final Rule _coordinateDecimalDegrees = _coordinateRule(
  id: 'coordinate-decimal-degrees',
  severity: Severity.error,
  kinds: {CoordinateIssueKind.decimalDegrees},
  groupMessage: (found) => _decimalDegreesMessage(found),
  message: (cc, i) => _decimalDegreesMessage([(cc, i)]),
  description: 'Decimal degrees are not allowed. Use DMS or DDM.',
  explanation: 'The specification allows two notations for coordinates: '
      'degrees, minutes and seconds (DMS, 45:40:30N) and degrees and decimal '
      'minutes (DDM, 45:40.500N). Decimal degrees (45.675N) are not allowed. '
      'Many readers cannot read them.\n'
      '\n'
      'This rule also reports a part with whole degrees only (46N). It has '
      'no minutes.',
  correctExample: 'DP 45:40:30N 014:18:20E\n'
      'DP 45:40.500N 014:18.333E',
  incorrectExample: 'DP 45.675N 14.305556E\n'
      'DP 46N 014E',
);

/// The message of [_coordinateDecimalDegrees] for the issues of one
/// command.
String _decimalDegreesMessage(List<_Found> found) {
  final cc = found.first.$1;
  final value = cc.result.value;
  final example =
      value == null ? '' : ' For example "${formatCoordinate(value)}".';
  final hasDecimals = found.any((f) => _issueText(f.$1, f.$2).contains('.'));
  if (!hasDecimals) {
    final what = found.length > 1
        ? 'The coordinate has only degrees'
        : 'The ${found.first.$2.part.name} has only degrees';
    return '$what. The minutes are missing. Write DD:MM:SS or DD:MM.mmm.'
        '$example';
  }
  final what = found.length > 1
      ? 'The coordinate uses'
      : 'The ${found.first.$2.part.name} uses';
  return '$what decimal degrees. Use DMS (DD:MM:SS) or DDM (DD:MM.mmm).'
      '$example';
}

final Rule _coordinateTrailingText = _coordinateRule(
  id: 'coordinate-trailing-text',
  severity: Severity.error,
  kinds: {CoordinateIssueKind.trailingText},
  description: 'A coordinate must not have more text after the longitude.',
  explanation: 'After the longitude and its letter (E or W), only a comment '
      'is allowed. A comment starts with "*". Other text after the '
      'coordinate is not part of the format. Readers can fail on it, or read '
      'it in different ways.',
  correctExample: 'DP 45:40:30N 014:18:20E * near the river',
  incorrectExample: 'DP 45:40:30N 014:18:20E near the river',
);

final Rule _coordinateSpaceBetweenParts = _coordinateRule(
  id: 'coordinate-space-between-parts',
  severity: Severity.warning,
  kinds: {
    CoordinateIssueKind.missingSpace,
    CoordinateIssueKind.extraSpace,
    CoordinateIssueKind.extraSpaceBeforeHemisphere,
  },
  description: 'Write one space between the latitude and the longitude, and '
      'at most one space before the letter N, S, E or W.',
  explanation: 'The latitude and the longitude are separated by one space '
      'character. A missing space, two or more spaces, or a tab are not the '
      'specified format.\n'
      '\n'
      'Between the number and its letter N, S, E or W, you can write no '
      'space or one space. Both forms are valid and have the same meaning: '
      '45:40:30N and 45:40:30 N. Two or more spaces, or a tab, are not the '
      'specified format.',
  correctExample: 'DP 45:40:30N 014:18:20E\n'
      'DP 45:40:30 N 014:18:20 E',
  incorrectExample: 'DP 45:40:30N014:18:20E\n'
      'DP 45:40:30N   014:18:20E\n'
      'DP 45:40:30  N 014:18:20  E',
);

final Rule _coordinateDigitCount = _coordinateRule(
  id: 'coordinate-digit-count',
  severity: Severity.warning,
  kinds: {
    CoordinateIssueKind.missingLeadingZero,
    CoordinateIssueKind.tooManyDigits,
  },
  groupMessage: (_) =>
      'Write the latitude degrees with 2 digits, the longitude '
      'degrees with 3 digits, and minutes and seconds with 2 digits '
      '(add leading zeros).',
  description: 'Degrees, minutes and seconds should have a fixed number of '
      'digits.',
  explanation: 'The latitude has 2 digits for the degrees (DD), the '
      'longitude has 3 digits (DDD). Minutes and seconds have 2 digits '
      '(MM, SS). Add leading zeros where needed: write 014:08:05E, not '
      '14:8:5E. Fixed widths make the files easy to read and to compare.',
  correctExample: 'DP 45:40:30N 014:08:05E',
  incorrectExample: 'DP 45:40:30N 14:8:5E',
);

final Rule _coordinateDecimalSeconds = _coordinateRule(
  id: 'coordinate-decimal-seconds',
  severity: Severity.warning,
  kinds: {CoordinateIssueKind.decimalSeconds},
  groupMessage: (_) => 'The seconds have decimals. DMS uses whole seconds. '
      'Round the seconds, or use DDM (DD:MM.mmm) for more precision.',
  description: 'DMS seconds should be whole numbers.',
  explanation: 'The DMS format is DD:MM:SS with whole seconds. One second is '
      'about 30 m. If you need more precision, use DDM (DD:MM.mmm). Three '
      'decimals of a minute are about 2 m.',
  correctExample: 'DP 45:40:30N 014:18:20E\n'
      'DP 45:40.508N 014:18.342E',
  incorrectExample: 'DP 45:40:30.5N 014:18:20.5E',
);

final Rule _coordinateMixedNotation = _coordinateRule(
  id: 'coordinate-mixed-notation',
  severity: Severity.warning,
  kinds: {CoordinateIssueKind.mixedNotation},
  description: 'The parts of a coordinate, and the two points of a DB arc, '
      'should use the same notation.',
  explanation: 'The specification says: use a consistent format for each '
      'command or data point. Write both parts of a coordinate in DMS '
      '(45:40:30N 014:18:20E) or both in DDM (45:40.500N 014:18.333E).\n'
      '\n'
      'A DB command has two points. Write both points in the same notation.',
  correctExample: 'DP 45:40:30N 014:18:20E\n'
      'V X=46:00:00N 014:00:00E\n'
      'DB 46:10:00N 014:00:00E, 46:00:00N 014:14:24E',
  incorrectExample: 'DP 45:40:30N 014:18.333E\n'
      'V X=46:00:00N 014:00:00E\n'
      'DB 46:10:00N 014:00:00E, 46:00.000N 014:14.400E',
  // A part with decimal degrees is reported by coordinate-decimal-degrees.
  include: (cc, i) =>
      cc.result.latitudeNotation != CoordinateNotation.decimalDegrees &&
      cc.result.longitudeNotation != CoordinateNotation.decimalDegrees,
  extraCheck: (ctx, c, coords) {
    final pair = _mixedPointNotations(coords);
    if (pair == null) return;
    ctx.reportArgument(
        c,
        'The two points of this ${c.upperKeyword} use ${pair.$1.label} and '
        '${pair.$2.label}. Use the same notation for both.');
  },
);

/// The two notations if the points of one command (the two points of a
/// `DB`) use different notations, otherwise null. Points that mix notations
/// in themselves, or use decimal degrees, are not compared, because other
/// rules report them.
(CoordinateNotation, CoordinateNotation)? _mixedPointNotations(
    List<CommandCoordinate> coords) {
  if (coords.length < 2) return null;
  final a = coords[0].result.notation;
  final b = coords[1].result.notation;
  if (a == null || b == null || a == b) return null;
  if (a == CoordinateNotation.decimalDegrees ||
      b == CoordinateNotation.decimalDegrees) {
    return null;
  }
  return (a, b);
}

final Rule _coordinateFileMixedNotation = Rule(
  id: 'coordinate-file-mixed-notation',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'dp-polygon-point',
  description: 'Use one notation (DMS or DDM) for all coordinates of a file.',
  explanation: 'The specification says: do not mix DMS and DDM notations. '
      'Stick to one definition throughout the file.\n'
      '\n'
      'This rule finds the notation of the first coordinate in the file. It '
      'reports the first coordinate that uses the other notation. It reports '
      'only one problem per file. Coordinates with decimal degrees are '
      'reported by the rule coordinate-decimal-degrees. A coordinate that '
      'mixes both notations, and a DB command whose two points use '
      'different notations, are reported by the rule '
      'coordinate-mixed-notation.',
  correctExample: 'DP 46:00:00N 014:00:00E\n'
      'DP 46:00:00N 014:10:00E',
  incorrectExample: 'DP 46:00:00N 014:00:00E\n'
      'DP 46:00.000N 014:10.000E',
  // A command check, not a file check: the linter checks the commands in
  // file order, and the coordinates of each command are read only once for
  // all coordinate rules. The state of the file is kept in [_NotationState].
  keywords: _coordinateKeywords,
  checkCommand: (ctx, c, a) {
    final state = ctx.memo('geometry-notation', _NotationState.new);
    if (state.reported) return;
    final coords = coordinatesOf(ctx, c, a);
    // coordinate-mixed-notation reports a DB with two notations.
    if (_mixedPointNotations(coords) != null) return;
    for (final cc in coords) {
      final n = cc.result.notation;
      if (n == null || n == CoordinateNotation.decimalDegrees) continue;
      final first = state.first;
      if (first == null) {
        state.first = cc;
        continue;
      }
      final firstNotation = first.result.notation!;
      if (n != firstNotation) {
        state.reported = true;
        ctx.reportArgument(
            c,
            'This coordinate uses ${n.label}, but the first coordinate of '
            'the file (line ${first.command.line}) uses '
            '${firstNotation.label}. Use one notation in the whole file.',
            offset: cc.offset,
            length: cc.text.length);
        return;
      }
    }
  },
);

/// The state of [_coordinateFileMixedNotation] for one file. It is kept in
/// [LintContext.memo].
class _NotationState {
  CommandCoordinate? first;
  bool reported = false;
}

// ---------------------------------------------------------------------------
// Polygon
// ---------------------------------------------------------------------------

/// The shape of [airspace] if the shape rules can check it: it has
/// geometry, all geometry commands are usable, and it has no `DC` circle
/// and no `DY` airway. Otherwise null.
GeometryShape? _checkableShape(LintContext ctx, Airspace airspace) {
  final shape = shapeOf(ctx, airspace);
  if (shape.isEmpty ||
      !shape.complete ||
      shape.points.isEmpty ||
      shape.hasCircle ||
      shape.hasAirway) {
    return null;
  }
  return shape;
}

/// True if the polygon has at least 3 different points and an area.
bool _hasArea(GeometryShape shape) {
  final ring = shape.ring;
  return distinctPointCount(ring.points) >= 3 &&
      (encirclesPole(ring.points) || !allOnOneLine(ring.points));
}

final Rule _polygonTooFewPoints = Rule(
  id: 'geometry-polygon-too-few-points',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'dp-polygon-point',
  description: 'A polygon must have at least 3 different points that are '
      'not on one line.',
  explanation: 'An airspace is an area. Its boundary needs at least 3 '
      'different points, and the points must not all be on one line. '
      'Otherwise the airspace has no area and readers cannot draw it.\n'
      '\n'
      'The closing point (the copy of the first point at the end) does not '
      'count as a different point. An airspace with a DC circle is not '
      'checked by this rule.',
  correctExample: _dpExample,
  incorrectExample: 'AC D\n'
      'AN Example CTR\n'
      'AH 4500 FT AMSL\n'
      'AL GND\n'
      'DP 46:00:00N 014:00:00E\n'
      'DP 46:00:00N 014:10:00E\n'
      'DP 46:00:00N 014:00:00E',
  checkAirspace: (ctx, a) {
    final shape = _checkableShape(ctx, a);
    if (shape == null) return;
    final ring = shape.ring;
    final distinct = distinctPointCount(ring.points);
    final first = shape.commands.first;
    if (distinct < 3) {
      ctx.reportCommand(
          first,
          'The boundary of ${a.label} has only $distinct different '
          '${distinct == 1 ? 'point' : 'points'}. A polygon needs at least 3 '
          'different points.');
    } else if (!encirclesPole(ring.points) && allOnOneLine(ring.points)) {
      ctx.reportCommand(
          first,
          'All points of the boundary of ${a.label} are on one line. The '
          'airspace has no area.');
    }
  },
);

final Rule _polygonNotClosed = Rule(
  id: 'geometry-polygon-not-closed',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'dp-polygon-point',
  description: 'The last point of a polygon should be the same as the first '
      'point.',
  explanation: 'The specification says that polygons are expected to be '
      'closed: the last point is the same as the first point. Most readers '
      'close an open polygon, but the file is clearer when the polygon is '
      'closed. The message gives the distance between the last and the first '
      'point. A large distance can mean that a point is missing.\n'
      '\n'
      'The rule checks polygons that have at least one DP point and that '
      'start and end with a DP or DB point. The specification gives the '
      '"closed" rule in the DP section, so a boundary without DP points (for '
      'example two DB arcs) is not checked. A boundary that starts or ends '
      'with a DA arc is not checked either, because the end of the arc is '
      'calculated.',
  correctExample: _dpExample,
  incorrectExample: 'AC D\n'
      'AN Example CTR\n'
      'AH 4500 FT AMSL\n'
      'AL GND\n'
      'DP 46:00:00N 014:00:00E\n'
      'DP 46:00:00N 014:10:00E\n'
      'DP 45:55:00N 014:10:00E\n'
      'DP 45:55:00N 014:00:00E',
  checkAirspace: (ctx, a) {
    final shape = _checkableShape(ctx, a);
    if (shape == null || !_hasArea(shape)) return;
    const explicit = {'DP', 'DB'};
    final firstCmd = shape.sources.first;
    final lastCmd = shape.sources.last;
    if (!explicit.contains(firstCmd.upperKeyword) ||
        !explicit.contains(lastCmd.upperKeyword)) {
      return;
    }
    // The "closed" rule is in the DP section of the specification. A
    // boundary without DP points (only arcs) is not checked.
    if (!shape.sources.any((c) => c.upperKeyword == 'DP')) return;
    final first = shape.points.first;
    final last = shape.points.last;
    if (first.closeTo(last, toleranceDeg: samePointToleranceDeg)) return;
    final gap = distanceNm(first, last);
    final cc = coordinatesOf(ctx, firstCmd, a).first;
    final String fix;
    if (gap < 0.1) {
      fix = 'It is probably meant to be the same point. Write the same '
          'coordinates as on line ${firstCmd.line}.';
    } else if (cc.result.isClean) {
      fix = 'Add "DP ${cc.text}" as the last point.';
    } else {
      fix = 'Add the first point again as the last point.';
    }
    ctx.reportCommand(
        lastCmd,
        'The polygon is not closed. The last point is '
        '${formatNmAndMetres(gap)} from the first point (line '
        '${firstCmd.line}). $fix');
  },
);

final Rule _dpDuplicatePoint = Rule(
  id: 'dp-duplicate-point',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'dp-polygon-point',
  description: 'Two DP commands in a row should not have the same point.',
  explanation: 'A DP point that is the same as the DP point before it adds '
      'nothing to the polygon. It is often a copy error. Remove one of the '
      'two points.\n'
      '\n'
      'The closing point of a polygon is not a duplicate, because it is not '
      'next to the first point.',
  correctExample: _dpExample,
  incorrectExample: 'DP 46:00:00N 014:00:00E\n'
      'DP 46:00:00N 014:10:00E\n'
      'DP 46:00:00N 014:10:00E\n'
      'DP 45:55:00N 014:10:00E',
  checkAirspace: (ctx, a) {
    Command? prev;
    for (final c in a.commands) {
      final k = c.upperKeyword;
      if (!shapeKeywords.contains(k)) continue;
      if (k != 'DP') {
        prev = null;
        continue;
      }
      if (prev != null) {
        final p = coordinatesOf(ctx, prev, a).first.position;
        final q = coordinatesOf(ctx, c, a).first.position;
        if (p != null &&
            q != null &&
            p.closeTo(q, toleranceDeg: samePointToleranceDeg)) {
          ctx.reportCommand(
              c,
              'This point is the same as the point on line ${prev.line}. '
              'Remove one of them.');
        }
      }
      prev = c;
    }
  },
);

final Rule _polygonCounterClockwise = Rule(
  id: 'geometry-polygon-counter-clockwise',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'dp-polygon-point',
  description: 'The points of a polygon are expected in clockwise order.',
  explanation: 'The specification says that polygon points are expected to '
      'be mapped clockwise and closed. Most readers draw the airspace '
      'correctly in both directions, but a program can use the direction, '
      'for example to find the inside of the airspace. Write the points in '
      'clockwise order. If you write the file with a program, change the '
      'program.\n'
      '\n'
      'The rule checks the whole boundary, also arcs. It does not check a '
      'boundary that crosses itself, because such a boundary has no single '
      'direction.',
  correctExample: _dpExample,
  incorrectExample: 'DP 46:00:00N 014:00:00E\n'
      'DP 45:55:00N 014:00:00E\n'
      'DP 45:55:00N 014:10:00E\n'
      'DP 46:00:00N 014:10:00E\n'
      'DP 46:00:00N 014:00:00E',
  checkAirspace: (ctx, a) {
    final shape = _checkableShape(ctx, a);
    if (shape == null || !_hasArea(shape)) return;
    final crossings = shape.crossings;
    if (crossings.count > 0 || crossings.limitReached) return;
    final ring = shape.ring;
    // A ring around a pole has no clear direction in this plane.
    if (encirclesPole(ring.points)) return;
    if (isClockwise(ring.points) == false) {
      ctx.reportCommand(
          shape.commands.first,
          'The boundary of ${a.label} goes counter-clockwise. The '
          'specification expects clockwise order.');
    }
  },
);

String _edgeText(PolygonRing ring, int i) {
  if (i == ring.length - 1 && !ring.explicitlyClosed) {
    return 'the closing edge from the last point back to the first point '
        '(the polygon is not closed)';
  }
  final c = ring.edgeCommand(i);
  switch (c.upperKeyword) {
    case 'DA':
    case 'DB':
      return 'the ${c.upperKeyword} arc on line ${c.line}';
    default:
      return 'the edge to the point on line ${c.line}';
  }
}

final Rule _polygonSelfIntersection = Rule(
  id: 'geometry-polygon-self-intersection',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'd-geometric-definitions',
  description: 'The boundary of an airspace should not cross itself.',
  explanation: 'The specification says: the boundary of an airspace should '
      'not cross itself. A boundary that crosses itself does not define a '
      'clear area. Readers can fill it in different ways, so pilots can see '
      'different airspaces. The cause is often a point in the wrong order, a '
      'wrong coordinate, or an arc with the wrong direction (V D=+ or '
      'V D=-).\n'
      '\n'
      'The boundary can touch itself. For example, a ring-shaped airspace is '
      'drawn as one boundary: the outer ring, a connecting line to the inner '
      'ring, the inner ring in the opposite direction, and the same '
      'connecting line back. This rule does not report it. Only a real '
      'crossing is reported: the boundary goes from one side of itself to '
      'the other side. Edges that only touch, a line that is used twice, '
      'and a point that the boundary passes twice without crossing are not '
      'reported.\n'
      '\n'
      'The message gives the position of the first crossing and the two '
      'edges that cross. Arcs are checked as many short edges. A crossing '
      'that makes only a very thin loop (less than '
      '${minLoopWidthMetres.round()} m wide on average) is not reported. '
      'Such loops come from rounded coordinates or from an arc that touches '
      'a straight edge, and they are not visible on a map. An airspace with '
      'a DC circle or a DY airway is not checked.',
  correctExample: _dpExample,
  incorrectExample: 'DP 46:00:00N 014:00:00E\n'
      'DP 46:00:00N 014:10:00E\n'
      'DP 45:55:00N 014:00:00E\n'
      'DP 45:55:00N 014:10:00E\n'
      'DP 46:00:00N 014:00:00E',
  checkAirspace: (ctx, a) {
    final shape = _checkableShape(ctx, a);
    if (shape == null || !_hasArea(shape)) return;
    final result = shape.crossings;
    final crossing = result.first;
    if (crossing == null) return;
    final ring = shape.ring;
    final at = ring.edgeCommand(crossing.second);
    final corners = crossing.corners;
    final buffer = StringBuffer('The boundary of ${a.label} crosses itself '
        'near ${formatCoordinate(crossing.point)}: ');
    if (corners == null) {
      buffer.write('${_edgeText(ring, crossing.second)} crosses '
          '${_edgeText(ring, crossing.first)}.');
    } else {
      buffer.write('the boundary passes this point on line '
          '${ring.drawnBy[corners.$1].line} and again on line '
          '${ring.drawnBy[corners.$2].line}, and there it goes from one side '
          'of itself to the other side.');
    }
    if (result.count > 1) {
      buffer.write(' The boundary has '
          '${result.limitReached ? 'at least ' : ''}${result.count} '
          'crossings.');
    }
    final arcs = {
      ring.edgeCommand(crossing.first).upperKeyword,
      at.upperKeyword,
    };
    if (arcs.contains('DA') || arcs.contains('DB')) {
      buffer.write(' Check the direction of the arc (V D=+ or V D=-).');
    }
    ctx.reportCommand(at, buffer.toString());
  },
);

// ---------------------------------------------------------------------------
// Centre, DA, DB, DC
// ---------------------------------------------------------------------------

final Rule _centerMissing = Rule(
  id: 'geometry-center-missing',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'v-variable-assignment',
  description: 'DA, DB and DC need a "V X=" centre before them in the same '
      'airspace.',
  explanation: 'The commands DA, DB and DC draw arcs and circles around a '
      'centre. The centre is set with "V X=<point>". The specification says '
      'that the V command must be declared before the command that uses '
      'it.\n'
      '\n'
      'The V values are reset at every AC. At the start of each airspace, X '
      'has no value. So each airspace must set its own centre. A centre from '
      'an earlier airspace is not used.',
  correctExample: 'V X=50:35:36N 007:56:42E\n'
      'DC 2.00',
  incorrectExample: 'DC 2.00\n'
      'V X=50:35:36N 007:56:42E',
  keywords: {'DA', 'DB', 'DC'},
  checkCommand: (ctx, c, a) {
    if (_previousVariable(ctx, c, a, 'X') != null) return;
    var later = '';
    for (final o in _scope(ctx, a)) {
      if (o.line > c.line &&
          o.upperKeyword == 'V' &&
          parseVariable(o).upperName == 'X') {
        later = ' The "V X=" on line ${o.line} comes after this command. '
            'Move it before the first command that uses it.';
        break;
      }
    }
    ctx.reportKeyword(
        c,
        '${c.upperKeyword} needs a centre. Write "V X=<point>" before it in '
        'the same airspace. $_resetNote$later'
        '${later.isEmpty ? _earlierScopeNote(ctx, a, 'centre', 'X', c.line) : ''}');
  },
);

const String _daNames = 'radius, start bearing and end bearing';
const List<String> _daPartNames = ['radius', 'start bearing', 'end bearing'];

final Rule _daWrongFormat = Rule(
  id: 'da-wrong-format',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'da-arc-between-start-and-end-bearing',
  description: 'DA needs three numbers separated by commas: $_daNames.',
  explanation: 'The format is "DA Radius, Start Angle, End Angle". The '
      'radius is in nautical miles, without a unit. The bearings are in '
      'degrees, from 0 to 360. Use a point (.) for decimals.',
  correctExample: 'V X=39:13:00N 118:13:00W\n'
      'DA 10, 270, 290',
  incorrectExample: 'V X=39:13:00N 118:13:00W\n'
      'DA 10 270 290\n'
      'DA 10NM, 270, 290\n'
      'DA 2,5, 270, 290',
  keywords: {'DA'},
  checkCommand: (ctx, c, a) {
    final parts = splitParts(c.argument, ',');
    if (parts.length != 3) {
      // `DA 2,5, 270, 290`: a decimal comma gives one part too many.
      final decimalComma =
          parts.length > 3 && RegExp(r'\d,\d').hasMatch(c.argument);
      ctx.reportArgument(
          c,
          'DA needs three numbers separated by commas: $_daNames. '
          'For example "DA 10, 270, 290".'
          '${decimalComma ? ' Use a point (.) as the decimal separator.' : ''}');
      return;
    }
    for (var i = 0; i < 3; i++) {
      final p = parts[i];
      if (parseDecimal(p.text, allowSign: true) != null) continue;
      final what = _daPartNames[i];
      ctx.reportArgument(
          c,
          p.text.isEmpty
              ? 'The $what is missing.'
              : 'The $what "${p.text}" is not a number.${_unitHint(p.text)}',
          offset: p.offset,
          length: p.text.isEmpty ? 1 : p.text.length);
    }
  },
);

final Rule _daRadiusNotPositive = Rule(
  id: 'da-radius-not-positive',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'da-arc-between-start-and-end-bearing',
  description: 'The radius of a DA arc must be greater than 0.',
  explanation: 'The radius is the distance from the centre to the arc, in '
      'nautical miles. A radius of 0 or less does not draw an arc.',
  correctExample: 'V X=39:13:00N 118:13:00W\n'
      'DA 10, 270, 290',
  incorrectExample: 'V X=39:13:00N 118:13:00W\n'
      'DA 0, 270, 290',
  keywords: {'DA'},
  checkCommand: (ctx, c, a) {
    final v = daValues(c.argument);
    if (v == null || v[0] > 0) return;
    final p = splitParts(c.argument, ',').first;
    ctx.reportArgument(c, 'The radius must be greater than 0. It is ${p.text}.',
        offset: p.offset, length: p.text.length);
  },
);

final Rule _daBearingOutOfRange = Rule(
  id: 'da-bearing-out-of-range',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'da-arc-between-start-and-end-bearing',
  description: 'The bearings of a DA arc must be from 0 to 360 degrees.',
  explanation: 'The start and end bearings are true bearings in degrees, '
      'from 0 to 360. 0 and 360 are both north. Negative values and values '
      'above 360 are not allowed.',
  correctExample: 'V X=39:13:00N 118:13:00W\n'
      'DA 10, 270, 290',
  incorrectExample: 'V X=39:13:00N 118:13:00W\n'
      'DA 10, -90, 380',
  keywords: {'DA'},
  checkCommand: (ctx, c, a) {
    final v = daValues(c.argument);
    if (v == null) return;
    final parts = splitParts(c.argument, ',');
    for (var i = 1; i < 3; i++) {
      if (v[i] >= 0 && v[i] <= 360) continue;
      ctx.reportArgument(
          c,
          'The ${_daPartNames[i]} must be from 0 to 360 degrees. '
          'It is ${parts[i].text}.',
          offset: parts[i].offset,
          length: parts[i].text.length);
    }
  },
);

final Rule _daCombinedWithDp = Rule(
  id: 'da-combined-with-dp',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'da-arc-between-start-and-end-bearing',
  description: 'Avoid DA arcs in an airspace that also has DP points.',
  explanation: 'The specification says: combining DA arcs with DP points can '
      'result in inconsistencies in how the airspace is displayed. Avoid DA '
      'if possible.\n'
      '\n'
      'The start and end of a DA arc are calculated from the centre, the '
      'radius and the bearings. Readers calculate them in slightly different '
      'ways, so the arc does not meet the DP points exactly. Use a DB arc in '
      'its place. DB gives the start and end points of the arc directly. '
      'This rule reports the first DA of each airspace that also has DP '
      'points.',
  correctExample: 'DP 39:23:00N 118:13:00W\n'
      'V X=39:13:00N 118:13:00W\n'
      'DB 39:23:00N 118:13:00W, 39:13:00N 118:00:06W\n'
      'DP 39:03:00N 118:13:00W',
  incorrectExample: 'DP 39:23:00N 118:13:00W\n'
      'V X=39:13:00N 118:13:00W\n'
      'DA 10, 0, 90\n'
      'DP 39:03:00N 118:13:00W',
  checkAirspace: (ctx, a) {
    Command? firstDa;
    Command? firstDp;
    for (final c in a.commands) {
      if (c.upperKeyword == 'DA') firstDa ??= c;
      if (c.upperKeyword == 'DP') firstDp ??= c;
    }
    if (firstDa == null || firstDp == null) return;
    ctx.reportKeyword(
        firstDa,
        'This airspace mixes DA arcs with DP points (line ${firstDp.line}). '
        'Readers can draw the joins in different ways. Use a DB arc, which '
        'gives the start and end points directly.');
  },
);

final Rule _daNotRecommended = Rule(
  id: 'da-not-recommended',
  severity: Severity.info,
  versions: SpecVersion.all,
  specAnchor: 'da-arc-between-start-and-end-bearing',
  description: 'Avoid DA arcs if possible. DB arcs are clearer.',
  explanation: 'The specification says: avoid using DA if possible. The '
      'start and end points of a DA arc are calculated from the centre, the '
      'radius and the bearings, and readers calculate them in slightly '
      'different ways. A DB arc gives the start and end points directly.\n'
      '\n'
      'DA is allowed. The sentence "Avoid using DA if possible" is in a note '
      'about DA arcs combined with DP points. That case is reported by '
      'da-combined-with-dp (a warning). In an airspace without DP points, '
      'the problem of the note (arcs that do not meet the points) does not '
      'happen. For this reason this rule is info, not a warning. It reports '
      'the first DA of each airspace without DP points.',
  correctExample: 'V X=39:13:00N 118:13:00W\n'
      'DB 39:23:00N 118:13:00W, 39:13:00N 118:00:06W\n'
      'DB 39:13:00N 118:00:06W, 39:23:00N 118:13:00W',
  incorrectExample: 'V X=39:13:00N 118:13:00W\n'
      'DA 10, 0, 90\n'
      'DA 10, 90, 0',
  checkAirspace: (ctx, a) {
    Command? firstDa;
    for (final c in a.commands) {
      if (c.upperKeyword == 'DP') return; // da-combined-with-dp
      if (c.upperKeyword == 'DA') firstDa ??= c;
    }
    if (firstDa == null) return;
    ctx.reportKeyword(
        firstDa,
        'The specification says: avoid DA arcs if possible. Readers '
        'calculate the ends of a DA arc in slightly different ways. A DB arc '
        'gives the start and end points directly.');
  },
);

final Rule _dbWrongFormat = Rule(
  id: 'db-wrong-format',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'db-arc-between-start-and-end-point',
  description: 'DB needs two points separated by a comma.',
  explanation: 'The format is "DB Point 1, Point 2". The arc goes from the '
      'first point to the second point around the "V X=" centre. Write a '
      'comma between the two points.',
  correctExample: 'V X=46:00:00N 014:00:00E\n'
      'DB 46:10:00N 014:00:00E, 46:00:00N 014:14:24E',
  incorrectExample: 'V X=46:00:00N 014:00:00E\n'
      'DB 46:10:00N 014:00:00E 46:00:00N 014:14:24E',
  keywords: {'DB'},
  checkCommand: (ctx, c, a) {
    final parts = splitParts(c.argument, ',');
    if (parts.length != 2) {
      final String detail;
      final single = parseCoordinate(c.argument);
      if (parts.length == 1 &&
          single.isValid &&
          !single.has(CoordinateIssueKind.trailingText)) {
        detail = 'This command has only one point. Write the start point and '
            'the end point of the arc in one DB command.';
      } else if (parts.length == 1) {
        detail = 'The comma between the two points is missing.';
      } else {
        detail = 'This command has ${parts.length} parts.';
      }
      ctx.reportArgument(
          c,
          'DB needs two points separated by a comma, for example '
          '"DB 46:10:00N 014:00:00E, 46:00:00N 014:14:24E". $detail');
      return;
    }
    for (var i = 0; i < 2; i++) {
      if (parts[i].text.isNotEmpty) continue;
      ctx.reportArgument(c, 'The ${_ordinal(i)} point is missing.',
          offset: parts[i].offset, length: 1);
    }
  },
);

/// The tolerance for [_dbRadiusMismatch]: the two distances from the centre
/// can differ by this many nautical miles plus [_dbRadiusRelative] of the
/// radius.
const double _dbRadiusAbsoluteNm = 0.1;
const double _dbRadiusRelative = 0.01;

const String _dbRadiusExplanation = 'A DB arc is given by a centre and two '
    'points. This is more information than an arc needs: the specification '
    'says that the arc is over-defined. If the two points have different '
    'distances from the centre, readers draw the arc in different ways. Some '
    'use the distance of the first point, some use the average, and some '
    'draw a spiral.';

String _dbRadiusTolerance() => 'This rule reports an arc when the two '
    'distances differ by more than '
    '${_dbRadiusAbsoluteNm.toStringAsFixed(1)} NM plus '
    '${(_dbRadiusRelative * 100).round()} % of the radius. Smaller '
    'differences come from rounding the coordinates and are not reported. '
    'Check the centre and the two points.';

/// Reports a DB arc whose two points have different distances from the
/// centre. Used by [_dbRadiusMismatch] (3.0) and [_dbRadiusMismatchV21].
void _checkDbRadius(LintContext ctx, Command c, Airspace? a) {
  final coords = coordinatesOf(ctx, c, a);
  if (coords.length != 2) return;
  final p1 = coords[0].position;
  final p2 = coords[1].position;
  if (p1 == null || p2 == null) return;
  final vx = _previousVariable(ctx, c, a, 'X');
  if (vx == null) return;
  final cc = coordinatesOf(ctx, vx, a);
  final centre = cc.isEmpty ? null : cc.first.position;
  if (centre == null) return;
  final r1 = distanceNm(centre, p1);
  final r2 = distanceNm(centre, p2);
  final diff = (r1 - r2).abs();
  final r = r1 > r2 ? r1 : r2;
  if (diff <= _dbRadiusAbsoluteNm + _dbRadiusRelative * r) return;
  ctx.reportArgument(
      c,
      'The two points have different distances from the centre (line '
      '${vx.line}): ${formatNm(r1)} and ${formatNm(r2)}. The difference '
      'is ${formatNmAndMetres(diff)}. Readers can draw this arc in '
      'different ways. Check the centre and the points.');
}

final Rule _dbRadiusMismatch = Rule(
  id: 'db-radius-mismatch',
  severity: Severity.error,
  versions: SpecVersion.only3,
  specAnchor: 'db-arc-between-start-and-end-point',
  description: 'Both points of a DB arc must have the same distance from '
      'the centre.',
  explanation: '$_dbRadiusExplanation The specification says: "Both points '
      'must be at the same distance from the centre."\n'
      '\n'
      '${_dbRadiusTolerance()}',
  correctExample: 'V X=46:00:00N 014:00:00E\n'
      'DB 46:10:00N 014:00:00E, 46:00:00N 014:14:24E',
  incorrectExample: 'V X=46:00:00N 014:00:00E\n'
      'DB 46:10:00N 014:00:00E, 46:00:00N 014:20:00E',
  keywords: {'DB'},
  checkCommand: _checkDbRadius,
);

final Rule _dbRadiusMismatchV21 = Rule(
  id: 'db-radius-mismatch-v21',
  severity: Severity.warning,
  versions: SpecVersion.only21,
  specAnchor: 'db-arc-between-start-and-end-point',
  anchorInVersion21Text: true,
  description: 'Both points of a DB arc should have the same distance from '
      'the centre (version 2.1).',
  explanation: '$_dbRadiusExplanation Version 2.1 only asks to calculate the '
      'centre carefully. Version 3.0 says that both points must be at the '
      'same distance from the centre, so this is an error in version 3.0.\n'
      '\n'
      '${_dbRadiusTolerance()}',
  correctExample: 'V X=46:00:00N 014:00:00E\n'
      'DB 46:10:00N 014:00:00E, 46:00:00N 014:14:24E',
  incorrectExample: 'V X=46:00:00N 014:00:00E\n'
      'DB 46:10:00N 014:00:00E, 46:00:00N 014:20:00E',
  keywords: {'DB'},
  checkCommand: _checkDbRadius,
);

final Rule _dcWrongFormat = Rule(
  id: 'dc-wrong-format',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'dc-circular-area',
  description: 'DC needs one number: the radius in nautical miles.',
  explanation: 'The format is "DC Radius". The radius is in nautical miles, '
      'without a unit. Use a point (.) for decimals.',
  correctExample: 'V X=50:35:36N 007:56:42E\n'
      'DC 2.00',
  incorrectExample: 'V X=50:35:36N 007:56:42E\n'
      'DC 2 NM',
  keywords: {'DC'},
  checkCommand: (ctx, c, a) {
    if (parseDecimal(c.argument, allowSign: true) != null) return;
    ctx.reportArgument(
        c,
        c.argument.isEmpty
            ? 'The radius is missing. Write the radius in NM, for example '
                '"DC 2.5".'
            : 'The radius "${c.argument}" is not a number.'
                '${_unitHint(c.argument)}');
  },
);

final Rule _dcRadiusNotPositive = Rule(
  id: 'dc-radius-not-positive',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'dc-circular-area',
  description: 'The radius of a DC circle must be greater than 0.',
  explanation: 'A circle with a radius of 0 or less has no area.',
  correctExample: 'V X=50:35:36N 007:56:42E\n'
      'DC 2.00',
  incorrectExample: 'V X=50:35:36N 007:56:42E\n'
      'DC 0',
  keywords: {'DC'},
  checkCommand: (ctx, c, a) {
    final r = parseDecimal(c.argument, allowSign: true);
    if (r == null || r > 0) return;
    ctx.reportArgument(
        c, 'The radius must be greater than 0. It is ${c.argument}.');
  },
);

final Rule _dcMixedWithOtherGeometry = Rule(
  id: 'dc-mixed-with-other-geometry',
  severity: Severity.error,
  versions: SpecVersion.only3,
  specAnchor: 'dc-circular-area',
  description: 'A DC circle must be the only geometry command of its '
      'airspace.',
  explanation: 'DC defines a circular area. The circle is the whole '
      'airspace. The specification says: DC must be the only geometry '
      'command of its airspace. Do not combine it with DP, DA, DB, DY or a '
      'second DC. Readers handle such a combination in different ways, and '
      'often draw a wrong shape.\n'
      '\n'
      'Write one airspace for each circle. If the area is a part of a '
      'circle, use DP points with DB arcs.\n'
      '\n'
      'V commands are not geometry commands. "V X=" and "V D=" before the DC '
      'are allowed.',
  correctExample: 'AC UNC\n'
      'AY Q\n'
      'AN PARA Example\n'
      'AH FL100\n'
      'AL GND\n'
      'V X=50:35:36N 007:56:42E\n'
      'DC 2.00',
  incorrectExample: 'AC UNC\n'
      'AY Q\n'
      'AN PARA Example\n'
      'AH FL100\n'
      'AL GND\n'
      'V X=50:35:36N 007:56:42E\n'
      'DC 2.00\n'
      'DP 50:40:00N 007:56:42E',
  checkAirspace: (ctx, a) {
    final commands = [
      for (final c in a.commands)
        if (shapeKeywords.contains(c.upperKeyword)) c
    ];
    final circles = [
      for (final c in commands)
        if (c.upperKeyword == 'DC') c
    ];
    if (circles.isEmpty || commands.length == 1) return;
    final dc = circles.first;
    if (circles.length > 1) {
      ctx.reportKeyword(
          circles[1],
          'An airspace can have only one DC circle. ${a.label} already has '
          'a circle on line ${dc.line}. DC must be the only geometry command '
          'of its airspace. Write one airspace for each circle.');
      return;
    }
    final other = commands.firstWhere((c) => !identical(c, dc));
    ctx.reportKeyword(
        dc,
        'DC must be the only geometry command of its airspace. Do not '
        'combine it with ${other.upperKeyword} (line ${other.line}). Use '
        'only the circle, or only DP points and arcs.');
  },
);

final Rule _dcMixedWithOtherGeometryV21 = version21Warning(
  _dcMixedWithOtherGeometry,
  description: 'A DC circle should be the only geometry command of its '
      'airspace (version 2.1).',
);

// ---------------------------------------------------------------------------
// DY
// ---------------------------------------------------------------------------

final Rule _dyDeprecated = Rule(
  id: 'dy-deprecated',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'dy-airway-segment',
  description: 'DY airway segments are not recommended. Use DP points.',
  explanation: 'DY is part of the original WinPilot format. The '
      'specification does not recommend it: consecutive DY segments do not '
      'join cleanly into one continuous airway. Draw the airway as a polygon '
      'with DP points.\n'
      '\n'
      'This rule reports the first DY of each airspace.',
  correctExample: 'AC D\n'
      'AY AWY\n'
      'AN Example airway\n'
      'AH FL195\n'
      'AL FL95\n'
      'DP 46:02:00N 014:00:00E\n'
      'DP 46:02:00N 015:00:00E\n'
      'DP 45:58:00N 015:00:00E\n'
      'DP 45:58:00N 014:00:00E\n'
      'DP 46:02:00N 014:00:00E',
  incorrectExample: 'AC D\n'
      'AY AWY\n'
      'AN Example airway\n'
      'AH FL195\n'
      'AL FL95\n'
      'V W=4\n'
      'DY 46:00:00N 014:00:00E\n'
      'DY 46:00:00N 015:00:00E',
  checkAirspace: (ctx, a) {
    final dy = a.firstWith('DY');
    if (dy == null) return;
    ctx.reportKeyword(
        dy,
        'DY is not recommended, because DY segments do not join cleanly. '
        'Draw the airway as a polygon with DP points.');
  },
);

final Rule _dyWidthMissing = Rule(
  id: 'dy-width-missing',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'v-variable-assignment',
  description: 'DY needs a "V W=" airway width before it in the same '
      'airspace.',
  explanation: 'The format is "DY Point". Each DY is one point of an '
      'airway. The width of the airway is set by a preceding "V W=<number>" '
      'command, in nautical miles. The specification says that the V '
      'command must be declared before the command that uses it. Without a '
      'width, readers cannot draw the airway.\n'
      '\n'
      'The V values are reset at every AC. At the start of each airspace, W '
      'has no value. So each airspace must set its own width. A width from '
      'an earlier airspace is not used.\n'
      '\n'
      'This rule reports the first DY of each airspace that has no width '
      'before it.',
  correctExample: 'V W=4\n'
      'DY 46:00:00N 014:00:00E\n'
      'DY 46:00:00N 015:00:00E',
  incorrectExample: 'DY 46:00:00N 014:00:00E\n'
      'DY 46:00:00N 015:00:00E',
  checkAirspace: (ctx, a) {
    var hasWidth = false;
    Command? firstWithout;
    Command? laterWidth;
    for (final c in a.commands) {
      if (c.upperKeyword == 'V' && parseVariable(c).upperName == 'W') {
        if (firstWithout != null) {
          laterWidth ??= c;
        } else {
          hasWidth = true;
        }
      }
      if (c.upperKeyword == 'DY' && !hasWidth) firstWithout ??= c;
    }
    if (firstWithout == null) return;
    final note = laterWidth != null
        ? ' The "V W=" on line ${laterWidth.line} comes after it. Move it '
            'before the first DY.'
        : _earlierScopeNote(ctx, a, 'width', 'W', firstWithout.line);
    ctx.reportKeyword(
        firstWithout,
        'DY needs an airway width. Write "V W=<width in NM>" before it in '
        'the same airspace. $_resetNote$note');
  },
);

// ---------------------------------------------------------------------------
// V
// ---------------------------------------------------------------------------

const String _vNames = 'X (centre), D (direction) and W (airway width)';

final Rule _vWrongFormat = Rule(
  id: 'v-wrong-format',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'v-variable-assignment',
  description: 'V must have the form "V Name=Value".',
  explanation: 'The V command sets a variable. The format is '
      '"V Command=Value": a name, the "=" sign, and a value. The names are '
      '$_vNames.',
  correctExample: 'V X=39:29.9N 119:46.1W\n'
      'V D=-',
  incorrectExample: 'V X 39:29.9N 119:46.1W\n'
      'V D=',
  keywords: {'V'},
  checkCommand: (ctx, c, a) {
    final v = parseVariable(c);
    if (!v.hasEquals) {
      ctx.reportArgument(
          c,
          'Write the variable as "V Name=Value", for example '
          '"V X=45:40:30N 014:18:20E". The "=" sign is missing.');
    } else if (v.name.isEmpty) {
      ctx.reportArgument(
          c,
          'The variable name before "=" is missing. '
          'Use $_vNames.');
    } else if (v.value.isEmpty) {
      ctx.reportArgument(c, 'The value after "=" is missing.',
          offset: v.nameOffset, length: c.argument.length - v.nameOffset);
    }
  },
);

final Rule _vSpaceAroundEquals = Rule(
  id: 'v-space-around-equals',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'v-variable-assignment',
  description: 'Write "V Name=Value" without blanks around "=".',
  explanation: 'The format of the V command is "V Command=Value". The '
      'specification writes the name, the "=" sign and the value without '
      'blanks between them. Many readers accept blanks around "=", but it '
      'is not the specified format and a strict reader can fail.',
  correctExample: 'V X=39:29.9N 119:46.1W\n'
      'V D=-',
  incorrectExample: 'V X = 39:29.9N 119:46.1W\n'
      'V D= -',
  keywords: {'V'},
  checkCommand: (ctx, c, a) {
    final v = parseVariable(c);
    // v-wrong-format reports a missing name or value.
    if (!v.hasEquals || v.name.isEmpty || v.value.isEmpty) return;
    final nameEnd = v.nameOffset + v.name.length;
    if (v.valueOffset == nameEnd + 1) return; // `Name=Value`
    ctx.reportArgument(
        c, 'Do not write blanks around "=". Write "V ${v.name}=${v.value}".',
        offset: nameEnd, length: v.valueOffset - nameEnd);
  },
);

final Rule _vUnknownVariable = Rule(
  id: 'v-unknown-variable',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'v-variable-assignment',
  description: 'The V variable must be X, D or W.',
  explanation: 'The specification defines three variables: X sets the '
      'centre for DA, DB and DC, D sets the direction of arcs, and W sets '
      'the width of an airway. Readers ignore other names, or read them in '
      'different ways.',
  correctExample: 'V X=39:29.9N 119:46.1W',
  incorrectExample: 'V C=39:29.9N 119:46.1W',
  keywords: {'V'},
  checkCommand: (ctx, c, a) {
    final v = parseVariable(c);
    if (!v.hasEquals || v.name.isEmpty) return;
    const known = {'X', 'D', 'W'};
    if (known.contains(v.upperName)) return;
    ctx.reportArgument(c, 'Unknown variable "${v.name}". Use $_vNames.',
        offset: v.nameOffset, length: v.name.length);
  },
);

final Rule _vInvalidDirection = Rule(
  id: 'v-invalid-direction',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'v-variable-assignment',
  description: 'V D= must be "+" (clockwise) or "-" (counter-clockwise).',
  explanation: 'V D= sets the direction of the DA and DB arcs that follow. '
      '"+" is clockwise, which is also the default. "-" is '
      'counter-clockwise. Other values are not allowed.',
  correctExample: 'V X=46:00:00N 014:00:00E\n'
      'V D=-\n'
      'DA 5, 200, 270',
  incorrectExample: 'V X=46:00:00N 014:00:00E\n'
      'V D=CCW\n'
      'DA 5, 200, 270',
  keywords: {'V'},
  checkCommand: (ctx, c, a) {
    final v = parseVariable(c);
    if (v.upperName != 'D' || v.value.isEmpty) return;
    if (v.value == '+' || v.value == '-') return;
    ctx.reportArgument(
        c,
        'The direction must be "+" (clockwise) or "-" '
        '(counter-clockwise), not "${v.value}".',
        offset: v.valueOffset,
        length: v.value.length);
  },
);

final Rule _vInvalidWidth = Rule(
  id: 'v-invalid-width',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'v-variable-assignment',
  description: 'V W= must be a number greater than 0.',
  explanation: 'V W= sets the width of an airway in nautical miles, without '
      'a unit. The width must be greater than 0.',
  correctExample: 'V W=4',
  incorrectExample: 'V W=4NM\n'
      'V W=0',
  keywords: {'V'},
  checkCommand: (ctx, c, a) {
    final v = parseVariable(c);
    if (v.upperName != 'W' || v.value.isEmpty) return;
    final w = parseDecimal(v.value, allowSign: true);
    if (w != null && w > 0) return;
    ctx.reportArgument(
        c,
        w == null
            ? 'The airway width "${v.value}" is not a number.'
                '${_unitHint(v.value)}'
            : 'The airway width must be greater than 0. It is ${v.value}.',
        offset: v.valueOffset,
        length: v.value.length);
  },
);

final Rule _vWidthWithoutAirway = Rule(
  id: 'v-width-without-airway',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'v-variable-assignment',
  description: 'V W= should only be used in an airspace with DY segments.',
  explanation: 'V W= sets the width of a DY airway. In an airspace without '
      'DY commands, the width has no effect. Remove it, or check that the '
      'airway is complete.',
  correctExample: 'V W=4\n'
      'DY 46:00:00N 014:00:00E\n'
      'DY 46:00:00N 015:00:00E',
  incorrectExample: 'V W=4\n'
      'DP 46:00:00N 014:00:00E\n'
      'DP 46:00:00N 015:00:00E\n'
      'DP 45:58:00N 015:00:00E',
  keywords: {'V'},
  checkCommand: (ctx, c, a) {
    if (a == null) return;
    if (parseVariable(c).upperName != 'W') return;
    if (a.firstWith('DY') != null) return;
    ctx.reportCommand(
        c,
        'The airway width has no effect, because ${a.label} has no DY '
        'segment. Remove this line.');
  },
);

final Rule _vCenterUnused = Rule(
  id: 'v-center-unused',
  severity: Severity.info,
  versions: SpecVersion.all,
  specAnchor: 'v-variable-assignment',
  description: 'A V X= centre should be used by a DA, DB or DC command.',
  explanation: 'V X= sets the centre for the DA, DB and DC commands that '
      'follow it. If no such command follows before the next V X= or the end '
      'of the airspace, the centre has no effect. It is not an error, but it '
      'can mean that an arc or a circle is missing.',
  correctExample: 'V X=50:35:36N 007:56:42E\n'
      'DC 2.00',
  incorrectExample: 'V X=50:35:36N 007:56:42E\n'
      'DP 50:40:00N 007:56:42E',
  checkAirspace: (ctx, a) {
    Command? open;
    void finish() {
      final o = open;
      if (o != null) {
        ctx.reportCommand(
            o,
            'This centre is not used. No DA, DB or DC command follows before '
            'the next "V X=" or the end of the airspace.');
      }
    }

    for (final c in a.commands) {
      final k = c.upperKeyword;
      if (k == 'V' && parseVariable(c).upperName == 'X') {
        finish();
        open = c;
      } else if (k == 'DA' || k == 'DB' || k == 'DC') {
        open = null;
      }
    }
    finish();
  },
);
