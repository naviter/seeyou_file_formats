/// Checks that the examples of the specification pass the linter.
///
/// The test reads every code block of `OpenAir_File_Format_Support.md` (in
/// the root of the repository), puts each example into a small valid
/// airspace, and lints it. An example must not produce an error or a
/// warning. Info diagnostics are allowed.
///
/// Blocks that only show the format of a command (for example `AC Class`)
/// are skipped. Known problems in the specification are listed in
/// [_knownSpecProblems]. When the specification is fixed, the test fails
/// and the entry must be removed.
@TestOn('vm')
library;

import 'dart:io';

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

import 'support/example_wrapper.dart';

/// The specification file, relative to the package folder.
const String _specPath = '../OpenAir_File_Format_Support.md';

/// Examples of the specification that are known to produce errors or
/// warnings. The key is the first line of the example. The value is the set
/// of rule ids that the example produces.
const Map<String, Set<String>> _knownSpecProblems = {
  // The DC example uses "AC Q". Q is an airspace type (danger area), not a
  // class. It should be "AC UNC" (or the real class) and "AY Q".
  'AC Q': {'ac-unknown-class'},
  // The centre of the DB example is not the centre of the arc. The first
  // point is 75.8 NM and the second point is 66.4 NM from the centre.
  'V X=39:13:00N 118:13:00W|DB': {'db-radius-mismatch'},
};

/// One code block of the specification.
class _Block {
  _Block(this.line, this.lines, this.isFormat);

  /// The line of the opening ``` in the Markdown file (1-based).
  final int line;
  final List<String> lines;

  /// True when the block only shows the format of a command.
  final bool isFormat;
}

/// Reads all fenced code blocks of [markdown].
List<_Block> _codeBlocks(List<String> markdown) {
  final blocks = <_Block>[];
  for (var i = 0; i < markdown.length; i++) {
    if (!markdown[i].trim().startsWith('```')) continue;
    final start = i;
    // The text before the block tells if it is a format block:
    // "Format:", "It has this form:", "It has one of these forms:".
    var before = start - 1;
    while (before >= 0 && markdown[before].trim().isEmpty) {
      before--;
    }
    final intro = before >= 0 ? markdown[before].trim() : '';
    final isFormat = RegExp(r'(Format|forms?):$').hasMatch(intro);
    final lines = <String>[];
    i++;
    while (i < markdown.length && markdown[i].trim() != '```') {
      lines.add(markdown[i]);
      i++;
    }
    blocks.add(_Block(start + 1, lines, isFormat));
  }
  return blocks;
}

/// Splits a block into examples. The specification separates examples with
/// a line "----" or "or".
List<List<String>> _examples(List<String> lines) {
  final result = <List<String>>[[]];
  for (final line in lines) {
    final t = line.trim();
    if (t == '----' || t == 'or') {
      result.add([]);
    } else if (t.isNotEmpty) {
      result.last.add(line);
    }
  }
  return [
    for (final e in result)
      if (e.isNotEmpty) e
  ];
}

/// The errors and warnings of [text], as readable strings.
List<String> _problems(String text, {SpecVersion? target}) => [
      for (final d
          in Linter(LintOptions(target: target)).lintString(text).diagnostics)
        if (d.severity != Severity.info)
          '${d.line}:${d.column} ${d.severity.label} [${d.ruleId}] '
              '${d.message}'
    ];

Set<String> _ruleIds(String text, {SpecVersion? target}) => {
      for (final d
          in Linter(LintOptions(target: target)).lintString(text).diagnostics)
        if (d.severity != Severity.info) d.ruleId
    };

/// The key of [example] in [_knownSpecProblems], or null.
String? _knownProblemKey(List<String> example) {
  for (final key in _knownSpecProblems.keys) {
    final parts = key.split('|');
    if (parts.length > example.length) continue;
    var match = true;
    for (var i = 0; i < parts.length; i++) {
      if (!example[i].trim().startsWith(parts[i])) match = false;
    }
    if (match) return key;
  }
  return null;
}

void main() {
  final specFile = File(_specPath);
  final blocks = _codeBlocks(specFile.readAsLinesSync());

  test('the specification has code blocks', () {
    expect(blocks.where((b) => !b.isFormat).length, greaterThan(15));
    expect(blocks.where((b) => b.isFormat).length, greaterThan(10));
  });

  final usedKnownProblems = <String>{};

  group('spec code blocks', () {
    for (final block in blocks) {
      if (block.isFormat) continue;
      for (final example in _examples(block.lines)) {
        final name = 'line ${block.line}: ${example.first.trim()}';
        final knownKey = _knownProblemKey(example);
        if (knownKey != null) usedKnownProblems.add(knownKey);

        test(name, () {
          final text = wrapExample(example);
          if (knownKey != null) {
            expect(_ruleIds(text), _knownSpecProblems[knownKey],
                reason: 'This example has a known problem in the '
                    'specification. If the specification is fixed, remove '
                    'the entry from _knownSpecProblems.\n$text');
          } else {
            expect(_problems(text), isEmpty, reason: text);
          }
        });

        // A list of AA commands: each command is also an example alone.
        // AA EXCEPT needs a weekday command, so it is not checked alone.
        final isAaList =
            example.length > 1 && example.every((l) => keywordOf(l) == 'AA');
        if (isAaList) {
          for (final line in example) {
            if (line.trim().toUpperCase().startsWith('AA EXCEPT')) continue;
            test('$name / alone: ${line.trim()}', () {
              final text = wrapExample([line]);
              expect(_problems(text), isEmpty, reason: text);
            });
          }
        }
      }
    }
  });

  test('every known spec problem is still in the specification', () {
    expect(usedKnownProblems, _knownSpecProblems.keys.toSet());
  });

  group('spec format blocks', () {
    // A format block uses placeholders such as "Class" or "Point". The
    // linter must report them, so this checks that the test really skips
    // only format blocks.
    // Any text is a valid name, so "AN Name" and "AG Station Name" are not
    // reported.
    for (final block in blocks.where((b) => b.isFormat)) {
      final first = block.lines.first.trim();
      if (first == 'AN Name' || first == 'AG Station Name') continue;
      test('line ${block.line}: $first is reported', () {
        expect(_problems(wrapExample(block.lines)), isNotEmpty);
      });
    }
  });

  group('examples in the text of the specification (3.0)', () {
    // These examples are written inside sentences of the specification.
    const valid = <String>[
      'DP 45:40:30N 014:18:20E|DP 45:40:30N 014:28:20E|'
          'DP 45:30:30N 014:28:20E|DP 45:40:30N 014:18:20E',
      'DP 45:40.500N 014:18.333E|DP 45:40.500N 014:28.333E|'
          'DP 45:30.500N 014:28.333E|DP 45:40.500N 014:18.333E',
      'AH 300 FT AGL',
      'AH 1500 M AMSL',
      'AH FL145|AL 1000 FT AMSL',
      'AH UNL',
      'AL GND',
      'AA 2026-07-04T08:00Z/2026-07-04T16:00Z',
      'AA 2026-12-25T00:00Z/2026-12-25T24:00Z',
      'AA MON 09:00Z/11:30Z',
      'AA MON-FRI 07:00Z/15:00Z',
      'AA FRI-MON 09:00Z/11:30Z',
      'AA MON,WED,FRI 09:00Z/11:30Z',
      'AA MON-FRI,SUN 09:00Z/11:30Z',
      'AA 09:00Z/11:30Z',
      'AA 09:00Z/24:00Z',
      'AA FRI 22:00Z/02:00Z',
      'AA SR/SS',
      'AA 07:00Z/SS',
      'AA SS/SR',
      'AA MON 09:00Z/11:30Z 2026-03-29/2026-10-24',
      'AA MON 09:00Z/11:30Z 2026-04-01/NONE',
      'AA MON 09:00Z/11:30Z NONE/2026-10-31',
      'AA SUN 22:30Z/23:30Z',
      'AA MON-FRI 07:00Z/15:00Z|AA EXCEPT 2026-12-25',
      'AA MON-FRI 07:00Z/15:00Z|AA EXCEPT 2026-12-31/2027-01-01',
      'AA NONE',
      'AC D',
      'AC UNC|AY Q',
      'AN CTR Muenchen',
      'AX 7000',
    ];
    for (final example in valid) {
      test(example, () {
        final text = wrapExample(example.split('|'));
        expect(_problems(text), isEmpty, reason: text);
      });
    }

    // The specification says that these examples are wrong.
    const invalid = <String, String>{
      'AH 100 M AGL/423 M AMSL': 'altitude-multiple-values',
      'AL 100 M AGL/423 M AMSL': 'altitude-multiple-values',
      'AA MON-MON 09:00Z/11:30Z': 'aa-weekday-range-same-day',
      // "06:00Z/SR is wrong on days when sunrise is before 06:00 UTC."
      'AA 06:00Z/SR': 'aa-sun-event-order-changes',
      'AA MON 09:00Z/11:30Z|AA NONE': 'aa-none-combined',
      'AA 2026-07-04T08:00+01:00/2026-07-04T16:00+01:00': 'aa-time-zone-not-z',
      'AA 2026-07-04T08:00Z/SS': 'aa-sun-event-not-allowed',
      'AA EXCEPT 2026-12-25': 'aa-except-without-weekday',
      'AA MON 09:00Z/NONE': 'aa-none-not-allowed',
      'ac d': 'case-not-upper-case',
      'AH 1000 ft AMSL': 'case-not-upper-case',
      'AH 1000FT AMSL': 'altitude-unit-no-space',
      'AA MON,WED, FRI 09:00Z/11:30Z': 'aa-weekday-list-has-spaces',
      // These forms are allowed, but "Writers should use the recommended
      // form" (Time) and "the StartDateTime/EndDateTime form" (Interval
      // activation). So they are warnings.
      'AA 2026-07-04T08:00Z/PT8H': 'aa-interval-not-recommended-form',
      'AA 2026-07-04T08:00:00Z/2026-07-04T16:00:00Z':
          'aa-value-not-recommended-form',
      'AA 20260704T0800Z/20260704T1600Z': 'aa-value-not-recommended-form',
    };
    invalid.forEach((example, ruleId) {
      test('$example is reported as $ruleId', () {
        final text = wrapExample(example.split('|'));
        expect(_ruleIds(text), {ruleId}, reason: text);
      });
    });
  });

  group('examples of the specification version 2.1', () {
    // Version 2.1 wrote altitudes in lower case and without a space, for
    // example "1000ft AMSL". These must stay valid in version 2.1 files.
    const valid = <String>[
      'AH FL145|AL 1000ft AMSL',
      'AH FL145|AL 1000ft AGL',
      'AH 300ft AGL',
      'AH 1500m AMSL',
      'AA 2023-12-16T12:00Z/2023-12-16T13:00Z|'
          'AA 2024-12-17T00:00Z/2024-12-17T24:00Z',
      'AA 2024-12-17T00:00Z/NONE',
      'AA NONE/2024-12-18T00:00Z',
      'AA NONE',
    ];
    for (final example in valid) {
      test(example, () {
        final text = wrapExample(example.split('|'), version: '2.1');
        expect(_problems(text), isEmpty, reason: text);
      });
    }

    const invalid = <String, String>{
      'AH 100m AGL/423m AMSL': 'altitude-multiple-values',
      'AA MON 09:00Z/11:30Z': 'aa-needs-version-3',
      // Version 2.1 says that intervals "must be sorted".
      'AA 2024-12-17T00:00Z/2024-12-17T10:00Z|'
              'AA 2023-12-16T12:00Z/2023-12-16T13:00Z':
          'aa-intervals-not-sorted-v21',
    };
    invalid.forEach((example, ruleId) {
      test('$example is reported as $ruleId', () {
        final text = wrapExample(example.split('|'), version: '2.1');
        expect(_ruleIds(text), {ruleId}, reason: text);
      });
    });
  });
}
