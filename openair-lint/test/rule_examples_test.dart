/// Checks the metadata of every rule against the rule itself.
///
/// - The rule ID starts with a prefix of its group.
/// - The correct example does not produce the rule.
/// - The incorrect example produces the rule.
///
/// The examples are shown by `--explain`, in RULES.md and on the web page,
/// so they must be right.
library;

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

import 'support/example_wrapper.dart';

/// The allowed ID prefixes of each rule group.
const Map<String, List<String>> _groupPrefixes = {
  'header': ['file-', 'header-', 'case-', 'command-', 'airspace-'],
  'attributes': ['ac-', 'ay-', 'an-', 'af-', 'ag-', 'ax-'],
  'altitude': ['altitude-'],
  'activation': ['aa-'],
  'geometry': [
    'coordinate-',
    'geometry-',
    'dp-',
    'da-',
    'db-',
    'dc-',
    'dy-',
    'v-',
  ],
};

/// Rules whose examples cannot be shown as text, because they are about
/// the bytes of the file (the encoding) or its name.
const Set<String> _byteRules = {
  'file-not-utf8',
  'file-invalid-utf8',
  'file-bom',
  'file-mixed-line-endings',
  'file-extension-not-openair',
};

/// Rules with a fix whose incorrect example shows a problem without a safe
/// fix, for example "AC R" (the class is not known) or "AH NOTAM". --fix
/// must not change these examples.
const Set<String> _exampleWithoutFix = {
  'header-version-invalid',
  'header-field-duplicate',
  'ac-unknown-class',
  'altitude-invalid',
  'altitude-unit-missing',
  'altitude-flight-level-invalid',
  'aa-invalid-syntax',
  'aa-time-zone-not-z', // the example uses +02:00, not UTC
};

/// True if [line] is a header comment (`*VERSION` or `*WRITTEN_BY`, in any
/// form).
bool _isHeaderLine(String line) =>
    RegExp(r'^\s*\*\s*(VERSION|WRITTEN_BY)', caseSensitive: false)
        .hasMatch(line);

/// True if [line] only shows that lines are left out (`...`).
bool _isEllipsis(String line) {
  final t = line.trim();
  return t == '...' || t.startsWith('... ');
}

/// The example of a rule as a complete file.
///
/// - Lines with `...` are removed.
/// - If the example has header lines, they are used as the header, and no
///   other header line is added. A header line after the first command
///   stays where it is.
/// - If the example has an AC command, the airspace is used as it is.
///   Otherwise the example is put into a small valid airspace.
String _exampleFile(String example, String version) {
  final lines = example.split('\n').where((l) => !_isEllipsis(l)).toList();
  final header = <String>[];
  while (lines.isNotEmpty &&
      (_isHeaderLine(lines.first) || lines.first.trim().isEmpty)) {
    header.add(lines.removeAt(0));
  }
  final hasHeader = header.isNotEmpty || lines.any(_isHeaderLine);
  // A file without commands (for example only comments) stays as it is.
  final hasCommand =
      lines.any((l) => l.trim().isNotEmpty && !l.trim().startsWith('*'));
  if (!hasCommand) return '${[...header, ...lines].join('\n')}\n';
  return wrapExample(lines,
      version: version, header: hasHeader ? header : null, keepAirspace: true);
}

void main() {
  test('rule IDs start with a prefix of their group', () {
    for (final group in ruleGroups) {
      final prefixes = _groupPrefixes[group.name]!;
      for (final rule in group.rules) {
        expect(prefixes.any(rule.id.startsWith), isTrue,
            reason: '${rule.id} (group ${group.name}) must start with one '
                'of $prefixes');
      }
    }
  });

  group('rule examples', () {
    for (final rule in allRules) {
      if (_byteRules.contains(rule.id)) continue;
      final version = rule.versions.contains(SpecVersion.v3_0)
          ? SpecVersion.v3_0
          : SpecVersion.v2_1;

      test('${rule.id}: the correct example passes', () {
        final text = _exampleFile(rule.correctExample, version.label);
        final found = lintRule(rule.id, text, target: version);
        expect(found.map((d) => '${d.line}: ${d.message}'), isEmpty,
            reason: text);
      });

      test('${rule.id}: the incorrect example is reported', () {
        final text = _exampleFile(rule.incorrectExample, version.label);
        final found = lintRule(rule.id, text, target: version);
        expect(found, isNotEmpty, reason: text);
      });

      if (rule.fixable && !_byteRules.contains(rule.id)) {
        final noFix = _exampleWithoutFix.contains(rule.id);
        test(
            '${rule.id}: --fix ${noFix ? 'does not change' : 'fixes'} '
            'the incorrect example', () {
          final text = _exampleFile(rule.incorrectExample, version.label);
          final linter = Linter(LintOptions(rules: [rule], target: version));
          final before = linter.lintString(text).diagnostics;
          final (fixed, result) = fixString(linter, text);
          if (noFix) {
            expect(fixed, text);
            return;
          }
          expect(result.fixedCount, greaterThan(0), reason: text);
          expect(result.result.diagnostics.length, lessThan(before.length),
              reason: fixed);
          // A second run changes nothing.
          expect(fixString(linter, fixed).$1, fixed);
        });
      }
    }
  });
}

/// Lints [content] with only the rule [ruleId].
List<Diagnostic> lintRule(String ruleId, String content,
    {SpecVersion? target}) {
  final rule = findRule(ruleId)!;
  return Linter(LintOptions(rules: [rule], target: target))
      .lintString(content)
      .diagnostics;
}
