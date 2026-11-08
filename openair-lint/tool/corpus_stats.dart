// Development tool: lints all OpenAir files in a directory and prints how
// often each rule fires. With --geometry it also parses every coordinate and
// builds every airspace boundary, and prints counts of coordinate issues.
//
// Usage:
//   dart run tool/corpus_stats.dart [--geometry] [--examples N] <directory>

import 'dart:io';

import 'package:openair_lint/openair_lint.dart';

void main(List<String> args) {
  final geometry = args.contains('--geometry');
  var examples = 0;
  final rest = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--geometry') continue;
    if (args[i] == '--examples' && i + 1 < args.length) {
      examples = int.parse(args[++i]);
      continue;
    }
    rest.add(args[i]);
  }
  if (rest.length != 1) {
    stderr.writeln(
        'Usage: dart run tool/corpus_stats.dart [--geometry] [--examples N] <directory>');
    exitCode = 2;
    return;
  }
  final files = Directory(rest.single)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) {
    final p = f.path.toLowerCase();
    return p.endsWith('.txt') || p.endsWith('.openair');
  }).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final linter = Linter();
  final ruleCounts = <String, int>{};
  final ruleFiles = <String, Set<String>>{};
  final ruleExamples = <String, List<String>>{};
  final issueCounts = <CoordinateIssueKind, int>{};
  var lines = 0, airspaces = 0, coordinates = 0, empty = 0, unused = 0;
  final sw = Stopwatch()..start();
  var lintMs = 0;

  for (final f in files) {
    final bytes = f.readAsBytesSync();
    final t0 = sw.elapsedMilliseconds;
    final result = linter.lintBytes(bytes);
    lintMs += sw.elapsedMilliseconds - t0;
    lines += result.file.lineCount;
    airspaces += result.file.airspaces.length;
    for (final d in result.diagnostics) {
      ruleCounts[d.ruleId] = (ruleCounts[d.ruleId] ?? 0) + 1;
      (ruleFiles[d.ruleId] ??= {}).add(f.path);
      final ex = ruleExamples[d.ruleId] ??= [];
      if (ex.length < examples) {
        ex.add('${f.path}:${d.line}:${d.column}: ${d.message}\n'
            '    | ${d.line <= result.file.lineCount ? result.file.lineText(d.line) : ''}');
      }
    }
    if (geometry) {
      for (final a in result.file.airspaces) {
        for (final c in a.commands) {
          if (c.upperKeyword == 'DP' || c.upperKeyword == 'DY') {
            coordinates++;
            for (final i in parseCoordinate(c.argument).issues) {
              issueCounts[i.kind] = (issueCounts[i.kind] ?? 0) + 1;
            }
          }
        }
        final b = buildBoundary(a);
        if (b.isEmpty) empty++;
        unused += b.unusedCommands.length;
        b.centre;
      }
    }
  }
  final totalMs = sw.elapsedMilliseconds;

  stdout.writeln('${files.length} files, $lines lines, $airspaces airspaces');
  stdout.writeln('Lint time: $lintMs ms (total $totalMs ms)');
  stdout.writeln('');
  stdout.writeln('Diagnostics per rule (count, files):');
  final ids = ruleCounts.keys.toList()..sort();
  for (final id in ids) {
    stdout
        .writeln('  ${id.padRight(40)} ${ruleCounts[id].toString().padLeft(8)}'
            ' ${ruleFiles[id]!.length.toString().padLeft(5)}');
    for (final e in ruleExamples[id] ?? const <String>[]) {
      stdout.writeln('      $e');
    }
  }
  if (geometry) {
    stdout.writeln('');
    stdout.writeln('$coordinates DP/DY coordinates. Issues:');
    for (final k in CoordinateIssueKind.values) {
      stdout.writeln('  ${k.name.padRight(24)} ${issueCounts[k] ?? 0}');
    }
    stdout.writeln('Airspaces without boundary points: $empty');
    stdout.writeln('Geometry commands that could not be used: $unused');
  }
}
