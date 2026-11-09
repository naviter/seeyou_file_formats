import 'dart:convert';

import '../diagnostic.dart';
import '../fixer.dart';
import '../linter.dart';
import '../rules/rule.dart';
import '../version.dart';

/// The output formats of the command line tool.
enum OutputFormat { text, json, github }

/// The results of one file, for the output.
class FileReport {
  FileReport(this.path, this.result, this.diagnostics,
      {this.fix, this.dryRun = false});

  /// The path as shown to the user (with `/` as separator).
  final String path;

  /// The lint result.
  final LintResult result;

  /// The diagnostics that are shown (after the minimum severity filter).
  final List<Diagnostic> diagnostics;

  /// The result of --fix or --fix-dry-run, or null without these options.
  /// Then [result] and [diagnostics] are the problems after the fixes.
  final FixResult? fix;

  /// True for --fix-dry-run: the file was not changed.
  final bool dryRun;
}

/// Counts of diagnostics by severity.
class Totals {
  int files = 0;
  int errors = 0;
  int warnings = 0;
  int info = 0;

  /// The number of shown problems that have an automatic fix.
  int fixable = 0;

  /// The number of fixed problems (--fix), or of problems that --fix would
  /// fix (--fix-dry-run).
  int fixed = 0;

  /// The number of files with at least one fixed problem.
  int fixedFiles = 0;

  /// The number of files that could not be fixed at all.
  int notFixedFiles = 0;

  void add(List<Diagnostic> diagnostics, {FixResult? fix}) {
    files++;
    if (fix != null) {
      fixed += fix.fixedCount;
      if (fix.fixedCount > 0) fixedFiles++;
      if (fix.notFixedReason != null) notFixedFiles++;
    }
    for (final d in diagnostics) {
      switch (d.severity) {
        case Severity.error:
          errors++;
        case Severity.warning:
          warnings++;
        case Severity.info:
          info++;
      }
      if (d.fixable) fixable++;
    }
  }

  Map<String, Object?> toJson() => {
        'files': files,
        'errors': errors,
        'warnings': warnings,
        'info': info,
        'fixable': fixable,
        'fixed': fixed,
      };
}

/// ANSI colours, or nothing if colour is off.
class Ansi {
  const Ansi(this.enabled);

  final bool enabled;

  String _wrap(String code, String text) =>
      enabled ? '\x1B[${code}m$text\x1B[0m' : text;

  String red(String t) => _wrap('31', t);
  String yellow(String t) => _wrap('33', t);
  String cyan(String t) => _wrap('36', t);
  String grey(String t) => _wrap('90', t);
  String green(String t) => _wrap('32', t);
  String bold(String t) => _wrap('1', t);

  String severity(Severity s) => switch (s) {
        Severity.error => red(s.label),
        Severity.warning => yellow(s.label),
        Severity.info => cyan(s.label),
      };
}

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

/// Writes the diagnostics of one file in the text format:
/// `<path>:<line>:<col>: <severity> [<rule-id>] <message>`.
///
/// The path and the message are passed through [visibleText], because they
/// can contain text from the file.
void writeTextFile(StringSink out, FileReport report, Ansi ansi) {
  final buffer = StringBuffer();
  final path = visibleText(report.path);
  final fix = report.fix;
  if (fix != null) _writeFixText(buffer, report, fix, path, ansi);
  for (final d in report.diagnostics) {
    buffer
      ..write(path)
      ..write(':')
      ..write(d.line)
      ..write(':')
      ..write(d.column)
      ..write(': ')
      ..write(ansi.severity(d.severity))
      ..write(' ')
      ..write(ansi.grey('[${d.ruleId}]'))
      ..write(' ')
      ..writeln(visibleText(d.message));
  }
  if (buffer.isNotEmpty) out.write(buffer);
}

/// Writes what --fix changed (or what --fix-dry-run would change).
void _writeFixText(StringBuffer buffer, FileReport report, FixResult fix,
    String path, Ansi ansi) {
  final reason = fix.notFixedReason;
  if (reason != null) {
    buffer.writeln('$path: ${ansi.yellow('not fixed')}: $reason');
    return;
  }
  if (fix.fixedCount == 0) return;
  final what = _plural(fix.fixedCount, 'problem');
  buffer.writeln(report.dryRun
      ? '$path: --fix would fix $what. The file is not changed.'
      : '$path: fixed $what.');
  if (!report.dryRun) return;
  for (final change in fix.fileChanges) {
    buffer.writeln('  $change');
  }
  final diff = fix.unifiedDiff(report.path);
  for (final line in diff.split('\n')) {
    if (line.isEmpty) continue;
    final shown = visibleText(line);
    if (line.startsWith('---') || line.startsWith('+++')) {
      buffer.writeln(ansi.bold(shown));
    } else if (line.startsWith('@@')) {
      buffer.writeln(ansi.cyan(shown));
    } else if (line.startsWith('-')) {
      buffer.writeln(ansi.red(shown));
    } else if (line.startsWith('+')) {
      buffer.writeln(ansi.green(shown));
    } else {
      buffer.writeln(shown);
    }
  }
}

/// The line after the summary about fixes, or null if there is nothing to
/// say. [fix] and [dryRun] are the options --fix and --fix-dry-run.
String? fixSummaryLine(Totals t, {required bool fix, required bool dryRun}) {
  final notFixed = t.notFixedFiles == 0
      ? ''
      : ' ${_plural(t.notFixedFiles, 'file')} could not be fixed.';
  if (fix) {
    return 'Fixed ${_plural(t.fixed, 'problem')} in '
        '${_plural(t.fixedFiles, 'file')}.$notFixed';
  }
  if (dryRun) {
    return '--fix would fix ${_plural(t.fixed, 'problem')} in '
        '${_plural(t.fixedFiles, 'file')}. No file was changed.$notFixed';
  }
  if (t.fixable == 0) return null;
  return '${t.fixable == 1 ? '1 problem has' : '${t.fixable} problems have'} '
      'an automatic fix. Use --fix to fix, or --fix-dry-run to see the '
      'changes first.';
}

/// The summary line of the text and GitHub formats.
String summaryLine(Totals t) =>
    'Checked ${_plural(t.files, 'file')}: ${_plural(t.errors, 'error')}, '
    '${_plural(t.warnings, 'warning')}, ${t.info} info.';

/// Writes the diagnostics of one file as GitHub Actions annotations.
void writeGithubFile(StringSink out, FileReport report) {
  final buffer = StringBuffer();
  for (final d in report.diagnostics) {
    final command = switch (d.severity) {
      Severity.error => 'error',
      Severity.warning => 'warning',
      Severity.info => 'notice',
    };
    buffer.writeln('::$command file=${_ghProperty(report.path)},'
        'line=${d.line},col=${d.column},'
        'title=${_ghProperty(d.ruleId)}::'
        '${_ghData('${visibleText(d.message)}\n${d.specUrl}')}');
  }
  if (buffer.isNotEmpty) out.write(buffer);
}

/// Returns [text] with control characters in a visible form, for example
/// ESC as `\x1B`.
///
/// Messages quote text from the file. A file must not be able to control
/// the terminal (change the title, clear the screen) or hide text. So this
/// replaces the C0 control characters (except tab), DEL, the C1 control
/// characters and the Unicode characters that change the text direction.
String visibleText(String text) {
  StringBuffer? buffer;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    final hidden = (c < 0x20 && c != 0x09) ||
        (c >= 0x7F && c <= 0x9F) ||
        (c >= 0x202A && c <= 0x202E) ||
        (c >= 0x2066 && c <= 0x2069);
    if (!hidden) {
      buffer?.writeCharCode(c);
      continue;
    }
    buffer ??= StringBuffer(text.substring(0, i));
    final hex = c.toRadixString(16).toUpperCase();
    buffer.write(c <= 0xFF ? '\\x${hex.padLeft(2, '0')}' : '\\u{$hex}');
  }
  return buffer?.toString() ?? text;
}

String _ghData(String s) =>
    s.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A');

String _ghProperty(String s) =>
    _ghData(s).replaceAll(':', '%3A').replaceAll(',', '%2C');

/// The JSON object of `--format json`.
Map<String, Object?> jsonReport(List<FileReport> reports, Totals totals) => {
      'version': packageVersion,
      'files': [
        for (final r in reports)
          {
            'path': r.path,
            'specVersion': r.result.specVersion.label,
            'declaredVersion': r.result.declaredVersion,
            'diagnostics': [for (final d in r.diagnostics) d.toJson()],
            if (r.fix != null) 'fix': _fixJson(r),
          }
      ],
      'summary': totals.toJson(),
    };

/// The "fix" object of one file in the JSON output.
Map<String, Object?> _fixJson(FileReport r) {
  final fix = r.fix!;
  return {
    'dryRun': r.dryRun,
    'fixed': fix.fixedCount,
    'fixedByRule': fix.fixedByRule,
    'changed': fix.changed,
    'fileChanges': fix.fileChanges,
    'notFixedReason': fix.notFixedReason,
    if (r.dryRun) 'diff': fix.unifiedDiff(r.path),
  };
}

/// Formats JSON with two spaces of indentation.
String prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

/// The text of `--list-rules`.
String rulesTable(List<Rule> rules, Ansi ansi) {
  if (rules.isEmpty) return 'No rules.\n';
  final idWidth = rules.map((r) => r.id.length).reduce((a, b) => a > b ? a : b);
  final verWidth =
      rules.map((r) => r.versionsLabel.length).reduce((a, b) => a > b ? a : b);
  final b = StringBuffer();
  for (final r in rules) {
    final sev = r.severity.label.padRight(8);
    b.writeln('${ansi.bold(r.id.padRight(idWidth))}  '
        '${ansi.enabled ? ansi.severity(r.severity) + ' ' * (8 - r.severity.label.length) : sev}'
        '${r.versionsLabel.padRight(verWidth)}  '
        '${r.fixable ? 'fix' : '   '}  ${r.description}');
  }
  return b.toString();
}

/// The text of `--explain <rule-id>`.
String explainRule(Rule r, Ansi ansi) {
  String indent(String text) =>
      text.split('\n').map((l) => l.isEmpty ? '' : '    $l').join('\n');
  return '${ansi.bold(r.id)}\n'
      '\n'
      'Severity: ${ansi.severity(r.severity)}\n'
      'Versions: ${r.versionsLabel}\n'
      'Specification: ${r.specUrl}\n'
      'Automatic fix: ${r.fixDescription ?? 'no'}\n'
      '\n'
      '${r.description}\n'
      '\n'
      '${r.explanation}\n'
      '\n'
      'Correct:\n'
      '\n'
      '${indent(r.correctExample)}\n'
      '\n'
      'Incorrect:\n'
      '\n'
      '${indent(r.incorrectExample)}\n';
}
