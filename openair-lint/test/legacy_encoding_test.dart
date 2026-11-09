import 'dart:convert';

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

/// A file with [lines], where each line is ASCII text with bytes in it.
/// The lines are given as lists of parts: a String is ASCII text, an int is
/// one byte.
List<int> _file(List<List<Object>> lines) => [
      ...ascii.encode('*VERSION: 2.1\n*WRITTEN_BY: test\nAC D\n'),
      for (final line in lines) ...[
        for (final part in line)
          if (part is String) ...ascii.encode(part) else part as int,
        0x0A,
      ],
    ];

EncodingGuess? _guess(List<List<Object>> lines) =>
    guessLegacyEncoding(parseOpenAirBytes(_file(lines)));

void main() {
  group('guessLegacyEncoding', () {
    test('a valid UTF-8 file has no guess', () {
      expect(guessLegacyEncoding(parseOpenAir('AN München\n')), isNull);
    });

    test('Slovenian names: Windows-1250', () {
      final g = _guess([
        ['AN Ko', 0xE8, 'evje'],
        ['AN Bre', 0x9E, 'ice'],
        ['AN ', 0x8A, 'o', 0x9A, 'tanj'],
      ])!;
      expect(g.encodings, [LegacyEncoding.windows1250]);
      expect(g.labels, 'Windows-1250 (Central European)');
    });

    test('Polish names: Windows-1250', () {
      final g = _guess([
        ['AN ', 0xA3, 0xF3, 'd', 0x9F],
        ['AN Gda', 0xF1, 'sk'],
        ['* Obowi', 0xB9, 'zuje'],
      ])!;
      expect(g.encodings, [LegacyEncoding.windows1250]);
    });

    test('French names: Windows-1252', () {
      final g = _guess([
        ['AN Li', 0xE8, 'ge'],
        ['AN V', 0xE0, 'V Saintes'],
        ['* ', 0xE0, " l'exception de la ZIT"],
        ['AN Cr', 0xEA, 'te'],
      ])!;
      expect(g.encodings, [LegacyEncoding.windows1252]);
    });

    test('German names: Windows-1252, and Windows-1250 gives the same text',
        () {
      final g = _guess([
        ['AN Br', 0xFC, 'ck'],
        ['AN Gro', 0xDF, 'enhain'],
        ['AN ', 0xC4, 'nderung'],
      ])!;
      expect(g.encodings, [LegacyEncoding.windows1252]);
      expect(g.sameText, [LegacyEncoding.windows1250]);
    });

    test('one letter that fits two languages: both encodings', () {
      // "Poznań" (Windows-1250) or "Poznañ" (Windows-1252).
      final g = _guess([
        ['AN FIS Pozna', 0xF1],
      ])!;
      expect(g.isUncertain, isTrue);
      expect(g.encodings.toSet(),
          {LegacyEncoding.windows1250, LegacyEncoding.windows1252});
    });

    test('Windows punctuation is not read as DOS letters', () {
      final g = _guess([
        ['* at the user', 0x92, 's risk'],
        ['* APR ', 0x96, ' OCT'],
      ])!;
      expect(g.best, LegacyEncoding.windows1252);
    });

    test('a DOS file: code page 850', () {
      // "Grenzverlauf angenähert", "Brück": ä is 0x84 and ü is 0x81 in
      // code page 850. 0x81 is not defined in Windows-1252.
      final g = _guess([
        ['* Grenzverlauf angen', 0x84, 'hert'],
        ['AN Br', 0x81, 'ck'],
        ['AN M', 0x81, 'nchen'],
      ])!;
      expect(g.best, LegacyEncoding.dos850);
    });

    test('Cyrillic text: Windows-1251', () {
      // "Москва" in Windows-1251.
      final g = _guess([
        ['AN ', 0xCC, 0xEE, 0xF1, 0xEA, 0xE2, 0xE0],
      ])!;
      expect(g.best, LegacyEncoding.windows1251);
    });

    test('decodeLegacyLine shows the line in an encoding', () {
      final file = parseOpenAirBytes(_file([
        ['AN Ko', 0xE8, 'evje ', 0x9A],
      ]));
      final parts = file.invalidUtf8;
      expect(
          decodeLegacyLine(file.lineText(4), parts, LegacyEncoding.windows1250),
          'AN Kočevje š');
      expect(
          decodeLegacyLine(file.lineText(4), parts, LegacyEncoding.windows1252),
          'AN Koèevje š');
    });
  });

  group('file-invalid-utf8 message', () {
    List<Diagnostic> lint(List<int> bytes) =>
        Linter(LintOptions(rules: [findRule('file-invalid-utf8')!]))
            .lintBytes(bytes)
            .diagnostics;

    test('names the encoding and shows the line', () {
      final d = lint(_file([
        ['AN Ko', 0xE8, 'evje'],
        ['AN Bre', 0x9E, 'ice'],
        ['AN ', 0x8A, 'o', 0x9A, 'tanj'],
      ]));
      expect(d, hasLength(3));
      expect(
          d.first.message,
          contains('The file is probably saved as Windows-1250 (Central '
              'European). With this encoding, the line reads "AN '
              'Kočevje".'));
    });

    test('shows both readings when the guess is not certain', () {
      final d = lint(_file([
        ['AN FIS Pozna', 0xF1],
      ]));
      expect(d.single.message, contains('"AN FIS Poznań"'));
      expect(d.single.message, contains('"AN FIS Poznañ"'));
    });

    test('says when Windows-1250 gives the same text', () {
      final d = lint(_file([
        ['AN Br', 0xFC, 'ck'],
      ]));
      expect(
          d.single.message,
          contains('Windows-1252 (Western European). Windows-1250 (Central '
              'European) gives the same text.'));
    });

    test('--fix says the probable encoding', () {
      final r = fixBytes(
          Linter(),
          _file([
            ['AN Ko', 0xE8, 'evje'],
            ['AN Bre', 0x9E, 'ice'],
          ]));
      expect(r.notFixedReason, contains('Windows-1250 (Central European)'));
    });
  });
}
