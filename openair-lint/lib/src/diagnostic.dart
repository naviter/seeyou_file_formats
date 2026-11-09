import 'fix.dart';

/// How serious a diagnostic is.
///
/// The order of the values is from low to high, so `index` can be compared:
/// `Severity.error.index > Severity.warning.index`.
enum Severity {
  /// A hint about style or a recommended order. The file is still valid.
  info('info'),

  /// The file breaks a "should" rule of the specification.
  warning('warning'),

  /// The file breaks a "must" rule of the specification.
  error('error');

  const Severity(this.label);

  /// The name used in output and options: `info`, `warning` or `error`.
  final String label;

  /// True if this severity is the same as or higher than [other].
  bool isAtLeast(Severity other) => index >= other.index;

  /// Returns the severity with this [label], or null.
  static Severity? fromLabel(String label) {
    for (final s in values) {
      if (s.label == label) return s;
    }
    return null;
  }

  @override
  String toString() => label;
}

/// One problem that the linter found in a file.
class Diagnostic implements Comparable<Diagnostic> {
  const Diagnostic({
    required this.ruleId,
    required this.severity,
    required this.line,
    required this.column,
    required this.endColumn,
    required this.message,
    required this.specUrl,
    this.fix,
  });

  /// The ID of the rule, for example `header-version-missing`.
  final String ruleId;

  /// The severity of the rule.
  final Severity severity;

  /// The line number, starting at 1.
  final int line;

  /// The column of the first character of the problem, starting at 1.
  ///
  /// Columns count UTF-16 code units, as Dart strings do. For normal text
  /// this is the same as the number of characters. A tab counts as 1.
  final int column;

  /// The column after the last character of the problem (exclusive).
  ///
  /// It is always greater than [column]. For a problem that has no length,
  /// for example a missing value at the end of a line, it is `column + 1`.
  final int endColumn;

  /// The message for the user, in plain English.
  final String message;

  /// A link to the section of the specification that the rule is about.
  final String specUrl;

  /// The automatic fix, or null if the problem has no safe automatic fix.
  /// See [Fix].
  final Fix? fix;

  /// True if [fix] is not null.
  bool get fixable => fix != null;

  @override
  int compareTo(Diagnostic other) {
    if (line != other.line) return line.compareTo(other.line);
    if (column != other.column) return column.compareTo(other.column);
    return ruleId.compareTo(other.ruleId);
  }

  /// A JSON map, as used by `--format json`.
  Map<String, Object?> toJson() => {
        'line': line,
        'column': column,
        'endColumn': endColumn,
        'severity': severity.label,
        'rule': ruleId,
        'message': message,
        'specUrl': specUrl,
        'fixable': fixable,
      };

  @override
  String toString() => '$line:$column: ${severity.label} [$ruleId] $message';

  @override
  bool operator ==(Object other) =>
      other is Diagnostic &&
      other.ruleId == ruleId &&
      other.severity == severity &&
      other.line == line &&
      other.column == column &&
      other.endColumn == endColumn &&
      other.message == message;

  @override
  int get hashCode =>
      Object.hash(ruleId, severity, line, column, endColumn, message);
}
