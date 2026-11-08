// An example of openair-lint as a Dart library.
//
// Run it from the openair-lint folder:
//   dart run example/openair_lint_example.dart

import 'package:openair_lint/openair_lint.dart';

void main() {
  const text = '*VERSION: 2.1\n'
      '*WRITTEN_BY: Example\n'
      'AC D\n'
      'AN Example CTR\n'
      'AH 4500ft AMSL\n'
      'AL GND\n'
      'DP 46:00:00N 014:00:00E\n'
      'DP 46:00:00N 014:10:00E\n'
      'DP 45:55:00N 014:10:00E\n'
      'DP 45:55:00N 014:00:00E\n';

  // Check the text as version 3.0, and show only errors and warnings.
  final diagnostics = lintString(
    text,
    const LintOptions(
      target: SpecVersion.v3_0, // null: use the *VERSION header
      minSeverity: Severity.warning,
    ),
  );
  for (final d in diagnostics) {
    print('${d.line}:${d.column} ${d.severity.label} [${d.ruleId}] '
        '${d.message}');
  }

  // The parser can also be used alone. It never throws.
  final file = parseOpenAir(text);
  for (final airspace in file.airspaces) {
    print('Airspace on line ${airspace.startLine} has '
        '${airspace.commands.length} commands.');
  }
}
