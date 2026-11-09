/// Linter and parser for OpenAir airspace files, following the OpenAir 3.0
/// file format specification by Naviter.
///
/// Lint a file:
///
/// ```dart
/// import 'package:openair_lint/openair_lint.dart';
///
/// final diagnostics = lintString(text);
/// for (final d in diagnostics) {
///   print('${d.line}:${d.column} ${d.severity.label} [${d.ruleId}] ${d.message}');
/// }
/// ```
///
/// Options:
///
/// ```dart
/// final linter = Linter(const LintOptions(
///   target: SpecVersion.v2_1,             // ignore the *VERSION header
///   disabledRules: {'header-version-missing'},
///   minSeverity: Severity.warning,        // no info diagnostics
/// ));
/// final result = linter.lintBytes(bytes); // LintResult
/// print(result.specVersion);              // the version that was used
/// ```
///
/// Parse a file without linting it:
///
/// ```dart
/// final file = parseOpenAir(text);        // never throws
/// for (final airspace in file.airspaces) {
///   print('${airspace.name}: ${airspace.commands.length} commands');
/// }
/// ```
///
/// The library uses no `dart:io`, so it also works on the web.
library;

export 'src/activation/activation.dart';
export 'src/diagnostic.dart';
export 'src/fix.dart';
export 'src/fixer.dart';
export 'src/geometry/arcs.dart'
    show arcByBearings, arcByPoints, arcSweep, circlePoints, defaultArcStepDeg;
export 'src/geometry/boundary.dart'
    show
        AirspaceBoundary,
        GeoBounds,
        buildBoundary,
        geometryKeywords,
        isClockwise;
export 'src/geometry/geo_math.dart'
    show
        destinationPoint,
        distanceNm,
        earthRadiusNm,
        initialBearing,
        normalizeBearing,
        normalizeLongitude;
export 'src/geometry/lat_lng.dart';
export 'src/lint_context.dart';
export 'src/linter.dart';
export 'src/model/openair_file.dart';
export 'src/parser/legacy_encoding.dart';
export 'src/parser/parser.dart' show parseOpenAir, parseOpenAirBytes;
export 'src/rules/registry.dart' show RuleGroup, allRules, findRule, ruleGroups;
export 'src/rules/rule.dart';
export 'src/spec_version.dart';
export 'src/values/coordinate.dart';
export 'src/values/text_parts.dart';
export 'src/values/variable.dart';
export 'src/version.dart';
