import 'dart:convert';
import 'dart:io';

import 'package:openair_lint/openair_lint.dart';
import 'package:openair_lint/src/cli/cli.dart';
import 'package:openair_lint/src/cli/output.dart' show visibleText;
import 'package:test/test.dart';

const validText = '*VERSION: 3.0\n'
    '*WRITTEN_BY: test\n'
    'AC D\n'
    'AY CTR\n'
    'AN Test CTR\n'
    'AH 4500 FT AMSL\n'
    'AL GND\n'
    'DP 46:00:00N 014:00:00E\n'
    'DP 46:00:00N 014:10:00E\n'
    'DP 45:55:00N 014:10:00E\n'
    'DP 45:55:00N 014:00:00E\n'
    'DP 46:00:00N 014:00:00E\n';

/// The valid text without the *VERSION line: one header-version-missing.
final missingVersionText = validText.substring('*VERSION: 3.0\n'.length);

class Run {
  Run(this.code, this.out, this.err);
  final int code;
  final String out;
  final String err;
}

Run run(List<String> args, {List<int>? stdinBytes}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = CliRunner(
    out: out,
    err: err,
    color: false,
    readStdin: () => stdinBytes ?? const [],
  ).run(args);
  return Run(code, out.toString(), err.toString());
}

void main() {
  late Directory tmp;
  late String valid;
  late String invalid;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('openair_lint_cli_');
    valid = '${tmp.path}/valid.openair';
    invalid = '${tmp.path}/sub/invalid.txt';
    File(valid).writeAsStringSync(validText);
    File(invalid)
      ..createSync(recursive: true)
      ..writeAsStringSync(missingVersionText);
    File('${tmp.path}/sub/ignored.md').writeAsStringSync('not openair');
    File('${tmp.path}/.hidden/x.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync(missingVersionText);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  String slash(String p) => p.replaceAll('\\', '/');

  test('valid file: exit 0 and a summary', () {
    final r = run([valid]);
    expect(r.code, exitOk);
    // The info is header-version-draft: version 3.0 is still a draft.
    expect(r.out, contains('[header-version-draft]'));
    expect(r.out.trim().split('\n').last,
        'Checked 1 file: 0 errors, 0 warnings, 1 info.');
  });

  test('a file with another extension gets file-extension-not-openair', () {
    final other = '${tmp.path}/airspace.dat';
    File(other).writeAsStringSync(validText);
    final r = run([other]);
    expect(r.code, exitOk);
    expect(r.out, contains('warning [file-extension-not-openair]'));
    expect(r.out, contains('".dat"'));
    // .openair and .txt are not reported, and stdin has no name.
    expect(run([valid]).out, isNot(contains('file-extension')));
    expect(run(['-'], stdinBytes: validText.codeUnits).out,
        isNot(contains('file-extension')));
  });

  test('control characters from the file are shown in a visible form', () {
    final esc = '${tmp.path}/esc.openair';
    File(esc).writeAsStringSync(validText.replaceFirst(
        'DP 46:00:00N 014:10:00E\n',
        'DP 46:00:00N 014:10:00E \x1B]0;title\x07\x1B[2J\n'));
    for (final format in ['text', 'github']) {
      final r = run(['--format', format, esc]);
      expect(r.out, isNot(contains('\x1B')), reason: format);
      expect(r.out, isNot(contains('\x07')), reason: format);
      expect(r.out, contains(r'\x1B]0;title\x07\x1B[2J'), reason: format);
    }
  });

  test('visibleText', () {
    expect(visibleText('a\tb'), 'a\tb');
    expect(visibleText('a\x1Bb'), r'a\x1Bb');
    expect(visibleText('a\u202Eb'), r'a\u{202E}b');
    expect(visibleText('a\x9Bb'), r'a\x9Bb');
    expect(visibleText('Ljubljana ü'), 'Ljubljana ü');
  });

  test('invalid file: exit 1 and the text format', () {
    final r = run([invalid]);
    expect(r.code, exitLintFailed);
    final lines = r.out.trim().split('\n');
    expect(lines.first,
        startsWith('${slash(invalid)}:1:1: error [header-version-missing] '));
    expect(lines.last, 'Checked 1 file: 1 error, 0 warnings, 0 info.');
  });

  test('directories are searched for .openair and .txt, not hidden folders',
      () {
    final r = run([tmp.path]);
    expect(r.code, exitLintFailed);
    expect(r.out, contains('Checked 2 files'));
    expect(r.out, isNot(contains('.hidden')));
  });

  test('--disable', () {
    final r = run(['--disable', 'header-version-missing', invalid]);
    expect(r.code, exitOk);
  });

  test('--disable with an unknown rule is a usage error', () {
    final r = run(['--disable', 'no-such-rule', invalid]);
    expect(r.code, exitUsage);
    expect(r.err, contains('Unknown rule ID "no-such-rule"'));
  });

  test('--min-severity hides lower severities', () {
    // header-version-missing is an error, so it is still shown.
    expect(run(['--min-severity', 'error', invalid]).code, exitLintFailed);
  });

  test('--format json', () {
    final r = run(['--format', 'json', valid, invalid]);
    expect(r.code, exitLintFailed);
    final json = jsonDecode(r.out) as Map<String, Object?>;
    expect(json['version'], packageVersion);
    final files = json['files'] as List<Object?>;
    expect(files, hasLength(2));
    final second = files[1] as Map<String, Object?>;
    expect(second['path'], slash(invalid));
    expect(second['specVersion'], '3.0');
    final d =
        (second['diagnostics'] as List<Object?>).single as Map<String, Object?>;
    expect(
        d.keys,
        containsAll(<String>[
          'line',
          'column',
          'endColumn',
          'severity',
          'rule',
          'message',
          'specUrl'
        ]));
    expect(d['rule'], 'header-version-missing');
    expect(d['severity'], 'error');
    expect(
        json['summary'], {'files': 2, 'errors': 1, 'warnings': 0, 'info': 1});
  });

  test('--format github', () {
    final r = run(['--format', 'github', invalid]);
    final first = r.out.split('\n').first;
    expect(
        first,
        startsWith('::error file=${slash(invalid).replaceAll(':', '%3A')},'
            'line=1,col=1,title=header-version-missing::'));
    expect(first, contains('%0Ahttps://'));
  });

  test('--target 2.1 changes the spec version', () {
    final r = run(['--format', 'json', '--target', '2.1', valid]);
    final json = jsonDecode(r.out) as Map<String, Object?>;
    final file =
        (json['files'] as List<Object?>).single as Map<String, Object?>;
    expect(file['specVersion'], '2.1');
  });

  test('--fail-on warning', () {
    expect(run(['--fail-on', 'warning', valid]).code, exitOk);
  });

  test('--list-rules', () {
    final r = run(['--list-rules']);
    expect(r.code, exitOk);
    expect(r.out, contains('header-version-missing'));
    final j = run(['--list-rules', '--format', 'json']);
    final list = jsonDecode(j.out) as List<Object?>;
    expect(list.length, allRules.length);
  });

  test('--explain', () {
    final r = run(['--explain', 'header-version-missing']);
    expect(r.code, exitOk);
    expect(r.out, contains('Severity: error'));
    expect(r.out, contains('Incorrect:'));
    expect(r.out, contains('#header'));
    expect(run(['--explain', 'nope']).code, exitUsage);
  });

  test('--version and --help', () {
    expect(run(['--version']).out.trim(), 'openair-lint $packageVersion');
    final h = run(['--help']);
    expect(h.code, exitOk);
    expect(h.out, contains('Usage: openair-lint'));
    expect(h.out, contains('--[no-]color'));
  });

  test('usage errors', () {
    expect(run([]).code, exitUsage);
    expect(run(['--target', '9.9', valid]).code, exitUsage);
    expect(run(['--bogus']).code, exitUsage);
  });

  test('a missing file is exit 2, other files are still checked', () {
    final r = run(['${tmp.path}/nope.openair', valid]);
    expect(r.code, exitUsage);
    expect(r.err, contains('does not exist'));
    expect(r.out, contains('Checked 1 file'));
  });

  test('standard input', () {
    final r = run(['-'], stdinBytes: utf8.encode(missingVersionText));
    expect(r.code, exitLintFailed);
    expect(r.out, startsWith('<stdin>:1:1: error'));
  });

  test('colour codes only with --color', () {
    final out = StringBuffer();
    CliRunner(out: out, err: StringBuffer()).run(['--color', invalid]);
    expect(out.toString(), contains('\x1B[31merror'));
    expect(run([invalid]).out, isNot(contains('\x1B[')));
  });

  test('the executable runs (smoke test)', () async {
    final result = await Process.run(
        Platform.resolvedExecutable, ['run', 'bin/openair_lint.dart', invalid]);
    expect(result.exitCode, exitLintFailed);
    expect(result.stdout as String, contains('header-version-missing'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
