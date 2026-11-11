/// Checks that the examples of the specification pass the linter.
///
/// The test reads every code block of `OpenAir_File_Format_Support.md` (in
/// the root of the repository), puts each example into a small valid
/// airspace, and lints it. An example must not produce an error or a
/// warning. Info diagnostics are allowed.
///
/// Blocks that only show the format of a command (for example `AC Class`)
/// are skipped. Examples that are expected to give an error or a warning
/// are listed in [_knownSpecProblems].
@TestOn('vm')
library;

import 'dart:io';

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

import 'support/example_wrapper.dart';

/// The specification file, relative to the package folder.
const String _specPath = '../OpenAir_File_Format_Support.md';

/// Examples of the specification that are expected to produce errors or
/// warnings. The key is the first line of the example. The value is the set
/// of rule ids that the example produces.
///
/// When a known problem in the specification is fixed, the test fails and
/// the entry must be removed.
const Map<String, Set<String>> _knownSpecProblems = {
  // The DY example. The specification says that DY "is not recommended",
  // so the dy-deprecated warning is correct.
  'V W=5': {'dy-deprecated'},
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
      // Geographic position: one space before the hemisphere letter.
      'DP 45:40:30 N 014:18:20 E|DP 45:40:30 N 014:28:20 E|'
          'DP 45:30:30 N 014:28:20 E|DP 45:40:30 N 014:18:20 E',
      'V X=46:00:00 N 014:00:00 E|DC 2',
      // Altitude and Supported Altitude References.
      'AH 300 FT AGL',
      'AH 1500 M AMSL',
      'AH 1500 FT AMSL',
      'AH 4500 FT AMSL|AL 300 M AGL',
      'AH 9500 FT STD',
      'AH FL95',
      'AH FL145|AL 1000 FT AMSL',
      'AH FL145|AL 1000 FT AGL',
      'AH FL145|AL 9500 FT STD',
      'AH UNL',
      'AL GND',
      // "A client can only compare the two limits when they use the same
      // kind of reference."
      'AH 1000 FT AGL|AL 2000 FT AMSL',
      // Time: the allowed forms.
      'AA 2026-07-04T08:00Z/2026-07-04T16:00Z',
      'AA 2026-07-04T08:00:00Z/2026-07-04T16:00:00Z',
      'AA 2026-12-25T00:00Z/2026-12-25T24:00Z',
      'AA 2026-12-25T00:00Z/2026-12-25T24:00:00Z',
      'AA 09:00:00Z/11:30:00Z',
      'AA 09:00Z/24:00:00Z',
      'AA MON 09:00Z/11:30Z 2026-12-25/2026-12-31',
      'AA MON 09:00Z/11:30Z',
      'AA MON-FRI 07:00Z/15:00Z',
      'AA FRI-MON 09:00Z/11:30Z',
      'AA MON,WED,FRI 09:00Z/11:30Z',
      'AA MON-FRI,SUN 09:00Z/11:30Z',
      'AA 09:00Z/11:30Z',
      'AA 09:00Z/24:00Z',
      'AA FRI 22:00Z/02:00Z',
      // "To end at midnight UTC, write 24:00Z of the day before."
      'AA 2026-07-04T18:00Z/2026-07-04T24:00Z',
      'AA FRI 22:00Z/24:00Z',
      'AA SR/SS',
      'AA 07:00Z/SS',
      'AA SS/SR',
      'AA BCMT/EECT',
      'AA SAT,SUN SR/SS',
      'AA MON 09:00Z/11:30Z 2026-03-29/2026-10-24',
      'AA MON 09:00Z/11:30Z 2026-04-01/NONE',
      'AA MON 09:00Z/11:30Z NONE/2026-10-31',
      'AA SUN 22:30Z/23:30Z',
      'AA MON-FRI 07:00Z/15:00Z|AA EXCEPT 2026-12-25',
      'AA MON-FRI 07:00Z/15:00Z|AA EXCEPT 2026-12-31/2027-01-01',
      // AS: the values of the command reference and of the text.
      'AS AIP',
      'AS NOTAM',
      'AS CUSTOM',
      'AS AIP+NOTAM',
      // "A restricted area that a NOTAM activates keeps AY R and has
      // AS AIP+NOTAM."
      'AY R|AS AIP+NOTAM',
      'AC D',
      'AC UNC|AY Q',
      'AN CTR Muenchen',
      'AX 7000',
      'AX 0424',
      // AF: channel names, and more than one AF.
      'AF 123.300',
      'AF 118.005',
      'AF 118.000',
      'AF 136.990',
      'AF 123.505',
      'AF 118.010',
      'AF 123.300|AF 118.005',
      // Comment syntax: a comment on its own line or after a command.
      '* A comment on its own line',
      'AH 4500 FT AMSL * comment after a command',
      // V: the values are reset at every AC, so each airspace sets X.
      'AC D|AN First|AH 4500 FT AMSL|AL GND|V X=46:00:00N 014:00:00E|DC 2|'
          'AC D|AN Second|AH 4500 FT AMSL|AL GND|'
          'V X=46:10:00N 014:00:00E|DC 2',
    ];
    for (final example in valid) {
      test(example, () {
        final text = wrapExample(example.split('|'));
        expect(_problems(text), isEmpty, reason: text);
      });
    }

    // The specification says that these examples are wrong. The value is
    // the rule id, or several rule ids separated by commas.
    const invalid = <String, String>{
      'AH 100 M AGL/423 M AMSL': 'altitude-multiple-values',
      'AL 100 M AGL/423 M AMSL': 'altitude-multiple-values',
      'AA MON-MON 09:00Z/11:30Z': 'aa-weekday-range-same-day',
      // "06:00Z/SR is wrong on days when sunrise is before 06:00 UTC."
      'AA 06:00Z/SR': 'aa-sun-event-order-changes',
      // "Version 3.0 does not allow AA NONE."
      'AA NONE': 'aa-none-removed',
      // AS: "Source is one of these values". Other values, also other
      // combinations, are not valid.
      'AS NOTAM+CUSTOM': 'as-unknown-source',
      'AS AIP + NOTAM': 'as-unknown-source',
      // "An airspace must not have more than one AS command."
      'AS AIP|AS NOTAM': 'airspace-attribute-duplicate',
      'AA 2026-07-04T08:00+01:00/2026-07-04T16:00+01:00': 'aa-time-zone-not-z',
      'AA 2026-07-04T08:00Z/SS': 'aa-sun-event-not-allowed',
      'AA EXCEPT 2026-12-25': 'aa-except-without-weekday',
      'AA MON 09:00Z/NONE': 'aa-none-not-allowed',
      'ac d': 'case-not-upper-case',
      'AH 1000 ft AMSL': 'case-not-upper-case',
      'AH 1000FT AMSL': 'altitude-unit-no-space',
      'AA MON,WED, FRI 09:00Z/11:30Z': 'aa-weekday-list-has-spaces',
      'AA mon 09:00Z/11:30Z': 'case-not-upper-case',
      'AA sr/SS': 'case-not-upper-case',
      'AA 2026-07-04t08:00z/2026-07-04T16:00Z': 'case-not-upper-case',
      'V X=46:00:00n 014:00:00e|DC 2': 'case-not-upper-case',
      // Altitude: "1000 AMSL and 1000 FT are not valid."
      'AH 1000 AMSL': 'altitude-unit-missing',
      'AH 1000 FT': 'altitude-reference-missing',
      // "MSL is an alias of AMSL. Writers should write AMSL."
      'AH 1500 FT MSL': 'altitude-msl-alias',
      // "FL 95 has the same meaning as FL95. Writers should write FL95."
      'AH FL 95': 'altitude-flight-level-space',
      // "The lower limit must be below the upper limit. A lower limit equal
      // to the upper limit is not valid." 9500 FT STD is the same as FL95.
      'AH 1000 FT AMSL|AL 1000 FT AMSL': 'altitude-lower-not-below-upper',
      'AH FL95|AL 9500 FT STD': 'altitude-lower-not-below-upper',
      // FL 95 is compared like FL95.
      'AH FL 95|AL FL95':
          'altitude-flight-level-space,altitude-lower-not-below-upper',
      // Time: "Only the forms in this table are allowed."
      'AA 20260704T0800Z/20260704T1600Z': 'aa-value-form-not-allowed',
      'AA MON 09:00Z/11:30Z 2026-W27-6/2026-W30-1': 'aa-value-form-not-allowed',
      'AA MON 09:00Z/11:30Z 2026-185/2026-200': 'aa-value-form-not-allowed',
      'AA 08:00:00.5Z/11:30Z': 'aa-value-form-not-allowed',
      'AA 08Z/11:30Z': 'aa-value-form-not-allowed',
      // Interval activation: "No other ISO 8601 interval form is allowed."
      'AA 2026-07-04T08:00Z/PT8H': 'aa-interval-form-not-allowed',
      // "An interval with the same start and end is not valid."
      'AA 2026-07-04T08:00Z/2026-07-04T08:00Z': 'aa-interval-end-before-start',
      // "24:00Z is allowed as an end time. It is not allowed as a start
      // time."
      'AA 24:00Z/02:00Z': 'aa-time-24-as-start',
      // "00:00Z is allowed as a start time. It is not allowed as an end
      // time." and "write FRI 22:00Z/24:00Z, not FRI 22:00Z/00:00Z".
      'AA 2026-07-04T18:00Z/2026-07-05T00:00Z': 'aa-time-00-as-end',
      'AA FRI 22:00Z/00:00Z': 'aa-time-00-as-end',
      // V: "A value from an earlier airspace is not used."
      'AC D|AN First|AH 4500 FT AMSL|AL GND|V X=46:00:00N 014:00:00E|DC 2|'
              'AC D|AN Second|AH 4500 FT AMSL|AL GND|DC 2':
          'geometry-center-missing',
      // Comment syntax: "the text after AN and AG cannot contain *".
      'AN ED-R6 Brokdorf * comment': 'an-contains-asterisk',
      'AG Nordholz Radar * comment': 'ag-contains-asterisk',
      // "An airspace can have at most one AN command" (also AY, AG, AX).
      'AN First|AN Second': 'airspace-attribute-duplicate',
      'AY RMZ|AY TMZ': 'airspace-attribute-duplicate',
      'AG Nordholz Radar|AG Bremen Radar': 'airspace-attribute-duplicate',
      'AX 7000|AX 0424': 'airspace-attribute-duplicate',
      // AX: "The digits 8 and 9 are not allowed."
      'AX 7080': 'ax-not-octal',
      // AF: "123.520 and 123.456 are not" channels.
      'AF 123.520': 'af-invalid-channel',
      'AF 123.456': 'af-invalid-channel',
      // AF: "Write the channel name, not the exact radio frequency."
      'AF 118.0083': 'af-not-three-decimals',
      'AF 123.3': 'af-not-three-decimals',
      'AF 117.950': 'af-outside-air-band',
      'AF 123.300 MHZ': 'af-invalid-format',
      // DC: "DC must be the only geometry command of its airspace."
      'V X=46:00:00N 014:00:00E|DC 2|DC 3': 'dc-mixed-with-other-geometry',
      // DB: "Both points must be at the same distance from the centre."
      'DP 46:00:00N 014:00:00E|V X=46:00:00N 014:00:00E|'
          'DB 46:10:00N 014:00:00E, 46:00:00N 014:16:00E|'
          'DP 46:00:00N 014:00:00E': 'db-radius-mismatch',
    };
    invalid.forEach((example, ruleIds) {
      test('$example is reported as $ruleIds', () {
        final text = wrapExample(example.split('|'));
        expect(_ruleIds(text), ruleIds.split(',').toSet(), reason: text);
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
      'AA NONE/2024-12-17T24:00Z',
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
      // AA NONE cannot be combined with other AA commands in version 2.1.
      'AA 2024-12-17T00:00Z/2024-12-17T10:00Z|AA NONE': 'aa-none-combined',
      // AS is new in version 3.0.
      'AS NOTAM': 'as-needs-version-3',
      // Version 2.1 says that intervals "must be sorted".
      'AA 2024-12-17T00:00Z/2024-12-17T10:00Z|'
              'AA 2023-12-16T12:00Z/2023-12-16T13:00Z':
          'aa-intervals-not-sorted-v21',
      // Version 2.1 did not limit the ISO 8601 forms. Version 3.0 allows
      // only some forms, so the other forms are warnings in version 2.1.
      'AA 2026-07-04T08:00Z/PT8H': 'aa-interval-form-not-allowed-v21',
      'AA 20260704T0800Z/20260704T1600Z': 'aa-value-form-not-allowed-v21',
      // The example of version 2.1 ends at 00:00Z. Version 3.0 allows only
      // 24:00Z of the day before, so this is a warning in version 2.1.
      'AA NONE/2024-12-18T00:00Z': 'aa-time-00-as-end-v21',
      // Version 2.1 only says that the DB arc is over-defined.
      'DP 46:00:00N 014:00:00E|V X=46:00:00N 014:00:00E|'
          'DB 46:10:00N 014:00:00E, 46:00:00N 014:16:00E|'
          'DP 46:00:00N 014:00:00E': 'db-radius-mismatch-v21',
    };
    invalid.forEach((example, ruleIds) {
      test('$example is reported as $ruleIds', () {
        final text = wrapExample(example.split('|'), version: '2.1');
        expect(_ruleIds(text), ruleIds.split(',').toSet(), reason: text);
      });
    });
  });
}
