import 'dart:io';

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

/// The GitHub anchors of all headings in the specification.
Set<String> specAnchors() {
  final spec = File('../OpenAir_File_Format_Support.md').readAsLinesSync();
  final anchors = <String>{};
  final counts = <String, int>{};
  var inCode = false;
  for (final line in spec) {
    if (line.trimLeft().startsWith('```')) inCode = !inCode;
    if (inCode) continue;
    final m = RegExp(r'^#{1,6}\s+(.*?)\s*#*\s*$').firstMatch(line);
    if (m == null) continue;
    final base = githubAnchor(m.group(1)!);
    final n = counts[base] ?? 0;
    counts[base] = n + 1;
    anchors.add(n == 0 ? base : '$base-$n');
  }
  return anchors;
}

/// The anchor that GitHub makes for a heading: lower case, punctuation
/// removed, spaces replaced by "-".
String githubAnchor(String heading) => heading
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
    .replaceAll(RegExp(r'\s'), '-');

void main() {
  test('githubAnchor', () {
    expect(githubAnchor('AA: Airspace Activation Times'),
        'aa-airspace-activation-times');
    expect(githubAnchor('AH: Upper Alitutde Limit'), 'ah-upper-alitutde-limit');
    expect(githubAnchor('AA commands a reader does not understand'),
        'aa-commands-a-reader-does-not-understand');
  });

  test('rule IDs are unique and kebab-case', () {
    final ids = <String>{};
    for (final r in allRules) {
      expect(ids.add(r.id), isTrue, reason: 'duplicate ID ${r.id}');
      expect(r.id, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)+$')));
      expect(r.id, isNot(internalErrorRuleId));
    }
  });

  test('every rule has complete metadata', () {
    for (final r in allRules) {
      expect(r.description.trim(), isNotEmpty, reason: r.id);
      expect(r.description.contains('\n'), isFalse,
          reason: '${r.id}: the description must be one line');
      expect(r.explanation.trim(), isNotEmpty, reason: r.id);
      expect(r.correctExample.trim(), isNotEmpty, reason: r.id);
      expect(r.incorrectExample.trim(), isNotEmpty, reason: r.id);
      expect(r.versions, isNotEmpty, reason: r.id);
      expect(r.correctExample, isNot(r.incorrectExample), reason: r.id);
    }
  });

  test('every spec anchor exists in the specification', () {
    final anchors = specAnchors();
    expect(anchors, contains('header'));
    for (final r in allRules) {
      if (r.anchorInVersion21Text) {
        expect(_anchors21, contains(r.specAnchor),
            reason: '${r.id}: anchor "${r.specAnchor}" is not a heading of '
                'the version 2.1 text');
        expect(r.specUrl, startsWith(specBaseUrl21));
        continue;
      }
      expect(r.specUrl, startsWith(specBaseUrl));
      expect(anchors, contains(r.specAnchor),
          reason: '${r.id}: anchor "${r.specAnchor}" is not a heading in '
              'OpenAir_File_Format_Support.md');
    }
  });

  test('findRule', () {
    expect(findRule('header-version-missing')!.severity, Severity.error);
    expect(findRule('no-such-rule'), isNull);
  });

  test('ruleGroups contain all rules once', () {
    final fromGroups = [for (final g in ruleGroups) ...g.rules];
    expect(fromGroups.length, allRules.length);
    expect(ruleGroups.map((g) => g.name),
        ['header', 'attributes', 'altitude', 'activation', 'geometry']);
  });

  test('packageVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(m!.group(1), packageVersion);
  });

  test('the public library has no dart:io (it must work on the web)', () {
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final path = f.path.replaceAll('\\', '/');
      if (path.contains('/cli/')) continue;
      expect(f.readAsStringSync(), isNot(contains("import 'dart:io'")),
          reason: '$path must not import dart:io');
    }
  });
}

/// The anchors of the headings of the version 2.1 text (tag v2.1.5, see
/// [specBaseUrl21]). The tag does not change, so this list does not change.
const Set<String> _anchors21 = {
  'seeyou-openair-file-format-specification',
  'units',
  'geographic-position',
  'altitude',
  'distance',
  'time',
  'header',
  'airspace-definition',
  'a-general-definitions',
  'ac-airspace-class',
  'an-airspace-name',
  'ay-airspace-type',
  'af-airspace-frequency',
  'ag-station-name',
  'aa-airspace-activation-times',
  'ax-transponder-code',
  'a-altitude-definitions',
  'ah-upper-alitutde-limit',
  'al-lower-alitutde-limit',
  'supported-altitude-references',
  'd-geometric-definitions',
  'dp-polygon-point',
  'da-arc-between-start-and-end-bearing',
  'db-arc-between-start-and-end-point',
  'dc-circular-area',
  'dy-airway-segment',
  'v-variable-assignment',
};
