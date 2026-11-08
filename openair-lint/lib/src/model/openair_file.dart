/// The data model that the parser creates from an OpenAir file.
///
/// All line and column numbers start at 1. Columns count UTF-16 code units
/// (one per character for normal text). A tab counts as one column.
library;

/// The text encoding that the reader detected.
enum TextEncoding {
  /// UTF-8, with or without a byte order mark. This is the only encoding
  /// that the specification allows.
  utf8('UTF-8'),

  /// UTF-16 little endian, detected from its byte order mark.
  utf16le('UTF-16 LE'),

  /// UTF-16 big endian, detected from its byte order mark.
  utf16be('UTF-16 BE');

  const TextEncoding(this.label);

  /// A name for messages, for example `UTF-8`.
  final String label;
}

/// The characters that end a line.
enum LineEnding {
  /// `\n` (Linux, macOS).
  lf,

  /// `\r\n` (Windows).
  crlf,

  /// `\r` alone (old Mac files).
  cr,

  /// No line ending. Only the last line of a file can have this.
  none,
}

/// A part of the input bytes that is not valid UTF-8.
///
/// The reader replaces each such part with one U+FFFD character and
/// continues. It never throws.
class InvalidUtf8 {
  const InvalidUtf8({
    required this.byteOffset,
    required this.bytes,
    required this.line,
    required this.column,
  });

  /// The offset of the first bad byte from the start of the file
  /// (0-based, counted after a byte order mark).
  final int byteOffset;

  /// The bad bytes (one or more).
  final List<int> bytes;

  /// The line of the replacement character.
  final int line;

  /// The column of the replacement character.
  final int column;

  /// The bad bytes as hex, for example `E9` or `C3 28`.
  String get hex => bytes
      .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
      .join(' ');
}

/// A special header comment such as `*VERSION: 3.0`.
///
/// The parser is lenient. It also accepts lower case keys, spaces after `*`
/// and `=` in place of `:`. Use [text] and [isCanonical] to check the exact
/// form.
class HeaderField {
  const HeaderField({
    required this.line,
    required this.key,
    required this.keyColumn,
    required this.separator,
    required this.value,
    required this.valueColumn,
    required this.text,
  });

  /// The line number.
  final int line;

  /// The key as written, for example `VERSION` or `version`.
  final String key;

  /// The column of the first character of [key].
  final int keyColumn;

  /// The separator as written: `:` or `=`.
  final String separator;

  /// The value without the spaces around it. It can be empty.
  final String value;

  /// The column of the first character of [value]. If [value] is empty,
  /// this is the column after the separator.
  final int valueColumn;

  /// The whole line as written.
  final String text;

  /// The key in upper case.
  String get upperKey => key.toUpperCase();

  /// True for `*VERSION` (any case).
  bool get isVersion => upperKey == 'VERSION';

  /// True for `*WRITTEN_BY` (any case).
  bool get isWrittenBy => upperKey == 'WRITTEN_BY';

  /// True if the line is written exactly as the specification shows:
  /// `*KEY: value`, with an upper case key, no space before the key, `:` and
  /// one space before the value, and no trailing spaces.
  bool get isCanonical =>
      text == '*${key.toUpperCase()}: $value' && value.isNotEmpty;

  /// The column after the last character of the value.
  int get valueEndColumn => valueColumn + value.length;
}

/// The header of a file.
///
/// The header area is all lines before the first command. It contains only
/// comments and empty lines.
class Header {
  const Header({
    required this.endLine,
    required this.fields,
  });

  /// The last line of the header area. It is 0 if the first line already
  /// has a command.
  final int endLine;

  /// All `*KEY: value` comments in the header area, in file order.
  /// This includes keys such as `*DATE:` that the specification does not
  /// define.
  final List<HeaderField> fields;

  /// The first `*VERSION` field in the header area, or null.
  HeaderField? get version => _first('VERSION');

  /// The first `*WRITTEN_BY` field in the header area, or null.
  HeaderField? get writtenBy => _first('WRITTEN_BY');

  /// The value of [version], or null if there is no version field.
  String? get versionValue => version?.value;

  /// All fields with this key (upper case), for example to find duplicates.
  List<HeaderField> fieldsWithKey(String upperKey) => [
        for (final f in fields)
          if (f.upperKey == upperKey) f
      ];

  HeaderField? _first(String upperKey) {
    for (final f in fields) {
      if (f.upperKey == upperKey) return f;
    }
    return null;
  }
}

/// One command line, for example `DP 45:40:30N 014:18:20E * comment`.
class Command {
  Command({
    required this.line,
    required this.column,
    required this.keyword,
    required this.argument,
    required this.argumentColumn,
    required this.comment,
    required this.commentColumn,
    required this.text,
  }) : upperKeyword = keyword.toUpperCase();

  /// The line number.
  final int line;

  /// The column of the first character of [keyword]. It is 1 unless the
  /// line starts with spaces or tabs.
  final int column;

  /// The keyword as written, for example `AC`, `ac` or `DP`.
  ///
  /// The keyword is the text from the first non-space character up to the
  /// next space, tab or `*`. So `AH5000FT` is one keyword, which is unknown.
  final String keyword;

  /// [keyword] in upper case. Use this to find the kind of command.
  final String upperKeyword;

  /// The text after the keyword, as written. Spaces at the start and the
  /// end and the comment are removed. It can be empty.
  final String argument;

  /// The column of the first character of [argument]. If [argument] is
  /// empty, this is the column after the keyword.
  final int argumentColumn;

  /// The comment text after `*`, without the `*`, or null if the line has
  /// no comment. The text is not trimmed.
  final String? comment;

  /// The column of the `*` that starts the comment, or null.
  final int? commentColumn;

  /// The whole line as written, including the comment.
  final String text;

  /// True if [keyword] is written in upper case.
  bool get isUpperCaseKeyword => keyword == upperKeyword;

  /// The column after the keyword.
  int get keywordEndColumn => column + keyword.length;

  /// The column after the last character of the argument (or after the
  /// keyword if there is no argument).
  int get endColumn =>
      argument.isEmpty ? keywordEndColumn : argumentColumn + argument.length;

  /// The number of space and tab characters between the keyword and the
  /// argument. It is 0 if there is no argument.
  int get spacesAfterKeyword =>
      argument.isEmpty ? 0 : argumentColumn - keywordEndColumn;

  @override
  String toString() => '$line: $keyword $argument';
}

/// One airspace definition: the commands from one `AC` command up to the
/// next `AC` command or the end of the file.
class Airspace {
  Airspace({required this.index, required this.commands});

  /// The position of this airspace in the file, starting at 0.
  final int index;

  /// The commands of this airspace, in file order. The first command is
  /// always the `AC` command (in any case). Comment-only lines and empty
  /// lines are not commands.
  final List<Command> commands;

  /// The `AC` command that starts this airspace.
  Command get ac => commands.first;

  /// The line of the `AC` command.
  int get startLine => commands.first.line;

  /// The line of the last command of this airspace.
  int get endLine => commands.last.line;

  /// All commands with this keyword. [upperKeyword] must be upper case,
  /// for example `AA`.
  List<Command> commandsWith(String upperKeyword) => [
        for (final c in commands)
          if (c.upperKeyword == upperKeyword) c
      ];

  /// The first command with this keyword, or null.
  Command? firstWith(String upperKeyword) {
    for (final c in commands) {
      if (c.upperKeyword == upperKeyword) return c;
    }
    return null;
  }

  /// The argument of the first `AN` command, or null.
  String? get name => firstWith('AN')?.argument;

  /// A short text that identifies this airspace in messages, for example
  /// `"CTR Ljubljana" (line 12)` or `airspace at line 12`.
  String get label {
    final n = name;
    return (n == null || n.isEmpty)
        ? 'airspace at line $startLine'
        : '"$n" (line $startLine)';
  }

  @override
  String toString() => 'Airspace($label)';
}

/// A parsed OpenAir file.
///
/// The parser never throws. It keeps everything it finds, also unknown and
/// wrong commands, so that rules can report them.
class OpenAirFile {
  OpenAirFile({
    required this.lines,
    required this.lineEndings,
    required this.encoding,
    required this.hasBom,
    required this.invalidUtf8,
    required this.header,
    required this.airspaces,
    required this.commandsOutsideAirspace,
    required this.lateHeaderFields,
  });

  /// The text of every line, without the line ending. `lines[0]` is line 1.
  final List<String> lines;

  /// The line ending of every line. Same length as [lines].
  final List<LineEnding> lineEndings;

  /// The detected encoding.
  final TextEncoding encoding;

  /// True if the file starts with a byte order mark (U+FEFF).
  final bool hasBom;

  /// Parts of the input that are not valid UTF-8. Empty when the input was a
  /// Dart string or valid UTF-8.
  final List<InvalidUtf8> invalidUtf8;

  /// The header (comments before the first command).
  final Header header;

  /// All airspace definitions, in file order.
  final List<Airspace> airspaces;

  /// Commands that are not inside an airspace definition. These are the
  /// commands before the first `AC` command.
  final List<Command> commandsOutsideAirspace;

  /// `*VERSION` and `*WRITTEN_BY` comments that come after the header area
  /// (after the first command). They are not used as the header.
  final List<HeaderField> lateHeaderFields;

  /// The number of lines.
  int get lineCount => lines.length;

  /// The text of one line. [lineNumber] starts at 1.
  String lineText(int lineNumber) => lines[lineNumber - 1];

  /// All commands of the file in file order (outside and inside airspaces).
  Iterable<Command> get allCommands sync* {
    yield* commandsOutsideAirspace;
    for (final a in airspaces) {
      yield* a.commands;
    }
  }
}
