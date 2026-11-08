import 'dart:convert';

import '../diagnostic.dart';
import '../linter.dart';
import '../rules/rule.dart';
import '../version.dart';

/// The output formats of the command line tool.
enum OutputFormat { text, json, github }

/// The results of one file, for the output.
class FileReport {
  FileReport(this.path, this.result, this.diagnostics);

  /// The path as shown to the user (with `/` as separator).
  final String path;

  /// The lint result.
  final LintResult result;

  /// The diagnostics that are shown (after the minimum severity filter).
  final List<Diagnostic> diagnostics;
}

/// Counts of diagnostics by severity.
class Totals {
  int files = 0;
  int errors = 0;
  int warnings = 0;
  int info = 0;

  void add(List<Diagnostic> diagnostics) {
    files++;
    for (final d in diagnostics) {
      switch (d.severity) {
        case Severity.error:
          errors++;
        case Severity.warning:
          warnings++;
        case Severity.info:
          info++;
      }
    }
  }

  Map<String, Object?> toJson() => {
        'files': files,
        'errors': errors,
        'warnings': warnings,
        'info': info,
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
          }
      ],
      'summary': totals.toJson(),
    };

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
        '${r.versionsLabel.padRight(verWidth)}  ${r.description}');
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
