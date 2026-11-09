// Development tool: runs the automatic fixes (--fix) on all OpenAir files in
// a directory and checks that they are safe.
//
// For each file it checks:
//
// - The fixes do not change the meaning: the same airspaces, classes, types,
//   names, frequencies, transponder codes, altitude limits, activation times
//   and boundary points. Values that could not be read before the fix are
//   not compared, because a fix can make them readable.
// - A second fix run changes nothing.
// - Which rules give new problems after the fix.
//
// It also prints some example changes for each rule.
//
// Usage:
//   dart run tool/fix_corpus_check.dart [--target 2.1] [--max-mb N]
//       [--examples N] <directory>

import 'dart:io';

import 'package:openair_lint/openair_lint.dart';
import 'package:openair_lint/src/altitude/altitude.dart';
import 'package:openair_lint/src/attributes/attribute_values.dart';

void main(List<String> args) {
  SpecVersion? target;
  var maxMb = 5.0;
  var examples = 3;
  final rest = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--target':
        target = SpecVersion.fromLabel(args[++i]);
      case '--max-mb':
        maxMb = double.parse(args[++i]);
      case '--examples':
        examples = int.parse(args[++i]);
      default:
        rest.add(args[i]);
    }
  }
  if (rest.length != 1) {
    stderr.writeln('Usage: dart run tool/fix_corpus_check.dart [--target 2.1] '
        '[--max-mb N] [--examples N] <directory>');
    exitCode = 2;
    return;
  }
  final files = Directory(rest.single)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) {
    final p = f.path.toLowerCase();
    return (p.endsWith('.txt') || p.endsWith('.openair')) &&
        f.lengthSync() <= maxMb * 1024 * 1024;
  }).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final options = LintOptions(target: target);
  final linter = Linter(options);
  final fixedByRule = <String, int>{};
  final newProblems = <String, int>{};
  final newProblemExamples = <String, List<String>>{};
  final meaningChanges = <String>[];
  final notIdempotent = <String>[];
  final notFixed = <String, String>{};
  final ruleExamples = <String, List<String>>{};
  var changedFiles = 0;
  final watch = Stopwatch()..start();

  for (final f in files) {
    final bytes = f.readAsBytesSync();
    final before = linter.lintBytes(bytes, fileName: f.path);
    final fix = fixBytes(linter, bytes, fileName: f.path);
    if (fix.notFixedReason != null) {
      notFixed[f.path] = fix.notFixedReason!;
      continue;
    }
    if (!fix.changed) continue;
    changedFiles++;
    fix.fixedByRule
        .forEach((k, v) => fixedByRule[k] = (fixedByRule[k] ?? 0) + v);

    // A second run must not change anything.
    final again = fixBytes(linter, fix.bytes, fileName: f.path);
    if (again.changed) {
      notIdempotent.add('${f.path}: ${again.fixedByRule}');
    }

    // The meaning must be the same.
    final a = parseOpenAirBytes(bytes);
    final b = parseOpenAirBytes(fix.bytes);
    meaningChanges.addAll(_compare(f.path, a, b));

    // New problems: rules that report more problems after the fix.
    final countBefore = _countByRule(before.diagnostics);
    final countAfter = _countByRule(fix.result.diagnostics);
    for (final e in countAfter.entries) {
      final more = e.value - (countBefore[e.key] ?? 0);
      if (more <= 0) continue;
      newProblems[e.key] = (newProblems[e.key] ?? 0) + more;
      final list = newProblemExamples.putIfAbsent(e.key, () => []);
      if (list.length < 3) {
        final d = fix.result.diagnostics.firstWhere((d) => d.ruleId == e.key);
        list.add('${f.path}:${d.line}: ${d.message}');
      }
    }

    // Examples: the fixes of one rule alone.
    final fixableRules = {
      for (final d in before.diagnostics)
        if (d.fixable) d.ruleId
    };
    for (final id in fixableRules) {
      final list = ruleExamples.putIfAbsent(id, () => []);
      if (list.length >= examples) continue;
      final one = Linter(LintOptions(target: target, rules: [findRule(id)!]));
      final r = fixBytes(one, bytes, fileName: f.path);
      final diff = r.unifiedDiff(f.path.split(RegExp(r'[\\/]')).last);
      final changed = diff
          .split('\n')
          .where((l) =>
              (l.startsWith('-') || l.startsWith('+')) &&
              !l.startsWith('---') &&
              !l.startsWith('+++'))
          .take(6)
          .toList();
      final text = [
        ...r.fileChanges,
        ...changed,
      ];
      if (text.isNotEmpty) list.add(text.join('\n    '));
    }
  }

  print('Checked ${files.length} files in ${watch.elapsed.inSeconds} s '
      '(target: ${target?.label ?? 'from the header'}).');
  print('Changed files: $changedFiles');
  print('');
  print('Fixed problems by rule:');
  for (final e in fixedByRule.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value))) {
    print('  ${e.key.padRight(40)} ${e.value}');
  }
  print('');
  print('Meaning changes: ${meaningChanges.length}');
  for (final m in meaningChanges.take(60)) {
    print('  $m');
  }
  print('');
  print('Not idempotent: ${notIdempotent.length}');
  for (final m in notIdempotent.take(20)) {
    print('  $m');
  }
  print('');
  print('Not fixed: ${notFixed.length}');
  for (final e in notFixed.entries.take(10)) {
    print('  ${e.key}: ${e.value}');
  }
  print('');
  print('New problems after the fix (rule: count):');
  for (final e in newProblems.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value))) {
    print('  ${e.key.padRight(40)} ${e.value}');
    for (final x in newProblemExamples[e.key]!) {
      print('      $x');
    }
  }
  print('');
  print('Examples of each rule alone:');
  for (final id in ruleExamples.keys.toList()..sort()) {
    print('  $id');
    for (final x in ruleExamples[id]!) {
      print('    $x');
      print('');
    }
  }
}

Map<String, int> _countByRule(List<Diagnostic> ds) {
  final m = <String, int>{};
  for (final d in ds) {
    m[d.ruleId] = (m[d.ruleId] ?? 0) + 1;
  }
  return m;
}

/// The differences of meaning between [a] (before) and [b] (after).
List<String> _compare(String path, OpenAirFile a, OpenAirFile b) {
  final out = <String>[];
  if (a.airspaces.length != b.airspaces.length) {
    return [
      '$path: ${a.airspaces.length} airspaces before, '
          '${b.airspaces.length} after'
    ];
  }
  for (var i = 0; i < a.airspaces.length; i++) {
    final x = a.airspaces[i];
    final y = b.airspaces[i];
    final where = '$path: airspace at line ${x.startLine} '
        '(now ${y.startLine})';
    void check(String what, Object? p, Object? q) {
      if (p != q) out.add('$where: $what "$p" -> "$q"');
    }

    check('class', _class(x), _class(y));
    check('name', x.firstWith('AN')?.argument, y.firstWith('AN')?.argument);
    check('station', x.firstWith('AG')?.argument, y.firstWith('AG')?.argument);
    final ayX = _type(x);
    if (ayX != null) check('type', ayX, _type(y));
    check('AX', x.firstWith('AX')?.argument, y.firstWith('AX')?.argument);
    final afX = _frequency(x);
    if (afX != null) check('AF', afX, _frequency(y));
    for (final k in const ['AH', 'AL']) {
      final p = _altitude(x, k);
      if (p != null) check(k, p, _altitude(y, k));
    }
    final aaX = _activation(x);
    final aaY = _activation(y);
    final knownX = aaX.where((s) => !s.startsWith('?')).toSet();
    final knownY = aaY.toSet();
    for (final s in knownX) {
      if (!knownY.contains(s)) out.add('$where: AA "$s" is missing after');
    }
    for (final s in knownY) {
      if (!aaX.contains(s) && !aaX.any((t) => t.startsWith('?'))) {
        out.add('$where: AA "$s" is new after');
      }
    }
    final pa = _points(x);
    final pb = _points(y);
    if (pa != null && pb != null && !_samePoints(pa, pb)) {
      out.add('$where: boundary ${pa.length} points -> ${pb.length} points');
    }
  }
  return out;
}

String _class(Airspace a) {
  final v = a.ac.argument.toUpperCase();
  return unclassifiedAliases.contains(v) ? 'UNC' : v;
}

String? _type(Airspace a) {
  final ay = a.firstWith('AY');
  if (ay == null) return null;
  final v = ay.argument.toUpperCase();
  final hint = typeHintFor(v);
  return hint != null && hint.certain ? hint.type : v;
}

double? _frequency(Airspace a) {
  final af = a.firstWith('AF');
  if (af == null) return null;
  final v = frequencyFormatFix(af.argument) ?? af.argument;
  return double.tryParse(v);
}

String? _altitude(Airspace a, String keyword) {
  final c = a.firstWith(keyword);
  if (c == null) return null;
  final p = parseAltitude(c.argument);
  if (p.kind == AltitudeKind.invalid) return null;
  final ft = p.feet;
  if (ft == null) return null;
  return '${ft.isInfinite ? 'UNL' : ft.toStringAsFixed(3)} '
      '${p.comparableReference?.label}';
}

/// The meaning of each AA command. A command with an error starts with "?".
List<String> _activation(Airspace a) {
  String t(AaTimeOfDay? x) => x == null ? '-' : '${x.ms ?? x.sunEvent}';
  return [
    for (final c in a.commands)
      if (c.upperKeyword == 'AA')
        switch (parseAa(c.argument)) {
          final AaCommand cmd when cmd.issues.any((i) => i.kind.blocking) =>
            '?${c.argument}',
          AaNoneCommand() => 'NONE',
          final AaIntervalCommand x =>
            'I ${x.startIsNone ? 'NONE' : x.start}/${x.endIsNone ? 'NONE' : x.end}',
          final AaWeekdayCommand x => 'W ${(x.weekdays.toList()..sort())} '
              '${t(x.startTime)}/${t(x.endTime)} '
              '${x.hasDateRange ? '${x.fromDate}/${x.toDate}' : ''}',
          final AaExceptCommand x => 'E ${x.fromDate}/${x.toDate}',
          AaUnknownCommand() => '?${c.argument}',
        }
  ];
}

List<LatLng>? _points(Airspace a) {
  final b = buildBoundary(a);
  if (b.isEmpty) return null;
  final p = <LatLng>[];
  for (final x in b.points) {
    if (p.isNotEmpty && _same(p.last, x)) continue;
    p.add(x);
  }
  if (p.length > 1 && _same(p.first, p.last)) p.removeLast();
  return p;
}

bool _same(LatLng a, LatLng b) =>
    (a.lat - b.lat).abs() < 1e-9 && (a.lon - b.lon).abs() < 1e-9;

/// True if [a] and [b] have the same points in the same order, or in the
/// opposite order with the same first point (the fix of
/// geometry-polygon-counter-clockwise).
bool _samePoints(List<LatLng> a, List<LatLng> b) {
  if (a.length != b.length) return false;
  var same = true;
  for (var i = 0; i < a.length && same; i++) {
    if (!_same(a[i], b[i])) same = false;
  }
  if (same) return true;
  if (a.isEmpty || !_same(a[0], b[0])) return false;
  for (var i = 1; i < a.length; i++) {
    if (!_same(a[i], b[a.length - i])) return false;
  }
  return true;
}
