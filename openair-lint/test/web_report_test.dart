import 'dart:convert';
import 'dart:typed_data';

import 'package:openair_lint/openair_lint.dart';
import 'package:test/test.dart';

import '../web/src/report.dart';

const String _text = '*VERSION: 2.1\n'
    '*WRITTEN_BY: test\n'
    'AC D\n'
    'AN Test CTR\n'
    'AH 4500 FT MSL\n'
    'AL 0 FT AGL\n'
    'DP 46:00:00N 014:00:00E\n'
    'DP 46:00:00N 014:10:00E\n'
    'DP 45:55:00N 014:10:00E\n'
    'DP 45:55:00N 014:00:00E\n'
    'DP 46:00:00N 014:00:00E\n';

final ReportFilter _all = ReportFilter(Severity.values.toSet(), '');

void main() {
  test('the summary counts the problems with a fix', () {
    final summary = runLint(text: _text, target: '').summary();
    final json = ReportSummary.fromJson(
        jsonDecode(jsonEncode(summary.toJson())) as Map<String, Object?>);
    expect(json.fixableCount(_all), 2);
    expect(json.fixableCount(ReportFilter({Severity.warning}, '')), 2);
    expect(json.fixableCount(ReportFilter({Severity.error}, '')), 0);
    expect(
        json.fixableCount(
            ReportFilter(Severity.values.toSet(), 'altitude-msl-alias')),
        1);
    expect(json.fixed, isNull);
  });

  test('a page says which problems have a fix', () {
    final page = runLint(text: _text, target: '').page(_all, 0, 100);
    final json = ReportPage.fromJson(
        jsonDecode(jsonEncode(page.toJson())) as Map<String, Object?>);
    expect(json.fixable, [for (final d in page.items) d.fixable]);
    expect(json.fixable.where((f) => f), hasLength(2));
  });

  test('"fix all" fixes the problems that match the filter', () {
    final request = FixRequest.all(_all);
    final report = runLint(
        bytes: Uint8List.fromList(utf8.encode(_text)),
        target: '',
        fileName: 'a.openair',
        fix: FixRequest.decode(request.encode()).encode());
    final fixed = utf8.decode(report.fixedBytes!);
    expect(fixed, contains('AH 4500 FT AMSL\nAL GND\n'));
    expect(report.summary().fixed, 2);
    expect(report.summary().fixableCount(_all), 0);
  });

  test('"fix all" with a rule filter fixes only that rule', () {
    final request = FixRequest.all(
        ReportFilter(Severity.values.toSet(), 'altitude-msl-alias'));
    final report = runLint(text: _text, target: '', fix: request.encode());
    final fixed = utf8.decode(report.fixedBytes!);
    expect(fixed, contains('AH 4500 FT AMSL\nAL 0 FT AGL\n'));
  });

  test('"fix" fixes one problem', () {
    final d = runLint(text: _text, target: '')
        .result
        .diagnostics
        .firstWhere((d) => d.ruleId == 'altitude-zero-agl');
    final request = FixRequest.one(d.ruleId, d.line, d.column);
    expect(FixRequest.decode(request.encode()).encode(), request.encode());
    final report = runLint(text: _text, target: '', fix: request.encode());
    final fixed = utf8.decode(report.fixedBytes!);
    expect(fixed, contains('AH 4500 FT MSL\nAL GND\n'));
    expect(report.summary().fixed, 1);
  });

  test('a file with invalid UTF-8 is not fixed', () {
    final bytes = Uint8List.fromList(
        [...utf8.encode(_text), ...utf8.encode('* M'), 0xFC, 0x0A]);
    final report =
        runLint(bytes: bytes, target: '', fix: FixRequest.all(_all).encode());
    expect(report.fixedBytes, isNull);
    expect(report.summary().notFixedReason, contains('UTF-8'));
  });
}
