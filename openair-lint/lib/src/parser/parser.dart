import '../model/openair_file.dart';
import 'decoder.dart';

/// Parses the bytes of an OpenAir file. It never throws.
///
/// See [decodeBytes] for the decoding rules.
OpenAirFile parseOpenAirBytes(List<int> bytes) {
  final decoded = decodeBytes(bytes);
  return _Parser(
          decoded.text, decoded.encoding, decoded.hasBom, decoded.invalid)
      .parse();
}

/// Parses the text of an OpenAir file. It never throws.
///
/// If [text] starts with U+FEFF (a byte order mark), it is removed and
/// [OpenAirFile.hasBom] is true.
OpenAirFile parseOpenAir(String text) {
  var hasBom = false;
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
    text = text.substring(1);
    hasBom = true;
  }
  return _Parser(text, TextEncoding.utf8, hasBom, const []).parse();
}

const int _space = 0x20;
const int _star = 0x2A;
const int _cr = 0x0D;
const int _lf = 0x0A;

/// True for space, tab and the other ASCII control characters
/// (but not for line endings, which are already removed).
bool _isBlank(int c) => c <= _space;

final RegExp _headerFieldPattern =
    RegExp(r'^([ \t]*)\*([ \t]*)([A-Za-z][A-Za-z0-9_]*)([ \t]*)([:=])');

class _Parser {
  _Parser(this.text, this.encoding, this.hasBom, this.invalid);

  final String text;
  final TextEncoding encoding;
  final bool hasBom;
  final List<InvalidByteSequence> invalid;

  final List<String> lines = [];
  final List<LineEnding> endings = [];
  final List<int> lineStarts = [];

  OpenAirFile parse() {
    _splitLines();

    final headerFields = <HeaderField>[];
    final lateFields = <HeaderField>[];
    final outside = <Command>[];
    final airspaces = <Airspace>[];
    List<Command>? current;
    var headerEnd = lines.length;
    var inHeader = true;

    for (var i = 0; i < lines.length; i++) {
      final lineNo = i + 1;
      final line = lines[i];
      final command = _parseCommand(line, lineNo);
      if (command == null) {
        // Empty line or comment-only line.
        if (line.contains('*')) {
          final field = _parseHeaderField(line, lineNo);
          if (field != null) {
            if (inHeader) {
              headerFields.add(field);
            } else if (field.isVersion || field.isWrittenBy) {
              lateFields.add(field);
            }
          }
        }
        continue;
      }
      if (inHeader) {
        inHeader = false;
        headerEnd = i; // lines 1..i are the header area
      }
      if (command.upperKeyword == 'AC') {
        current = <Command>[command];
        airspaces.add(Airspace(index: airspaces.length, commands: current));
      } else if (current != null) {
        current.add(command);
      } else {
        outside.add(command);
      }
    }

    return OpenAirFile(
      lines: List.unmodifiable(lines),
      lineEndings: List.unmodifiable(endings),
      encoding: encoding,
      hasBom: hasBom,
      invalidUtf8: _locateInvalid(),
      header:
          Header(endLine: headerEnd, fields: List.unmodifiable(headerFields)),
      airspaces: List.unmodifiable(airspaces),
      commandsOutsideAirspace: List.unmodifiable(outside),
      lateHeaderFields: List.unmodifiable(lateFields),
    );
  }

  void _splitLines() {
    final n = text.length;
    var start = 0;
    var i = 0;
    while (i < n) {
      final c = text.codeUnitAt(i);
      if (c == _lf) {
        lineStarts.add(start);
        lines.add(text.substring(start, i));
        endings.add(LineEnding.lf);
        i++;
        start = i;
      } else if (c == _cr) {
        lineStarts.add(start);
        lines.add(text.substring(start, i));
        if (i + 1 < n && text.codeUnitAt(i + 1) == _lf) {
          endings.add(LineEnding.crlf);
          i += 2;
        } else {
          endings.add(LineEnding.cr);
          i++;
        }
        start = i;
      } else {
        i++;
      }
    }
    if (start < n) {
      lineStarts.add(start);
      lines.add(text.substring(start));
      endings.add(LineEnding.none);
    }
  }

  /// Returns null for an empty line or a comment-only line.
  Command? _parseCommand(String line, int lineNo) {
    final n = line.length;
    final star = line.indexOf('*');
    final contentEnd = star < 0 ? n : star;
    var k = 0;
    while (k < contentEnd && _isBlank(line.codeUnitAt(k))) {
      k++;
    }
    if (k >= contentEnd) return null;
    var kEnd = k;
    while (kEnd < contentEnd && !_isBlank(line.codeUnitAt(kEnd))) {
      kEnd++;
    }
    var a = kEnd;
    while (a < contentEnd && _isBlank(line.codeUnitAt(a))) {
      a++;
    }
    var aEnd = contentEnd;
    while (aEnd > a && _isBlank(line.codeUnitAt(aEnd - 1))) {
      aEnd--;
    }
    final keyword = line.substring(k, kEnd);
    final argument = a < aEnd ? line.substring(a, aEnd) : '';
    return Command(
      line: lineNo,
      column: k + 1,
      keyword: keyword,
      argument: argument,
      argumentColumn: argument.isEmpty ? kEnd + 1 : a + 1,
      comment: star < 0 ? null : line.substring(star + 1),
      commentColumn: star < 0 ? null : star + 1,
      text: line,
    );
  }

  HeaderField? _parseHeaderField(String line, int lineNo) {
    // Fast check: the first non-blank character must be '*'.
    var k = 0;
    while (k < line.length && _isBlank(line.codeUnitAt(k))) {
      k++;
    }
    if (k >= line.length || line.codeUnitAt(k) != _star) return null;
    final m = _headerFieldPattern.firstMatch(line);
    if (m == null) return null;
    final key = m.group(3)!;
    final keyStart =
        m.group(1)!.length + 1 + m.group(2)!.length; // 0-based offset
    var v = m.end;
    while (v < line.length && _isBlank(line.codeUnitAt(v))) {
      v++;
    }
    var vEnd = line.length;
    while (vEnd > v && _isBlank(line.codeUnitAt(vEnd - 1))) {
      vEnd--;
    }
    return HeaderField(
      line: lineNo,
      key: key,
      keyColumn: keyStart + 1,
      separator: m.group(5)!,
      value: line.substring(v, vEnd),
      valueColumn: (v < vEnd ? v : m.end) + 1,
      text: line,
    );
  }

  List<InvalidUtf8> _locateInvalid() {
    if (invalid.isEmpty) return const [];
    final result = <InvalidUtf8>[];
    var lineIndex = 0;
    for (final inv in invalid) {
      // invalid is sorted by textOffset, so lineIndex only moves forward.
      while (lineIndex + 1 < lineStarts.length &&
          lineStarts[lineIndex + 1] <= inv.textOffset) {
        lineIndex++;
      }
      final lineStart = lineStarts.isEmpty ? 0 : lineStarts[lineIndex];
      result.add(InvalidUtf8(
        byteOffset: inv.byteOffset,
        bytes: inv.bytes,
        line: lineIndex + 1,
        column: inv.textOffset - lineStart + 1,
      ));
    }
    return List.unmodifiable(result);
  }
}
