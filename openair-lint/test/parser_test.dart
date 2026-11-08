import 'dart:convert';

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

void main() {
  group('lines', () {
    test('splits LF, CRLF and CR and keeps the endings', () {
      final f = parseOpenAir('a\nb\r\nc\rd');
      expect(f.lines, ['a', 'b', 'c', 'd']);
      expect(f.lineEndings,
          [LineEnding.lf, LineEnding.crlf, LineEnding.cr, LineEnding.none]);
    });

    test('a final line ending does not add an empty line', () {
      expect(parseOpenAir('a\n').lines, ['a']);
      expect(parseOpenAir('a\n\n').lines, ['a', '']);
      expect(parseOpenAir('').lines, isEmpty);
    });

    test('lineText is 1-based', () {
      expect(parseOpenAir('x\ny').lineText(2), 'y');
    });
  });

  group('encoding', () {
    test('valid UTF-8 without BOM', () {
      final f = parseOpenAirBytes(utf8.encode('AN Zürich\n'));
      expect(f.hasBom, isFalse);
      expect(f.encoding, TextEncoding.utf8);
      expect(f.invalidUtf8, isEmpty);
      expect(f.lines.single, 'AN Zürich');
    });

    test('UTF-8 BOM is detected and removed', () {
      final f = parseOpenAirBytes([0xEF, 0xBB, 0xBF, ...utf8.encode('AC D')]);
      expect(f.hasBom, isTrue);
      expect(f.lines.single, 'AC D');
      expect(f.airspaces, hasLength(1));
    });

    test('BOM in a Dart string is removed', () {
      final f = parseOpenAir('﻿AC D');
      expect(f.hasBom, isTrue);
      expect(f.airspaces.single.ac.column, 1);
    });

    test('invalid UTF-8 does not throw and is located', () {
      // Line 2 has a Latin-1 "é" (0xE9) at column 5.
      final bytes = [
        ...ascii.encode('AC D\nAN Ca'),
        0xE9,
        ...ascii.encode('n\nAH FL100\n'),
      ];
      final f = parseOpenAirBytes(bytes);
      expect(f.lines[1], 'AN Ca�n');
      expect(f.invalidUtf8, hasLength(1));
      final inv = f.invalidUtf8.single;
      expect(inv.line, 2);
      expect(inv.column, 6);
      expect(inv.byteOffset, 10);
      expect(inv.hex, 'E9');
      expect(f.airspaces.single.commands, hasLength(3));
    });

    test('byte offset of invalid UTF-8 is counted after a BOM', () {
      final f = parseOpenAirBytes([0xEF, 0xBB, 0xBF, 0x41, 0xFF]);
      expect(f.invalidUtf8.single.byteOffset, 1);
      expect(f.invalidUtf8.single.column, 2);
    });

    test('a truncated multi-byte sequence is one bad part', () {
      // E2 82 is the start of a 3-byte sequence (like the euro sign).
      final f = parseOpenAirBytes([0x41, 0xE2, 0x82, 0x42]);
      expect(f.lines.single, 'A�B');
      expect(f.invalidUtf8.single.bytes, [0xE2, 0x82]);
    });

    test('many invalid bytes on several lines', () {
      final f = parseOpenAirBytes([0xE9, 0x0A, 0x41, 0xE9, 0x0D, 0x0A, 0xFC]);
      expect(f.invalidUtf8.map((i) => '${i.line}:${i.column}'),
          ['1:1', '2:2', '3:1']);
    });

    test('UTF-16 LE with BOM is decoded', () {
      final units = 'AC D\n'.codeUnits;
      final bytes = [0xFF, 0xFE];
      for (final u in units) {
        bytes
          ..add(u & 0xFF)
          ..add(u >> 8);
      }
      final f = parseOpenAirBytes(bytes);
      expect(f.encoding, TextEncoding.utf16le);
      expect(f.lines.single, 'AC D');
    });
  });

  group('commands', () {
    test('keyword, argument and columns', () {
      final f = parseOpenAir('  DP  45:00:00N 014:00:00E   * corner \n');
      final c = f.allCommands.single;
      expect(c.keyword, 'DP');
      expect(c.column, 3);
      expect(c.argument, '45:00:00N 014:00:00E');
      expect(c.argumentColumn, 7);
      expect(c.endColumn, 27);
      expect(c.comment, ' corner ');
      expect(c.commentColumn, 30);
      expect(c.spacesAfterKeyword, 2);
      expect(c.keywordEndColumn, 5);
    });

    test('command without argument', () {
      final c = parseOpenAir('AC').allCommands.single;
      expect(c.argument, '');
      expect(c.argumentColumn, 3);
      expect(c.endColumn, 3);
    });

    test('comment directly after a command', () {
      final c = parseOpenAir('AA NONE*no times').allCommands.single;
      expect(c.argument, 'NONE');
      expect(c.comment, 'no times');
    });

    test('a star inside the argument starts a comment', () {
      final c = parseOpenAir('AN TMA *1').allCommands.single;
      expect(c.argument, 'TMA');
      expect(c.comment, '1');
    });

    test('keyword is kept as written; upperKeyword is upper case', () {
      final c = parseOpenAir('ah 1000 ft').allCommands.single;
      expect(c.keyword, 'ah');
      expect(c.upperKeyword, 'AH');
      expect(c.isUpperCaseKeyword, isFalse);
    });

    test('keyword without space is one unknown keyword', () {
      final c = parseOpenAir('AH5000FT').allCommands.single;
      expect(c.keyword, 'AH5000FT');
      expect(c.argument, '');
    });

    test('tabs are blanks', () {
      final c = parseOpenAir('AC\tD').allCommands.single;
      expect(c.keyword, 'AC');
      expect(c.argument, 'D');
      expect(c.argumentColumn, 4);
    });
  });

  group('airspace blocks', () {
    const text = '*VERSION: 3.0\n'
        '*WRITTEN_BY: test\n'
        'AN Orphan\n'
        '\n'
        'AC D\n'
        'AN One\n'
        '* comment\n'
        'DP 45:00:00N 014:00:00E\n'
        '\n'
        'ac c\n'
        'AN Two\n';

    test('blocks start at each AC (any case)', () {
      final f = parseOpenAir(text);
      expect(f.airspaces, hasLength(2));
      final a = f.airspaces[0];
      expect(a.index, 0);
      expect(a.startLine, 5);
      expect(a.endLine, 8);
      expect(a.name, 'One');
      expect(a.commands.map((c) => c.upperKeyword), ['AC', 'AN', 'DP']);
      final b = f.airspaces[1];
      expect(b.ac.keyword, 'ac');
      expect(b.startLine, 10);
      expect(b.label, '"Two" (line 10)');
    });

    test('commands before the first AC are outside any airspace', () {
      final f = parseOpenAir(text);
      expect(f.commandsOutsideAirspace.single.line, 3);
      expect(f.allCommands.map((c) => c.line), [3, 5, 6, 8, 10, 11]);
    });

    test('helpers find commands', () {
      final a = parseOpenAir('AC D\nAA NONE\nAA 2026-01-01T00:00Z/NONE\n')
          .airspaces
          .single;
      expect(a.commandsWith('AA'), hasLength(2));
      expect(a.firstWith('AA')!.line, 2);
      expect(a.firstWith('AH'), isNull);
      expect(a.label, 'airspace at line 1');
    });
  });

  group('header', () {
    test('reads version and written by', () {
      final f = parseOpenAir('*VERSION: 3.0\n*WRITTEN_BY: SeeYou\nAC D\n');
      final h = f.header;
      expect(h.endLine, 2);
      expect(h.versionValue, '3.0');
      expect(h.version!.line, 1);
      expect(h.version!.valueColumn, 11);
      expect(h.version!.isCanonical, isTrue);
      expect(h.writtenBy!.value, 'SeeYou');
      expect(h.writtenBy!.line, 2);
    });

    test('lenient forms are read, but are not canonical', () {
      final f = parseOpenAir('* version = 2.1  \nAC D\n');
      final v = f.header.version!;
      expect(v.key, 'version');
      expect(v.separator, '=');
      expect(v.value, '2.1');
      expect(v.keyColumn, 3);
      expect(v.isCanonical, isFalse);
    });

    test('other fields are kept', () {
      final f =
          parseOpenAir('*VERSION: 3.0\n*DATE: 2026-01-01\n* plain text\n');
      expect(f.header.fields.map((x) => x.upperKey), ['VERSION', 'DATE']);
      expect(f.header.endLine, 3);
    });

    test('header fields after the first command are late fields', () {
      final f = parseOpenAir('AC D\n*VERSION: 3.0\n*NOTE: x\n');
      expect(f.header.version, isNull);
      expect(f.header.endLine, 0);
      expect(f.lateHeaderFields.single.line, 2);
    });

    test('empty value', () {
      final v = parseOpenAir('*VERSION:').header.version!;
      expect(v.value, '');
      expect(v.valueColumn, 10);
    });
  });

  test('parser never throws on random bytes', () {
    var seed = 42;
    int next() => seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    for (var round = 0; round < 200; round++) {
      final bytes = List<int>.generate(next() % 300, (_) => next() % 256);
      final f = parseOpenAirBytes(bytes);
      expect(f.lines.length, f.lineEndings.length);
    }
  });
}
