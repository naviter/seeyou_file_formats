// Runs all files in ../openair-conformance.
//
// valid/<group>/<case>.openair:   no error and no warning.
// invalid/<group>/<case>.openair: the errors and warnings are exactly the
//                                 lines of <case>.expected ("<line> <rule-id>").

import 'dart:io';

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

const conformanceDir = '../openair-conformance';

String _rel(File f) =>
    f.path.replaceAll('\\', '/').substring(conformanceDir.length + 1);

List<File> _cases(String kind) {
  final dir = Directory('$conformanceDir/$kind');
  if (!dir.existsSync()) return [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.openair'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

String _group(File f) => _rel(f).split('/')[1];

/// Reads a .expected file: one `<line> <rule-id>` per line.
List<String> readExpected(File f) {
  final result = <String>[];
  for (final raw in f.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length != 2 || int.tryParse(parts[0]) == null) {
      throw FormatException('Bad line in ${f.path}: "$raw"');
    }
    result.add('${int.parse(parts[0])} ${parts[1]}');
  }
  return result..sort(_byLineThenId);
}

int _byLineThenId(String a, String b) {
  final la = int.parse(a.split(' ')[0]);
  final lb = int.parse(b.split(' ')[0]);
  return la != lb ? la.compareTo(lb) : a.compareTo(b);
}

List<String> _actual(List<Diagnostic> diagnostics) => [
      for (final d in diagnostics)
        if (d.severity != Severity.info) '${d.line} ${d.ruleId}'
    ]..sort(_byLineThenId);

String _describe(List<Diagnostic> diagnostics) =>
    diagnostics.isEmpty ? '(none)' : diagnostics.map((d) => '  $d').join('\n');

/// Checks the common form of a conformance file.
///
/// The lines are read with the decoder of the linter, because some files
/// test the encoding (UTF-16 or bytes that are not valid UTF-8).
void _checkForm(File f) {
  final lines = parseOpenAirBytes(f.readAsBytesSync()).lines;
  final group = _group(f);
  if (group != 'header') {
    expect(lines.length, greaterThanOrEqualTo(3),
        reason: '${_rel(f)} is too short');
    expect(lines[0], anyOf('*VERSION: 3.0', '*VERSION: 2.1'),
        reason: '${_rel(f)}: line 1 must be the *VERSION header');
    expect(lines[1], '*WRITTEN_BY: openair-conformance',
        reason: '${_rel(f)}: line 2 must be *WRITTEN_BY: openair-conformance');
  }
  expect(lines.any((l) => l.startsWith('* Tests:')), isTrue,
      reason: '${_rel(f)} needs a "* Tests: ..." comment line');
}

void main() {
  final linter = Linter();

  test('the conformance folder exists', () {
    expect(Directory(conformanceDir).existsSync(), isTrue);
    expect(_cases('valid'), isNotEmpty);
    expect(_cases('invalid'), isNotEmpty);
  });

  group('valid', () {
    for (final f in _cases('valid')) {
      test(_rel(f), () {
        _checkForm(f);
        final result = linter.lintBytes(f.readAsBytesSync());
        final bad = result.diagnostics
            .where((d) => d.severity != Severity.info)
            .toList();
        expect(bad, isEmpty,
            reason: '${_rel(f)} must have no errors or warnings, but has:\n'
                '${_describe(bad)}');
      });
    }
  });

  group('invalid', () {
    for (final f in _cases('invalid')) {
      test(_rel(f), () {
        _checkForm(f);
        final expectedFile =
            File(f.path.replaceFirst(RegExp(r'\.openair$'), '.expected'));
        expect(expectedFile.existsSync(), isTrue,
            reason: '${_rel(f)} needs a .expected file');
        final expected = readExpected(expectedFile);
        expect(expected, isNotEmpty,
            reason: '${_rel(expectedFile)} must list at least one problem');
        final result = linter.lintBytes(f.readAsBytesSync());
        expect(_actual(result.diagnostics), expected,
            reason: '${_rel(f)}: the diagnostics do not match the '
                '.expected file. All diagnostics:\n'
                '${_describe(result.diagnostics)}');
      });
    }
  });

  test('every .expected file has an .openair file', () {
    final dir = Directory('$conformanceDir/invalid');
    for (final e in dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.expected'))) {
      final openair = e.path.replaceFirst(RegExp(r'\.expected$'), '.openair');
      expect(File(openair).existsSync(), isTrue,
          reason: '${_rel(e)} has no .openair file');
    }
  });

  test('every rule ID in .expected files exists', () {
    for (final f in _cases('invalid')) {
      final e = File(f.path.replaceFirst(RegExp(r'\.openair$'), '.expected'));
      if (!e.existsSync()) continue;
      for (final line in readExpected(e)) {
        final id = line.split(' ')[1];
        expect(findRule(id), isNotNull,
            reason: '${_rel(e)}: unknown rule ID "$id"');
      }
    }
  });
}
