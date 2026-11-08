import 'diagnostic.dart';
import 'geometry/boundary.dart';
import 'model/openair_file.dart';
import 'rules/rule.dart';
import 'spec_version.dart';

/// What a rule gets when it runs: the parsed file, the spec version and
/// methods to report problems.
///
/// One context is used for all rules of one file. The linter sets
/// [rule] before it calls each check, so [report] always uses the ID and
/// severity of the rule that is running.
class LintContext {
  LintContext({
    required this.file,
    required this.specVersion,
    required this.versionSource,
    required this.target,
    this.fileName,
    required void Function(Diagnostic) sink,
  }) : _sink = sink;

  /// The parsed file.
  final OpenAirFile file;

  /// The spec version used for this file (from the header or the target).
  final SpecVersion specVersion;

  /// Why [specVersion] was chosen.
  final VersionSource versionSource;

  /// The version that the user asked for with `--target`, or null.
  final SpecVersion? target;

  /// The name or path of the file, or null if it is not known (for example
  /// for standard input or pasted text).
  final String? fileName;

  final void Function(Diagnostic) _sink;
  final Map<Object, Object?> _memo = {};

  /// The rule that is running now. Set by the linter.
  late Rule rule;

  /// True if the file is checked as version 3.0.
  bool get isV3 => specVersion == SpecVersion.v3_0;

  /// True if the file is checked as version 2.1.
  bool get isV21 => specVersion == SpecVersion.v2_1;

  /// The value of the `*VERSION:` header, or null.
  String? get declaredVersion => file.header.versionValue;

  /// Reports a problem for the running rule.
  ///
  /// [line] and [column] start at 1. [endColumn] is the column after the
  /// last character of the problem. If it is null or not greater than
  /// [column], the problem has a length of 1.
  void report(String message,
      {required int line, int column = 1, int? endColumn}) {
    final l = line < 1 ? 1 : line;
    final c = column < 1 ? 1 : column;
    final e = (endColumn == null || endColumn <= c) ? c + 1 : endColumn;
    _sink(Diagnostic(
      ruleId: rule.id,
      severity: rule.severity,
      line: l,
      column: c,
      endColumn: e,
      message:
          rule.messageNote == null ? message : '$message ${rule.messageNote}',
      specUrl: rule.specUrl,
    ));
  }

  /// Reports a problem for a whole command: from the keyword to the end of
  /// the argument (the comment is not included).
  void reportCommand(Command command, String message) => report(message,
      line: command.line, column: command.column, endColumn: command.endColumn);

  /// Reports a problem for the keyword of a command.
  void reportKeyword(Command command, String message) => report(message,
      line: command.line,
      column: command.column,
      endColumn: command.keywordEndColumn);

  /// Reports a problem for the argument of a command, or for a part of it.
  ///
  /// [offset] is the position in [Command.argument] (0-based). [length] is
  /// the length of the wrong part; null means "to the end of the argument".
  /// If the argument is empty, the problem points to the end of the keyword.
  void reportArgument(Command command, String message,
      {int offset = 0, int? length}) {
    if (command.argument.isEmpty) {
      report(message,
          line: command.line,
          column: command.keywordEndColumn,
          endColumn: command.keywordEndColumn + 1);
      return;
    }
    final start = command.argumentColumn + offset;
    final len = length ?? (command.argument.length - offset);
    report(message, line: command.line, column: start, endColumn: start + len);
  }

  /// Reports a problem for a whole line (from column 1 to the end of the
  /// text). Use it for problems that are not about one command.
  void reportLine(int line, String message) {
    final text =
        (line >= 1 && line <= file.lineCount) ? file.lineText(line) : '';
    report(message, line: line, column: 1, endColumn: text.length + 1);
  }

  /// Reports a problem for an airspace at its `AC` command.
  void reportAirspace(Airspace airspace, String message) =>
      reportCommand(airspace.ac, message);

  /// Computes a value once per file and keeps it for other rules.
  ///
  /// Use it for work that several rules need, for example a parsed
  /// coordinate or a schedule. [key] must have value equality, for example
  /// a record: `ctx.memo(('aa-parsed', command), () => parseAa(command))`.
  /// `Command` and `Airspace` objects are compared by identity, which is
  /// correct here.
  T memo<T>(Object key, T Function() compute) {
    if (_memo.containsKey(key)) return _memo[key] as T;
    final value = compute();
    _memo[key] = value;
    return value;
  }

  /// The boundary of [airspace], computed once per file (see
  /// [buildBoundary]).
  AirspaceBoundary boundaryOf(Airspace airspace) =>
      memo(('boundary', airspace), () => buildBoundary(airspace));
}
