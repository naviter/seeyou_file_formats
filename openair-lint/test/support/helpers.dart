/// Helpers for rule tests. Import with
/// `import '../support/helpers.dart';` from `test/rules/`.
library;

import 'package:openair_lint/openair_lint.dart';

/// The header of a version 3.0 test file (2 lines).
const String header30 = '*VERSION: 3.0\n*WRITTEN_BY: openair-lint test\n';

/// The header of a version 2.1 test file (2 lines).
const String header21 = '*VERSION: 2.1\n*WRITTEN_BY: openair-lint test\n';

/// A complete, valid airspace (9 lines). Use it as a base and change one
/// line in a test.
const String validAirspace = 'AC D\n'
    'AY CTR\n'
    'AN Test CTR\n'
    'AH 4500 FT AMSL\n'
    'AL GND\n'
    'DP 46:00:00N 014:00:00E\n'
    'DP 46:00:00N 014:10:00E\n'
    'DP 45:55:00N 014:10:00E\n'
    'DP 45:55:00N 014:00:00E\n'
    'DP 46:00:00N 014:00:00E\n';

/// Returns [body] with a version 3.0 header in front of it (or a 2.1
/// header if [version] is `2.1`). The body starts at line 3.
String withHeader(String body, {String version = '3.0'}) =>
    '*VERSION: $version\n*WRITTEN_BY: openair-lint test\n$body';

/// Lints [content] with only the rule [ruleId] and returns its diagnostics.
///
/// Running one rule makes the test independent of the other rules.
/// Throws if the rule does not exist.
List<Diagnostic> lintRule(String ruleId, String content,
    {SpecVersion? target}) {
  final rule = findRule(ruleId);
  if (rule == null) throw ArgumentError('Unknown rule $ruleId');
  return Linter(LintOptions(rules: [rule], target: target))
      .lintString(content)
      .diagnostics;
}

/// Lints [content] with all rules.
List<Diagnostic> lintAll(String content, {SpecVersion? target}) =>
    Linter(LintOptions(target: target)).lintString(content).diagnostics;

/// The lines where [ruleId] fires in [content], for short assertions:
/// `expect(linesOf('ac-unknown-class', text), [3]);`
List<int> linesOf(String ruleId, String content, {SpecVersion? target}) =>
    [for (final d in lintRule(ruleId, content, target: target)) d.line];

/// The diagnostics in the format of `.expected` files: `<line> <rule-id>`,
/// errors and warnings only.
List<String> expectedFormat(List<Diagnostic> diagnostics) => [
      for (final d in diagnostics)
        if (d.severity != Severity.info) '${d.line} ${d.ruleId}'
    ];
