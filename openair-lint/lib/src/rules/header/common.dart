part of '../header_rules.dart';

/// The anchor of the general requirements (encoding, case, comments).
const String _generalAnchor = 'general-requirements';

/// All commands that the specification defines (upper case).
const Set<String> _specKeywords = {
  'AC', 'AN', 'AY', 'AF', 'AG', 'AA', 'AX', 'AH', 'AL', //
  'DP', 'DA', 'DB', 'DC', 'DY', 'V',
};

/// The `A` commands that describe the airspace. They come before the
/// geometry. `AC` is not in this set, because it always starts a block.
const Set<String> _attributeKeywords = {
  'AN', 'AY', 'AF', 'AG', 'AA', 'AX', 'AH', 'AL', //
};

/// The commands that define the geometry, including `V`.
const Set<String> _geometryKeywords = {'DP', 'DA', 'DB', 'DC', 'DY', 'V'};

/// The commands that create a shape (points, arcs, circles, airways).
const Set<String> _shapeKeywords = {'DP', 'DA', 'DB', 'DC', 'DY'};

/// Commands that are used in real files but that the specification does not
/// define. The value says what the command does in other software.
const Map<String, String> _extraCommands = {
  'AI': 'It is an airspace ID in files from openAIP.',
  'AR': 'Some files use it for a radio frequency. Use "AF" for the '
      'frequency.',
  'AT': 'It sets the position of a label in WinPilot.',
  'SP': 'It sets the pen (line style and colour) in WinPilot.',
  'SB': 'It sets the brush (fill colour) in WinPilot.',
  'TO': 'It starts an open terrain line in WinPilot. Readers that do not '
      'know it add the points after it to the airspace before it.',
  'TC': 'It starts a closed terrain area in WinPilot. Readers that do not '
      'know it add the points after it to the airspace before it.',
};

/// Shortens [text] for a message.
String _short(String text, [int max = 40]) =>
    text.length <= max ? text : '${text.substring(0, max - 3)}...';

/// True if [c] (one UTF-16 code unit as a string) is a lower case letter:
/// it changes when it is written in upper case.
bool _isLowerCaseChar(String c) => c.toUpperCase() != c;

/// The line ranges of StrePla add-on blocks
/// (`*$STREPLA_ADDON BEGIN` ... `*$STREPLA_ADDON END`).
///
/// StrePla writes extra data (for example a colour table) in these blocks.
/// The data looks like airspaces, but it is not.
List<({int start, int end})> _streplaBlocks(LintContext ctx) =>
    ctx.memo(('header-strepla-blocks',), () {
      final result = <({int start, int end})>[];
      final lines = ctx.file.lines;
      int? start;
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].trimLeft();
        if (!l.startsWith(r'*$STREPLA_ADDON')) continue;
        final rest = l.substring(r'*$STREPLA_ADDON'.length).trimLeft();
        if (rest.toUpperCase().startsWith('BEGIN')) {
          start ??= i + 1;
        } else if (rest.toUpperCase().startsWith('END') && start != null) {
          result.add((start: start, end: i + 1));
          start = null;
        }
      }
      if (start != null) result.add((start: start, end: lines.length));
      return result;
    });

/// The probable encoding of a UTF-16 file that has no byte order mark:
/// `UTF-16 LE`, `UTF-16 BE`, or null if the file does not look like UTF-16.
///
/// The reader decodes such a file as UTF-8. Every ASCII character then has
/// a NUL character (U+0000) before or after it. NUL is never valid in an
/// OpenAir file. The check uses the first 4096 characters: the file looks
/// like UTF-16 when at least a quarter of them are NUL.
String? _looksLikeUtf16(LintContext ctx) =>
    ctx.memo(('header-utf16-without-bom',), () {
      final file = ctx.file;
      if (file.encoding != TextEncoding.utf8) return null;
      var total = 0;
      var nul = 0;
      for (final line in file.lines) {
        for (final c in line.codeUnits) {
          total++;
          if (c == 0) nul++;
          if (total >= 4096) break;
        }
        if (total >= 4096) break;
      }
      if (total < 8 || nul * 4 < total) return null;
      // Little endian: "A" is the bytes 41 00, so the text starts with "A".
      // Big endian: "A" is 00 41, so the text starts with NUL.
      final first = file.lines.firstWhere((l) => l.isNotEmpty);
      return first.codeUnitAt(0) == 0 ? 'UTF-16 BE' : 'UTF-16 LE';
    });

/// True if [line] is inside a StrePla add-on block.
bool _inStrepla(LintContext ctx, int line) {
  for (final b in _streplaBlocks(ctx)) {
    if (line >= b.start && line <= b.end) return true;
  }
  return false;
}
