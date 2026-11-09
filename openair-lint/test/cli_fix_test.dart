import 'dart:convert';
import 'dart:io';

import 'package:openair_lint/src/cli/cli.dart';
import 'package:test/test.dart';

import 'cli_test.dart' show Run, run, validText;

/// [validText] with two problems that have a fix: "MSL" and a second copy
/// of a point.
final String fixableText = validText
    .replaceFirst('4500 FT AMSL', '4500 FT MSL')
    .replaceFirst('DP 46:00:00N 014:10:00E\n',
        'DP 46:00:00N 014:10:00E\nDP 46:00:00N 014:10:00E\n');

void main() {
  late Directory tmp;
  late String path;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('openair_lint_fix_');
    path = '${tmp.path}/airspace.openair';
    File(path).writeAsStringSync(fixableText);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  String lastLine(Run r) => r.out.trim().split('\n').last;

  test('without --fix, the summary says how many problems have a fix', () {
    final r = run([path]);
    expect(r.out, contains('2 problems have an automatic fix.'));
    expect(File(path).readAsStringSync(), fixableText);
  });

  test('--fix saves the file and shows the problems that are left', () {
    final r = run(['--fix', path]);
    expect(r.code, exitOk);
    expect(File(path).readAsStringSync(), validText);
    expect(r.out, contains('airspace.openair: fixed 2 problems.'));
    expect(r.out, isNot(contains('[altitude-msl-alias]')));
    expect(r.out, contains('[header-version-draft]'));
    expect(lastLine(r), 'Fixed 2 problems in 1 file.');
  });

  test('--fix-dry-run shows a diff and does not change the file', () {
    final r = run(['--fix-dry-run', path]);
    expect(r.code, exitOk);
    expect(File(path).readAsStringSync(), fixableText);
    expect(r.out, contains('-AH 4500 FT MSL\n+AH 4500 FT AMSL\n'));
    expect(r.out, contains('\n-DP 46:00:00N 014:10:00E\n'));
    expect(lastLine(r),
        '--fix would fix 2 problems in 1 file. No file was changed.');
  });

  test('--fix-dry-run works with standard input', () {
    final r = run(['--fix-dry-run', '-'], stdinBytes: utf8.encode(fixableText));
    expect(r.code, exitOk);
    expect(r.out, contains('+AH 4500 FT AMSL'));
  });

  test('--fix with standard input is an error', () {
    final r = run(['--fix', '-'], stdinBytes: utf8.encode(fixableText));
    expect(r.code, exitUsage);
    expect(r.err, contains('--fix-dry-run'));
  });

  test('--fix and --fix-dry-run together are an error', () {
    final r = run(['--fix', '--fix-dry-run', path]);
    expect(r.code, exitUsage);
    expect(File(path).readAsStringSync(), fixableText);
  });

  test('the exit code is for the problems after the fixes', () {
    // Lower case is an error in version 3.0, but it has a fix.
    File(path).writeAsStringSync(
        fixableText.replaceFirst('AH 4500 FT MSL', 'AH 4500 FT msl'));
    expect(run([path]).code, exitLintFailed);
    expect(run(['--fix-dry-run', path]).code, exitOk);
  });

  test('JSON has the fix of each file', () {
    final r = run(['--fix-dry-run', '-f', 'json', path]);
    final json = jsonDecode(r.out) as Map<String, Object?>;
    final file = (json['files'] as List).single as Map<String, Object?>;
    final fix = file['fix'] as Map<String, Object?>;
    expect(fix['fixed'], 2);
    expect(fix['dryRun'], isTrue);
    expect(fix['changed'], isTrue);
    expect(
        fix['fixedByRule'], {'altitude-msl-alias': 1, 'dp-duplicate-point': 1});
    expect(fix['diff'], contains('+AH 4500 FT AMSL'));
    expect((json['summary'] as Map)['fixed'], 2);
  });

  test('a file with invalid UTF-8 is not changed', () {
    final bytes = [
      ...utf8.encode(fixableText),
      ...utf8.encode('* M'),
      0xFC,
      0x0A,
    ];
    File(path).writeAsBytesSync(bytes);
    final r = run(['--fix', path]);
    expect(File(path).readAsBytesSync(), bytes);
    expect(r.out, contains('not fixed'));
    expect(
        lastLine(r),
        'Fixed 0 problems in 0 files. '
        '1 file could not be fixed.');
  });

  test('--list-rules and --explain show the fix', () {
    expect(run(['--list-rules']).out,
        contains(RegExp(r'altitude-msl-alias +warning +2\.1, 3\.0  fix  ')));
    expect(run(['--list-rules']).out,
        contains(RegExp(r'altitude-gnd-in-ah +error +2\.1, 3\.0       ')));
    expect(run(['--explain', 'altitude-msl-alias']).out,
        contains('Automatic fix: --fix writes "AMSL"'));
    expect(run(['--explain', 'altitude-gnd-in-ah']).out,
        contains('Automatic fix: no'));
  });
}
