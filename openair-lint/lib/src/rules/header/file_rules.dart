part of '../header_rules.dart';

// ---------------------------------------------------------------------------
// file-not-utf8
// ---------------------------------------------------------------------------

final Rule _fileNotUtf8 = Rule(
  id: 'file-not-utf8',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: _generalAnchor,
  description: 'The file must use the UTF-8 encoding, not UTF-16.',
  explanation: 'The specification requires the UTF-8 encoding. This file '
      'uses UTF-16. Many readers cannot read UTF-16 files at all.\n'
      '\n'
      'openair-lint finds UTF-16 from the byte order mark at the start of '
      'the file (FF FE or FE FF). It also finds UTF-16 without a byte order '
      'mark: then many characters of the text are NUL (U+0000). In this case '
      'openair-lint does not report the other problems of the header and of '
      'the commands, because it cannot read the text.\n'
      '\n'
      'Save the file again as UTF-8. Most text editors have this option in '
      'the "Save as" dialog.',
  correctExample: '(the file is saved as UTF-8)\n'
      '*VERSION: 3.0\n'
      '*WRITTEN_BY: SeeYou',
  incorrectExample: '(the file is saved as UTF-16, it starts with the bytes '
      'FF FE)\n'
      '*VERSION: 3.0\n'
      '*WRITTEN_BY: SeeYou',
  checkFile: (ctx) {
    final encoding = ctx.file.encoding;
    if (encoding != TextEncoding.utf8) {
      ctx.report(
          'The file uses the ${encoding.label} encoding. The specification '
          'requires UTF-8. Save the file as UTF-8.',
          line: 1);
      return;
    }
    final utf16 = _looksLikeUtf16(ctx);
    if (utf16 == null) return;
    ctx.report(
        'The file contains many NUL characters (U+0000). It is probably '
        'saved as $utf16 without a byte order mark. The specification '
        'requires UTF-8. Save the file as UTF-8.',
        line: 1);
  },
);

// ---------------------------------------------------------------------------
// file-invalid-utf8
// ---------------------------------------------------------------------------

final Rule _fileInvalidUtf8 = Rule(
  id: 'file-invalid-utf8',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: _generalAnchor,
  description: 'The file must contain only valid UTF-8 text.',
  explanation: 'The specification requires the UTF-8 encoding. Some bytes '
      'in this file are not valid UTF-8. This usually means that the file '
      'was saved in an older 8-bit encoding, for example Windows-1252, '
      'Windows-1250 or ISO 8859-1. Readers show these characters wrongly, '
      'or they stop reading the file.\n'
      '\n'
      'Open the file in an editor with the correct old encoding, and save it '
      'again as UTF-8. openair-lint reports one problem for each line with '
      'invalid bytes.',
  correctExample: 'AN Muenchen CTR\n'
      'AN München CTR      * saved as UTF-8: "ü" is the bytes C3 BC',
  incorrectExample: 'AN München CTR      * saved as Windows-1252: "ü" is the '
      'byte FC',
  checkFile: (ctx) {
    final invalid = ctx.file.invalidUtf8;
    if (invalid.isEmpty) return;
    // file-not-utf8 reports a UTF-16 file without a byte order mark.
    if (_looksLikeUtf16(ctx) != null) return;
    var i = 0;
    while (i < invalid.length) {
      final first = invalid[i];
      var count = 0;
      final hex = <String>[];
      var lastColumn = first.column;
      while (i < invalid.length && invalid[i].line == first.line) {
        if (hex.length < 3) hex.add(invalid[i].hex);
        lastColumn = invalid[i].column;
        count++;
        i++;
      }
      final where = count == 1
          ? 'The byte${first.bytes.length == 1 ? '' : 's'} ${first.hex} at '
              'byte offset ${first.byteOffset} ${first.bytes.length == 1 ? 'is' : 'are'} '
              'not valid UTF-8.'
          : 'This line has $count parts that are not valid UTF-8 '
              '(${hex.join(', ')}${count > 3 ? ', ...' : ''}).';
      ctx.report(
          '$where The file is probably saved in an older 8-bit encoding. '
          'Save it as UTF-8.',
          line: first.line,
          column: first.column,
          endColumn: lastColumn + 1);
    }
  },
);

// ---------------------------------------------------------------------------
// file-replacement-character
// ---------------------------------------------------------------------------

final Rule _fileReplacementCharacter = Rule(
  id: 'file-replacement-character',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: _generalAnchor,
  description: 'The text should not contain the replacement character '
      '"\u{FFFD}" (U+FFFD).',
  explanation: 'The character "\u{FFFD}" (U+FFFD) replaces a character that '
      'a program could not read. When it is in a file, an earlier conversion '
      'lost the original character. For example, "München" became '
      '"M\u{FFFD}nchen".\n'
      '\n'
      'Write the correct character in place of "\u{FFFD}". This rule does not '
      'report bytes that are not valid UTF-8; the rule file-invalid-utf8 '
      'reports them.',
  correctExample: 'AN München CTR',
  incorrectExample: 'AN M\u{FFFD}nchen CTR',
  checkFile: (ctx) {
    final file = ctx.file;
    final fromInvalid = <int, Set<int>>{};
    for (final inv in file.invalidUtf8) {
      (fromInvalid[inv.line] ??= {}).add(inv.column);
    }
    for (var n = 1; n <= file.lineCount; n++) {
      final text = file.lineText(n);
      var idx = text.indexOf('\u{FFFD}');
      while (idx >= 0) {
        if (!(fromInvalid[n]?.contains(idx + 1) ?? false)) {
          ctx.report(
              'The text contains the replacement character "\u{FFFD}" '
              '(U+FFFD). A character was lost in an earlier conversion. '
              'Write the correct character.',
              line: n,
              column: idx + 1);
          break;
        }
        idx = text.indexOf('\u{FFFD}', idx + 1);
      }
    }
  },
);

// ---------------------------------------------------------------------------
// file-bom
// ---------------------------------------------------------------------------

final Rule _fileBom = Rule(
  id: 'file-bom',
  severity: Severity.info,
  versions: SpecVersion.all,
  specAnchor: _generalAnchor,
  description: 'A UTF-8 file does not need a byte order mark (BOM).',
  explanation: 'The file starts with a UTF-8 byte order mark (the bytes '
      'EF BB BF). UTF-8 does not need it. Most readers ignore it, but some '
      'older readers see it as part of the first line. Then they do not '
      'find the "*VERSION:" header or the first command.\n'
      '\n'
      'Save the file as "UTF-8" and not as "UTF-8 with BOM".',
  correctExample: '*VERSION: 3.0\n'
      '*WRITTEN_BY: SeeYou\n'
      '* The first byte of the file is the "*" of *VERSION.',
  incorrectExample: '\u{FEFF}*VERSION: 3.0\n'
      '*WRITTEN_BY: SeeYou\n'
      '* The file starts with the bytes EF BB BF (the BOM) before *VERSION.',
  checkFile: (ctx) {
    if (!ctx.file.hasBom || ctx.file.encoding != TextEncoding.utf8) return;
    ctx.report(
        'The file starts with a UTF-8 byte order mark (BOM). It is not '
        'needed, and some older readers do not expect it.',
        line: 1);
  },
);

// ---------------------------------------------------------------------------
// file-mixed-line-endings
// ---------------------------------------------------------------------------

final Rule _fileMixedLineEndings = Rule(
  id: 'file-mixed-line-endings',
  severity: Severity.info,
  versions: SpecVersion.all,
  specAnchor: _generalAnchor,
  description: 'All lines should use the same line ending.',
  explanation: 'The file uses more than one kind of line ending: LF '
      '(Linux, macOS), CRLF (Windows) or CR (old Mac). This often happens '
      'when files from different sources are joined. Most readers accept '
      'it, but some tools then count the lines differently or show empty '
      'lines.\n'
      '\n'
      'Use one kind of line ending in the whole file. Many editors can '
      'convert the line endings.',
  correctExample: 'AC D\\n\n'
      'AN Example CTR\\n',
  incorrectExample: 'AC D\\r\\n\n'
      'AN Example CTR\\n',
  checkFile: (ctx) {
    final endings = ctx.file.lineEndings;
    final counts = <LineEnding, int>{};
    for (final e in endings) {
      if (e == LineEnding.none) continue;
      counts[e] = (counts[e] ?? 0) + 1;
    }
    if (counts.length < 2) return;
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final main = sorted.first.key;
    var firstOther = 0;
    for (var i = 0; i < endings.length; i++) {
      if (endings[i] != main && endings[i] != LineEnding.none) {
        firstOther = i + 1;
        break;
      }
    }
    final summary =
        sorted.map((e) => '${e.value} ${_endingLabel(e.key)}').join(', ');
    ctx.report(
        'The file mixes line endings ($summary). This is the first line that '
        'ends with ${_endingLabel(endings[firstOther - 1])}. Use one kind of '
        'line ending in the whole file.',
        line: firstOther,
        column: ctx.file.lineText(firstOther).length + 1);
  },
);

String _endingLabel(LineEnding e) => switch (e) {
      LineEnding.lf => 'LF',
      LineEnding.crlf => 'CRLF',
      LineEnding.cr => 'CR',
      LineEnding.none => 'no line ending',
    };

// ---------------------------------------------------------------------------
// file-no-airspace
// ---------------------------------------------------------------------------

final Rule _fileNoAirspace = Rule(
  id: 'file-no-airspace',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'airspace-definition',
  description: 'The file must contain at least one airspace definition.',
  explanation: 'An OpenAir file contains airspace definitions. Each '
      'definition starts with an "AC" command. This file has no "AC" '
      'command, so it has no airspace. It can be empty, contain only '
      'comments, or be a file of another format.',
  correctExample: '*VERSION: 3.0\n'
      '*WRITTEN_BY: SeeYou\n'
      '\n'
      'AC D\n'
      'AN Example CTR\n'
      'AH 4500 FT AMSL\n'
      'AL GND\n'
      'DP 46:00:00N 014:00:00E\n'
      '...',
  incorrectExample: '*VERSION: 3.0\n'
      '*WRITTEN_BY: SeeYou\n'
      '* No airspaces yet',
  checkFile: (ctx) {
    final file = ctx.file;
    if (file.airspaces.isNotEmpty) return;
    if (_looksLikeUtf16(ctx) != null) return;
    final empty = file.lines.every((l) => l.trim().isEmpty);
    ctx.report(
        empty
            ? 'The file is empty. It must contain at least one airspace.'
            : 'The file has no airspace. Each airspace starts with an "AC" '
                'command.',
        line: 1);
  },
);

// ---------------------------------------------------------------------------
// file-garbled-text
// ---------------------------------------------------------------------------

final Rule _fileGarbledText = Rule(
  id: 'file-garbled-text',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'an-airspace-name',
  description: 'A name should not contain garbled characters such as "Ã¼" '
      'in place of "ü".',
  explanation: 'Some characters in the name look like UTF-8 text that was '
      'read with a wrong encoding and then saved again. For example, "ü" '
      'became "Ã¼", and "Š" became "Å" followed by a non-breaking space. '
      'Pilots then see the garbled name.\n'
      '\n'
      'Write the correct characters. The specification also recommends '
      'simple letters in names, for example "ue" in place of "ü".\n'
      '\n'
      'This rule checks the text after "AN" and "AG".',
  correctExample: 'AN Muenchen CTR',
  incorrectExample: 'AN MÃ¼nchen CTR',
  keywords: {'AN', 'AG'},
  checkCommand: (ctx, c, a) {
    final hit = _findGarbled(c.argument);
    if (hit == null) return;
    final bad = _visible(c.argument.substring(hit.$1, hit.$2));
    ctx.reportArgument(
        c,
        'The text "$bad" looks garbled. It is probably "${hit.$3}", read with '
        'a wrong encoding. Write the correct characters.',
        offset: hit.$1,
        length: hit.$2 - hit.$1);
  },
);

/// [text] with invisible characters (control characters, no-break space,
/// soft hyphen) written as `<U+0081>`, so that a message shows them.
String _visible(String text) {
  final b = StringBuffer();
  for (final c in text.codeUnits) {
    if (c < 0x20 || (c >= 0x7F && c <= 0xA0) || c == 0xAD) {
      b.write('<U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}>');
    } else {
      b.writeCharCode(c);
    }
  }
  return b.toString();
}

/// Windows-1252 characters in the range 0x80-0x9F, as code point -> byte.
const Map<int, int> _cp1252 = {
  0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, //
  0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
  0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
  0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
  0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
  0x017E: 0x9E, 0x0178: 0x9F,
};

/// The byte that [codeUnit] has in Windows-1252 or ISO 8859-1, or -1.
int _legacyByte(int codeUnit) {
  if (codeUnit >= 0x80 && codeUnit <= 0xFF) return codeUnit;
  return _cp1252[codeUnit] ?? -1;
}

/// Finds UTF-8 text that was decoded as Windows-1252 or ISO 8859-1.
///
/// Returns (start, end, decoded text) of the first garbled part, or null.
(int, int, String)? _findGarbled(String text) {
  for (var i = 0; i < text.length; i++) {
    final lead = _legacyByte(text.codeUnitAt(i));
    final int need;
    if (lead >= 0xC2 && lead <= 0xDF) {
      need = 1;
    } else if (lead >= 0xE0 && lead <= 0xEF) {
      need = 2;
    } else if (lead >= 0xF0 && lead <= 0xF4) {
      need = 3;
    } else {
      continue;
    }
    if (i + need >= text.length) continue;
    final bytes = [lead];
    for (var k = 1; k <= need; k++) {
      final b = _legacyByte(text.codeUnitAt(i + k));
      if (b < 0x80 || b > 0xBF) break;
      bytes.add(b);
    }
    if (bytes.length != need + 1) continue;
    final decoded = _decodeUtf8Sequence(bytes);
    if (decoded == null || !_isProbableCharacter(decoded.runes.first)) {
      continue;
    }
    // Take the following garbled characters too, for a better message.
    var end = i + need + 1;
    final buffer = StringBuffer(decoded);
    while (true) {
      final next = _findGarbled(text.substring(end));
      if (next == null || next.$1 != 0) break;
      buffer.write(next.$3);
      end += next.$2;
    }
    return (i, end, buffer.toString());
  }
  return null;
}

/// True if [cp] is a character that is often in airspace names, so that a
/// garbled form of it is probable.
///
/// Correct text can contain a pair such as "Ö–" (U+00D6 and an en dash). Its
/// bytes in Windows-1252 (D6 96) are also a valid UTF-8 sequence, but for a
/// Hebrew accent (U+0596). Such a result is not probable, so the text is not
/// garbled. The accepted characters are Latin letters and signs
/// (U+00A0-U+024F, U+1E00-U+1EFF), Greek and Cyrillic (U+0370-U+04FF),
/// common punctuation (U+2010-U+203A), the euro sign and the trade mark
/// sign.
bool _isProbableCharacter(int cp) =>
    (cp >= 0x00A0 && cp <= 0x024F) ||
    (cp >= 0x1E00 && cp <= 0x1EFF) ||
    (cp >= 0x0370 && cp <= 0x04FF) ||
    (cp >= 0x2010 && cp <= 0x203A) ||
    cp == 0x20AC ||
    cp == 0x2122;

/// Decodes one complete UTF-8 sequence, or returns null if it is not valid
/// (overlong forms and surrogates are not valid).
String? _decodeUtf8Sequence(List<int> b) {
  int cp;
  switch (b.length) {
    case 2:
      cp = ((b[0] & 0x1F) << 6) | (b[1] & 0x3F);
      if (cp < 0x80) return null;
    case 3:
      cp = ((b[0] & 0x0F) << 12) | ((b[1] & 0x3F) << 6) | (b[2] & 0x3F);
      if (cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF)) return null;
    case 4:
      cp = ((b[0] & 0x07) << 18) |
          ((b[1] & 0x3F) << 12) |
          ((b[2] & 0x3F) << 6) |
          (b[3] & 0x3F);
      if (cp < 0x10000 || cp > 0x10FFFF) return null;
    default:
      return null;
  }
  return String.fromCharCode(cp);
}

// ---------------------------------------------------------------------------
// file-strepla-block
// ---------------------------------------------------------------------------

final Rule _fileStreplaBlock = Rule(
  id: 'file-strepla-block',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'airspace-definition',
  description: 'The file should not contain StrePla add-on blocks.',
  explanation: 'The program StrePla writes extra data between the comments '
      '"*\$STREPLA_ADDON BEGIN" and "*\$STREPLA_ADDON END", for example a '
      'colour table. The lines in the block look like commands, but they are '
      'not airspaces. The specification does not define these blocks. A '
      'reader that does not know them reads the lines as airspaces without '
      'altitude limits and without geometry.\n'
      '\n'
      'Remove the block. openair-lint does not check the structure of the '
      'airspaces inside the block.',
  correctExample: 'AC D\n'
      'AN Example CTR\n'
      '...',
  incorrectExample: '*\$STREPLA_ADDON BEGIN colortable\n'
      'AC A\n'
      'AN COLORENTRY\n'
      'SP 0 1 0x0000FF\n'
      '*\$STREPLA_ADDON END',
  checkFile: (ctx) {
    for (final b in _streplaBlocks(ctx)) {
      ctx.reportLine(
          b.start,
          'This is a StrePla add-on block (lines ${b.start} to ${b.end}). '
          'It is not part of the specification. Readers that do not know it '
          'read its lines as airspaces. Remove the block.');
    }
  },
);

// ---------------------------------------------------------------------------
// file-extension-not-openair
// ---------------------------------------------------------------------------

final Rule _fileExtensionNotOpenAir = Rule(
  id: 'file-extension-not-openair',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: _generalAnchor,
  description: 'The file name should end with .openair (or .txt, the legacy '
      'extension).',
  explanation: 'The specification says: use the file extension .openair, '
      'with .txt as legacy alternative. Programs and people find OpenAir '
      'files by the extension. openair-lint also searches directories only '
      'for *.openair and *.txt files.\n'
      '\n'
      'This rule needs the name of the file. The command line tool gives it '
      'for every file. It is not checked for standard input or for text '
      'that is pasted on the web page. The extension .txt is allowed and '
      'not reported.',
  correctExample: '* File name: austria.openair\n'
      'AC D\n'
      '...',
  incorrectExample: '* File name: austria.dat\n'
      'AC D\n'
      '...',
  checkFile: (ctx) {
    final name = ctx.fileName;
    if (name == null) return;
    final base = name.split(RegExp(r'[\/]')).last;
    final lower = base.toLowerCase();
    if (lower.endsWith('.openair') || lower.endsWith('.txt')) return;
    final dot = base.lastIndexOf('.');
    final extension = dot <= 0 ? null : base.substring(dot);
    ctx.report(
        '${extension == null ? 'The file name "$base" has no extension' : 'The file extension "$extension" is not an OpenAir extension'}. '
        'Use .openair (or .txt, the legacy extension). Programs find OpenAir '
        'files by the extension.',
        line: 1);
  },
);
