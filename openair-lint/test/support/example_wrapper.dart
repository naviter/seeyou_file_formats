/// Puts a short example (a few OpenAir lines) into a complete file.
///
/// Used by `spec_examples_test.dart` and `rule_examples_test.dart`.
library;

/// A small, valid polygon (clockwise and closed), used when an example has
/// no geometry.
const List<String> defaultPolygon = [
  'DP 46:00:00N 014:00:00E',
  'DP 46:00:00N 014:10:00E',
  'DP 45:55:00N 014:10:00E',
  'DP 45:55:00N 014:00:00E',
  'DP 46:00:00N 014:00:00E',
];

/// The upper case keyword of [line] (the first word before a blank or
/// `*`).
String keywordOf(String line) =>
    line.trimLeft().split(RegExp(r'[\s*]')).first.toUpperCase();

bool _isGeometry(String line) =>
    const {'DP', 'DA', 'DB', 'DC', 'DY', 'V'}.contains(keywordOf(line));

bool _isComment(String line) => line.trimLeft().startsWith('*');

/// Puts the example [lines] into a complete file of version [version].
///
/// The example keeps its own lines and their order. Missing parts are
/// added: the header, "AC D" and a name, "AH 4500 FT AMSL", "AL GND" and a
/// small polygon. Comment lines of the example stay before the first
/// command.
///
/// If the example has more than one AC command, or if [keepAirspace] is
/// true and the example has an AC command, only the header is added.
///
/// [header] replaces the default header lines.
String wrapExample(List<String> lines,
    {String version = '3.0', List<String>? header, bool keepAirspace = false}) {
  header ??= [
    '*VERSION: $version',
    '*WRITTEN_BY: openair-lint example test',
  ];
  final acCount = lines.where((l) => keywordOf(l) == 'AC').length;
  if (acCount > 1 || (keepAirspace && acCount == 1)) {
    return '${[...header, ...lines].join('\n')}\n';
  }

  bool has(String keyword) => lines.any((l) => keywordOf(l) == keyword);
  final comments = lines.where(_isComment).toList();
  final commands = lines.where((l) => !_isComment(l)).toList();
  final geometry = commands.where(_isGeometry).toList();
  final attributes = commands.where((l) => !_isGeometry(l)).toList();
  final ac = attributes.where((l) => keywordOf(l) == 'AC').toList();
  final others = attributes.where((l) => keywordOf(l) != 'AC').toList();
  return [
    ...header,
    ...comments,
    if (ac.isEmpty) 'AC D' else ...ac,
    if (!has('AN')) 'AN Example',
    ...others,
    if (!has('AH')) 'AH 4500 FT AMSL',
    if (!has('AL')) 'AL GND',
    if (geometry.isEmpty) ...defaultPolygon else ...geometry,
    '',
  ].join('\n');
}
