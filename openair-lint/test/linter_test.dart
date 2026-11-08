import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

Rule testRule(
  String id, {
  Severity severity = Severity.warning,
  Set<SpecVersion> versions = SpecVersion.all,
  Set<String>? keywords,
  FileCheck? checkFile,
  AirspaceCheck? checkAirspace,
  CommandCheck? checkCommand,
}) =>
    Rule(
      id: id,
      severity: severity,
      versions: versions,
      specAnchor: 'header',
      description: 'Test rule.',
      explanation: 'Test rule.',
      correctExample: 'AC D',
      incorrectExample: 'AC X',
      keywords: keywords,
      checkFile: checkFile,
      checkAirspace: checkAirspace,
      checkCommand: checkCommand,
    );

const text = '*VERSION: 3.0\n'
    'AN outside\n'
    'AC D\n'
    'AN One\n'
    'ac c\n'
    'AN Two\n';

void main() {
  group('dispatch', () {
    test('command rules with keywords run only for those keywords', () {
      final seen = <String>[];
      final rule = testRule('test-an',
          keywords: {'AN'},
          checkCommand: (ctx, c, a) => seen.add('${c.line}:${a?.index}'));
      Linter(LintOptions(rules: [rule])).lintString(text);
      expect(seen, ['2:null', '4:0', '6:1']);
    });

    test('keywords match any case', () {
      final seen = <int>[];
      final rule = testRule('test-ac',
          keywords: {'AC'}, checkCommand: (ctx, c, a) => seen.add(c.line));
      Linter(LintOptions(rules: [rule])).lintString(text);
      expect(seen, [3, 5]);
    });

    test('command rules without keywords run for every command', () {
      var count = 0;
      final rule = testRule('test-all', checkCommand: (ctx, c, a) => count++);
      Linter(LintOptions(rules: [rule])).lintString(text);
      expect(count, 5);
    });

    test('airspace and file rules', () {
      final seen = <String>[];
      final rule = testRule('test-both',
          checkFile: (ctx) => seen.add('file'),
          checkAirspace: (ctx, a) => seen.add('airspace ${a.startLine}'));
      Linter(LintOptions(rules: [rule])).lintString(text);
      expect(seen, ['file', 'airspace 3', 'airspace 5']);
    });
  });

  group('reporting', () {
    test('diagnostics have the rule id, severity and spec url', () {
      final rule = testRule('test-report',
          severity: Severity.error,
          keywords: {'AN'},
          checkCommand: (ctx, c, a) => ctx.reportArgument(c, 'bad name'));
      final d = Linter(LintOptions(rules: [rule])).lintString(text).diagnostics;
      expect(d, hasLength(3));
      expect(d.first.ruleId, 'test-report');
      expect(d.first.severity, Severity.error);
      expect(d.first.specUrl, '$specBaseUrl#header');
      expect((d.first.line, d.first.column, d.first.endColumn), (2, 4, 11));
    });

    test('report helpers compute columns', () {
      final results = <String>[];
      final rule =
          testRule('test-cols', keywords: {'DP'}, checkCommand: (ctx, c, a) {
        ctx.reportCommand(c, 'command');
        ctx.reportKeyword(c, 'keyword');
        ctx.reportArgument(c, 'part', offset: 3, length: 2);
        ctx.reportLine(c.line, 'line');
        ctx.report('point', line: c.line, column: 5);
      });
      final d = Linter(LintOptions(rules: [rule]))
          .lintString('AC D\n DP 45:00:00N 014:00:00E * x\n')
          .diagnostics;
      for (final x in d) {
        results.add('${x.message} ${x.column}-${x.endColumn}');
      }
      expect(results, [
        'line 1-29',
        'command 2-25',
        'keyword 2-4',
        'point 5-6',
        'part 8-10',
      ]);
    });

    test('reportArgument on an empty argument points after the keyword', () {
      final rule = testRule('test-empty',
          keywords: {'AC'},
          checkCommand: (ctx, c, a) => ctx.reportArgument(c, 'empty'));
      final d =
          Linter(LintOptions(rules: [rule])).lintString('AC\n').diagnostics;
      expect((d.single.column, d.single.endColumn), (3, 4));
    });

    test('diagnostics are sorted by line and column', () {
      final rule = testRule('test-sort', checkFile: (ctx) {
        ctx.report('c', line: 3, column: 1);
        ctx.report('b', line: 1, column: 5);
        ctx.report('a', line: 1, column: 2);
      });
      final d = Linter(LintOptions(rules: [rule])).lintString('').diagnostics;
      expect(d.map((x) => x.message), ['a', 'b', 'c']);
    });

    test('a rule that throws is reported, other rules still run', () {
      final bad = testRule('test-throws',
          keywords: {'AN'}, checkCommand: (ctx, c, a) => throw StateError('x'));
      final good =
          testRule('test-good', checkFile: (ctx) => ctx.report('ok', line: 1));
      final d =
          Linter(LintOptions(rules: [bad, good])).lintString(text).diagnostics;
      expect(d.where((x) => x.ruleId == internalErrorRuleId), hasLength(1));
      expect(d.where((x) => x.ruleId == 'test-good'), hasLength(1));
    });
  });

  group('options', () {
    final info = testRule('test-info',
        severity: Severity.info, checkFile: (ctx) => ctx.report('i', line: 1));
    final warning = testRule('test-warning',
        severity: Severity.warning,
        checkFile: (ctx) => ctx.report('w', line: 1));
    final error = testRule('test-error',
        severity: Severity.error, checkFile: (ctx) => ctx.report('e', line: 1));
    final only21 = testRule('test-only21',
        versions: SpecVersion.only21,
        checkFile: (ctx) => ctx.report('21', line: 1));

    List<String> ids(LintOptions o, [String content = '*VERSION: 3.0\n']) =>
        Linter(o).lintString(content).diagnostics.map((d) => d.ruleId).toList()
          ..sort();

    test('min severity', () {
      final rules = [info, warning, error];
      expect(ids(LintOptions(rules: rules)),
          ['test-error', 'test-info', 'test-warning']);
      expect(ids(LintOptions(rules: rules, minSeverity: Severity.warning)),
          ['test-error', 'test-warning']);
      expect(ids(LintOptions(rules: rules, minSeverity: Severity.error)),
          ['test-error']);
    });

    test('disabled rules', () {
      expect(
          ids(LintOptions(
              rules: [info, warning], disabledRules: {'test-info'})),
          ['test-warning']);
    });

    test('rules run only for their versions', () {
      expect(ids(LintOptions(rules: [only21])), isEmpty);
      expect(ids(LintOptions(rules: [only21]), '*VERSION: 2.1\n'),
          ['test-only21']);
      expect(ids(LintOptions(rules: [only21], target: SpecVersion.v2_1)),
          ['test-only21']);
    });
  });

  group('spec version', () {
    ResolvedVersion r(String? declared, [SpecVersion? target]) =>
        resolveSpecVersion(declared, target);

    test('known versions', () {
      expect(r('3.0').version, SpecVersion.v3_0);
      expect(r('2.1').version, SpecVersion.v2_1);
      expect(r('2.1').source, VersionSource.header);
      expect(r('3.0.0').version, SpecVersion.v3_0);
    });

    test('old versions are checked as 2.1', () {
      expect(r('2.0').version, SpecVersion.v2_1);
      expect(r('2.0').source, VersionSource.headerOld);
      expect(r('1.0').version, SpecVersion.v2_1);
    });

    test('newer versions are checked as 3.0', () {
      expect(r('3.1').version, SpecVersion.v3_0);
      expect(r('4.0').source, VersionSource.headerNewer);
    });

    test('missing and invalid', () {
      expect(r(null).version, SpecVersion.v3_0);
      expect(r(null).source, VersionSource.missing);
      expect(r('abc').source, VersionSource.headerInvalid);
      expect(r('abc').version, SpecVersion.v3_0);
    });

    test('target wins', () {
      expect(r('3.0', SpecVersion.v2_1).version, SpecVersion.v2_1);
      expect(r('3.0', SpecVersion.v2_1).source, VersionSource.target);
    });

    test('LintResult has the version', () {
      final result = Linter(const LintOptions(rules: []))
          .lintString('*VERSION: 2.0\nAC D\n');
      expect(result.specVersion, SpecVersion.v2_1);
      expect(result.versionSource, VersionSource.headerOld);
      expect(result.declaredVersion, '2.0');
    });
  });

  test('top-level lintString and lintBytes', () {
    expect(lintString('AC D\n').map((d) => d.ruleId),
        contains('header-version-missing'));
    expect(lintBytes('*VERSION: 3.0\n'.codeUnits).map((d) => d.ruleId),
        isNot(contains('header-version-missing')));
  });
}
