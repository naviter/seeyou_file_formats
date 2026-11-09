/// The result of one lint run, and the parts of it that the page shows.
///
/// A large file can have hundreds of thousands of diagnostics. So the full
/// [Report] stays where the lint ran (in the web worker). The page gets a
/// small [ReportSummary] and asks for one [ReportPage] at a time. All
/// messages between the worker and the page are small JSON texts.
///
/// This file uses no browser API, so it also runs on the Dart VM.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:openair_lint/openair_lint.dart';

/// Lines longer than this are cut. Only the part around the diagnostics is
/// kept, so that a file with very long lines does not create a huge report.
const int _maxLineLength = 1000;

/// The number of characters kept before and after the diagnostics of a
/// long line.
const int _contextLength = 200;

/// The largest part of one long line that is kept.
const int _maxSnippetLength = 2000;

/// Lints [bytes] (a file) or [text] (pasted text).
///
/// [target] is `3.0`, `2.1`, or an empty string for "use the header".
/// [fileName] is the name of the file, or null for pasted text.
///
/// If [fix] is not null (see [FixRequest.encode]), the problems that it
/// selects are fixed first. Then the report is for the fixed file, and
/// [Report.fixedBytes] has the fixed file. Pasted text is fixed as UTF-8.
Report runLint(
    {Uint8List? bytes,
    String? text,
    required String target,
    String? fileName,
    String? fix}) {
  final options = LintOptions(target: SpecVersion.fromLabel(target));
  final linter = Linter(options);
  if (fix != null) {
    final request = FixRequest.decode(fix);
    final result = fixBytes(linter, bytes ?? utf8.encode(text ?? ''),
        fileName: fileName,
        select: request.matches,
        maxPasses: request.maxPasses);
    return Report(result.result, fix: result);
  }
  final result = bytes != null
      ? linter.lintBytes(bytes, fileName: fileName)
      : linter.lintString(text ?? '');
  return Report(result);
}

/// Which diagnostics the page shows.
class ReportFilter {
  const ReportFilter(this.severities, this.rule);

  /// Reads the text of [encode].
  factory ReportFilter.decode(String text) {
    final bar = text.indexOf('|');
    final severities = <Severity>{
      for (final label in text.substring(0, bar).split(','))
        if (Severity.fromLabel(label) case final s?) s
    };
    return ReportFilter(severities, text.substring(bar + 1));
  }

  /// The severities that are shown.
  final Set<Severity> severities;

  /// The rule ID that is shown, or an empty string for all rules.
  final String rule;

  bool matches(Diagnostic d) =>
      severities.contains(d.severity) && (rule.isEmpty || d.ruleId == rule);

  /// The filter as one text, for example `error,warning|ac-unknown-class`.
  String encode() => '${[
        for (final s in Severity.values)
          if (severities.contains(s)) s.label
      ].join(',')}'
      '|$rule';
}

/// Which problems the page asks to fix.
class FixRequest {
  /// All problems with a fix that match [filter].
  FixRequest.all(ReportFilter this.filter)
      : ruleId = null,
        line = null,
        column = null;

  /// One problem: the problem of rule [ruleId] at [line] and [column].
  FixRequest.one(String this.ruleId, int this.line, int this.column)
      : filter = null;

  /// Reads the text of [encode].
  factory FixRequest.decode(String text) {
    final bar = text.indexOf('|');
    final kind = text.substring(0, bar);
    final rest = text.substring(bar + 1);
    if (kind == 'all') return FixRequest.all(ReportFilter.decode(rest));
    final parts = rest.split('|');
    return FixRequest.one(parts[0], int.parse(parts[1]), int.parse(parts[2]));
  }

  final ReportFilter? filter;
  final String? ruleId;
  final int? line;
  final int? column;

  /// True if the fix of [d] is selected.
  bool matches(Diagnostic d) {
    final f = filter;
    if (f != null) return f.matches(d);
    return d.ruleId == ruleId && d.line == line && d.column == column;
  }

  /// One problem is fixed in one pass. All problems are fixed in as many
  /// passes as needed.
  int get maxPasses => filter == null ? 1 : maxFixPasses;

  /// The request as one text, for example `all|error,warning|` or
  /// `one|altitude-msl-alias|12|14`.
  String encode() =>
      filter != null ? 'all|${filter!.encode()}' : 'one|$ruleId|$line|$column';
}

/// The full result of one lint run.
class Report {
  Report(this.result, {this.fix});

  final LintResult result;

  /// The result of the fix, if the page asked for one.
  final FixResult? fix;

  /// The fixed file, or null if no fix was asked for or nothing changed.
  Uint8List? get fixedBytes {
    final f = fix;
    if (f == null || !f.changed) return null;
    return Uint8List.fromList(f.bytes);
  }

  String? _filterKey;
  List<int> _matches = const [];

  /// The indexes in the diagnostics list that match [filter].
  /// The result for the last filter is kept, because the page asks for
  /// several pages with the same filter.
  List<int> _matching(ReportFilter filter) {
    final key = filter.encode();
    if (key == _filterKey) return _matches;
    final diagnostics = result.diagnostics;
    _matches = [
      for (var i = 0; i < diagnostics.length; i++)
        if (filter.matches(diagnostics[i])) i
    ];
    _filterKey = key;
    return _matches;
  }

  /// The numbers that the page shows above the list.
  ReportSummary summary() {
    final file = result.file;
    final counts = List.filled(Severity.values.length, 0);
    final rules = <String, int>{};
    final fixable = <String, int>{};
    for (final d in result.diagnostics) {
      counts[d.severity.index]++;
      rules[d.ruleId] = (rules[d.ruleId] ?? 0) + 1;
      if (d.fixable) fixable[d.ruleId] = (fixable[d.ruleId] ?? 0) + 1;
    }
    final ruleCounts =
        rules.entries.map((e) => (e.key, e.value, fixable[e.key] ?? 0)).toList()
          ..sort((a, b) {
            final c = b.$2.compareTo(a.$2);
            return c != 0 ? c : a.$1.compareTo(b.$1);
          });
    return ReportSummary(
      specVersion: result.specVersion.label,
      versionSource: result.versionSource.name,
      declaredVersion: result.declaredVersion,
      lineCount: file.lineCount,
      airspaceCount: file.airspaces.length,
      encoding: file.encoding.label,
      hasBom: file.hasBom,
      counts: counts,
      rules: ruleCounts,
      fixed: fix?.fixedCount,
      fileChanges: fix?.fileChanges ?? const [],
      notFixedReason: fix?.notFixedReason,
      encodingGuess: guessLegacyEncoding(file)?.labels,
    );
  }

  /// Up to [count] diagnostics that match [filter], from position [offset].
  ReportPage page(ReportFilter filter, int offset, int count) {
    final matches = _matching(filter);
    final start = offset.clamp(0, matches.length);
    final end = (start + count).clamp(start, matches.length);
    final items = [
      for (var i = start; i < end; i++) result.diagnostics[matches[i]]
    ];
    return ReportPage(
      total: matches.length,
      offset: start,
      items: items,
      fixable: [for (final d in items) d.fixable],
      snippets: _snippets(items),
    );
  }

  /// All diagnostics that match [filter], in the text format of the
  /// command line tool, with a summary line at the end.
  String exportText(String name, ReportFilter filter) {
    final out = StringBuffer();
    final counts = List.filled(Severity.values.length, 0);
    for (final i in _matching(filter)) {
      final d = result.diagnostics[i];
      counts[d.severity.index]++;
      out.writeln('$name:${d.line}:${d.column}: ${d.severity.label} '
          '[${d.ruleId}] ${d.message}');
    }
    out.writeln('${_plural(counts[Severity.error.index], 'error')}, '
        '${_plural(counts[Severity.warning.index], 'warning')}, '
        '${counts[Severity.info.index]} info.');
    return out.toString();
  }

  /// The source text around each of [items] (null if the line does not
  /// exist). Each diagnostic has its own snippet, because two diagnostics
  /// can be far apart on one very long line.
  List<Snippet?> _snippets(List<Diagnostic> items) {
    final file = result.file;
    return [
      for (final d in items)
        if (d.line < 1 || d.line > file.lineCount)
          null
        else
          _snippet(file.lineText(d.line), d.column - 1, d.endColumn - 1)
    ];
  }
}

/// The numbers of a [Report]. It is small, so it can be sent as JSON.
class ReportSummary {
  const ReportSummary({
    required this.specVersion,
    required this.versionSource,
    required this.declaredVersion,
    required this.lineCount,
    required this.airspaceCount,
    required this.encoding,
    required this.hasBom,
    required this.counts,
    required this.rules,
    this.fixed,
    this.fileChanges = const [],
    this.notFixedReason,
    this.encodingGuess,
  });

  factory ReportSummary.fromJson(Map<String, Object?> json) => ReportSummary(
        specVersion: json['specVersion']! as String,
        versionSource: json['versionSource']! as String,
        declaredVersion: json['declaredVersion'] as String?,
        lineCount: json['lineCount']! as int,
        airspaceCount: json['airspaceCount']! as int,
        encoding: json['encoding']! as String,
        hasBom: json['hasBom']! as bool,
        counts: (json['counts']! as List<Object?>).cast<int>(),
        rules: [
          for (final r
              in (json['rules']! as List<Object?>).cast<List<Object?>>())
            (r[0]! as String, r[1]! as int, r[2]! as int)
        ],
        fixed: json['fixed'] as int?,
        fileChanges:
            (json['fileChanges'] as List<Object?>? ?? const []).cast<String>(),
        notFixedReason: json['notFixedReason'] as String?,
        encodingGuess: json['encodingGuess'] as String?,
      );

  /// The spec version that was used, for example `3.0`.
  final String specVersion;

  /// The name of the [VersionSource] value, for example `header`.
  final String versionSource;

  /// The value of the `*VERSION:` header, or null.
  final String? declaredVersion;

  final int lineCount;
  final int airspaceCount;

  /// The label of the [TextEncoding], for example `UTF-8`.
  final String encoding;
  final bool hasBom;

  /// The number of diagnostics for each severity, by [Severity.index].
  final List<int> counts;

  /// The rule IDs with their number of diagnostics and the number of
  /// diagnostics with a fix. The most frequent rule is first.
  final List<(String, int, int)> rules;

  /// The number of fixed problems, or null if no fix was asked for.
  final int? fixed;

  /// Changes of the whole file by the fix (see [FixResult.fileChanges]).
  final List<String> fileChanges;

  /// Why the file could not be fixed, or null.
  final String? notFixedReason;

  /// The probable old 8-bit encoding of a file that is not valid UTF-8 (see
  /// [EncodingGuess.labels]), or null.
  final String? encodingGuess;

  /// The number of diagnostics with a fix that match [filter].
  int fixableCount(ReportFilter filter) {
    var n = 0;
    for (final (id, _, fixable) in rules) {
      if (fixable == 0) continue;
      if (filter.rule.isNotEmpty && filter.rule != id) continue;
      final rule = findRule(id);
      if (rule == null || !filter.severities.contains(rule.severity)) continue;
      n += fixable;
    }
    return n;
  }

  /// The number of diagnostics with this severity.
  int count(Severity severity) => counts[severity.index];

  /// The number of all diagnostics.
  int get total => counts.fold(0, (a, b) => a + b);

  Map<String, Object?> toJson() => {
        'specVersion': specVersion,
        'versionSource': versionSource,
        'declaredVersion': declaredVersion,
        'lineCount': lineCount,
        'airspaceCount': airspaceCount,
        'encoding': encoding,
        'hasBom': hasBom,
        'counts': counts,
        'rules': [
          for (final r in rules) [r.$1, r.$2, r.$3]
        ],
        'fixed': fixed,
        'fileChanges': fileChanges,
        'notFixedReason': notFixedReason,
        'encodingGuess': encodingGuess,
      };
}

/// One page of diagnostics that match a filter.
class ReportPage {
  const ReportPage({
    required this.total,
    required this.offset,
    required this.items,
    required this.fixable,
    required this.snippets,
  });

  factory ReportPage.fromJson(Map<String, Object?> json) => ReportPage(
        total: json['total']! as int,
        offset: json['offset']! as int,
        items: [
          for (final raw in json['items']! as List<Object?>)
            _diagnosticFromJson(raw! as List<Object?>)
        ],
        fixable: [
          for (final raw in json['items']! as List<Object?>)
            (raw! as List<Object?>)[7] == true
        ],
        snippets: [
          for (final raw in json['snippets']! as List<Object?>)
            if (raw case [final int start, final String text, final int length])
              Snippet(start, text, length)
            else
              null
        ],
      );

  /// The number of all diagnostics that match the filter.
  final int total;

  /// The position of the first item in the list of matching diagnostics.
  final int offset;

  final List<Diagnostic> items;

  /// True for each item of [items] that has an automatic fix.
  final List<bool> fixable;

  /// The source text around each of [items], at the same index. Null if
  /// the diagnostic has no source line.
  final List<Snippet?> snippets;

  Map<String, Object?> toJson() => {
        'total': total,
        'offset': offset,
        'items': [
          for (final d in items)
            [
              d.line,
              d.column,
              d.endColumn,
              d.severity.label,
              d.ruleId,
              d.message,
              d.specUrl,
              d.fixable,
            ]
        ],
        'snippets': [
          for (final s in snippets)
            if (s == null) null else [s.start, s.text, s.lineLength]
        ],
      };
}

Diagnostic _diagnosticFromJson(List<Object?> d) => Diagnostic(
      line: d[0]! as int,
      column: d[1]! as int,
      endColumn: d[2]! as int,
      severity: Severity.fromLabel(d[3]! as String) ?? Severity.error,
      ruleId: d[4]! as String,
      message: d[5]! as String,
      specUrl: d[6]! as String,
    );

/// A part of one source line.
class Snippet {
  const Snippet(this.start, this.text, this.lineLength);

  /// The 0-based position of [text] in the line.
  final int start;

  /// The text of the line from [start]. It is the whole line for normal
  /// lines.
  final String text;

  /// The length of the whole line.
  final int lineLength;

  /// The 0-based position after [text] in the line.
  int get end => start + text.length;
}

Snippet _snippet(String line, int from, int to) {
  if (line.length <= _maxLineLength) return Snippet(0, line, line.length);
  var start = from - _contextLength;
  if (start < 0) start = 0;
  if (start > line.length) start = line.length;
  var end = to + _contextLength;
  if (end > line.length) end = line.length;
  if (end - start > _maxSnippetLength) end = start + _maxSnippetLength;
  if (end < start) end = start;
  return Snippet(start, line.substring(start, end), line.length);
}

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
