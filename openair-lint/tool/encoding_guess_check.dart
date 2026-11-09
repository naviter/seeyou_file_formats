// Development tool: prints the guessed 8-bit encoding of each file that is
// not valid UTF-8, with one decoded line, so that a person can check the
// guess.
//
// Usage:
//   dart run tool/encoding_guess_check.dart <directory>...

import 'dart:io';

import 'package:openair_lint/openair_lint.dart';

void main(List<String> args) {
  final counts = <String, int>{};
  for (final dir in args) {
    final files =
        Directory(dir).listSync(recursive: true).whereType<File>().where((f) {
      final p = f.path.toLowerCase();
      return p.endsWith('.txt') || p.endsWith('.openair');
    }).toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final file = parseOpenAirBytes(f.readAsBytesSync());
      if (file.invalidUtf8.isEmpty) continue;
      final guess = guessLegacyEncoding(file);
      final label = guess?.encodings.map((e) => e.name).join(' or ') ?? '?';
      counts[label] = (counts[label] ?? 0) + 1;
      var sample = '';
      if (guess != null) {
        // A line with a letter, not only a symbol such as "°".
        final byLine = <int, List<InvalidUtf8>>{};
        for (final x in file.invalidUtf8) {
          (byLine[x.line] ??= []).add(x);
        }
        for (final e in byLine.entries) {
          final text =
              decodeLegacyLine(file.lineText(e.key), e.value, guess.best)
                  .trim();
          sample = text;
          if (RegExp(r'^A[NG]\s').hasMatch(text)) break;
        }
      }
      if (sample.length > 70) sample = sample.substring(0, 70);
      print('${label.padRight(30)} ${f.path}\n    $sample');
    }
  }
  print('');
  counts.forEach((k, v) => print('$k: $v'));
}
