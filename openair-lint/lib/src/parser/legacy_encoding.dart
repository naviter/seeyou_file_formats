/// A guess of the old 8-bit encoding of a file that is not valid UTF-8.
///
/// Many old OpenAir files are saved in a Windows code page, for example
/// Windows-1250 for Slovenian or Czech names, or Windows-1252 for French or
/// German names. Some very old files use a DOS code page. Their non-ASCII
/// bytes are not valid UTF-8. The guess only helps the user: openair-lint
/// does not convert the file, because a wrong guess gives wrong letters
/// without any error (for example "Koèevje" in place of "Kočevje").
library;

import '../model/openair_file.dart';
import 'legacy_tables.dart';

/// The 8-bit encodings that [guessLegacyEncoding] knows. When several
/// encodings give the same characters for a file, the first one in this
/// list names them.
enum LegacyEncoding {
  windows1252(1252, 'Windows-1252', 'Western European', _western, 2),
  windows1250(1250, 'Windows-1250', 'Central European', _central, 2),
  windows1257(1257, 'Windows-1257', 'Baltic', _baltic, 0),
  windows1254(1254, 'Windows-1254', 'Turkish', _turkish, 0),
  windows1251(1251, 'Windows-1251', 'Cyrillic', null, 0),
  windows1253(1253, 'Windows-1253', 'Greek', null, 0),
  dos850(850, 'DOS code page 850', 'Western European', _western, -1),
  dos852(852, 'DOS code page 852', 'Central European', _central, -1),
  dos437(437, 'DOS code page 437', 'US', _western, -1);

  const LegacyEncoding(
      this.codePage, this.name, this.region, this._languages, this._prior);

  /// The code page number.
  final int codePage;

  /// The name, for example `Windows-1250`.
  final String name;

  /// The languages of the code page, for messages.
  final String region;

  /// The languages of this code page. Null for the Cyrillic and Greek code
  /// pages: there every letter of the script counts.
  final List<_Language>? _languages;

  /// Points for the code pages that are used most in airspace files (2 for
  /// Windows-1252 and Windows-1250), and minus 1 for the old DOS code
  /// pages. One point is one byte that fits. The points decide when the
  /// letters fit two code pages almost equally well.
  final double _prior;

  /// The name with the region, for example
  /// `Windows-1250 (Central European)`.
  String get label => '$name ($region)';

  /// The character of [byte] (0x80 to 0xFF), or null if the byte is not
  /// defined in this code page.
  String? charOf(int byte) {
    final cp = windowsCodePages[codePage]![byte - 0x80];
    if ((cp >= 0x80 && cp <= 0x9F) || cp == 0xFFFD) return null;
    return String.fromCharCode(cp);
  }

  /// [bytes] as text. An undefined byte is "?".
  String decode(List<int> bytes) => bytes
      .map((b) => b < 0x80 ? String.fromCharCode(b) : charOf(b) ?? '?')
      .join();
}

/// The letters of one language that are not ASCII, in lower case: the
/// [common] ones and the [rare] ones.
class _Language {
  const _Language(this.common, [this.rare = '']);

  final String common;
  final String rare;

  /// 1 for a common letter, 0.4 for a rare letter, 0 for other letters.
  double weight(String letter) {
    if (common.contains(letter)) return 1;
    if (rare.contains(letter)) return 0.4;
    return 0;
  }
}

const List<_Language> _western = [
  _Language('àâçéèêôîû', 'ëïÿœæù'), // French
  _Language('äöüß'), // German
  _Language('áéíñóú', 'ü'), // Spanish
  _Language('àèéìòù', 'íîóú'), // Italian
  _Language('ãçéáâêíóõú', 'àô'), // Portuguese
  _Language('', 'éëïöüáó'), // Dutch
  _Language('æøå', 'é'), // Danish, Norwegian
  _Language('åäö', 'é'), // Swedish
  _Language('äö', 'åšž'), // Finnish
  _Language('áéíóúýþæöð'), // Icelandic
  _Language('àçèéíòóú', 'ï'), // Catalan
];

const List<_Language> _central = [
  _Language('áčéěíóřšúůýž', 'ďňť'), // Czech
  _Language('áčéíóšúýžľ', 'äďĺňôŕť'), // Slovak
  _Language('ąćęłńóśźż'), // Polish
  _Language('čšžćđ'), // Slovenian, Croatian
  _Language('áéíóöőúüű'), // Hungarian
  _Language('ăâîşţ'), // Romanian
  _Language('äöüß'), // German
];

const List<_Language> _baltic = [
  _Language('ąčęėįšųūž'), // Lithuanian
  _Language('āčēģīķļņšūž'), // Latvian
  _Language('äöõü', 'šž'), // Estonian
];

const List<_Language> _turkish = [
  _Language('çğıöşü', 'âîû'), // Turkish
];

/// The result of [guessLegacyEncoding].
class EncodingGuess {
  const EncodingGuess(this.encodings, {this.sameText = const []});

  /// The probable encodings, the most probable first. It has one or two
  /// items. Two items mean that the bytes do not show which one is right.
  final List<LegacyEncoding> encodings;

  /// Windows-1250 or Windows-1252, if it gives exactly the same text as
  /// [best] for this file. For example, a file with only "ó" and "é" reads the same
  /// in Windows-1252 and Windows-1250.
  final List<LegacyEncoding> sameText;

  /// The most probable encoding.
  LegacyEncoding get best => encodings.first;

  /// True if two encodings are equally probable.
  bool get isUncertain => encodings.length > 1;

  /// The names for a message, for example "Windows-1250 (Central European)"
  /// or "Windows-1250 (Central European) or Windows-1252 (Western
  /// European)".
  String get labels => encodings.map((e) => e.label).join(' or ');
}

bool _isAsciiLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

bool _isAsciiLower(int c) => c >= 0x61 && c <= 0x7A;

bool _isLetter(String c) =>
    c.toUpperCase() != c.toLowerCase() || c == 'ß' || c == 'ı';

bool _isUpper(String c) => c != c.toLowerCase();

bool _isLatin(String c) {
  final u = c.codeUnitAt(0);
  return u < 0x250 || (u >= 0x1E00 && u <= 0x1EFF);
}

/// The script of the Cyrillic and Greek code pages.
bool _inScript(LegacyEncoding e, String c) {
  final u = c.codeUnitAt(0);
  return e == LegacyEncoding.windows1251
      ? u >= 0x400 && u <= 0x4FF
      : u >= 0x370 && u <= 0x3FF;
}

/// The letter in lower case, for the alphabets.
String _lower(String c) => c == 'İ' ? 'ı' : c.toLowerCase();

/// One byte that is not valid UTF-8, with what is around it.
class _Byte {
  _Byte(this.value,
      {required this.before,
      required this.after,
      required this.besideAscii,
      required this.afterLower,
      required this.runLength});

  final int value;

  /// The character directly before and after the byte (UTF-16 code
  /// units). 0 at the start or the end of the line, -1 for another invalid
  /// byte.
  final int before;
  final int after;

  /// True if the byte stands alone: one byte, without a letter directly
  /// before or after it. A letter alone is rarely a word.
  bool get alone =>
      runLength == 1 && !_isAsciiLetter(before) && !_isAsciiLetter(after);

  /// True if an ASCII letter is directly before or after the byte.
  final bool besideAscii;

  /// True if a lower case ASCII letter is directly before the byte.
  final bool afterLower;

  /// The number of bytes in the run of invalid bytes that has this byte
  /// (bytes without other characters between them).
  final int runLength;
}

/// How well [e] explains [bytes], in points: each byte that fits gives up
/// to 1 point, each byte that does not fit gives minus 2 points. The
/// points of the code page ([LegacyEncoding._prior]) are added.
///
/// - A letter of the best language of [e] counts 1 (common) or 0.4 (rare).
///   A letter of another language of [e] counts 70 % of that. A letter
///   alone (not in a word) counts half.
/// - Punctuation counts as [_symbolCredit] says: for example a dash between
///   two spaces (" – ") or an apostrophe between two letters ("user’s")
///   counts 1. Other symbols count 0.
/// - Minus 2 for each byte that does not fit: an undefined byte, an upper
///   case letter directly after a lower case letter ("FrÚjus"), a Cyrillic
///   or Greek letter next to an ASCII letter or alone, and a Latin letter
///   in a run of 3 or more invalid bytes. Western and Central European
///   words rarely have three letters with accents in a row; Cyrillic text
///   that is read as Windows-1252 has many.
double _score(LegacyEncoding e, List<_Byte> bytes) {
  final letters = <String, double>{};
  var penalty = 0;
  var symbols = 0.0;
  for (final b in bytes) {
    final c = e.charOf(b.value);
    if (c == null) {
      penalty++;
      continue;
    }
    if (!_isLetter(c)) {
      symbols += _symbolCredit(c, b);
      continue;
    }
    if (_isUpper(c) && b.afterLower) {
      penalty++;
      continue;
    }
    if (_isLatin(c)) {
      if (b.runLength >= 3) {
        penalty++;
        continue;
      }
    } else if (b.besideAscii || b.runLength < 2) {
      penalty++;
      continue;
    }
    final key = _lower(c);
    letters[key] = (letters[key] ?? 0) + (b.alone ? 0.5 : 1);
  }
  var covered = symbols;
  final languages = e._languages;
  if (languages == null) {
    for (final entry in letters.entries) {
      if (_inScript(e, entry.key)) covered += entry.value;
    }
  } else {
    // Files often mix languages, for example French place names in a
    // Dutch file. A letter of another language of the code page counts
    // 70 %.
    double anyLanguage(String letter) {
      var w = 0.0;
      for (final l in languages) {
        final x = l.weight(letter);
        if (x > w) w = x;
      }
      return w;
    }

    var best = 0.0;
    for (final language in languages) {
      var n = 0.0;
      for (final entry in letters.entries) {
        final own = language.weight(entry.key);
        final other = 0.7 * anyLanguage(entry.key);
        n += (own > other ? own : other) * entry.value;
      }
      if (n > best) best = n;
    }
    covered += best;
  }
  return covered - 2 * penalty + e._prior;
}

/// The points of the symbol [c] at the place of [b]. Punctuation of the
/// Windows code pages is common in airspace files, for example a dash
/// between two spaces or an apostrophe in a word. The same bytes are
/// letters in the DOS code pages, which then do not fit the place.
double _symbolCredit(String c, _Byte b) {
  bool isSpace(int x) => x == 0x20 || x == 0x09 || x == 0;
  switch (c) {
    case '–' || '—':
      return isSpace(b.before) && isSpace(b.after) ? 1 : 0.5;
    case '’' || '‘':
      return _isAsciiLetter(b.before) && _isAsciiLetter(b.after) ? 1 : 0.5;
    case '“' || '”' || '„' || '«' || '»' || '°' || '…' || '•':
      return 0.5;
    default:
      return 0;
  }
}

/// Guesses the 8-bit encoding of [file] from its bytes that are not valid
/// UTF-8. Returns null if the file has no such bytes or if no encoding fits.
///
/// The guess looks for the encoding in which the bytes are common letters
/// of one language. For example, the bytes E8, 9A and 9E are "č", "š" and
/// "ž" in Windows-1250 (all common Slovenian letters), but "è", "š" and "ž"
/// in Windows-1252 (no language has all three).
///
/// Encodings that give the same characters for all bytes of the file count
/// as one: then it does not matter which one the user selects. For
/// example, "ä", "ö" and "ü" are the same in Windows-1252 and Windows-1250.
/// If two encodings that give different characters fit almost equally well,
/// the result has both.
EncodingGuess? guessLegacyEncoding(OpenAirFile file) {
  final invalid = file.invalidUtf8;
  if (invalid.isEmpty) return null;

  final bytes = <_Byte>[];
  var i = 0;
  while (i < invalid.length) {
    // A run: invalid parts in consecutive columns of one line.
    var j = i + 1;
    while (j < invalid.length &&
        invalid[j].line == invalid[i].line &&
        invalid[j].column == invalid[j - 1].column + 1) {
      j++;
    }
    final first = invalid[i];
    final last = invalid[j - 1];
    final text = file.lineText(first.line);
    final before = first.column - 2;
    final after = last.column;
    final beforeChar = before >= 0 ? text.codeUnitAt(before) : 0;
    final afterChar = after < text.length ? text.codeUnitAt(after) : 0;
    final besideAscii = _isAsciiLetter(beforeChar) || _isAsciiLetter(afterChar);
    final run = [for (var k = i; k < j; k++) ...invalid[k].bytes];
    for (var k = 0; k < run.length; k++) {
      bytes.add(_Byte(run[k],
          before: k == 0 ? beforeChar : -1,
          after: k == run.length - 1 ? afterChar : -1,
          besideAscii: besideAscii,
          afterLower: k == 0 && _isAsciiLower(beforeChar),
          runLength: run.length));
    }
    i = j;
  }

  // Encodings with the same characters for all bytes form one group.
  final groups = <String, List<LegacyEncoding>>{};
  for (final e in LegacyEncoding.values) {
    final key = e.decode([for (final b in bytes) b.value]);
    (groups[key] ??= []).add(e);
  }
  final scored = [
    for (final g in groups.values) (g.first, _score(g.first, bytes))
  ]..sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      return c != 0 ? c : a.$1.index.compareTo(b.$1.index);
    });

  final (best, bestScore) = scored.first;
  final sameText = [
    for (final g in groups.values)
      if (g.first == best)
        for (final e in g.skip(1))
          if (e == LegacyEncoding.windows1250 ||
              e == LegacyEncoding.windows1252)
            e
  ];
  if (scored.length == 1) return EncodingGuess([best], sameText: sameText);
  if (bestScore <= 0) return null;
  final (second, secondScore) = scored[1];
  if (secondScore > 0 && bestScore - secondScore < _uncertainMargin) {
    return EncodingGuess([best, second]);
  }
  return EncodingGuess([best], sameText: sameText);
}

/// When the second encoding has less than this many points fewer than the
/// best one, the guess names both.
const double _uncertainMargin = 1;

/// [text] (a line of a file) as [encoding] reads it. [parts] are the parts
/// of this line that are not valid UTF-8 (see [OpenAirFile.invalidUtf8]).
/// Each one is decoded with [encoding].
String decodeLegacyLine(
    String text, List<InvalidUtf8> parts, LegacyEncoding encoding) {
  for (final x in parts.reversed) {
    final c = x.column - 1;
    if (c < 0 || c >= text.length) continue;
    text =
        text.substring(0, c) + encoding.decode(x.bytes) + text.substring(c + 1);
  }
  return text;
}
