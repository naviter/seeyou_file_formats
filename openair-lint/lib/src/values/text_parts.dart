/// Small helpers to split command arguments and read numbers.
library;

/// One part of a text, with its position in the original text.
class TextPart {
  const TextPart(this.text, this.offset);

  /// The text of the part, without spaces at the start and the end.
  final String text;

  /// The offset of [text] in the original text (0-based). If [text] is
  /// empty, this is the offset where the part would start.
  final int offset;

  /// The offset after the last character of [text].
  int get end => offset + text.length;

  @override
  String toString() => 'TextPart("$text" at $offset)';
}

bool _isBlank(int c) => c <= 0x20;

/// Splits [source] at every [separator] and trims each part.
///
/// Each part keeps its offset in [source], so a rule can point to the exact
/// column: `command.argumentColumn + part.offset`.
///
/// ```dart
/// splitParts('10, 270,290', ',') // ["10" at 0, "270" at 4, "290" at 8]
/// ```
List<TextPart> splitParts(String source, String separator) {
  final result = <TextPart>[];
  var start = 0;
  while (true) {
    final idx = source.indexOf(separator, start);
    final end = idx < 0 ? source.length : idx;
    result.add(_trimmed(source, start, end));
    if (idx < 0) break;
    start = idx + separator.length;
  }
  return result;
}

/// Splits [source] at runs of spaces and tabs. Empty parts are not returned.
List<TextPart> splitWords(String source) {
  final result = <TextPart>[];
  var i = 0;
  final n = source.length;
  while (i < n) {
    while (i < n && _isBlank(source.codeUnitAt(i))) {
      i++;
    }
    if (i >= n) break;
    final s = i;
    while (i < n && !_isBlank(source.codeUnitAt(i))) {
      i++;
    }
    result.add(TextPart(source.substring(s, i), s));
  }
  return result;
}

TextPart _trimmed(String source, int start, int end) {
  var s = start;
  var e = end;
  while (s < e && _isBlank(source.codeUnitAt(s))) {
    s++;
  }
  while (e > s && _isBlank(source.codeUnitAt(e - 1))) {
    e--;
  }
  return TextPart(source.substring(s, e), s);
}

final RegExp _decimalPattern = RegExp(r'^[+-]?(\d+(\.\d*)?|\.\d+)$');

/// Parses a plain decimal number such as `10`, `2.5` or `.5`.
///
/// Exponents (`1e3`), `NaN`, `Infinity`, commas and spaces are not accepted.
/// A sign (`+` or `-`) is only accepted when [allowSign] is true.
/// Returns null if [text] is not such a number.
double? parseDecimal(String text, {bool allowSign = false}) {
  if (!_decimalPattern.hasMatch(text)) return null;
  if (!allowSign && (text.startsWith('+') || text.startsWith('-'))) {
    return null;
  }
  final value = double.tryParse(text.endsWith('.') ? '${text}0' : text);
  // A number with hundreds of digits is Infinity as a double. It is not a
  // usable number.
  if (value == null || !value.isFinite) return null;
  return value;
}
