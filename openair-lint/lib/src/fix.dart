import 'model/openair_file.dart';

/// One change of a [Fix].
///
/// Line numbers and columns are the same as in a [Diagnostic]: they start
/// at 1, and columns count UTF-16 code units of the line text (without the
/// line ending).
sealed class FixEdit {
  const FixEdit();
}

/// Replaces the text from [column] to [endColumn] (exclusive) of [line]
/// with [text]. If [endColumn] is equal to [column], [text] is inserted
/// before [column].
///
/// [text] must not contain a line break.
final class ReplaceText extends FixEdit {
  const ReplaceText(this.line, this.column, this.endColumn, this.text)
      : assert(endColumn >= column);

  final int line;
  final int column;
  final int endColumn;
  final String text;

  @override
  String toString() => 'ReplaceText($line:$column-$endColumn, "$text")';
}

/// Removes [line] and its line ending.
final class DeleteLine extends FixEdit {
  const DeleteLine(this.line);

  final int line;

  @override
  String toString() => 'DeleteLine($line)';
}

/// Adds a new line with [text] after [line].
///
/// [text] must not contain a line break.
final class InsertLine extends FixEdit {
  const InsertLine(this.line, this.text);

  final int line;
  final String text;

  @override
  String toString() => 'InsertLine(after $line, "$text")';
}

/// Uses [ending] for every line that has a line ending.
final class SetLineEndings extends FixEdit {
  const SetLineEndings(this.ending) : assert(ending != LineEnding.none);

  final LineEnding ending;

  @override
  String toString() => 'SetLineEndings($ending)';
}

/// Removes the UTF-8 byte order mark at the start of the file.
final class RemoveBom extends FixEdit {
  const RemoveBom();

  @override
  String toString() => 'RemoveBom()';
}

/// Saves the file as UTF-8 (without a byte order mark).
final class ConvertToUtf8 extends FixEdit {
  const ConvertToUtf8();

  @override
  String toString() => 'ConvertToUtf8()';
}

/// An automatic fix for one diagnostic.
///
/// A rule gives a fix only when there is exactly one correct result and
/// the meaning of the file does not change. For example, `MSL` becomes
/// `AMSL`, but a missing unit is not added, because openair-lint cannot
/// know if the value is in feet or in metres.
///
/// The edits of one fix are applied together, or not at all.
class Fix {
  /// [edits] must not be empty.
  const Fix(this.edits);

  /// A fix that replaces one part of one line.
  Fix.replace(int line, int column, int endColumn, String text)
      : edits = [ReplaceText(line, column, endColumn, text)];

  /// A fix that removes one line.
  Fix.deleteLine(int line) : edits = [DeleteLine(line)];

  /// The changes.
  final List<FixEdit> edits;

  @override
  String toString() => 'Fix($edits)';
}

/// A fix that replaces a part of the argument of [command].
///
/// [offset] is the position in [Command.argument] (0-based), and [length]
/// is the length of the replaced part (0 inserts [text]). Null means "to
/// the end of the argument".
Fix argumentFix(Command command, String text, {int offset = 0, int? length}) {
  final start = command.argumentColumn + offset;
  final len = length ?? (command.argument.length - offset);
  return Fix.replace(command.line, start, start + len, text);
}
