part of '../header_rules.dart';

// ---------------------------------------------------------------------------
// command-outside-airspace
// ---------------------------------------------------------------------------

final Rule _commandOutsideAirspace = Rule(
  id: 'command-outside-airspace',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'airspace-definition',
  description: 'Every command must be inside an airspace definition, after '
      'an AC command.',
  explanation: 'Each airspace definition must begin with the "AC" command. '
      'A command before the first "AC" command does not belong to any '
      'airspace. Readers handle such commands differently: most ignore '
      'them, some use a "V X=" command for the next airspace.\n'
      '\n'
      'Move the command into the airspace that it belongs to, after the '
      '"AC" command. Only comments and empty lines can come before the first '
      '"AC" command.',
  correctExample: '*VERSION: 3.0\n'
      '*WRITTEN_BY: SeeYou\n'
      '\n'
      'AC D\n'
      'AN Example CTR',
  incorrectExample: '*VERSION: 3.0\n'
      '*WRITTEN_BY: SeeYou\n'
      '\n'
      'AN Example CTR\n'
      'AC D',
  checkFile: (ctx) {
    for (final c in ctx.file.commandsOutsideAirspace) {
      // Unknown commands and extra commands are reported by other rules.
      if (!_specKeywords.contains(c.upperKeyword)) continue;
      if (_inStrepla(ctx, c.line)) continue;
      if (_looksLikeUtf16(ctx) != null) return;
      ctx.reportCommand(
          c,
          'The command "${c.keyword}" is before the first "AC" command, so '
          'it is not part of an airspace. Move it after the "AC" command of '
          'its airspace.');
    }
  },
);

// ---------------------------------------------------------------------------
// command-unknown
// ---------------------------------------------------------------------------

final Rule _commandUnknown = Rule(
  id: 'command-unknown',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'command-reference',
  description: 'Every line must be a command of the specification, a '
      'comment or an empty line.',
  explanation: 'The first word of each line is the command. This line '
      'starts with a word that is not a command of the specification. '
      'Readers do not understand the line.\n'
      '\n'
      'Common causes are a missing space after the command (for example '
      '"AH5000 FT"), a no-break space (U+00A0) in place of a normal space '
      'after the command, a note without "*" in front of it, or a comment '
      'that starts with "#" or "//" in place of "*".\n'
      '\n'
      'Commands of other programs, for example "SP" and "SB" of WinPilot, '
      'are reported by the rule command-not-in-spec.',
  correctExample: 'AH 5000 FT AMSL\n'
      '* Note: changed in 2026',
  incorrectExample: 'AH5000 FT AMSL\n'
      'Note: changed in 2026',
  checkCommand: (ctx, c, a) {
    final keyword = c.upperKeyword;
    if (_specKeywords.contains(keyword) ||
        _extraCommands.containsKey(keyword)) {
      return;
    }
    if (_inStrepla(ctx, c.line)) return;
    // A UTF-16 file without a byte order mark: file-not-utf8 reports it.
    if (_looksLikeUtf16(ctx) != null) return;
    ctx.reportCommand(c, _unknownMessage(c));
  },
);

final RegExp _gluedVariable = RegExp(r'^V[XDWZ]=', caseSensitive: false);

/// A description of [c] (one UTF-16 code unit) if it is a space character
/// that is not a normal space or tab, or null. Readers do not see such a
/// character as a blank.
String? _unicodeSpaceName(int c) => switch (c) {
      0x00A0 => 'a no-break space (U+00A0)',
      0x202F => 'a narrow no-break space (U+202F)',
      0x200B => 'a zero-width space (U+200B)',
      0x3000 => 'an ideographic space (U+3000)',
      0x1680 ||
      0x205F ||
      (>= 0x2000 && <= 0x200A) =>
        'a Unicode space (U+${c.toRadixString(16).toUpperCase()})',
      _ => null,
    };

String _unknownMessage(Command c) {
  final keyword = c.keyword;
  final upper = c.upperKeyword;
  final shown = _visible(_short(keyword));
  if (keyword.codeUnitAt(0) == 0xFEFF) {
    return 'The line starts with a byte order mark (U+FEFF). This often '
        'happens when files are joined. Remove it.';
  }
  if (keyword.startsWith('#') ||
      keyword.startsWith('//') ||
      keyword.startsWith(';')) {
    final marker = keyword.startsWith('//') ? '//' : keyword[0];
    return 'Comments start with "*". "$marker" does not start a comment. '
        'Write "*" in place of "$marker".';
  }
  // A command followed by a no-break space or another Unicode space, for
  // example "AN" + U+00A0 + "Example". The message names the character,
  // because it looks like a normal space.
  for (final length in const [2, 1]) {
    if (upper.length <= length) continue;
    final prefix = upper.substring(0, length);
    if (!_specKeywords.contains(prefix) &&
        !_extraCommands.containsKey(prefix)) {
      continue;
    }
    final space = _unicodeSpaceName(keyword.codeUnitAt(length));
    if (space == null) continue;
    return 'The character after "${keyword.substring(0, length)}" is '
        '$space, not a normal space. Readers do not see the command. Write a '
        'normal space.';
  }
  if (upper.length > 2) {
    final prefix = upper.substring(0, 2);
    final next = upper.codeUnitAt(2);
    final isLetter =
        (next >= 0x41 && next <= 0x5A) || (next >= 0x61 && next <= 0x7A);
    if (_specKeywords.contains(prefix) && !isLetter) {
      return 'Unknown command "$shown". Write a space after '
          '"${keyword.substring(0, 2)}".';
    }
  }
  if (_gluedVariable.hasMatch(upper)) {
    return 'Unknown command "$shown". Write a space after "V".';
  }
  final first = upper.codeUnitAt(0);
  if (first >= 0x30 && first <= 0x39) {
    return 'The line starts with a number, not with a command. If it is a '
        'point, write "DP" in front of it. If it is a note, start it with '
        '"*".';
  }
  return 'Unknown command "$shown". Readers do not understand '
      'this line. If it is a note, start it with "*" to make it a comment.';
}

// ---------------------------------------------------------------------------
// command-not-in-spec
// ---------------------------------------------------------------------------

final Rule _commandNotInSpec = Rule(
  id: 'command-not-in-spec',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'command-reference',
  description: 'Commands of other programs (SP, SB, AT, AI, AR, TO, TC) are '
      'not part of the specification.',
  explanation: 'Some files use commands that other programs defined, for '
      'example "SP" and "SB" (pen and brush) and "AT" (label position) of '
      'WinPilot, or "AI" (airspace ID) of openAIP. This specification does '
      'not define them. Readers ignore them, or they read them in different '
      'ways.\n'
      '\n'
      'Remove these commands. If the information is useful for people, '
      'write it in a comment.\n'
      '\n'
      'Such commands are often on many lines. openair-lint reports each '
      'command only once per file, at its first line. The message says how '
      'many lines use it.',
  correctExample: 'AC D\n'
      'AN Example CTR\n'
      'AF 118.480',
  incorrectExample: 'AC D\n'
      'AN Example CTR\n'
      'SP 0,1,0,0,255\n'
      'AR 118.480',
  checkFile: (ctx) {
    final first = <String, Command>{};
    final counts = <String, int>{};
    for (final c in ctx.file.allCommands) {
      final k = c.upperKeyword;
      if (!_extraCommands.containsKey(k)) continue;
      if (_inStrepla(ctx, c.line)) continue;
      first.putIfAbsent(k, () => c);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    for (final entry in first.entries) {
      final c = entry.value;
      final n = counts[entry.key]!;
      final lines = n == 1
          ? ''
          : ' The file has $n lines with "${entry.key}". Only this first '
              'one is reported.';
      ctx.reportKeyword(
          c,
          '"${c.keyword}" is not part of the specification. '
          '${_extraCommands[entry.key]} Readers that follow the '
          'specification ignore it.$lines');
    }
  },
);

// ---------------------------------------------------------------------------
// airspace-ah-missing, airspace-al-missing
// ---------------------------------------------------------------------------

Rule _limitMissing(String keyword, String anchor) {
  final upper = keyword == 'AH';
  final what = upper ? 'upper limit' : 'lower limit';
  return Rule(
    id: 'airspace-${keyword.toLowerCase()}-missing',
    severity: Severity.error,
    versions: SpecVersion.all,
    specAnchor: anchor,
    description: 'Every airspace must have an "$keyword" command '
        '(the $what).',
    explanation: 'Each airspace definition needs exactly one upper limit '
        '("AH") and one lower limit ("AL"). This airspace has no "$keyword" '
        'command. Readers then guess the $what, and different readers guess '
        'differently.\n'
        '\n'
        'Add the "$keyword" command after the "AC" command. '
        '${upper ? 'Use "AH UNL" if the airspace has no upper limit.' : 'Use "AL GND" if the airspace starts at the ground.'}',
    correctExample: 'AC D\n'
        'AN Example CTR\n'
        'AH 4500 FT AMSL\n'
        'AL GND\n'
        'DP 46:00:00N 014:00:00E\n'
        '...',
    incorrectExample: 'AC D\n'
        'AN Example CTR\n'
        '${upper ? 'AL GND' : 'AH 4500 FT AMSL'}\n'
        'DP 46:00:00N 014:00:00E\n'
        '...',
    checkAirspace: (ctx, a) {
      if (_inStrepla(ctx, a.startLine)) return;
      if (a.firstWith(keyword) != null) return;
      ctx.reportAirspace(
          a,
          'This airspace has no "$keyword" command. Every airspace needs '
          '${upper ? 'an' : 'a'} $what.');
    },
  );
}

final Rule _airspaceAhMissing = _limitMissing('AH', 'ah-upper-altitude-limit');
final Rule _airspaceAlMissing = _limitMissing('AL', 'al-lower-altitude-limit');

// ---------------------------------------------------------------------------
// airspace-ah-duplicate, airspace-al-duplicate
// ---------------------------------------------------------------------------

Rule _limitDuplicate(String keyword, String anchor) {
  final upper = keyword == 'AH';
  final what = upper ? 'upper limit' : 'lower limit';
  return Rule(
    id: 'airspace-${keyword.toLowerCase()}-duplicate',
    severity: Severity.error,
    versions: SpecVersion.all,
    specAnchor: anchor,
    description: 'An airspace must have only one "$keyword" command.',
    explanation: 'Each airspace definition must include only one $what. '
        'With two "$keyword" commands, the airspace is ambiguous: some '
        'readers use the first one and others use the last one.\n'
        '\n'
        'Keep one "$keyword" command. If the airspace really has two parts '
        'with different limits, write two airspace definitions.',
    correctExample: 'AC D\n'
        'AN Example CTR\n'
        '${upper ? 'AH 4500 FT AMSL' : 'AL GND'}',
    incorrectExample: 'AC D\n'
        'AN Example CTR\n'
        '${upper ? 'AH 4500 FT AMSL\nAH FL95' : 'AL GND\nAL 1000 FT AGL'}',
    checkAirspace: (ctx, a) {
      if (_inStrepla(ctx, a.startLine)) return;
      // When an AC command is missing, the rule airspace-ac-missing reports
      // it. Each part of the block is then checked on its own.
      for (final part in _airspaceParts(ctx, a)) {
        final list = [
          for (final c in part)
            if (c.upperKeyword == keyword) c
        ];
        if (list.length < 2) continue;
        final first = list.first;
        for (final c in list.skip(1)) {
          ctx.reportCommand(
              c,
              'This airspace already has an "$keyword" command on line '
              '${first.line}. An airspace must have only one $what.');
        }
      }
    },
  );
}

final Rule _airspaceAhDuplicate =
    _limitDuplicate('AH', 'ah-upper-altitude-limit');
final Rule _airspaceAlDuplicate =
    _limitDuplicate('AL', 'al-lower-altitude-limit');

// ---------------------------------------------------------------------------
// airspace-geometry-missing
// ---------------------------------------------------------------------------

final Rule _airspaceGeometryMissing = Rule(
  id: 'airspace-geometry-missing',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'command-reference',
  description: 'Every airspace must have a geometry (DP, DA, DB, DC or DY '
      'commands).',
  explanation: 'Each airspace must have at least one geometry command: '
      '"DP", "DA", "DB", "DC" or "DY". A "V" command alone is not a '
      'geometry. This airspace has no geometry command, so it has no shape. '
      'Readers cannot show it, and most of them ignore it.\n'
      '\n'
      'Add the geometry, or remove the airspace.',
  correctExample: 'AC D\n'
      'AN Example CTR\n'
      'AH 4500 FT AMSL\n'
      'AL GND\n'
      'V X=46:00:00N 014:00:00E\n'
      'DC 5',
  incorrectExample: 'AC D\n'
      'AN Example CTR\n'
      'AH 4500 FT AMSL\n'
      'AL GND\n'
      'V X=46:00:00N 014:00:00E',
  checkAirspace: (ctx, a) {
    if (_inStrepla(ctx, a.startLine)) return;
    for (final c in a.commands) {
      if (_shapeKeywords.contains(c.upperKeyword)) return;
    }
    ctx.reportAirspace(
        a,
        'This airspace has no geometry. Add "DP" points, or a "DC" circle, '
        '"DA" or "DB" arcs or "DY" segments.');
  },
);

// ---------------------------------------------------------------------------
// airspace-attribute-duplicate
// ---------------------------------------------------------------------------

/// The attribute commands that an airspace can have only once, other than
/// `AC` (it always starts a new airspace) and `AH` and `AL` (they have their
/// own rules). `AS` is new in version 3.0. In a file of version 2.1, the
/// rule `as-needs-version-3` reports every `AS` command.
const List<String> _singleAttributes = ['AN', 'AY', 'AG', 'AS', 'AX'];

/// The `A` commands that an airspace can have more than once.
const Set<String> _repeatableAttributes = {'AA', 'AF'};

/// The commands in [part] that repeat an earlier command of
/// [_singleAttributes], `AH` or `AL`. Other rules report them.
Set<Command> _repeatedCommands(List<Command> part) {
  final seen = <String>{};
  final result = <Command>{};
  for (final c in part) {
    final k = c.upperKeyword;
    if (_repeatableAttributes.contains(k) || !_attributeKeywords.contains(k)) {
      continue;
    }
    if (!seen.add(k)) result.add(c);
  }
  return result;
}

final Rule _airspaceAttributeDuplicate = Rule(
  id: 'airspace-attribute-duplicate',
  severity: Severity.error,
  versions: SpecVersion.only3,
  specAnchor: 'command-reference',
  description: 'An airspace must have at most one AN, AY, AG, AS and AX '
      'command.',
  explanation: 'Each airspace can have at most one "AN" (name), "AY" '
      '(type), "AG" (station), "AS" (source) and "AX" (transponder code) '
      'command. When a '
      'command is in the same airspace two times, readers use only one of '
      'the values, and different readers use different ones. Some readers '
      'even start a new airspace at the second "AN".\n'
      '\n'
      'Keep one command. If the lines are two airspaces, start the second '
      'one with its own "AC" command.\n'
      '\n'
      '"AF" can be used more than once: write one "AF" command for each '
      'frequency. "AH" and "AL" have their own rules '
      '(airspace-ah-duplicate and airspace-al-duplicate).',
  correctExample: 'AC D\n'
      'AN Example CTR\n'
      'AF 118.480\n'
      'AF 120.500',
  incorrectExample: 'AC D\n'
      'AN Example CTR\n'
      'AN Example TMA\n'
      'AF 118.480',
  checkAirspace: (ctx, a) {
    if (_inStrepla(ctx, a.startLine)) return;
    // When an AC command is missing, the rule airspace-ac-missing reports
    // it. Each part of the block is then checked on its own.
    for (final part in _airspaceParts(ctx, a)) {
      final firsts = <String, Command>{};
      for (final c in part) {
        final k = c.upperKeyword;
        if (!_singleAttributes.contains(k)) continue;
        if (k == 'AS' && ctx.specVersion == SpecVersion.v2_1) continue;
        final first = firsts[k];
        if (first == null) {
          firsts[k] = c;
          continue;
        }
        final next = _nextAirspaceHint(ctx, a, c);
        ctx.reportCommand(
            c,
            'This airspace already has an "$k" command on line ${first.line}. '
            'An airspace can have at most one "$k" command. '
            '${next ?? 'Keep one "$k" command, or start a new airspace with "AC".'}');
      }
    }
  },
);

final Rule _airspaceAttributeDuplicateV21 = version21Warning(
  _airspaceAttributeDuplicate,
  description: 'An airspace should have at most one AN, AY, AG and AX '
      'command (version 2.1).',
);

// ---------------------------------------------------------------------------
// airspace-command-order
// ---------------------------------------------------------------------------

final Rule _airspaceCommandOrder = Rule(
  id: 'airspace-command-order',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'airspace-definition',
  description: 'The "A" commands should come before the geometry (D and V '
      'commands).',
  explanation: 'An airspace definition starts with "AC" and the other "A" '
      'commands. The geometric definition with "D" and "V" commands follows '
      'them. Some readers stop reading the "A" commands of an airspace when '
      'the geometry starts. For example, a reader can start a new airspace '
      'at an "AN" command after the geometry.\n'
      '\n'
      'Move all "A" commands before the first "D" or "V" command. '
      'openair-lint reports this once per airspace, at the first "A" command '
      'after the geometry.',
  correctExample: 'AC D\n'
      'AN Example CTR\n'
      'AH 4500 FT AMSL\n'
      'AL GND\n'
      'V X=46:00:00N 014:00:00E\n'
      'DC 5',
  incorrectExample: 'AC D\n'
      'AN Example CTR\n'
      'V X=46:00:00N 014:00:00E\n'
      'DC 5\n'
      'AH 4500 FT AMSL\n'
      'AL GND',
  checkAirspace: (ctx, a) {
    if (_inStrepla(ctx, a.startLine)) return;
    // When an AC command is missing, each part of the block is checked on
    // its own. The "A" commands at the start of a later part are not late.
    for (final part in _airspaceParts(ctx, a)) {
      Command? geometry;
      Command? firstLate;
      var lateCount = 0;
      final repeated = _repeatedCommands(part);
      for (final c in part) {
        final k = c.upperKeyword;
        if (_geometryKeywords.contains(k)) {
          geometry ??= c;
        } else if (geometry != null &&
            _attributeKeywords.contains(k) &&
            !repeated.contains(c)) {
          firstLate ??= c;
          lateCount++;
        }
      }
      if (firstLate == null) continue;
      final more = lateCount > 1
          ? ' ${lateCount - 1} more "A" command'
              '${lateCount == 2 ? ' is' : 's are'} after the geometry too.'
          : '';
      final next = _nextAirspaceHint(ctx, a, firstLate);
      ctx.reportKeyword(
          firstLate,
          'The command "${firstLate.keyword}" is after the geometry, which '
          'starts on line ${geometry!.line}. '
          '${next ?? 'Move the "A" commands before the first "D" or "V" command.$more'}');
    }
  },
);

// ---------------------------------------------------------------------------
// airspace-ac-missing
// ---------------------------------------------------------------------------

/// The parts of an airspace block. Each part is probably one airspace.
///
/// Usually the whole block is one part. When the "AC" command between two
/// airspaces is missing, the parser reads both airspaces as one block. Then
/// the block has a geometry, after it a second group of "A" commands that
/// repeats commands of the first group (for example "AN", "AH" and "AL"),
/// and after that more geometry. Such a block has two parts. The second
/// part starts at the first "A" command after the first geometry.
///
/// A repeated command at the end of the block, with no geometry after it,
/// does not start a part. That is usually an "AN" written before the "AC"
/// of the next airspace (see [_nextAirspaceHint]).
List<List<Command>> _airspaceParts(LintContext ctx, Airspace a) =>
    ctx.memo(('header-airspace-parts', a), () {
      final commands = a.commands;
      var lastShape = -1;
      for (var i = 0; i < commands.length; i++) {
        if (_shapeKeywords.contains(commands[i].upperKeyword)) lastShape = i;
      }
      final parts = <List<Command>>[];
      var start = 0;
      // The index of the first command with each keyword in the current
      // part.
      final firstIndex = <String, int>{};
      var hasShape = false;
      var lastGeometry = -1;
      for (var i = 0; i < commands.length; i++) {
        final k = commands[i].upperKeyword;
        if (_geometryKeywords.contains(k)) {
          if (_shapeKeywords.contains(k)) hasShape = true;
          lastGeometry = i;
          continue;
        }
        if (_repeatableAttributes.contains(k) ||
            !_attributeKeywords.contains(k)) {
          continue;
        }
        // A new part starts only if the keyword is repeated from the group
        // before the last geometry. A keyword that is repeated after the
        // geometry (for example "AH" two times after the first "DP") is a
        // duplicate in the same group, not a new airspace.
        final first = firstIndex[k];
        if (hasShape &&
            first != null &&
            first < lastGeometry &&
            i < lastShape) {
          final newStart = lastGeometry + 1;
          parts.add(commands.sublist(start, newStart));
          start = newStart;
          firstIndex.clear();
          for (var j = newStart; j < i; j++) {
            firstIndex.putIfAbsent(commands[j].upperKeyword, () => j);
          }
          hasShape = false;
        }
        firstIndex.putIfAbsent(k, () => i);
      }
      parts.add(commands.sublist(start));
      return parts;
    });

/// `"AN"`, `"AN" and "AH"` or `"AN", "AH" and "AL"`.
String _quotedList(List<String> items) {
  final quoted = [for (final i in items) '"$i"'];
  if (quoted.isEmpty) return '';
  if (quoted.length == 1) return quoted.single;
  return '${quoted.sublist(0, quoted.length - 1).join(', ')} and '
      '${quoted.last}';
}

final Rule _airspaceAcMissing = Rule(
  id: 'airspace-ac-missing',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'airspace-definition',
  description: 'Each airspace must begin with an AC command. Here an AC '
      'command is probably missing between two airspaces.',
  explanation: 'Each individual airspace definition must begin with the '
      '"AC" command. Readers start a new airspace only at an "AC" command.\n'
      '\n'
      'In this airspace, the geometry is followed by a second group of "A" '
      'commands that repeats the first group (for example "AN", "AH" and '
      '"AL"), and then by more geometry. These are almost always two '
      'airspaces, and the "AC" command of the second one is missing. Readers '
      'read them as one airspace with a wrong shape, and they use only one '
      'of the names and altitude limits.\n'
      '\n'
      'Add the "AC" command before the first "A" command of the second '
      'airspace. openair-lint reports only this problem. It does not also '
      'report the repeated "A" commands as duplicates.',
  correctExample: 'AC D\n'
      'AN First CTR\n'
      'AH 4500 FT AMSL\n'
      'AL GND\n'
      'DP 46:00:00N 014:00:00E\n'
      '...\n'
      'AC D\n'
      'AN Second CTR\n'
      'AH FL95\n'
      'AL 4500 FT AMSL\n'
      'DP 46:30:00N 014:00:00E\n'
      '...',
  incorrectExample: 'AC D\n'
      'AN First CTR\n'
      'AH 4500 FT AMSL\n'
      'AL GND\n'
      'DP 46:00:00N 014:00:00E\n'
      '...\n'
      'AN Second CTR\n'
      'AH FL95\n'
      'AL 4500 FT AMSL\n'
      'DP 46:30:00N 014:00:00E\n'
      '...',
  checkAirspace: (ctx, a) {
    if (_inStrepla(ctx, a.startLine)) return;
    final parts = _airspaceParts(ctx, a);
    for (var p = 1; p < parts.length; p++) {
      final previous = parts[p - 1];
      final part = parts[p];
      final before = {for (final c in previous) c.upperKeyword};
      final repeated = <String>[];
      for (final c in part) {
        final k = c.upperKeyword;
        if (_repeatableAttributes.contains(k) ||
            !_attributeKeywords.contains(k)) {
          continue;
        }
        if (before.contains(k) && !repeated.contains(k)) repeated.add(k);
      }
      if (repeated.isEmpty) continue;
      final what = repeated.length == 1
          ? 'the command ${_quotedList(repeated)} comes'
          : 'the commands ${_quotedList(repeated)} come';
      ctx.reportKeyword(
          part.first,
          'An "AC" command is probably missing before this line. Lines '
          '${previous.first.line} to ${previous.last.line} already define an '
          'airspace with a geometry. After them, $what again, and more '
          'geometry follows. '
          'Each airspace must begin with an "AC" command.');
    }
  },
);

/// A hint for an "A" command at the end of an airspace, after its geometry,
/// directly before the next airspace. Such a command was often meant for
/// the next airspace, for example `AN` written before `AC`.
///
/// Returns null if [c] is not in this position, or if the next airspace
/// already has a command with the same keyword.
String? _nextAirspaceHint(LintContext ctx, Airspace a, Command c) {
  final airspaces = ctx.file.airspaces;
  if (a.index + 1 >= airspaces.length) return null;
  final index = a.commands.indexOf(c);
  var shapeBefore = false;
  for (var i = 0; i < a.commands.length; i++) {
    final k = a.commands[i].upperKeyword;
    if (!_geometryKeywords.contains(k)) continue;
    if (i < index) shapeBefore = true;
    if (i > index) return null;
  }
  if (!shapeBefore) return null;
  final next = airspaces[a.index + 1];
  if (next.firstWith(c.upperKeyword) != null) return null;
  return 'It is probably part of the next airspace, which starts on line '
      '${next.startLine}. Move it after that "AC" command.';
}

// ---------------------------------------------------------------------------
// airspace-an-missing, airspace-an-missing-v21
// ---------------------------------------------------------------------------

/// Reports [a] if it has no `AN` command.
void _checkAnMissing(LintContext ctx, Airspace a) {
  if (_inStrepla(ctx, a.startLine)) return;
  if (a.firstWith('AN') != null) return;
  ctx.reportAirspace(a, 'This airspace has no name. Add an "AN" command.');
}

final Rule _airspaceAnMissing = Rule(
  id: 'airspace-an-missing',
  severity: Severity.error,
  versions: SpecVersion.only3,
  specAnchor: 'an-airspace-name',
  description: 'Every airspace must have an "AN" command (the name).',
  explanation: 'Each airspace definition needs exactly one name ("AN"). '
      'Pilots need the name to know which airspace a reader shows or warns '
      'about.\n'
      '\n'
      'Add an "AN" command with the name of the airspace after the "AC" '
      'command.',
  correctExample: 'AC D\n'
      'AN Example CTR\n'
      'AH 4500 FT AMSL',
  incorrectExample: 'AC D\n'
      'AH 4500 FT AMSL',
  checkAirspace: _checkAnMissing,
);

final Rule _airspaceAnMissingV21 = Rule(
  id: 'airspace-an-missing-v21',
  severity: Severity.info,
  versions: SpecVersion.only21,
  specAnchor: 'an-airspace-name',
  anchorInVersion21Text: true,
  description: 'An airspace usually has a name (AN) (version 2.1).',
  explanation: 'In version 2.1 the "AN" command is optional, but pilots '
      'need the name to know which airspace a reader shows or warns about. '
      'Add an "AN" command with the name of the airspace.\n'
      '\n'
      'In version 3.0 "AN" is required, and an airspace without it is an '
      'error (airspace-an-missing).',
  correctExample: 'AC D\n'
      'AN Example CTR\n'
      'AH 4500 FT AMSL',
  incorrectExample: 'AC D\n'
      'AH 4500 FT AMSL',
  checkAirspace: _checkAnMissing,
);

// ---------------------------------------------------------------------------
// airspace-duplicate
// ---------------------------------------------------------------------------

final Rule _airspaceDuplicate = Rule(
  id: 'airspace-duplicate',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'airspace-definition',
  description: 'The same airspace should not be in the file two times.',
  explanation: 'Two airspace definitions in the file have the same '
      'commands: the same class, name, limits, activation times and '
      'geometry. Readers show the airspace two times and can warn two '
      'times. This often happens when files are joined.\n'
      '\n'
      'Remove one of them. The comparison ignores case, blanks, comments '
      'and commands that the specification does not define.',
  correctExample: 'AC D\n'
      'AN Example CTR\n'
      'AH 4500 FT AMSL\n'
      'AL GND\n'
      'V X=46:00:00N 014:00:00E\n'
      'DC 5\n'
      'AC D\n'
      'AN Example TMA\n'
      'AH FL95\n'
      'AL 4500 FT AMSL\n'
      'V X=46:00:00N 014:00:00E\n'
      'DC 10',
  incorrectExample: 'AC D\n'
      'AN Example CTR\n'
      'AH 4500 FT AMSL\n'
      'AL GND\n'
      'V X=46:00:00N 014:00:00E\n'
      'DC 5\n'
      'AC D\n'
      'AN Example CTR\n'
      'AH 4500 FT AMSL\n'
      'AL GND\n'
      'V X=46:00:00N 014:00:00E\n'
      'DC 5',
  checkFile: (ctx) {
    // First group the airspaces by a cheap key. Only airspaces with the
    // same key are compared command by command.
    final groups = <String, List<_AirspaceText>>{};
    for (final a in ctx.file.airspaces) {
      if (_inStrepla(ctx, a.startLine)) continue;
      var count = 0;
      Command? firstShape;
      Command? lastShape;
      for (final c in a.commands) {
        final k = c.upperKeyword;
        if (!_specKeywords.contains(k)) continue;
        count++;
        if (_shapeKeywords.contains(k)) {
          firstShape ??= c;
          lastShape = c;
        }
      }
      if (firstShape == null) continue; // No geometry: other rules report it.
      final key = '$count|${_normalizeArgument(a.name ?? '')}|'
          '${_normalizeArgument(firstShape.argument)}|'
          '${_normalizeArgument(lastShape!.argument)}';
      final text = _AirspaceText(a);
      final list = groups[key] ??= [];
      _AirspaceText? original;
      for (final other in list) {
        if (other.sameAs(text)) {
          original = other;
          break;
        }
      }
      if (original != null) {
        ctx.reportAirspace(
            a,
            'This airspace is the same as the airspace on line '
            '${original.airspace.startLine}. Remove one of them.');
      } else {
        list.add(text);
      }
    }
  },
);

/// The commands of an airspace in a normal form, for comparison.
class _AirspaceText {
  _AirspaceText(this.airspace);

  final Airspace airspace;

  /// The commands of the specification, in upper case, with one blank
  /// between words. Computed only when needed.
  late final List<String> normalized = [
    for (final c in airspace.commands)
      if (_specKeywords.contains(c.upperKeyword))
        '${c.upperKeyword} ${_normalizeArgument(c.argument)}'
  ];

  bool sameAs(_AirspaceText other) {
    final a = normalized;
    final b = other.normalized;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final RegExp _blanks = RegExp(r'\s+');

String _normalizeArgument(String argument) =>
    argument.replaceAll(_blanks, ' ').toUpperCase();
