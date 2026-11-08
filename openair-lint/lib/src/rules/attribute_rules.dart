import '../attributes/attribute_values.dart';
import '../diagnostic.dart';
import '../lint_context.dart';
import '../model/openair_file.dart';
import '../spec_version.dart';
import 'rule.dart';

/// Rules for the airspace attributes AC, AY, AN, AF, AG and AX.
///
/// The tables of allowed values and the value checks are in
/// `lib/src/attributes/attribute_values.dart`.
final List<Rule> attributeRules = [
  _acClassMissing,
  _acUnknownClass,
  _ayTypeMissing,
  _ayUnknownType,
  _ayNotAfterAc,
  _anNameEmpty,
  _anNameTooLong,
  _anNonAscii,
  _anNameCutByComment,
  _afInvalidFormat,
  _afOutsideAirBand,
  _afInvalidChannel,
  _afNotThreeDecimals,
  _agStationEmpty,
  _agStationIsFrequency,
  _agStationCutByComment,
  _axNotFourDigits,
  _axNotOctal,
  _axEmergencyCode,
];

/// The maximum length of a name before `an-name-too-long` reports it.
const int maxNameLength = 100;

const String _classList = 'A, B, C, D, E, F, G and UNC';

// ---------------------------------------------------------------------------
// AC
// ---------------------------------------------------------------------------

final Rule _acClassMissing = Rule(
  id: 'ac-class-missing',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'ac-airspace-class',
  description: 'The AC command must contain an airspace class.',
  explanation: 'Every airspace starts with an AC command, and the AC command '
      'contains the class of the airspace. The classes are $_classList. '
      'Use UNC if the airspace has no class or the class is not known.',
  correctExample: 'AC D\nAN Example CTR',
  incorrectExample: 'AC\nAN Example CTR',
  keywords: {'AC'},
  checkCommand: (ctx, c, a) {
    if (c.argument.isNotEmpty) return;
    ctx.reportCommand(
        c,
        'AC has no class. Write the class of the airspace ($_classList), '
        'for example "AC D". Use "AC UNC" if the class is not known.');
  },
);

final Rule _acUnknownClass = Rule(
  id: 'ac-unknown-class',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'ac-airspace-class',
  description: 'The AC class must be A, B, C, D, E, F, G or UNC.',
  explanation: 'AC contains only the airspace class. The classes are '
      '$_classList (unclassified).\n'
      '\n'
      'Old OpenAir files also use AC for the type of the airspace, for '
      'example "AC R" for a restricted area or "AC CTR" for a control zone. '
      'The specification does not allow this. Write the class in AC and the '
      'type in AY. If the class is not known, write "AC UNC".',
  correctExample: 'AC UNC\nAY R\nAN Example restricted area',
  incorrectExample: 'AC R\nAN Example restricted area',
  keywords: {'AC'},
  checkCommand: (ctx, c, a) {
    final value = c.argument;
    if (value.isEmpty) return;
    final upper = value.toUpperCase();
    if (airspaceClasses.contains(upper)) return;
    ctx.reportArgument(c, _unknownClassMessage(value, upper, a));
  },
);

/// The characters that separate two classes in a value such as `D E`,
/// `C/D` or `D,E`.
final RegExp _classSeparator = RegExp(r'[\s/,;]+');

String _unknownClassMessage(String value, String upper, Airspace? airspace) {
  if (unclassifiedAliases.contains(upper)) {
    return '"$value" is not a class. For an unclassified airspace, '
        'write "AC UNC".';
  }
  final parts = upper.split(_classSeparator);
  if (parts.length > 1 && parts.every(airspaceClasses.contains)) {
    return '"$value" has more than one class. AC must contain exactly one '
        'class ($_classList). Write the class that applies to this '
        'airspace, for example "AC ${parts.first}". If the airspace has '
        'parts with different classes, write each part as its own airspace.';
  }
  final hint = typeHintFor(upper);
  final ay = airspace?.firstWith('AY');
  final start = hint != null && hint.certain
      ? '"$value" is an airspace type, not a class.'
      : '"$value" is not a class.';
  if (ay != null && ay.argument.isNotEmpty) {
    final ayType = typeHintFor(ay.argument.toUpperCase())?.type;
    if (hint != null && hint.certain && ayType != null && hint.type != ayType) {
      return '$start It means "AY ${hint.type}", but "AY ${ay.argument}" on '
          'line ${ay.line} gives a different type. Check which type is '
          'correct and write it in AY. Then write the class in AC '
          '($_classList), or "AC UNC" if the class is not known.';
    }
    return '$start The type is already in "AY ${ay.argument}". Write the '
        'class in AC ($_classList), or "AC UNC" if the class is not known.';
  }
  if (hint == null) {
    return '$start The classes are $_classList. Old files use AC for the '
        'airspace type. Write "AC UNC" (or the real class), and write the '
        'type with AY.';
  }
  if (hint.certain) {
    return '$start Write "AC UNC" (or the real class) and "AY ${hint.type}".';
  }
  return '$start Old files use AC for the airspace type. Write "AC UNC" '
      '(or the real class), and write the type with AY. The closest type is '
      'probably "AY ${hint.type}".';
}

// ---------------------------------------------------------------------------
// AY
// ---------------------------------------------------------------------------

final Rule _ayTypeMissing = Rule(
  id: 'ay-type-missing',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'ay-airspace-type',
  description: 'The AY command must contain an airspace type.',
  explanation: 'AY gives the type of the airspace, for example "AY CTR" or '
      '"AY R". An AY command without a type has no meaning. Write a type '
      'from the table in the specification, write "AY NONE" for an airspace '
      'without a type, or remove the AY command.',
  correctExample: 'AC D\nAY CTR',
  incorrectExample: 'AC D\nAY',
  keywords: {'AY'},
  checkCommand: (ctx, c, a) {
    if (c.argument.isNotEmpty) return;
    ctx.reportCommand(
        c,
        'AY has no type. Write a type from the specification, for example '
        '"AY CTR", or "AY NONE" for an airspace without a type.');
  },
);

final Rule _ayUnknownType = Rule(
  id: 'ay-unknown-type',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'ay-airspace-type',
  description: 'The AY type must be a type from the table in the '
      'specification.',
  explanation: 'AY accepts only the types in the table of the specification, '
      'for example CTR, TMA, RMZ, TMZ, R (restricted), Q (danger), '
      'P (prohibited) or GSEC (gliding sector). Use NONE for an airspace '
      'without a type. A reader does not understand other values.\n'
      '\n'
      'Old files sometimes use long names, for example "RESTRICTED" in place '
      'of "R". openair-lint suggests the type from the table when it can.',
  correctExample: 'AC UNC\nAY R',
  incorrectExample: 'AC UNC\nAY RESTRICTED',
  keywords: {'AY'},
  checkCommand: (ctx, c, a) {
    final value = c.argument;
    if (value.isEmpty) return;
    final upper = value.toUpperCase();
    if (isAirspaceType(upper)) return;
    ctx.reportArgument(c, _unknownTypeMessage(value, upper));
  },
);

String _unknownTypeMessage(String value, String upper) {
  final start = '"$value" is not an airspace type from the specification.';
  if (airspaceClasses.contains(upper)) {
    return '$start "$value" is an airspace class. Write the class in AC, and '
        'write a type in AY, or "AY NONE" if the airspace has no type.';
  }
  if (unclassifiedAliases.contains(upper)) {
    return '$start For an airspace without a type, write "AY NONE".';
  }
  final hint = typeHintFor(upper);
  if (hint == null) {
    return '$start Use a type from the table, for example "AY CTR", or '
        '"AY NONE" for an airspace without a type.';
  }
  if (hint.certain) return '$start Write "AY ${hint.type}".';
  return '$start The closest type is probably "AY ${hint.type}". Check the '
      'table in the specification.';
}

final Rule _ayNotAfterAc = Rule(
  id: 'ay-not-after-ac',
  severity: Severity.info,
  versions: SpecVersion.all,
  specAnchor: 'ay-airspace-type',
  description: 'AY is usually written directly after the AC command.',
  explanation: 'The specification says that AY is typically used immediately '
      'after the AC command. The class and the type together describe the '
      'airspace, so they are easier to read on two lines next to each other. '
      'The order does not change the meaning.',
  correctExample: 'AC E\nAY RMZ\nAN Example RMZ',
  incorrectExample: 'AC E\nAN Example RMZ\nAY RMZ',
  checkAirspace: (ctx, a) {
    final ay = a.firstWith('AY');
    if (ay == null || a.commands.length < 2 || identical(a.commands[1], ay)) {
      return;
    }
    ctx.reportKeyword(
        ay,
        'Write AY directly after the AC command on line ${a.ac.line}. '
        'This makes the class and the type easy to read together.');
  },
);

// ---------------------------------------------------------------------------
// AN
// ---------------------------------------------------------------------------

final Rule _anNameEmpty = Rule(
  id: 'an-name-empty',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'an-airspace-name',
  description: 'The AN command must contain a name.',
  explanation: 'AN gives the name of the airspace. Pilots see this name on '
      'the map and in warnings. An AN command without a name has no '
      'meaning. Write the name, or remove the AN command.',
  correctExample: 'AC D\nAN Example CTR',
  incorrectExample: 'AC D\nAN',
  keywords: {'AN'},
  checkCommand: (ctx, c, a) {
    if (c.argument.isNotEmpty) return;
    ctx.reportCommand(
        c,
        'AN has no name. Write the name of the airspace, for example '
        '"AN Example CTR", or remove the AN command.');
  },
);

final Rule _anNameTooLong = Rule(
  id: 'an-name-too-long',
  severity: Severity.info,
  versions: SpecVersion.all,
  specAnchor: 'an-airspace-name',
  description: 'The AN name is very long (more than $maxNameLength '
      'characters).',
  explanation: 'Pilots read the name on small screens. A very long name is '
      'hard to show and hard to read. Very long names often contain data '
      'that belongs in other commands: put the frequency in AF, the station '
      'name in AG, the altitudes in AH and AL, and the activation times '
      'in AA.\n'
      '\n'
      'The specification has no limit for the length. openair-lint reports '
      'names with more than $maxNameLength characters.',
  correctExample: 'AN TSA EXAMPLE 22\nAF 135.630',
  incorrectExample:
      'AN TSA EXAMPLE 22 135.63 125.00 125.78 129.65 132.125 129.425 134.455 '
      '135.80 122.575 128.275 131.275 133.615 255.70 121.50',
  keywords: {'AN'},
  checkCommand: (ctx, c, a) {
    final length = c.argument.runes.length;
    if (length <= maxNameLength) return;
    ctx.reportArgument(
        c,
        'The name has $length characters. Long names are hard to read on '
        'small screens. Keep the name short, and put other data in its own '
        'command (AF, AG, AH, AL or AA).');
  },
);

final Rule _anNonAscii = Rule(
  id: 'an-non-ascii',
  severity: Severity.info,
  versions: SpecVersion.all,
  specAnchor: 'an-airspace-name',
  description: 'The AN name contains special (non-ASCII) characters.',
  explanation: 'Any UTF-8 character is allowed in the name. But some older '
      'systems cannot show special characters correctly. The specification '
      'says that it is better to use simpler characters, for example "ue" '
      'in place of "ü".',
  correctExample: 'AN CTR Muenchen',
  incorrectExample: 'AN CTR München',
  keywords: {'AN'},
  checkCommand: (ctx, c, a) {
    final name = c.argument;
    final first = _firstNonAscii(name);
    if (first < 0) return;
    // Double-encoded text is reported by file-garbled-text (header group).
    if (findDoubleEncoding(name) != null) return;
    final special = <String>{};
    for (final rune in name.runes) {
      if (rune > 0x7E && rune != 0xFFFD) special.add(_showChar(rune));
    }
    final ascii = asciiVersion(name);
    final buffer = StringBuffer('The name contains special characters: '
        '${special.join(' ')}. Some older systems cannot show them. '
        'The specification recommends simpler characters.');
    if (ascii != null && ascii != name) {
      buffer.write(' For example: "AN $ascii".');
    }
    var last = name.length;
    while (last > first && !isNonAscii(name.codeUnitAt(last - 1))) {
      last--;
    }
    ctx.reportArgument(c, buffer.toString(),
        offset: first, length: last - first);
  },
);

/// The offset of the first non-ASCII character in [text] that is not a
/// replacement character (invalid UTF-8 is reported by another rule), or -1.
int _firstNonAscii(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (isNonAscii(c) && c != 0xFFFD) return i;
  }
  return -1;
}

String _showChar(int rune) {
  if (rune == 0xA0) return '(no-break space)';
  if (rune < 0xA0) {
    return '(control character U+${rune.toRadixString(16).toUpperCase()})';
  }
  return '"${String.fromCharCode(rune)}"';
}

const String _cutExplanation = 'The "*" character starts a comment, and the '
    'comment runs to the end of the line. This is also true after AN and AG. '
    'A reader shows only the text before the "*". If the "*" is part of the '
    'text, the rest of the text is lost.\n'
    '\n'
    'openair-lint reports a comment that looks like a part of the text: a '
    'pair of "*" around words (for example "(*NOTAM*)" or "*TWR HRS*"), a '
    '"*" without a blank before it (for example "ALPHA* MTA ALPHAVILLE"), or '
    'text before the "*" with a bracket that is not closed. Remove the "*" '
    'characters from the text. A real comment needs a blank before the "*". '
    'A real comment can contain more "*" characters, for example "AN Wien '
    'CTR * source: AIP *AMDT 3*".';

final Rule _anNameCutByComment = Rule(
  id: 'an-name-cut-by-comment',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'seeyou-openair-file-format-specification',
  description: 'The AN name should not contain "*". The "*" starts a comment '
      'and cuts the name.',
  explanation: _cutExplanation,
  correctExample: 'AN EKR664 ZONE 1 (NOTAM)',
  incorrectExample: 'AN EKR664 ZONE 1 (*NOTAM*)',
  keywords: {'AN'},
  checkCommand: (ctx, c, a) => _checkCutByComment(ctx, c, 'name'),
);

/// Reports [c] if its comment probably cuts the text of AN or AG in two.
/// [what] is the word for the text in the message ("name" or
/// "station name").
void _checkCutByComment(LintContext ctx, Command c, String what) {
  final comment = c.comment;
  final starColumn = c.commentColumn;
  if (comment == null || starColumn == null || c.argument.isEmpty) return;
  final rest = comment.trim();
  // "AN Name *" and decoration such as "AN Name ** note" are real comments.
  if (rest.isEmpty || rest.startsWith('*')) return;
  final starIndex = starColumn - 1;
  final before = starIndex > 0 ? c.text[starIndex - 1] : ' ';
  final noBlankBefore = before != ' ' && before != '\t';
  // A pair of "*" around a word or words, as in "*TWR HRS*" or "(*NOTAM*)":
  // the first "*" is directly before a word, and the second "*" is
  // directly after a word. A comment such as "* source: AIP *AMDT 3*" is a
  // real comment that only contains a "*".
  final starPair = _starPair.hasMatch(comment);
  final unclosed = _hasUnclosedBracket(c.argument);
  if (!noBlankBefore && !starPair && !unclosed) return;
  final fixed = c.text
      .substring(c.argumentColumn - 1)
      .replaceAll('*', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  ctx.report(
      'The "*" starts a comment, so readers show only the $what '
      '"${c.argument}". The text after the "*" is lost. If this text is '
      'part of the $what, remove the "*" characters: '
      '"${c.upperKeyword} $fixed".',
      line: c.line,
      column: starColumn,
      endColumn: c.text.trimRight().length + 1);
}

/// The text of a comment (after its "*") that starts directly with a word
/// and has a second "*" directly after a word: `TWR HRS* ...`.
final RegExp _starPair = RegExp(r'^[^\s*]([^*]*[^\s*])?\*');

/// True if [text] has more opening than closing brackets of one kind.
bool _hasUnclosedBracket(String text) {
  int count(String char) => char.allMatches(text).length;
  return count('(') > count(')') || count('[') > count(']');
}

// ---------------------------------------------------------------------------
// AF
// ---------------------------------------------------------------------------

const String _bandText = '118.000 to 136.990 MHz';

final Rule _afInvalidFormat = Rule(
  id: 'af-invalid-format',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'af-airspace-frequency',
  description: 'The AF frequency must be one number in MHz, with a dot as '
      'the decimal separator.',
  explanation: 'AF gives the radio frequency that pilots use for this '
      'airspace. Write one frequency in MHz, with a dot as the decimal '
      'separator and without a unit, for example "AF 123.300". A reader '
      'cannot use a value with a comma, a unit, letters or more than one '
      'frequency.\n'
      '\n'
      'Put the name of the radio station in AG, not in AF.',
  correctExample: 'AF 123.300\nAG Example Information',
  incorrectExample: 'AF 123,300 MHz',
  keywords: {'AF'},
  checkCommand: (ctx, c, a) {
    final problem = frequencyFormatProblem(c.argument);
    if (problem == null) return;
    if (c.argument.isEmpty) {
      ctx.reportCommand(c, problem);
    } else {
      ctx.reportArgument(c, problem);
    }
  },
);

final Rule _afOutsideAirBand = Rule(
  id: 'af-outside-air-band',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'af-airspace-frequency',
  description: 'The AF frequency should be in the VHF air band '
      '($_bandText).',
  explanation: 'Glider pilots use VHF radios. The VHF air band for voice '
      'is from 118.000 to 136.990 MHz. A frequency outside this band is '
      'usually a mistake, for example a navigation frequency (VOR) or a '
      'military UHF frequency, or the value is in kHz and not in MHz.\n'
      '\n'
      'The specification does not define the frequency band. openair-lint '
      'reports a warning because such a value is almost always a mistake.',
  correctExample: 'AF 123.300',
  incorrectExample: 'AF 114.880',
  keywords: {'AF'},
  checkCommand: (ctx, c, a) {
    final f = parseFrequency(c.argument);
    if (f == null || f.inAirBand) return;
    final khz = f.khz;
    final asMhz = (f.decimals == 0 &&
            khz != null &&
            khz ~/ 1000 >= airBandLowKhz &&
            khz ~/ 1000 <= airBandHighKhz)
        ? ' If the value is in kHz, write it in MHz: '
            '"AF ${formatKhz(khz ~/ 1000)}".'
        : '';
    ctx.reportArgument(
        c,
        '${f.text} MHz is outside the VHF air band for voice '
        '($_bandText). Check the frequency.$asMhz');
  },
);

final Rule _afInvalidChannel = Rule(
  id: 'af-invalid-channel',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'af-airspace-frequency',
  description: 'The AF frequency should be a valid 25 kHz or 8.33 kHz '
      'channel name.',
  explanation: 'Pilots set a channel name on the radio, for example 118.005 '
      'or 123.455. With 25 kHz and 8.33 kHz channel spacing, the last two '
      'digits of a channel name are 00, 05, 10, 15, 25, 30, 35, 40, 50, 55, '
      '60, 65, 75, 80, 85 or 90. Other values, for example 118.020 or '
      '123.456, are not channels that a radio can use.\n'
      '\n'
      'A value with two decimals that ends in 2 or 7, for example 122.47, is '
      'often a 25 kHz frequency with the last digit cut off (122.475).\n'
      '\n'
      'A value with more than three decimals is accepted if it is the radio '
      'frequency of a channel (within 1 kHz), for example 118.0083 for the '
      'channel 118.010. af-not-three-decimals then asks for the channel '
      'name. Other values, for example 123.4567, are reported here.\n'
      '\n'
      'The specification does not define the channels. openair-lint reports '
      'a warning because such a value is almost always a mistake.',
  correctExample: 'AF 122.475',
  incorrectExample: 'AF 122.47',
  keywords: {'AF'},
  checkCommand: (ctx, c, a) {
    final f = parseFrequency(c.argument);
    if (f == null || !f.inAirBand || f.channelKhz != null) return;
    if (f.khz == null) {
      // More than 3 decimals, and no channel has a real frequency close to
      // the value.
      final (nearest, _) = nearestChannelByFrequency(f.mhz * 1000);
      ctx.reportArgument(
          c,
          '${f.text} is not the frequency of a channel. The nearest channel '
          'name is ${formatKhz(nearest)}. Write the channel name that pilots '
          'set on the radio, with three decimals.');
      return;
    }
    final khz = f.khz!;
    final (low, high) = nearestChannelNames(khz);
    final buffer = StringBuffer('${f.text} is not a valid channel name. '
        'The nearest channel names are ${formatKhz(low)} and '
        '${formatKhz(high)}.');
    if (f.decimals == 2 && (khz % 100 == 20 || khz % 100 == 70)) {
      buffer.write(' If you mean the 25 kHz frequency ${formatKhz(khz + 5)}, '
          'write all three decimals: "AF ${formatKhz(khz + 5)}".');
    }
    ctx.reportArgument(c, buffer.toString());
  },
);

final Rule _afNotThreeDecimals = Rule(
  id: 'af-not-three-decimals',
  severity: Severity.info,
  versions: SpecVersion.all,
  specAnchor: 'af-airspace-frequency',
  description: 'Write the AF frequency with three decimals.',
  explanation: 'The example in the specification uses three decimals: '
      '"AF 123.300". With 8.33 kHz channel spacing, three decimals are '
      'necessary to show the channel, for example 118.005. Write every '
      'frequency with three decimals, so that all frequencies look the same '
      'and pilots can set the exact channel.\n'
      '\n'
      'Write the channel name that pilots set on the radio. Do not write '
      'the exact 8.33 kHz frequency, for example write 118.010, '
      'not 118.0083.',
  correctExample: 'AF 126.100',
  incorrectExample: 'AF 126.1',
  keywords: {'AF'},
  checkCommand: (ctx, c, a) {
    final f = parseFrequency(c.argument);
    if (f == null || f.decimals == 3 || !f.inAirBand) return;
    // A value that is not a channel is reported by af-invalid-channel,
    // with a better fix.
    final channel = f.channelKhz;
    if (channel == null) return;
    if (f.khz != null) {
      ctx.reportArgument(c,
          'Write the frequency with three decimals: "AF ${formatKhz(channel)}".');
    } else {
      ctx.reportArgument(
          c,
          '${f.text} is not a channel name. It is the radio frequency of the '
          'channel ${formatKhz(channel)}. Write the channel name that pilots '
          'set on the radio, with three decimals: '
          '"AF ${formatKhz(channel)}".');
    }
  },
);

// ---------------------------------------------------------------------------
// AG
// ---------------------------------------------------------------------------

final Rule _agStationEmpty = Rule(
  id: 'ag-station-empty',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'ag-station-name',
  description: 'The AG command must contain a station name.',
  explanation: 'AG gives the name of the radio station that controls the '
      'airspace, as a pilot says it in a radio call, for example '
      '"AG Nordholz Radar". An AG command without a name has no meaning. '
      'Write the name, or remove the AG command.',
  correctExample: 'AF 123.300\nAG Nordholz Radar',
  incorrectExample: 'AF 123.300\nAG',
  keywords: {'AG'},
  checkCommand: (ctx, c, a) {
    if (c.argument.isNotEmpty) return;
    ctx.reportCommand(
        c,
        'AG has no station name. Write the name that pilots use in a radio '
        'call, for example "AG Nordholz Radar", or remove the AG command.');
  },
);

final RegExp _frequencyLike = RegExp(r'^\d{2,3}[.,]\d{1,4}$');

final Rule _agStationIsFrequency = Rule(
  id: 'ag-station-is-frequency',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'ag-station-name',
  description: 'The AG station name should be a name, not a frequency.',
  explanation: 'AG gives the name of the radio station, for example '
      '"AG Nordholz Radar". The frequency belongs in AF. A reader shows the '
      'AG text as the name of the station.\n'
      '\n'
      'The specification does not forbid numbers in AG. openair-lint reports '
      'a warning because a frequency in AG is almost always a mistake.',
  correctExample: 'AF 118.655\nAG Vamdrup Information',
  incorrectExample: 'AG 118.655',
  keywords: {'AG'},
  checkCommand: (ctx, c, a) {
    if (!_frequencyLike.hasMatch(c.argument)) return;
    ctx.reportArgument(
        c,
        '"${c.argument}" is a frequency, not a station name. Put the '
        'frequency in AF, and the name of the station in AG.');
  },
);

final Rule _agStationCutByComment = Rule(
  id: 'ag-station-cut-by-comment',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'seeyou-openair-file-format-specification',
  description: 'The AG station name should not contain "*". The "*" starts a '
      'comment and cuts the name.',
  explanation: _cutExplanation,
  correctExample: 'AG Langen Information (FIS)',
  incorrectExample: 'AG Langen Information (*FIS*)',
  keywords: {'AG'},
  checkCommand: (ctx, c, a) => _checkCutByComment(ctx, c, 'station name'),
);

// ---------------------------------------------------------------------------
// AX
// ---------------------------------------------------------------------------

final Rule _axNotFourDigits = Rule(
  id: 'ax-not-four-digits',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'ax-transponder-code',
  description: 'The AX transponder code must have exactly 4 digits.',
  explanation: 'AX gives the transponder code (squawk) for the airspace. '
      'The specification requires a code with 4 digits, for example '
      '"AX 7000". Write all 4 digits, also a zero at the start: write '
      '"AX 0424", not "AX 424". Do not add other text.',
  correctExample: 'AX 0424',
  incorrectExample: 'AX 424',
  keywords: {'AX'},
  checkCommand: (ctx, c, a) {
    final code = c.argument;
    if (isFourDigitCode(code)) return;
    if (code.isEmpty) {
      ctx.reportCommand(c,
          'AX has no transponder code. Write a code with 4 digits, for example "AX 7000".');
      return;
    }
    var message = 'The transponder code must have exactly 4 digits, but '
        '"$code" has ${RegExp(r'[0-9]').allMatches(code).length} digits'
        '${RegExp(r'^[0-9]+$').hasMatch(code) ? '' : ' and other characters'}.';
    if (RegExp(r'^[0-7]{1,3}$').hasMatch(code)) {
      message += ' If the code starts with zeros, write them: '
          '"AX ${code.padLeft(4, '0')}".';
    } else if (RegExp(r'^[0-9]{1,3}$').hasMatch(code)) {
      // Leading zeros do not help: the digit 8 or 9 is not possible in a
      // transponder code (ax-not-octal).
      message += ' Zeros at the start do not make it a valid code, because '
          'transponder codes use only the digits 0 to 7. Check the value.';
    } else {
      message += ' Write only the 4 digits, for example "AX 7000".';
    }
    ctx.reportArgument(c, message);
  },
);

final Rule _axNotOctal = Rule(
  id: 'ax-not-octal',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'ax-transponder-code',
  description: 'The AX transponder code should use only the digits 0 to 7.',
  explanation: 'A transponder code has 4 octal digits. Each digit is '
      'from 0 to 7, so there are 4096 codes, from 0000 to 7777. A '
      'transponder cannot be set to a code with the digit 8 or 9. Such a '
      'code is almost always a mistake.\n'
      '\n'
      'The specification only requires 4 digits. It does not say that the '
      'digits must be from 0 to 7. For this reason, openair-lint reports a '
      'warning and not an error.',
  correctExample: 'AX 4410',
  incorrectExample: 'AX 4810',
  keywords: {'AX'},
  checkCommand: (ctx, c, a) {
    final code = c.argument;
    if (!isFourDigitCode(code)) return;
    if (!code.contains(RegExp('[89]'))) return;
    ctx.reportArgument(
        c,
        '"$code" is not a transponder code. A transponder code uses only the '
        'digits 0 to 7, so 8 and 9 are not possible.');
  },
);

final Rule _axEmergencyCode = Rule(
  id: 'ax-emergency-code',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'ax-transponder-code',
  description: 'The AX transponder code should not be an emergency code '
      '(7500, 7600 or 7700).',
  explanation: 'The codes 7500 (unlawful interference), 7600 (radio failure) '
      'and 7700 (emergency) have a special meaning everywhere. An airspace '
      'never asks pilots to use them. Such a code in AX is a mistake.\n'
      '\n'
      'The specification does not list these codes. openair-lint reports a '
      'warning because such a code is almost always a mistake.',
  correctExample: 'AX 7000',
  incorrectExample: 'AX 7700',
  keywords: {'AX'},
  checkCommand: (ctx, c, a) {
    final meaning = emergencyCodes[c.argument];
    if (meaning == null) return;
    ctx.reportArgument(
        c,
        '${c.argument} is the transponder code for $meaning. An airspace '
        'never uses this code. Check the value.');
  },
);
