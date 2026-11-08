import '../model/openair_file.dart';

/// A parsed `V` command, for example `V X=45:40:30N 014:18:20E` or `V D=-`.
class VariableAssignment {
  const VariableAssignment({
    required this.name,
    required this.nameOffset,
    required this.value,
    required this.valueOffset,
    required this.hasEquals,
  });

  /// The variable name as written, for example `X` or `x`. It can be empty.
  final String name;

  /// The offset of [name] in the argument of the command (0-based).
  final int nameOffset;

  /// The value after `=`, without spaces at the start and the end.
  /// It can be empty.
  final String value;

  /// The offset of [value] in the argument of the command (0-based).
  /// If [value] is empty, this is the offset after `=` (or after the name).
  final int valueOffset;

  /// False if the argument has no `=`.
  final bool hasEquals;

  /// [name] in upper case.
  String get upperName => name.toUpperCase();

  /// True if the text is written as the specification shows: an upper case
  /// name, `=` right after the name and the value right after `=`.
  bool get isCompact =>
      hasEquals &&
      name == upperName &&
      nameOffset == 0 &&
      valueOffset == name.length + 1;
}

/// Parses the argument of a `V` command. It never throws.
///
/// `V X = 45:40:30N 014:18:20E` gives name `X` and value
/// `45:40:30N 014:18:20E`. Spaces around `=` are accepted;
/// [VariableAssignment.isCompact] tells if there were any.
VariableAssignment parseVariable(Command command) =>
    parseVariableText(command.argument);

/// Same as [parseVariable], for the argument text.
VariableAssignment parseVariableText(String argument) {
  final eq = argument.indexOf('=');
  if (eq < 0) {
    final name = argument.trim();
    return VariableAssignment(
      name: name,
      nameOffset: argument.indexOf(name),
      value: '',
      valueOffset: argument.length,
      hasEquals: false,
    );
  }
  final rawName = argument.substring(0, eq);
  final name = rawName.trim();
  final nameOffset = name.isEmpty ? 0 : rawName.indexOf(name);
  var v = eq + 1;
  while (v < argument.length &&
      (argument.codeUnitAt(v) == 0x20 || argument.codeUnitAt(v) == 0x09)) {
    v++;
  }
  final value = argument.substring(v).trimRight();
  return VariableAssignment(
    name: name,
    nameOffset: nameOffset,
    value: value,
    valueOffset: value.isEmpty ? eq + 1 : v,
    hasEquals: true,
  );
}
