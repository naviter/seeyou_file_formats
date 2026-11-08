// Runs all files in test/fixtures.
//
// These files test rules that are openair-lint checks, not requirements of
// the specification. For example: StrePla blocks, garbled text, a point
// that is repeated, or a fixed start time near the start of the local day.
// They are not in ../openair-conformance, because other validators do not
// have to report these problems.
//
// The format is the same as in ../openair-conformance:
// test/fixtures/<group>/<case>.openair and <case>.expected with
// "<line> <rule-id>" for each error and warning.

import 'dart:io';

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

import 'support/helpers.dart';

void main() {
  final files = Directory('test/fixtures')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.openair'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('the fixture folder has files', () {
    expect(files, isNotEmpty);
  });

  for (final f in files) {
    final segments = f.uri.pathSegments;
    final name = segments.skip(segments.length - 2).join('/');
    test(name, () {
      final expectedFile =
          File(f.path.replaceFirst(RegExp(r'\.openair$'), '.expected'));
      expect(expectedFile.existsSync(), isTrue,
          reason: '$name needs a .expected file');
      final expected = [
        for (final line in expectedFile.readAsLinesSync())
          if (line.trim().isNotEmpty && !line.startsWith('#')) line.trim()
      ]..sort();
      expect(expected, isNotEmpty,
          reason: '$name: the .expected file must list at least one problem');
      final result = Linter().lintBytes(f.readAsBytesSync());
      final actual = expectedFormat(result.diagnostics)..sort();
      expect(actual, expected,
          reason: '$name: all diagnostics:\n'
              '${result.diagnostics.map((d) => '  $d').join('\n')}');
    });
  }
}
