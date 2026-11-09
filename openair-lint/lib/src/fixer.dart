import 'dart:convert' show utf8;

import 'diagnostic.dart';
import 'fix.dart';
import 'linter.dart';
import 'model/openair_file.dart';
import 'parser/legacy_encoding.dart';
import 'parser/parser.dart';

/// The largest number of passes of [fixBytes].
///
/// A fix can make another problem visible, or two fixes can change the same
/// text. Such fixes are applied in the next pass, after the file is checked
/// again. Real files need two or three passes.
const int maxFixPasses = 10;

/// The result of [fixBytes].
class FixResult {
  FixResult._({
    required this.originalBytes,
    required this.bytes,
    required this.result,
    required this.fixedByRule,
    required this.fileChanges,
    required this.notFixedReason,
    required List<String> originalLines,
    required List<String> lines,
    required List<int?> origin,
  })  : _originalLines = originalLines,
        _lines = lines,
        _origin = origin;

  /// The bytes of the file before the fixes.
  final List<int> originalBytes;

  /// The bytes of the file after the fixes. They are the same as
  /// [originalBytes] if nothing was fixed.
  final List<int> bytes;

  /// The lint result of the fixed file: the problems that are left.
  final LintResult result;

  /// The number of fixed problems for each rule ID.
  final Map<String, int> fixedByRule;

  /// Changes of the whole file that a diff of the lines does not show, for
  /// example "Removed the byte order mark (BOM).".
  final List<String> fileChanges;

  /// Why the file was not fixed at all, or null. For example, a file with
  /// bytes that are not valid UTF-8 is not fixed, because openair-lint
  /// cannot write these bytes back unchanged.
  final String? notFixedReason;

  final List<String> _originalLines;
  final List<String> _lines;

  /// For each line of the fixed file, the index of the line in the
  /// original file, or null for a new line. The indexes go up.
  final List<int?> _origin;

  /// The number of fixed problems.
  int get fixedCount => fixedByRule.values.fold(0, (a, b) => a + b);

  /// True if the fixed file is different from the original file.
  bool get changed {
    if (bytes.length != originalBytes.length) return true;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != originalBytes[i]) return true;
    }
    return false;
  }

  /// The changed lines as a unified diff (the format of `diff -u`), with
  /// [context] unchanged lines around each change. Empty if no line
  /// changed. [path] is used in the `---` and `+++` lines.
  ///
  /// Changes of the whole file (see [fileChanges]) are not in the diff.
  String unifiedDiff(String path, {int context = 2}) {
    final ops = _diffOps();
    if (!ops.any((o) => o.kind != _OpKind.equal)) return '';
    final b = StringBuffer()
      ..writeln('--- $path')
      ..writeln('+++ $path (fixed)');
    var i = 0;
    while (i < ops.length) {
      if (ops[i].kind == _OpKind.equal) {
        i++;
        continue;
      }
      // A hunk: from [context] lines before the change to [context] lines
      // after the last change that is not more than 2 * context lines away.
      var start = i;
      var back = 0;
      while (
          start > 0 && back < context && ops[start - 1].kind == _OpKind.equal) {
        start--;
        back++;
      }
      var end = i;
      while (true) {
        while (end < ops.length && ops[end].kind != _OpKind.equal) {
          end++;
        }
        var equal = 0;
        while (end + equal < ops.length &&
            ops[end + equal].kind == _OpKind.equal) {
          equal++;
        }
        final more = end + equal < ops.length;
        if (more && equal <= 2 * context) {
          end += equal;
          continue;
        }
        end += equal < context ? equal : context;
        break;
      }
      final hunk = ops.sublist(start, end);
      final oldLines = hunk.where((o) => o.kind != _OpKind.insert).length;
      final newLines = hunk.where((o) => o.kind != _OpKind.delete).length;
      final oldStart = _firstLine(ops, start, old: true);
      final newStart = _firstLine(ops, start, old: false);
      b.writeln('@@ -${_range(oldStart, oldLines)} '
          '+${_range(newStart, newLines)} @@');
      for (final o in hunk) {
        switch (o.kind) {
          case _OpKind.equal:
            b.writeln(' ${_originalLines[o.oldIndex!]}');
          case _OpKind.delete:
            b.writeln('-${_originalLines[o.oldIndex!]}');
          case _OpKind.insert:
            b.writeln('+${_lines[o.newIndex!]}');
        }
      }
      i = end;
    }
    return b.toString();
  }

  /// The line number (1-based) of the first old or new line at or after
  /// [index] in [ops]. For an empty range, it is the line before.
  static int _firstLine(List<_Op> ops, int index, {required bool old}) {
    var count = 0;
    for (var k = 0; k < index; k++) {
      final o = ops[k];
      if (old ? o.kind != _OpKind.insert : o.kind != _OpKind.delete) count++;
    }
    return count + 1;
  }

  static String _range(int start, int count) =>
      count == 1 ? '$start' : '${count == 0 ? start - 1 : start},$count';

  /// The diff as a list of operations. Within a block of changes, the
  /// removed lines come before the added lines.
  List<_Op> _diffOps() {
    final ops = <_Op>[];
    final deletes = <_Op>[];
    final inserts = <_Op>[];
    void flush() {
      ops
        ..addAll(deletes)
        ..addAll(inserts);
      deletes.clear();
      inserts.clear();
    }

    var o = 0;
    for (var n = 0; n < _lines.length; n++) {
      final from = _origin[n];
      if (from == null) {
        inserts.add(_Op(_OpKind.insert, null, n));
        continue;
      }
      while (o < from) {
        deletes.add(_Op(_OpKind.delete, o, null));
        o++;
      }
      if (_originalLines[o] == _lines[n]) {
        flush();
        ops.add(_Op(_OpKind.equal, o, n));
      } else {
        deletes.add(_Op(_OpKind.delete, o, null));
        inserts.add(_Op(_OpKind.insert, null, n));
      }
      o++;
    }
    while (o < _originalLines.length) {
      deletes.add(_Op(_OpKind.delete, o, null));
      o++;
    }
    flush();
    return ops;
  }
}

enum _OpKind { equal, delete, insert }

class _Op {
  const _Op(this.kind, this.oldIndex, this.newIndex);
  final _OpKind kind;
  final int? oldIndex;
  final int? newIndex;
}

/// The text of a file, line by line, while it is fixed.
class _State {
  _State(this.lines, this.endings, this.origin, this.encoding, this.bom);

  final List<String> lines;
  final List<LineEnding> endings;
  final List<int?> origin;
  final TextEncoding encoding;
  final bool bom;

  String get text {
    final b = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      b
        ..write(lines[i])
        ..write(switch (endings[i]) {
          LineEnding.lf => '\n',
          LineEnding.crlf => '\r\n',
          LineEnding.cr => '\r',
          LineEnding.none => '',
        });
    }
    return b.toString();
  }

  List<int> encode() {
    final t = text;
    switch (encoding) {
      case TextEncoding.utf8:
        return [
          if (bom) ...const [0xEF, 0xBB, 0xBF],
          ...utf8.encode(t)
        ];
      case TextEncoding.utf16le:
        return [
          0xFF, 0xFE, //
          for (final u in t.codeUnits) ...[u & 0xFF, u >> 8],
        ];
      case TextEncoding.utf16be:
        return [
          0xFE, 0xFF, //
          for (final u in t.codeUnits) ...[u >> 8, u & 0xFF],
        ];
    }
  }

  /// The most frequent line ending, or LF if no line has one.
  LineEnding get mainEnding {
    final counts = <LineEnding, int>{};
    for (final e in endings) {
      if (e != LineEnding.none) counts[e] = (counts[e] ?? 0) + 1;
    }
    var best = LineEnding.lf;
    var bestCount = 0;
    for (final e in const [LineEnding.lf, LineEnding.crlf, LineEnding.cr]) {
      final c = counts[e] ?? 0;
      if (c > bestCount) {
        best = e;
        bestCount = c;
      }
    }
    return best;
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// True if [text] has a UTF-16 surrogate without its pair. UTF-8 cannot
/// store such a code unit.
bool _hasLoneSurrogate(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 < text.length) {
        final d = text.codeUnitAt(i + 1);
        if (d >= 0xDC00 && d <= 0xDFFF) {
          i++;
          continue;
        }
      }
      return true;
    }
    if (c >= 0xDC00 && c <= 0xDFFF) return true;
  }
  return false;
}

/// The fixes of one pass that do not change the same text.
class _Selection {
  _Selection(this.state);

  final _State state;
  final Map<int, List<ReplaceText>> replaces = {};
  final Set<int> deleted = {};
  final Map<int, InsertLine> inserts = {};
  LineEnding? ending;
  bool removeBom = false;
  bool toUtf8 = false;
  final List<Diagnostic> accepted = [];

  /// Adds the fix of [d] if none of its edits conflicts with the edits that
  /// are already selected. Returns true if it was added.
  bool tryAdd(Diagnostic d) {
    final fix = d.fix;
    if (fix == null) return false;
    final pendingReplaces = <ReplaceText>[];
    final pendingDeletes = <int>{};
    final pendingInserts = <int, InsertLine>{};
    LineEnding? pendingEnding;

    bool lineExists(int line) => line >= 1 && line <= state.lines.length;
    bool overlaps(ReplaceText a, ReplaceText b) {
      if (a.line != b.line) return false;
      if (a.column < a.endColumn && b.column < b.endColumn) {
        return a.column < b.endColumn && b.column < a.endColumn;
      }
      // An insert touches the other range.
      return a.column <= b.endColumn && b.column <= a.endColumn;
    }

    for (final e in fix.edits) {
      switch (e) {
        case ReplaceText():
          if (!lineExists(e.line)) return false;
          final length = state.lines[e.line - 1].length;
          if (e.column < 1 || e.endColumn > length + 1) return false;
          if (e.text.contains('\n') || e.text.contains('\r')) return false;
          if (deleted.contains(e.line) || pendingDeletes.contains(e.line)) {
            return false;
          }
          final others = [...?replaces[e.line], ...pendingReplaces];
          if (others.any((o) => overlaps(o, e))) return false;
          pendingReplaces.add(e);
        case DeleteLine():
          final l = e.line;
          if (!lineExists(l)) return false;
          if (deleted.contains(l) || pendingDeletes.contains(l)) return false;
          if ((replaces[l]?.isNotEmpty ?? false) ||
              pendingReplaces.any((r) => r.line == l)) {
            return false;
          }
          if (inserts.containsKey(l) || pendingInserts.containsKey(l)) {
            return false;
          }
          pendingDeletes.add(l);
        case InsertLine():
          final l = e.line;
          if (!lineExists(l)) return false;
          if (e.text.contains('\n') || e.text.contains('\r')) return false;
          if (inserts.containsKey(l) || pendingInserts.containsKey(l)) {
            return false;
          }
          if (deleted.contains(l) || pendingDeletes.contains(l)) return false;
          pendingInserts[l] = e;
        case SetLineEndings():
          if (ending != null || pendingEnding != null) return false;
          pendingEnding = e.ending;
        case RemoveBom():
          break;
        case ConvertToUtf8():
          if (_hasLoneSurrogate(state.text)) return false;
      }
    }
    for (final r in pendingReplaces) {
      (replaces[r.line] ??= []).add(r);
    }
    deleted.addAll(pendingDeletes);
    inserts.addAll(pendingInserts);
    ending ??= pendingEnding;
    for (final e in fix.edits) {
      if (e is RemoveBom) removeBom = true;
      if (e is ConvertToUtf8) toUtf8 = true;
    }
    accepted.add(d);
    return true;
  }

  /// The new state with all selected fixes.
  _State apply() {
    final lines = <String>[];
    final endings = <LineEnding>[];
    final origin = <int?>[];
    final newLineEnding = ending ?? state.mainEnding;
    for (var i = 0; i < state.lines.length; i++) {
      final l = i + 1;
      if (deleted.contains(l)) {
        // Keep "no line ending at the end of the file".
        if (state.endings[i] == LineEnding.none && endings.isNotEmpty) {
          endings[endings.length - 1] = LineEnding.none;
        }
        continue;
      }
      var text = state.lines[i];
      final edits = [...?replaces[l]]
        ..sort((a, b) => b.column.compareTo(a.column));
      for (final e in edits) {
        text = text.substring(0, e.column - 1) +
            e.text +
            text.substring(e.endColumn - 1);
      }
      var lineEnding = state.endings[i];
      if (ending != null && lineEnding != LineEnding.none) {
        lineEnding = ending!;
      }
      lines.add(text);
      endings.add(lineEnding);
      origin.add(state.origin[i]);
      final insert = inserts[l];
      if (insert != null) {
        final LineEnding insertEnding;
        if (lineEnding == LineEnding.none) {
          endings[endings.length - 1] = newLineEnding;
          insertEnding = LineEnding.none;
        } else {
          insertEnding = lineEnding;
        }
        lines.add(insert.text);
        endings.add(insertEnding);
        origin.add(null);
      }
    }
    return _State(
      lines,
      endings,
      origin,
      toUtf8 ? TextEncoding.utf8 : state.encoding,
      toUtf8 || removeBom ? false : state.bom,
    );
  }
}

/// Fixes the problems of a file that have an automatic fix (see [Fix]),
/// and checks the fixed file again.
///
/// The fixes are applied in passes. In each pass, the file is checked and
/// all fixes that do not change the same text are applied. Then the file
/// is checked again, until no fix is left or after [maxFixPasses] passes.
///
/// Only the rules that [linter] runs are fixed: disabled rules and rules
/// below the minimum severity are not fixed. Everything that no fix changes
/// stays the same, byte by byte: the encoding, the byte order mark, the
/// line endings and the end of the file.
///
/// A file whose bytes cannot be written back unchanged (bytes that are not
/// valid UTF-8, or an odd number of bytes in a UTF-16 file) is not fixed.
/// Then [FixResult.notFixedReason] says why.
///
/// [select] chooses the problems to fix. Null means all problems with a
/// fix. [maxPasses] limits the passes; use 1 to fix only the problems that
/// are in the file now (for example one problem that the user chose).
///
/// It never throws.
FixResult fixBytes(Linter linter, List<int> bytes,
    {String? fileName,
    bool Function(Diagnostic d)? select,
    int maxPasses = maxFixPasses}) {
  final file = parseOpenAirBytes(bytes);
  var state = _State(
    List.of(file.lines),
    List.of(file.lineEndings),
    List<int?>.generate(file.lines.length, (i) => i),
    file.encoding,
    file.hasBom,
  );
  final fixedByRule = <String, int>{};
  if (!_sameBytes(state.encode(), bytes)) {
    final guess = guessLegacyEncoding(file);
    final reason = file.invalidUtf8.isNotEmpty
        ? 'The file has bytes that are not valid UTF-8. openair-lint cannot '
            'write them back unchanged.'
            '${guess == null ? '' : ' The file is probably saved as '
                '${guess.labels}.'} Save the file as UTF-8 first.'
        : 'openair-lint cannot write the bytes of this file back unchanged. '
            'Save the file as UTF-8 first.';
    return FixResult._(
      originalBytes: bytes,
      bytes: bytes,
      result: linter.lintParsed(file, fileName: fileName),
      fixedByRule: fixedByRule,
      fileChanges: const [],
      notFixedReason: reason,
      originalLines: file.lines,
      lines: file.lines,
      origin: state.origin,
    );
  }

  final original = state;
  var current = bytes;
  var result = linter.lintParsed(file, fileName: fileName);
  for (var pass = 1; pass <= maxPasses; pass++) {
    final selection = _Selection(state);
    for (final d in result.diagnostics) {
      if (select == null || select(d)) selection.tryAdd(d);
    }
    if (selection.accepted.isEmpty) break;
    final next = selection.apply();
    final nextBytes = next.encode();
    if (_sameBytes(nextBytes, current)) break;
    for (final d in selection.accepted) {
      fixedByRule[d.ruleId] = (fixedByRule[d.ruleId] ?? 0) + 1;
    }
    state = next;
    current = nextBytes;
    result = linter.lintBytes(current, fileName: fileName);
  }

  final fileChanges = <String>[
    if (original.encoding != state.encoding)
      'Saved the file as ${state.encoding.label} '
          '(it was ${original.encoding.label}).'
    else if (original.bom && !state.bom)
      'Removed the byte order mark (BOM).',
    if (!_sameEndings(original, state))
      'Changed the line endings to ${_endingName(state.mainEnding)}.',
  ];
  return FixResult._(
    originalBytes: bytes,
    bytes: current,
    result: result,
    fixedByRule: fixedByRule,
    fileChanges: fileChanges,
    notFixedReason: null,
    originalLines: original.lines,
    lines: state.lines,
    origin: state.origin,
  );
}

/// True if no line that is in both states has another line ending. New
/// lines and the end of the file are not compared.
bool _sameEndings(_State a, _State b) {
  for (var n = 0; n < b.lines.length; n++) {
    final o = b.origin[n];
    if (o == null) continue;
    final ea = a.endings[o];
    final eb = b.endings[n];
    if (ea != eb && ea != LineEnding.none && eb != LineEnding.none) {
      return false;
    }
  }
  return true;
}

String _endingName(LineEnding e) => switch (e) {
      LineEnding.lf => 'LF',
      LineEnding.crlf => 'CRLF',
      LineEnding.cr => 'CR',
      LineEnding.none => 'none',
    };

/// Fixes the text of a file (see [fixBytes]). The text is handled as
/// UTF-8. Returns the fixed text and the result.
(String, FixResult) fixString(Linter linter, String text, {String? fileName}) {
  final r = fixBytes(linter, utf8.encode(text), fileName: fileName);
  return (utf8.decode(r.bytes, allowMalformed: true), r);
}
