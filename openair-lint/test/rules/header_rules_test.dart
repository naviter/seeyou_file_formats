import 'dart:convert';

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

import '../support/helpers.dart';

/// Lints [bytes] with only the rule [ruleId].
List<Diagnostic> lintRuleBytes(String ruleId, List<int> bytes) =>
    Linter(LintOptions(rules: [findRule(ruleId)!]))
        .lintBytes(bytes)
        .diagnostics;

/// The IDs of all rules of the header group, without header-version-draft.
///
/// header-version-draft reports every file with "*VERSION: 3.0" while
/// version 3.0 is a draft. Its own tests are in its group.
final Set<String> headerIds = {
  for (final g in ruleGroups)
    if (g.name == 'header') ...g.rules.map((r) => r.id)
}..remove('header-version-draft');

/// A second valid airspace (other name and geometry).
const String otherAirspace = 'AC C\n'
    'AY TMA\n'
    'AN Other TMA\n'
    'AH FL95\n'
    'AL 4500 FT AMSL\n'
    'V X=46:30:00N 014:30:00E\n'
    'DC 5\n';

void main() {
  test('a valid file has no header group diagnostics', () {
    final d = lintAll(withHeader(validAirspace + otherAirspace))
        .where((d) => headerIds.contains(d.ruleId))
        .toList();
    expect(d, isEmpty);
  });

  group('header-version-draft', () {
    const id = 'header-version-draft';
    test('reports *VERSION: 3.0 while 3.0 is a draft', () {
      expect(linesOf(id, withHeader(validAirspace)), [1]);
      expect(findRule(id)!.severity, Severity.info);
    });
    test('does not report other versions or a missing header', () {
      expect(linesOf(id, withHeader(validAirspace, version: '2.1')), isEmpty);
      expect(linesOf(id, validAirspace), isEmpty);
      expect(linesOf(id, validAirspace, target: SpecVersion.v3_0), isEmpty);
    });
  });

  test('header-version-missing says how to check the file as 2.1', () {
    final d = lintRule('header-version-missing', validAirspace).single;
    expect(d.message, contains('--target 2.1'));
    final with21 = lintRule('header-version-missing', validAirspace,
            target: SpecVersion.v2_1)
        .single;
    expect(with21.message, isNot(contains('--target')));
  });

  test('a valid 2.1 file has no header group diagnostics', () {
    final d = lintAll(withHeader(validAirspace, version: '2.1'))
        .where((d) => headerIds.contains(d.ruleId))
        .toList();
    expect(d, isEmpty);
  });

  // -------------------------------------------------------------------------
  // File and encoding
  // -------------------------------------------------------------------------

  group('file-not-utf8', () {
    const id = 'file-not-utf8';

    List<int> utf16le(String s) {
      final out = <int>[0xFF, 0xFE];
      for (final u in s.codeUnits) {
        out
          ..add(u & 0xFF)
          ..add(u >> 8);
      }
      return out;
    }

    test('reports a UTF-16 file', () {
      final d = lintRuleBytes(id, utf16le(withHeader(validAirspace)));
      expect(d, hasLength(1));
      expect(d.single.line, 1);
      expect(d.single.message, contains('UTF-16 LE'));
      expect(d.single.severity, Severity.error);
    });

    test('no diagnostic for UTF-8', () {
      expect(
          lintRuleBytes(id, utf8.encode(withHeader(validAirspace))), isEmpty);
    });

    /// [s] as UTF-16 bytes without a byte order mark.
    List<int> utf16NoBom(String s, {required bool littleEndian}) => [
          for (final u in s.codeUnits)
            ...(littleEndian ? [u & 0xFF, u >> 8] : [u >> 8, u & 0xFF])
        ];

    test('reports UTF-16 LE without a byte order mark', () {
      final bytes = utf16NoBom(withHeader(validAirspace), littleEndian: true);
      final d = lintRuleBytes(id, bytes);
      expect(d, hasLength(1));
      expect(d.single.line, 1);
      expect(d.single.message, contains('UTF-16 LE without a byte order'));
    });

    test('reports UTF-16 BE without a byte order mark', () {
      final bytes = utf16NoBom(withHeader(validAirspace), littleEndian: false);
      expect(lintRuleBytes(id, bytes).single.message,
          contains('UTF-16 BE without a byte order'));
    });

    test('UTF-16 without a byte order mark gives no other header problems', () {
      final bytes = utf16NoBom('${withHeader(validAirspace)}AN Grüße\n',
          littleEndian: true);
      final d = Linter()
          .lintBytes(bytes)
          .diagnostics
          .where((d) => headerIds.contains(d.ruleId))
          .map((d) => d.ruleId)
          .toList();
      expect(d, ['file-not-utf8']);
    });

    test('a few NUL characters are not UTF-16', () {
      final text = withHeader(validAirspace.replaceFirst('Test', 'Te\u0000st'));
      expect(lintRule(id, text), isEmpty);
    });
  });

  group('file-invalid-utf8', () {
    const id = 'file-invalid-utf8';

    test('reports one diagnostic per line with bad bytes', () {
      final bytes = [
        ...utf8.encode(withHeader('')),
        ...latin1.encode('AC D\nAN München ü\nAG Städt\n'),
      ];
      final d = lintRuleBytes(id, bytes);
      expect(d.map((d) => d.line), [4, 5]);
      expect(d[0].column, 5);
      expect(d[0].endColumn, 13);
      expect(d[0].message, contains('2 parts'));
      expect(d[1].message, contains('E4'));
    });

    test('no diagnostic for valid UTF-8', () {
      expect(lintRuleBytes(id, utf8.encode(withHeader('AC D\nAN München\n'))),
          isEmpty);
    });
  });

  group('file-replacement-character', () {
    const id = 'file-replacement-character';

    test('reports U+FFFD in the text', () {
      final d = lintRule(id, withHeader('AC D\nAN M�nchen �\n'));
      expect(d, hasLength(1));
      expect(d.single.line, 4);
      expect(d.single.column, 5);
      expect(d.single.severity, Severity.warning);
    });

    test('does not report bytes that are not valid UTF-8', () {
      final bytes = [
        ...utf8.encode(withHeader('AC D\n')),
        ...latin1.encode('AN München\n'),
      ];
      expect(lintRuleBytes(id, bytes), isEmpty);
    });
  });

  group('file-bom', () {
    const id = 'file-bom';

    test('reports a UTF-8 byte order mark as info', () {
      final d = lintRuleBytes(
          id, [0xEF, 0xBB, 0xBF, ...utf8.encode(withHeader(validAirspace))]);
      expect(d, hasLength(1));
      expect(d.single.severity, Severity.info);
      expect(d.single.line, 1);
    });

    test('a BOM in a string is also found', () {
      expect(linesOf(id, '﻿${withHeader(validAirspace)}'), [1]);
    });

    test('no diagnostic without a BOM', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
    });
  });

  group('file-mixed-line-endings', () {
    const id = 'file-mixed-line-endings';

    test('reports the first line with the less common ending', () {
      final text = withHeader(validAirspace).replaceAll('\n', '\r\n');
      final mixed = text.replaceFirst('AN Test CTR\r\n', 'AN Test CTR\n');
      final d = lintRule(id, mixed);
      expect(d, hasLength(1));
      expect(d.single.line, 5);
      expect(d.single.message, contains('11 CRLF, 1 LF'));
      expect(d.single.severity, Severity.info);
    });

    test('a last line without a line ending is not mixed', () {
      final text = withHeader(validAirspace).replaceAll('\n', '\r\n');
      expect(lintRule(id, '$text* end'), isEmpty);
    });

    test('no diagnostic for one kind of line ending', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
      expect(lintRule(id, withHeader(validAirspace).replaceAll('\n', '\r')),
          isEmpty);
    });
  });

  group('file-no-airspace', () {
    const id = 'file-no-airspace';

    test('reports an empty file', () {
      final d = lintRule(id, '');
      expect(d, hasLength(1));
      expect(d.single.message, contains('empty'));
    });

    test('reports a file with only comments', () {
      final d = lintRule(id, withHeader('* nothing here\n'));
      expect(d, hasLength(1));
      expect(d.single.message, contains('no airspace'));
    });

    test('reports a file with commands but no AC', () {
      expect(linesOf(id, withHeader('AN Lost name\n')), [1]);
    });

    test('no diagnostic for a file with an airspace', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
    });
  });

  group('file-garbled-text', () {
    const id = 'file-garbled-text';

    test('reports UTF-8 read as Windows-1252', () {
      final d = lintRule(id, withHeader('AC D\nAN MÃ¼nchen CTR\n'));
      expect(d, hasLength(1));
      expect(d.single.line, 4);
      expect(d.single.column, 5);
      expect(d.single.endColumn, 7);
      expect(d.single.message, contains('"ü"'));
      expect(d.single.severity, Severity.warning);
    });

    test('shows invisible characters in the message', () {
      // "Š" is C5 A0 in UTF-8. Read as Latin-1, it is "Å" and a no-break
      // space.
      final d = lintRule(id, withHeader('AC D\nAN TMA Å IAULIAI\n'));
      expect(d, hasLength(1));
      expect(d.single.message, contains('Å<U+00A0>'));
      expect(d.single.message, contains('"Š"'));
    });

    test('joins several garbled characters', () {
      // "ÓŁ" as UTF-8 (C3 93 C5 81) read as Windows-1252.
      final d = lintRule(id, withHeader('AG Ã“Å\u0081 RADIO\n'));
      expect(d.single.message, contains('"ÓŁ"'));
    });

    test('no diagnostic for normal names', () {
      expect(lintRule(id, withHeader('AC D\nAN München\nAG Wien\n')), isEmpty);
      expect(lintRule(id, withHeader('AC D\nAN Åland © 2026\n')), isEmpty);
    });

    test('comments are not checked', () {
      expect(lintRule(id, withHeader('AC D * MÃ¼nchen\n')), isEmpty);
    });

    test('a capital letter and an en dash are correct text', () {
      // "Ö–" is D6 96 in Windows-1252. As UTF-8, D6 96 is a Hebrew accent
      // (U+0596), which is not a probable character in a name.
      expect(lintRule(id, withHeader('AC D\nAN TMA MALMÖ–STURUP\n')), isEmpty);
      expect(lintRule(id, withHeader('AC D\nAN NIEDERÖ–LAND\n')), isEmpty);
      expect(lintRule(id, withHeader('AC D\nAN ZONE Ö¹\n')), isEmpty);
    });

    test('Cyrillic text read as Windows-1252 is reported', () {
      // "а" (U+0430) is D0 B0 in UTF-8: "Ð°" in Windows-1252.
      final d = lintRule(id, withHeader('AC D\nAN Ð°\n'));
      expect(d.single.message, contains('"а"'));
    });
  });

  group('file-strepla-block', () {
    const id = 'file-strepla-block';
    const block = '*\$STREPLA_ADDON BEGIN colortable\n'
        'AC A\n'
        'AN COLORENTRY\n'
        'SP 0 1 0x0000FF\n'
        'SB 0xFF000000\n'
        '*\$STREPLA_ADDON END\n';

    test('reports the block once', () {
      final d = lintRule(id, withHeader(block + validAirspace));
      expect(d, hasLength(1));
      expect(d.single.line, 3);
      expect(d.single.message, contains('lines 3 to 8'));
    });

    test('the airspaces in the block are not checked', () {
      final ids = lintAll(withHeader(block + validAirspace))
          .map((d) => d.ruleId)
          .toSet();
      expect(ids, contains(id));
      expect(ids, isNot(contains('airspace-ah-missing')));
      expect(ids, isNot(contains('airspace-geometry-missing')));
      expect(ids, isNot(contains('command-not-in-spec')));
    });

    test('no diagnostic without a block', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Header comments
  // -------------------------------------------------------------------------

  group('header-version-missing', () {
    const id = 'header-version-missing';

    test('no diagnostic when *VERSION is present', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
    });

    test('no diagnostic for version 2.1', () {
      expect(lintRule(id, withHeader(validAirspace, version: '2.1')), isEmpty);
    });

    test('reports line 1 when *VERSION is missing', () {
      final d = lintRule(id, '*WRITTEN_BY: test\n$validAirspace');
      expect(d, hasLength(1));
      expect(d.single.line, 1);
      expect(d.single.column, 1);
      expect(d.single.severity, Severity.error);
      expect(d.single.message, contains('checked as version 3.0'));
      expect(d.single.specUrl, endsWith('#header'));
    });

    test('reports an empty file', () {
      expect(linesOf(id, ''), [1]);
    });

    test('a *VERSION after the first command does not count', () {
      final d = lintRule(id, '$validAirspace*VERSION: 3.0\n');
      expect(d, hasLength(1));
      expect(d.single.message, contains('line 11'));
    });

    test('accepts *VERSION after other header comments', () {
      expect(
          lintRule(id, '* My airspace file\n\n*VERSION: 3.0\n$validAirspace'),
          isEmpty);
    });

    test('with --target, the message does not say which version is used', () {
      final d = lintRule(id, validAirspace, target: SpecVersion.v2_1);
      expect(d.single.message, isNot(contains('checked as version')));
    });

    test('a version line without ":" is reported on its own line', () {
      final d = lintRule(
          id, '* My file\n*VERSION 3.0\n*WRITTEN_BY: test\n$validAirspace');
      expect(d, hasLength(1));
      expect(d.single.line, 2);
      expect(d.single.message, contains('no ":"'));
    });

    test('a comment such as "* Version history" is not a version line', () {
      expect(linesOf(id, '* Version history:\n$validAirspace'), [1]);
    });

    test('a banner line "* Version: MAR26" is a normal comment', () {
      const banner = '*****************************************\n'
          '*      Version: MAR26 - SFVS-FSVV      *\n'
          '*****************************************\n';
      final d = lintRule(id, '$banner$validAirspace');
      expect(d, hasLength(1));
      expect(d.single.line, 1);
    });

    test('suggests version 2.1, because 3.0 is a draft', () {
      final d = lintRule(id, '*WRITTEN_BY: test\n$validAirspace');
      expect(d.single.message, contains('"*VERSION: 2.1"'));
      expect(d.single.message, contains('3.0 is still a draft'));
    });

    test('a version line without ":" suggests its own number', () {
      final d = lintRule(id, '*VERSION 2.1\n$validAirspace');
      expect(d.single.message, contains('"*VERSION: 2.1"'));
    });

    test('a late comment "* Version: updated ..." is not mentioned', () {
      final d =
          lintRule(id, '$validAirspace* Version: updated 2024-02-01 by John\n');
      expect(d.single.message, isNot(contains('line 11')));
    });
  });

  group('header-version-invalid', () {
    const id = 'header-version-invalid';

    test('reports a value that is not a number', () {
      final d = lintRule(id, '*VERSION: MAR26\n$validAirspace');
      expect(d, hasLength(1));
      expect(d.single.line, 1);
      expect(d.single.column, 11);
      expect(d.single.endColumn, 16);
      expect(d.single.message, contains('"MAR26"'));
      expect(d.single.message, contains('Data version'));
      expect(d.single.message, contains('checked as version 3.0'));
    });

    test('suggests the number inside the value', () {
      final d = lintRule(id, '*VERSION: V2.1\n$validAirspace');
      expect(d.single.message, contains('"*VERSION: 2.1"'));
      final d2 = lintRule(id, '*VERSION: OpenAir 2,1\n$validAirspace');
      expect(d2.single.message, contains('"*VERSION: 2.1"'));
    });

    test('a date does not give a wrong hint', () {
      final d = lintRule(id, '*VERSION: Data 14.03.2015\n$validAirspace');
      expect(d.single.message, isNot(contains('"*VERSION: 1')));
    });

    test('reports an empty value', () {
      final d = lintRule(id, '*VERSION:\n$validAirspace');
      expect(d, hasLength(1));
      expect(d.single.message, contains('no value'));
      expect(d.single.column, 2);
    });

    test('no diagnostic for version numbers', () {
      for (final v in ['3.0', '2.1', '2.0', '3.1', '3.0.0']) {
        expect(lintRule(id, '*VERSION: $v\n$validAirspace'), isEmpty,
            reason: v);
      }
    });

    test('no diagnostic without a version', () {
      expect(lintRule(id, validAirspace), isEmpty);
    });

    test('suggests 2.1 for a value with a clear number and other text', () {
      final d =
          lintRule(id, '*VERSION: 2.1 (generated 2026-01-01)\n$validAirspace');
      expect(d.single.message, contains('"*VERSION: 2.1"'));
    });

    test('suggests 3.0 for "3" and 2.1 for "2"', () {
      final d3 = lintRule(id, '*VERSION: 3\n$validAirspace');
      expect(d3.single.message, contains('"*VERSION: 3.0"'));
      expect(d3.single.message, contains('3.0 is still a draft'));
      expect(d3.single.message, isNot(contains('Data version')));
      final d2 = lintRule(id, '*VERSION: 2\n$validAirspace');
      expect(d2.single.message, contains('"*VERSION: 2.1"'));
      expect(d2.single.message, isNot(contains('draft')));
    });

    test('a text value suggests 2.1, not 3.0', () {
      final d = lintRule(id, '*VERSION: MAR26\n$validAirspace');
      expect(d.single.message, contains('"*VERSION: 2.1"'));
      expect(d.single.message, isNot(contains('for example "*VERSION: 3.0"')));
    });

    test('a free text "* Version:" comment is not the version', () {
      // The comment on line 1 is a data version. Line 2 is the header.
      const text = '* Version: 2024-03-01\n*VERSION: 2.1\n*WRITTEN_BY: x\n';
      expect(lintRule(id, '$text$validAirspace'), isEmpty);
    });

    test('the form of the specification is the version, also with text', () {
      expect(linesOf(id, '* Note\n*VERSION: 2024-03-01\n$validAirspace'), [2]);
    });
  });

  group('header-version-old', () {
    const id = 'header-version-old';

    test('reports 2.0 as info', () {
      final d = lintRule(id, withHeader(validAirspace, version: '2.0'));
      expect(d, hasLength(1));
      expect(d.single.severity, Severity.info);
      expect(d.single.message, contains('rules of version 2.1'));
    });

    test('reports 1.0', () {
      expect(linesOf(id, withHeader(validAirspace, version: '1.0')), [1]);
    });

    test('no diagnostic for 2.1, 3.0 and invalid values', () {
      for (final v in ['2.1', '3.0', 'abc', '3.1']) {
        expect(lintRule(id, withHeader(validAirspace, version: v)), isEmpty,
            reason: v);
      }
    });
  });

  group('header-version-unknown', () {
    const id = 'header-version-unknown';

    test('reports a version newer than 3.0', () {
      final d = lintRule(id, withHeader(validAirspace, version: '3.1'));
      expect(d, hasLength(1));
      expect(d.single.severity, Severity.warning);
      expect(d.single.message, contains('does not know version 3.1'));
    });

    test('reports a version between 2.1 and 3.0', () {
      final d = lintRule(id, withHeader(validAirspace, version: '2.5'));
      expect(d.single.message, contains('does not exist'));
    });

    test('reports a third number', () {
      final d = lintRule(id, withHeader(validAirspace, version: '3.0.0'));
      expect(d.single.message, contains('"3.0"'));
      expect(d.single.column, 11);
    });

    test('no diagnostic for 2.1, 3.0, 2.0 and invalid values', () {
      for (final v in ['2.1', '3.0', '2.0', 'abc']) {
        expect(lintRule(id, withHeader(validAirspace, version: v)), isEmpty,
            reason: v);
      }
    });
  });

  group('header-written-by-missing', () {
    const id = 'header-written-by-missing';

    test('reports a missing *WRITTEN_BY at the version line', () {
      final d = lintRule(id, '* file\n*VERSION: 3.0\n$validAirspace');
      expect(d, hasLength(1));
      expect(d.single.line, 2);
      expect(d.single.severity, Severity.error);
    });

    test('reports line 1 when there is no header', () {
      expect(linesOf(id, validAirspace), [1]);
    });

    test('a line such as "* Written by X" is reported on its own line', () {
      final d = lintRule(
          id, '*VERSION: 3.0\n* written by Example Club\n$validAirspace');
      expect(d.single.line, 2);
      expect(d.single.message, contains('"*WRITTEN_BY: Name"'));
    });

    test('is not reported on a "* Version:" banner line', () {
      final d = lintRule(id, '*   Version: MAR26   *\n$validAirspace');
      expect(d.single.line, 1);
      expect(d.single.column, 1);
      expect(d.single.endColumn, greaterThan(2));
    });

    test('mentions a *WRITTEN_BY after the first command', () {
      final d = lintRule(id, '*VERSION: 3.0\n$validAirspace*WRITTEN_BY: x\n');
      expect(d.single.message, contains('line 12'));
    });

    test('no diagnostic when present', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
    });
  });

  group('header-written-by-empty', () {
    const id = 'header-written-by-empty';

    test('reports an empty value', () {
      final d = lintRule(id, '*VERSION: 3.0\n*WRITTEN_BY:\n$validAirspace');
      expect(d, hasLength(1));
      expect(d.single.line, 2);
      expect(d.single.column, 2);
    });

    test('no diagnostic with a value or without the comment', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
      expect(lintRule(id, validAirspace), isEmpty);
    });
  });

  group('header-field-format', () {
    const id = 'header-field-format';

    test('reports a space after "*"', () {
      final d = lintRule(id, '* VERSION: 2.0\n*WRITTEN_BY: x\n$validAirspace');
      expect(d, hasLength(1));
      expect(d.single.line, 1);
      expect(d.single.message, contains('"*VERSION: 2.0"'));
      expect(d.single.message, contains('between "*" and "VERSION"'));
      expect(d.single.severity, Severity.warning);
    });

    test('reports lower case, "=" and a missing space', () {
      final d = lintRule(id, '*version=3.0\n*WRITTEN_BY:x\n$validAirspace');
      expect(d.map((d) => d.line), [1, 2]);
      expect(d[0].message, contains('upper case'));
      expect(d[0].message, contains('in place of "="'));
      expect(d[1].message, contains('one space after ":"'));
    });

    test('reports blanks before "*" and before ":"', () {
      final d = lintRule(id, '  *VERSION : 3.0\n$validAirspace');
      expect(d.single.message, contains('blanks before "*"'));
      expect(d.single.message, contains('blanks before ":"'));
    });

    test('no diagnostic for the canonical form, also with trailing blanks', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
      expect(lintRule(id, '*VERSION: 3.0  \n*WRITTEN_BY: x\t\n$validAirspace'),
          isEmpty);
    });

    test('a version value that is not a number is left to another rule', () {
      expect(lintRule(id, '*   Version: MAR26\n$validAirspace'), isEmpty);
    });

    test('other header keys are not checked', () {
      expect(lintRule(id, '*VERSION: 3.0\n* date = 2026\n$validAirspace'),
          isEmpty);
    });
  });

  group('header-field-duplicate', () {
    const id = 'header-field-duplicate';

    test('reports a second *VERSION with another value', () {
      final d =
          lintRule(id, '*VERSION: 3.0\n*VERSION: 2.1\n*WRITTEN_BY: x\nAC D\n');
      expect(d, hasLength(1));
      expect(d.single.line, 2);
      expect(d.single.message, contains('another value'));
    });

    test('reports a second *WRITTEN_BY', () {
      final d =
          lintRule(id, '*VERSION: 3.0\n*WRITTEN_BY: x\n*WRITTEN_BY: x\nAC D\n');
      expect(d.single.line, 3);
      expect(d.single.message, isNot(contains('another value')));
    });

    test('no diagnostic for one of each', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
    });

    test('a free text "* Version:" comment is not a second *VERSION', () {
      const text = '* Version: 2024-03-01\n*VERSION: 2.1\n*WRITTEN_BY: x\n';
      expect(lintRule(id, '$text$validAirspace'), isEmpty);
      const text2 = '*VERSION: 2.1\n* Version: MAR26\n*WRITTEN_BY: x\n';
      expect(lintRule(id, '$text2$validAirspace'), isEmpty);
    });

    test('a lenient second *VERSION with a number is reported', () {
      const text = '*VERSION: 2.1\n* version = 2.0\n*WRITTEN_BY: x\n';
      expect(linesOf(id, '$text$validAirspace'), [2]);
    });
  });

  group('header-after-first-command', () {
    const id = 'header-after-first-command';

    test('reports a *VERSION after the first command', () {
      final d =
          lintRule(id, '*WRITTEN_BY: x\nAC D\n*VERSION: 3.0\nAN Example\n');
      expect(d, hasLength(1));
      expect(d.single.line, 3);
      expect(d.single.message, contains('Move it to the top'));
      expect(d.single.severity, Severity.warning);
    });

    test('says when a joined file has another version', () {
      final d = lintRule(
          id, withHeader('$validAirspace*VERSION: 2.0\n$otherAirspace'));
      expect(d.single.message, contains('another version'));
    });

    test('says when the same header is repeated', () {
      final d = lintRule(
          id, withHeader('$validAirspace*WRITTEN_BY: openair-lint test\n'));
      expect(d.single.message, contains('another file'));
    });

    test('no diagnostic for a normal header', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
    });

    test('a normal comment that starts with "Version:" is not reported', () {
      final text = withHeader(validAirspace.replaceFirst(
          'AH ', '* Version: updated 2024-02-01 by John\nAH '));
      expect(lintRule(id, text), isEmpty);
    });

    test('a lenient late version with a number is reported', () {
      final text = withHeader('$validAirspace* version = 2.0\n');
      expect(linesOf(id, text), [13]);
    });
  });

  // -------------------------------------------------------------------------
  // Upper case
  // -------------------------------------------------------------------------

  group('case-not-upper-case', () {
    const id = 'case-not-upper-case';

    test('reports a lower case command', () {
      final d = lintRule(id, withHeader('ac D\n'));
      expect(d, hasLength(1));
      expect(d.single.line, 3);
      expect(d.single.column, 1);
      expect(d.single.endColumn, 3);
      expect(d.single.message, contains('"AC"'));
      expect(d.single.severity, Severity.error);
    });

    test('points to the first lower case letter of a command', () {
      final d = lintRule(id, withHeader('AC D\nAh 1000 ft AMSL\n'));
      expect(d.single.column, 2);
    });

    test('reports one diagnostic per line, at the first lower case letter', () {
      final d = lintRule(id, withHeader('AC D\nAH 1000 ft amsl\n'));
      expect(d, hasLength(1));
      expect(d.single.column, 9);
      expect(d.single.endColumn, 11);
      expect(d.single.message, contains('"ft"'));
      expect(d.single.message, contains('"FT"'));
    });

    test('checks coordinates, weekdays and variables', () {
      final text = withHeader('AC D\n'
          'DP 46:00:00n 014:00:00E\n'
          'AA Mon-Fri 07:00Z/15:00Z\n'
          'V x=46:00:00N 014:00:00E\n'
          'AA 2026-07-04t08:00Z/2026-07-04T16:00Z\n');
      expect(linesOf(id, text), [4, 5, 6, 7]);
      expect(lintRule(id, text)[1].message, contains('"Mon"'));
    });

    test('AN, AG and comments can use any case', () {
      expect(
          lintRule(
              id,
              withHeader('AC D * lower case comment\n'
                  'AN Lower case name\n'
                  'AG Wien Radar\n'
                  'AH FL95 * ok\n')),
          isEmpty);
    });

    test('commands that the specification does not define are not checked', () {
      expect(lintRule(id, withHeader('AC D\nSP abc\nnote here\n')), isEmpty);
    });

    test('version 2.1 has no upper case rule', () {
      expect(lintRule(id, withHeader('ac d\nAH 1000ft\n', version: '2.1')),
          isEmpty);
    });

    test('no diagnostic for a valid airspace', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Commands
  // -------------------------------------------------------------------------

  group('command-outside-airspace', () {
    const id = 'command-outside-airspace';

    test('reports commands before the first AC', () {
      final d = lintRule(id,
          withHeader('AN Example\nV X=46:00:00N 014:00:00E\n$validAirspace'));
      expect(d.map((d) => d.line), [3, 4]);
      expect(d.first.severity, Severity.error);
    });

    test('unknown and extra commands are left to other rules', () {
      expect(
          lintRule(id, withHeader('Hello\nSP 0 1 0\n$validAirspace')), isEmpty);
    });

    test('no diagnostic for comments and empty lines', () {
      expect(lintRule(id, withHeader('* comment\n\n$validAirspace')), isEmpty);
    });
  });

  group('command-unknown', () {
    const id = 'command-unknown';

    String msg(String line) =>
        lintRule(id, withHeader('AC D\n$line\n')).single.message;

    test('reports an unknown command', () {
      final d = lintRule(id, withHeader('AC D\nNote: changed\n'));
      expect(d, hasLength(1));
      expect(d.single.line, 4);
      expect(d.single.column, 1);
      expect(d.single.endColumn, 14);
      expect(d.single.message, contains('"Note:"'));
      expect(d.single.severity, Severity.error);
    });

    test('suggests a space after a known command', () {
      expect(msg('AH5000FT AMSL'), contains('space after "AH"'));
      expect(msg('DP46:00:00N 014:00:00E'), contains('space after "DP"'));
      expect(msg('VX=46:00:00N 014:00:00E'), contains('space after "V"'));
    });

    test('explains other comment characters', () {
      expect(msg('# NOTAMs'), contains('"*"'));
      expect(msg('// note'), contains('in place of "//"'));
    });

    test('explains a line that starts with a number', () {
      expect(msg('46:00:00N 014:00:00E'), contains('"DP"'));
    });

    test('explains a byte order mark inside the file', () {
      expect(msg('﻿AC D'), contains('byte order mark'));
    });

    test('no diagnostic for commands of the specification and extras', () {
      expect(lintRule(id, withHeader('$validAirspace' 'SP 0 1 0\nAI 123\n')),
          isEmpty);
    });

    test('lower case commands are known commands', () {
      expect(lintRule(id, withHeader('ac D\nan x\n')), isEmpty);
    });

    test('a "//" comment names "//" in the message', () {
      final d = lintRule(id, withHeader('// comment\n$validAirspace'));
      expect(d.single.message, contains('"//" does not start a comment'));
      expect(d.single.message, contains('in place of "//"'));
      final d2 = lintRule(id, withHeader('# comment\n$validAirspace'));
      expect(d2.single.message, contains('"#" does not start a comment'));
    });

    test('names a no-break space after the command', () {
      final d =
          lintRule(id, withHeader(validAirspace.replaceFirst('AN ', 'AN ')));
      expect(d, hasLength(1));
      expect(d.single.message, contains('no-break space (U+00A0)'));
      expect(d.single.message, contains('after "AN"'));
    });

    test('names a Unicode space after "V"', () {
      final d = lintRule(
          id, withHeader('${validAirspace}V X=46:00:00N 014:00:00E\n'));
      expect(d.single.message, contains('after "V"'));
      expect(d.single.message, contains('U+2009'));
    });

    test('shows invisible characters in the command', () {
      final d = lintRule(id, withHeader('XY abc\n$validAirspace'));
      expect(d.single.message, contains('"XY<U+00A0>abc"'));
    });
  });

  group('command-not-in-spec', () {
    const id = 'command-not-in-spec';

    test('reports each extra command once per file', () {
      final d = lintRule(
          id,
          withHeader('AC D\nSP 0 1 0\nSB 1\nAN X\nSP 0 1 0\n'
              'AC D\nSP 0 1 0\nAT 46:00:00N 014:00:00E\n'));
      expect(d.map((d) => d.line), [4, 5, 10]);
      expect(d.first.message, contains('3 lines with "SP"'));
      expect(d[1].message, isNot(contains('lines with')));
      expect(d.first.endColumn, 3);
      expect(d.first.severity, Severity.warning);
    });

    test('explains AR', () {
      final d = lintRule(id, withHeader('AC D\nAR 126.7\n'));
      expect(d.single.message, contains('Use "AF"'));
    });

    test('no diagnostic for a valid file', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Airspace blocks
  // -------------------------------------------------------------------------

  group('airspace-ah-missing and airspace-al-missing', () {
    test('reports a missing AH at the AC command', () {
      final text =
          withHeader(validAirspace.replaceFirst('AH 4500 FT AMSL\n', ''));
      final d = lintRule('airspace-ah-missing', text);
      expect(d, hasLength(1));
      expect(d.single.line, 3);
      expect(d.single.message, contains('upper limit'));
      expect(lintRule('airspace-al-missing', text), isEmpty);
    });

    test('reports a missing AL', () {
      final text = withHeader(validAirspace.replaceFirst('AL GND\n', ''));
      final d = lintRule('airspace-al-missing', text);
      expect(d.single.message, contains('a lower limit'));
    });

    test('lower case AH counts', () {
      final text = withHeader(validAirspace.replaceFirst('AH 4500', 'ah 4500'));
      expect(lintRule('airspace-ah-missing', text), isEmpty);
    });
  });

  group('airspace-ah-duplicate and airspace-al-duplicate', () {
    test('reports the second AH', () {
      final text = withHeader(
          validAirspace.replaceFirst('AL GND\n', 'AL GND\nAH FL95\n'));
      final d = lintRule('airspace-ah-duplicate', text);
      expect(d, hasLength(1));
      expect(d.single.line, 8);
      expect(d.single.message, contains('line 6'));
      expect(d.single.severity, Severity.error);
    });

    test('reports the second AL', () {
      final text = withHeader(
          validAirspace.replaceFirst('AL GND\n', 'AL GND\nAL 1000 FT AGL\n'));
      expect(linesOf('airspace-al-duplicate', text), [8]);
    });

    test('no diagnostic for one of each', () {
      expect(lintRule('airspace-ah-duplicate', withHeader(validAirspace)),
          isEmpty);
      expect(lintRule('airspace-al-duplicate', withHeader(validAirspace)),
          isEmpty);
    });
  });

  group('airspace-ac-missing', () {
    const id = 'airspace-ac-missing';

    /// A second airspace without its AC command (8 lines).
    const second = 'AN Second\n'
        'AH FL95\n'
        'AL 4500 FT AMSL\n'
        'DP 46:30:00N 014:00:00E\n'
        'DP 46:30:00N 014:10:00E\n'
        'DP 46:25:00N 014:10:00E\n'
        'DP 46:30:00N 014:00:00E\n';

    test('reports a missing AC between two airspaces', () {
      final d = lintRule(id, withHeader(validAirspace + second));
      expect(d, hasLength(1));
      expect(d.single.line, 13);
      expect(d.single.column, 1);
      expect(d.single.endColumn, 3);
      expect(d.single.severity, Severity.error);
      expect(d.single.message, contains('Lines 3 to 12'));
      expect(d.single.message, contains('"AN", "AH" and "AL"'));
    });

    test('the repeated commands are not reported as duplicates', () {
      final d = lintAll(withHeader(validAirspace + second))
          .where((d) => headerIds.contains(d.ruleId))
          .map((d) => '${d.line} ${d.ruleId}')
          .toList();
      expect(d, ['13 airspace-ac-missing']);
    });

    test(
        'the second airspace starts at the first A command after the '
        'geometry', () {
      // AF is new, so it is not repeated. But it belongs to the second
      // airspace.
      final d = lintRule(id, withHeader('${validAirspace}AF 123.500\n$second'));
      expect(d.single.line, 13);
      expect(d.single.message, contains('"AN", "AH" and "AL" come'));
    });

    test('one repeated command', () {
      final onlyName = second.replaceFirst('AH FL95\nAL 4500 FT AMSL\n', '');
      final d = lintRule(id, withHeader(validAirspace + onlyName));
      expect(d.single.message, contains('the command "AN" comes again'));
    });

    test('reports each missing AC in a block', () {
      final third = second.replaceAll('46:', '47:');
      expect(linesOf(id, withHeader(validAirspace + second + third)), [13, 20]);
    });

    test('a duplicate inside the second airspace is still reported', () {
      final text = withHeader(validAirspace +
          second.replaceFirst('AH FL95\n', 'AH FL95\nAH FL85\n'));
      expect(linesOf('airspace-ah-duplicate', text), [15]);
    });

    test('an AN before the next AC is not a missing AC', () {
      final text = withHeader('${validAirspace}AN Next\n$otherAirspace');
      expect(lintRule(id, text), isEmpty);
    });

    test('no diagnostic for a duplicate without more geometry', () {
      final text = withHeader('${validAirspace}AH FL95\n');
      expect(lintRule(id, text), isEmpty);
    });

    test('no diagnostic for valid airspaces', () {
      expect(lintRule(id, withHeader(validAirspace + otherAirspace)), isEmpty);
    });
  });

  group('airspace-geometry-missing', () {
    const id = 'airspace-geometry-missing';

    test('reports an airspace without D commands', () {
      final d = lintRule(
          id,
          withHeader(
              'AC D\nAN X\nAH FL95\nAL GND\nV X=46:00:00N 014:00:00E\n'));
      expect(d, hasLength(1));
      expect(d.single.line, 3);
    });

    test('no diagnostic for DP, DC or DY geometry', () {
      expect(lintRule(id, withHeader(validAirspace + otherAirspace)), isEmpty);
      expect(lintRule(id, withHeader('AC D\nV W=2\nDY 46:00:00N 014:00:00E\n')),
          isEmpty);
    });
  });

  group('airspace-attribute-duplicate', () {
    const id = 'airspace-attribute-duplicate';

    test('reports a second AN, AY, AG and AX as an error', () {
      // validAirspace has AY on line 4 and AN on line 5. The new lines are
      // inserted before AH (line 6).
      for (final (lines, duplicateLine) in [
        ('AN Other CTR', 6),
        ('AY TMA', 6),
        ('AG Test Tower\nAG Test Radar', 7),
        ('AX 7000\nAX 0424', 7),
      ]) {
        final text = withHeader(validAirspace.replaceFirst(
            'AH 4500 FT AMSL\n', '$lines\nAH 4500 FT AMSL\n'));
        final d = lintRule(id, text);
        expect(d, hasLength(1), reason: lines);
        expect(d.single.line, duplicateLine, reason: lines);
        expect(d.single.severity, Severity.error, reason: lines);
        expect(d.single.message, contains('at most one'), reason: lines);
      }
    });

    test('AF can be repeated', () {
      final text = withHeader(validAirspace.replaceFirst(
          'AN Test CTR\n', 'AN Test CTR\nAF 118.480\nAF 120.500\n'));
      expect(lintRule(id, text), isEmpty);
      expect(lintAll(text).where((d) => d.severity != Severity.info), isEmpty);
    });

    test('an AF after the geometry is reported by airspace-command-order', () {
      final text = withHeader(
          '${validAirspace.replaceFirst('AN Test CTR\n', 'AN Test CTR\nAF 118.480\n')}AF 120.500\n');
      expect(lintRule(id, text), isEmpty);
      expect(linesOf('airspace-command-order', text), [14]);
      expect(linesOf('airspace-ac-missing', text), isEmpty);
    });

    test('an AN written before the next AC gets a hint', () {
      final text = withHeader(
          '${validAirspace}AN Other TMA\n${otherAirspace.replaceFirst('AN Other TMA\n', '')}');
      final d = lintRule(id, text);
      expect(d.single.line, 13);
      expect(
          d.single.message,
          contains('next airspace, which starts on '
              'line 14'));
    });

    test('AA can be repeated', () {
      final text = withHeader(validAirspace.replaceFirst(
          'AL GND\n', 'AL GND\nAA MON 08:00Z/10:00Z\nAA TUE 08:00Z/10:00Z\n'));
      expect(lintRule(id, text), isEmpty);
    });

    test('no diagnostic for a valid airspace', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
    });
  });

  group('airspace-command-order', () {
    const id = 'airspace-command-order';

    test('reports the first A command after the geometry', () {
      final text = withHeader(
          'AC D\nAN X\nV X=46:00:00N 014:00:00E\nDC 5\nAH FL95\nAL GND\n');
      final d = lintRule(id, text);
      expect(d, hasLength(1));
      expect(d.single.line, 7);
      expect(d.single.endColumn, 3);
      expect(d.single.message, contains('starts on line 5'));
      expect(d.single.message, contains('1 more "A" command is'));
      expect(d.single.severity, Severity.warning);
    });

    test('a repeated command is left to the duplicate rules', () {
      final text = withHeader('AC D\nAN X\nAH FL95\nAL GND\n'
          'V X=46:00:00N 014:00:00E\nDC 5\nAN Y\n');
      expect(lintRule(id, text), isEmpty);
    });

    test('extra commands such as SP are not checked', () {
      expect(lintRule(id, withHeader('${validAirspace}SP 0 1 0\n')), isEmpty);
    });

    test('no diagnostic for the recommended order', () {
      expect(lintRule(id, withHeader(validAirspace + otherAirspace)), isEmpty);
    });
  });

  group('airspace-an-missing', () {
    const id = 'airspace-an-missing';

    test('reports an airspace without a name as an error', () {
      final d = lintRule(
          id, withHeader(validAirspace.replaceFirst('AN Test CTR\n', '')));
      expect(d, hasLength(1));
      expect(d.single.line, 3);
      expect(d.single.severity, Severity.error);
    });

    test('no diagnostic with a name', () {
      expect(lintRule(id, withHeader(validAirspace)), isEmpty);
    });

    test('does not check version 2.1 files', () {
      expect(
          lintRule(
              id,
              withHeader(validAirspace.replaceFirst('AN Test CTR\n', ''),
                  version: '2.1')),
          isEmpty);
    });
  });

  group('airspace-an-missing-v21', () {
    const id = 'airspace-an-missing-v21';

    test('reports an airspace without a name as info in version 2.1', () {
      final d = lintRule(
          id,
          withHeader(validAirspace.replaceFirst('AN Test CTR\n', ''),
              version: '2.1'));
      expect(d, hasLength(1));
      expect(d.single.line, 3);
      expect(d.single.severity, Severity.info);
    });

    test('does not check version 3.0 files', () {
      expect(
          lintRule(
              id, withHeader(validAirspace.replaceFirst('AN Test CTR\n', ''))),
          isEmpty);
    });
  });

  group('airspace-duplicate', () {
    const id = 'airspace-duplicate';

    test('reports the second copy at its AC command', () {
      final d = lintRule(
          id, withHeader(validAirspace + otherAirspace + validAirspace));
      expect(d, hasLength(1));
      expect(d.single.line, 20);
      expect(d.single.message, contains('line 3'));
      expect(d.single.severity, Severity.warning);
    });

    test('ignores case, blanks, comments and extra commands', () {
      final copy = validAirspace
          .replaceFirst('AN Test CTR', 'AN TEST  CTR * copy')
          .replaceFirst('AY CTR\n', 'AY CTR\nAI 12345\n');
      expect(linesOf(id, withHeader(validAirspace + copy)), [13]);
    });

    test('no diagnostic when one command is different', () {
      final other = validAirspace.replaceFirst('AH 4500', 'AH 5500');
      expect(lintRule(id, withHeader(validAirspace + other)), isEmpty);
      final other2 = validAirspace.replaceFirst(
          'DP 45:55:00N 014:00:00E', 'DP 45:54:00N 014:00:00E');
      expect(lintRule(id, withHeader(validAirspace + other2)), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Metadata
  // -------------------------------------------------------------------------

  test('all header rules are in the header group, with unique IDs', () {
    final group = ruleGroups.firstWhere((g) => g.name == 'header');
    expect(group.rules.map((r) => r.id).toSet(), hasLength(group.rules.length));
    expect(group.rules.length, greaterThanOrEqualTo(30));
  });

  test('only case-not-upper-case reports lower case in a valid airspace', () {
    final text = withHeader(validAirspace
        .replaceFirst('AC D', 'ac D')
        .replaceFirst('AH 4500 FT AMSL', 'AH 4500 ft amsl'));
    final d = lintAll(text)
        .where((d) => headerIds.contains(d.ruleId))
        .map((d) => '${d.line} ${d.ruleId}')
        .toList();
    expect(d, ['3 case-not-upper-case', '6 case-not-upper-case']);
  });
}
