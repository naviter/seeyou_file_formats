import '../attributes/attribute_values.dart';
import '../diagnostic.dart';
import '../fix.dart';
import '../lint_context.dart';
import '../model/openair_file.dart';
import '../spec_version.dart';
import 'rule.dart';

/// Rules for the airspace attributes AC, AY, AN, AF, AG, AS and AX.
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
  _anContainsAsterisk,
  _anContainsAsteriskV21,
  _afInvalidFormat,
  _afOutsideAirBand,
  _afOutsideAirBandV21,
  _afInvalidChannel,
  _afInvalidChannelV21,
  _afNotThreeDecimals,
  _agStationEmpty,
  _agStationIsFrequency,
  _agContainsAsterisk,
  _agContainsAsteriskV21,
  _asSourceMissing,
  _asUnknownSource,
  _asNeedsVersion3,
  _axNotFourDigits,
  _axNotOctal,
  _axNotOctalV21,
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
  fixDescription: '--fix writes "UNC" in place of an old word for '
      '"unclassified": UNCLASSIFIED, UNCL, UNK, UKN or UNKNOWN. It does not '
      'change other values.',
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
    ctx.reportArgument(c, _unknownClassMessage(value, upper, a),
        fix:
            unclassifiedAliases.contains(upper) ? argumentFix(c, 'UNC') : null);
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
  fixDescription: '--fix writes the type of the table in place of a word '
      'with the same meaning, for example "R" in place of "RESTRICTED" and '
      '"GSEC" in place of "GLIDING_SECTOR". It does not change a value '
      'when the type is only a guess.',
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
    final hint = typeHintFor(upper);
    ctx.reportArgument(c, _unknownTypeMessage(value, upper),
        fix: hint != null &&
                hint.certain &&
                !airspaceClasses.contains(upper) &&
                !unclassifiedAliases.contains(upper)
            ? argumentFix(c, hint.type)
            : null);
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

String _asteriskExplanation(String keyword, String what) =>
    'The "*" character always starts a comment, and the comment runs to the '
    'end of the line. For this reason, the $what after $keyword cannot '
    'contain "*", and a comment is not allowed on the same line as '
    '$keyword. A reader shows only the text before the "*" as the $what.\n'
    '\n'
    'If the "*" is part of the $what, remove the "*" characters. If the '
    'text after the "*" is a comment, put the comment on its own line, '
    'before or after the $keyword line.\n'
    '\n'
    'In version 2.1 files this is a warning '
    '(${keyword.toLowerCase()}-contains-asterisk-v21).';

String _asteriskExplanationV21(String keyword, String what) =>
    'The version 2.1 text says: a comment begins with "*" and extends to '
    'the end of the line. So also in a version 2.1 file, a reader shows only '
    'the text before the "*" as the $what.\n'
    '\n'
    'If the "*" is part of the $what, remove the "*" characters. If the '
    'text after the "*" is a comment, put the comment on its own line, '
    'before or after the $keyword line.\n'
    '\n'
    'Version 3.0 also says that the $what cannot contain "*" and that a '
    'comment is not allowed on the same line as $keyword. In version 3.0 '
    'this is an error (${keyword.toLowerCase()}-contains-asterisk).';

/// The anchor of the general requirements (with the comment syntax) in the
/// version 2.1 text: the title of the document.
const String _generalAnchor21 = 'seeyou-openair-file-format-specification';

final Rule _anContainsAsterisk = Rule(
  id: 'an-contains-asterisk',
  severity: Severity.error,
  versions: SpecVersion.only3,
  specAnchor: 'an-airspace-name',
  description: 'An AN line must not contain "*". The "*" starts a comment, '
      'and a comment is not allowed on the same line as AN.',
  explanation: _asteriskExplanation('AN', 'name'),
  correctExample: '* part in France\n'
      'AN EKR664 ZONE 1 (NOTAM)',
  incorrectExample: 'AN EKR664 ZONE 1 (*NOTAM*) * part in France',
  keywords: {'AN'},
  checkCommand: (ctx, c, a) => _checkAsterisk(ctx, c, 'name'),
);

final Rule _agContainsAsterisk = Rule(
  id: 'ag-contains-asterisk',
  severity: Severity.error,
  versions: SpecVersion.only3,
  specAnchor: 'ag-station-name',
  description: 'An AG line must not contain "*". The "*" starts a comment, '
      'and a comment is not allowed on the same line as AG.',
  explanation: _asteriskExplanation('AG', 'station name'),
  correctExample: '* only in summer\n'
      'AG Langen Information (FIS)',
  incorrectExample: 'AG Langen Information (*FIS*) * only in summer',
  keywords: {'AG'},
  checkCommand: (ctx, c, a) => _checkAsterisk(ctx, c, 'station name'),
);

final Rule _anContainsAsteriskV21 = Rule(
  id: 'an-contains-asterisk-v21',
  severity: Severity.warning,
  versions: SpecVersion.only21,
  specAnchor: _generalAnchor21,
  anchorInVersion21Text: true,
  description: 'An AN line should not contain "*" (version 2.1). The "*" '
      'starts a comment, so readers cut the name there.',
  explanation: _asteriskExplanationV21('AN', 'name'),
  correctExample: '* part in France\n'
      'AN EKR664 ZONE 1 (NOTAM)',
  incorrectExample: 'AN EKR664 ZONE 1 (*NOTAM*) * part in France',
  keywords: {'AN'},
  checkCommand: (ctx, c, a) => _checkAsterisk(ctx, c, 'name'),
);

final Rule _agContainsAsteriskV21 = Rule(
  id: 'ag-contains-asterisk-v21',
  severity: Severity.warning,
  versions: SpecVersion.only21,
  specAnchor: _generalAnchor21,
  anchorInVersion21Text: true,
  description: 'An AG line should not contain "*" (version 2.1). The "*" '
      'starts a comment, so readers cut the station name there.',
  explanation: _asteriskExplanationV21('AG', 'station name'),
  correctExample: '* only in summer\n'
      'AG Langen Information (FIS)',
  incorrectExample: 'AG Langen Information (*FIS*) * only in summer',
  keywords: {'AG'},
  checkCommand: (ctx, c, a) => _checkAsterisk(ctx, c, 'station name'),
);

/// Reports [c] (an AN or AG command) if its line contains "*". [what] is
/// the word for the text in the message ("name" or "station name").
void _checkAsterisk(LintContext ctx, Command c, String what) {
  final comment = c.comment;
  final starColumn = c.commentColumn;
  if (comment == null || starColumn == null) return;
  final keyword = c.upperKeyword;
  final shown = c.argument.isEmpty
      ? 'readers show an empty $what'
      : 'readers show only the $what "${c.argument}"';
  // The version 2.1 text does not forbid a comment after AN or AG. It only
  // says that a comment runs to the end of the line.
  final notAllowed = ctx.isV21
      ? ''
      : ' A comment is not allowed on the same line as $keyword.';
  final buffer = StringBuffer('The "*" starts a comment, so the $what ends '
      'before the "*", and $shown.$notAllowed');
  if (_looksLikePartOfText(c, comment, starColumn)) {
    final fixed = c.text
        .substring(c.argumentColumn - 1)
        .replaceAll('*', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    buffer.write(' If the text after the "*" is part of the $what, remove '
        'the "*" characters: "$keyword $fixed".');
  } else {
    final rest = comment.replaceFirst(RegExp(r'^[\s*]+'), '').trimRight();
    buffer.write(rest.isEmpty
        ? ' Remove the "*".'
        : ' Remove the "*", or put the comment on its own line: "* $rest".');
  }
  ctx.report(buffer.toString(),
      line: c.line,
      column: starColumn,
      endColumn: c.text.trimRight().length + 1);
}

/// True if the text after the first "*" of [c] probably belongs to the
/// name or the station name. This only selects the advice in the message.
///
/// Such text is: a pair of "*" around words (for example "(*NOTAM*)" or
/// "*TWR HRS*"), a "*" without a blank before it (for example
/// "ALPHA* MTA ALPHAVILLE"), or a name before the "*" with a bracket that
/// is not closed.
bool _looksLikePartOfText(Command c, String comment, int starColumn) {
  final rest = comment.trim();
  // "AN Name *" and decoration such as "AN Name ** note" are comments.
  if (rest.isEmpty || rest.startsWith('*')) return false;
  if (_starPair.hasMatch(comment)) return true;
  if (c.argument.isEmpty) return false;
  final starIndex = starColumn - 1;
  final before = starIndex > 0 ? c.text[starIndex - 1] : ' ';
  return (before != ' ' && before != '\t') || _hasUnclosedBracket(c.argument);
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
  fixDescription: '--fix writes a dot in place of a decimal comma '
      '("123.300" in place of "123,300"), and removes the unit MHz '
      '("123.300" in place of "123.300 MHz"). It does not change other '
      'values.',
  description: 'The AF frequency must be one number in MHz, with a dot as '
      'the decimal separator and without a unit.',
  explanation: 'AF gives the radio frequency that pilots use for this '
      'airspace. Write one frequency in MHz, with a dot as the decimal '
      'separator and without a unit, for example "AF 123.300". A reader '
      'cannot use a value with a comma, a unit, letters or more than one '
      'frequency.\n'
      '\n'
      'If the airspace has more than one frequency, write one AF command '
      'for each frequency. Put the name of the radio station in AG, not '
      'in AF.',
  correctExample: 'AF 123.300\nAG Example Information',
  incorrectExample: 'AF 123,300 MHz',
  keywords: {'AF'},
  checkCommand: (ctx, c, a) {
    final problem = frequencyFormatProblem(c.argument);
    if (problem == null) return;
    if (c.argument.isEmpty) {
      ctx.reportCommand(c, problem);
    } else {
      ctx.reportArgument(c, problem,
          fix: frequencyFormatFix(c.argument) == null
              ? null
              : argumentFix(c, frequencyFormatFix(c.argument)!));
    }
  },
);

final Rule _afOutsideAirBand = Rule(
  id: 'af-outside-air-band',
  severity: Severity.error,
  versions: SpecVersion.only3,
  specAnchor: 'af-airspace-frequency',
  description: 'The AF frequency must be in the VHF air band '
      '($_bandText).',
  explanation: 'The specification requires a channel in the VHF air band, '
      'from 118.000 to 136.990 MHz. Glider pilots use VHF radios. A '
      'frequency outside this band is usually a mistake, for example a '
      'navigation frequency (VOR) or a military UHF frequency, or the value '
      'is in kHz and not in MHz.',
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
  severity: Severity.error,
  versions: SpecVersion.only3,
  specAnchor: 'af-airspace-frequency',
  description: 'The AF frequency must be a valid 25 kHz or 8.33 kHz '
      'channel name.',
  explanation: 'Pilots set a channel name on the radio, for example 118.005 '
      'or 123.455. With 25 kHz and 8.33 kHz channel spacing, not every '
      'value is a channel. The last two digits of a channel name are 00, '
      '05, 10, 15, 25, 30, 35, 40, 50, 55, 60, 65, 75, 80, 85 or 90. Other '
      'values, for example 118.020 or 123.456, are not channels that a '
      'radio can use.\n'
      '\n'
      'A value with two decimals that ends in 2 or 7, for example 122.47, is '
      'often a 25 kHz frequency with the last digit cut off (122.475).\n'
      '\n'
      'A value with more than three decimals that is the exact radio '
      'frequency of a channel (within 1 kHz), for example 118.0083 for the '
      'channel 118.010, is reported by af-not-three-decimals. Other values '
      'with more than three decimals, for example 123.4567, are reported '
      'here.',
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

final Rule _afOutsideAirBandV21 = version21Warning(
  _afOutsideAirBand,
  description: 'The AF frequency should be in the VHF air band '
      '($_bandText) (version 2.1).',
);

final Rule _afInvalidChannelV21 = version21Warning(
  _afInvalidChannel,
  description: 'The AF frequency should be a valid 25 kHz or 8.33 kHz '
      'channel name (version 2.1).',
);

final Rule _afNotThreeDecimals = Rule(
  id: 'af-not-three-decimals',
  severity: Severity.error,
  versions: SpecVersion.only3,
  specAnchor: 'af-airspace-frequency',
  fixDescription: '--fix writes the frequency with three decimals, for '
      'example "126.100" in place of "126.1" or "126.1000". It does not '
      'change a radio frequency such as 118.0083 to a channel name.',
  description: 'The AF frequency must have exactly three decimals.',
  explanation: 'The specification requires one number with a dot and '
      'exactly three decimals, for example "AF 123.300" or "AF 118.005". '
      'With 8.33 kHz channel spacing, three decimals are necessary to show '
      'the channel. Write "AF 126.100", not "AF 126.1" or "AF 126.1000".\n'
      '\n'
      'Write the channel name that pilots set on the radio, not the exact '
      'radio frequency. For example, write 118.010, not 118.0083.\n'
      '\n'
      'Version 2.1 did not define the number of decimals, so this rule '
      'applies only to version 3.0.',
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
          'Write the frequency with three decimals: "AF ${formatKhz(channel)}".',
          fix: argumentFix(c, formatKhz(channel)));
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

// ---------------------------------------------------------------------------
// AS
// ---------------------------------------------------------------------------

const String _sourceList = 'AIP, NOTAM, AIP+NOTAM or CUSTOM';

final Rule _asSourceMissing = Rule(
  id: 'as-source-missing',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'as-airspace-source',
  description: 'The AS command must contain a source.',
  explanation: 'AS says where the airspace and its activation are '
      'published. The values are $_sourceList. An AS command without a '
      'value has no meaning. Write the value, or remove the AS command. An '
      'airspace without AS is the same as "AS AIP".',
  correctExample: 'AS NOTAM',
  incorrectExample: 'AS',
  keywords: {'AS'},
  checkCommand: (ctx, c, a) {
    if (airspaceSourceWords(c.argument).isNotEmpty) return;
    ctx.reportArgument(
        c,
        'AS has no source. Write $_sourceList, for example "AS NOTAM", or '
        'remove the AS command.');
  },
);

final Rule _asUnknownSource = Rule(
  id: 'as-unknown-source',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'as-airspace-source',
  fixDescription: '--fix writes the correct value when the value has the '
      'right sources in a wrong form, for example "AIP+NOTAM" in place of '
      '"AIP + NOTAM" or "NOTAM+AIP", and "AIP" in place of "AIP+". It does '
      'not change other values.',
  description: 'The AS value must be AIP, NOTAM, AIP+NOTAM or CUSTOM.',
  explanation: 'AS says where the airspace and its activation are '
      'published. Only these values are allowed:\n'
      '\n'
      'AIP: the airspace and its activation times are published in the '
      'AIP, including AIP amendments and AIP supplements.\n'
      'NOTAM: the airspace exists only because of a NOTAM.\n'
      'AIP+NOTAM: the airspace is published in the AIP, and a NOTAM can also '
      'activate it.\n'
      'CUSTOM: the airspace does not come from an official publication.\n'
      '\n'
      'AIP+NOTAM is one value. Write it without spaces. Other combinations, '
      'for example NOTAM+CUSTOM, are not allowed.',
  correctExample: 'AS AIP+NOTAM',
  incorrectExample: 'AS AIP + NOTAM',
  keywords: {'AS'},
  checkCommand: (ctx, c, a) {
    final value = c.argument;
    // Lower case is reported by case-not-upper-case.
    if (airspaceSourceWords(value).isEmpty ||
        airspaceSources.contains(value.toUpperCase())) {
      return;
    }
    final correction = airspaceSourceCorrection(value);
    final String advice;
    if (correction != null) {
      advice = 'Write "AS $correction".';
    } else if (airspaceSourceWords(value)
        .every(const {'AIP', 'NOTAM', 'CUSTOM'}.contains)) {
      advice = 'The only combination is AIP+NOTAM. Write one value: '
          '$_sourceList.';
    } else {
      advice = 'The values are $_sourceList. ${_unknownSourceHint(value)}';
    }
    ctx.reportArgument(c, '"$value" is not a value of AS. $advice',
        fix: correction == null ? null : argumentFix(c, correction));
  },
);

String _unknownSourceHint(String value) {
  final upper = value.toUpperCase();
  if (upper.contains('AIP') || upper == 'SUP' || upper == 'AMDT') {
    return 'AIP amendments and AIP supplements are part of the AIP: '
        'write "AIP" or "AIP+NOTAM".';
  }
  if (upper.contains('NOTAM')) return 'Write "NOTAM" or "AIP+NOTAM".';
  return 'If the airspace does not come from an official publication, '
      'write "CUSTOM".';
}

final Rule _asNeedsVersion3 = Rule(
  id: 'as-needs-version-3',
  severity: Severity.error,
  versions: SpecVersion.only21,
  specAnchor: 'as-airspace-source',
  description: 'The AS command needs version 3.0.',
  explanation: 'The AS command is new in version 3.0. Version 2.1 does not '
      'define it, so a reader of version 2.1 does not know it.\n'
      '\n'
      'Write "*VERSION: 3.0" in the header, or remove the AS command.',
  correctExample: '*VERSION: 2.1\n'
      '...\n'
      '* Source: NOTAM',
  incorrectExample: '*VERSION: 2.1\n'
      '...\n'
      'AS NOTAM',
  keywords: {'AS'},
  checkCommand: (ctx, c, a) {
    final version = ctx.target != null
        ? 'version ${ctx.specVersion.label} (the --target option)'
        : 'version ${ctx.specVersion.label}';
    ctx.reportKeyword(
        c,
        'AS is new in version 3.0, but this file is checked as $version. '
        'A reader of version 2.1 does not know the AS command. Write '
        '"*VERSION: 3.0" in the header, or remove the AS command.');
  },
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
      'The specification requires a code with exactly 4 digits, for example '
      '"AX 7000". Write all 4 digits, also the zeros at the start: write '
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
  severity: Severity.error,
  versions: SpecVersion.only3,
  specAnchor: 'ax-transponder-code',
  description: 'The AX transponder code must use only the digits 0 to 7.',
  explanation: 'Transponder codes are octal. Each of the 4 digits is from 0 '
      'to 7, so there are 4096 codes, from 0000 to 7777. The digits 8 and 9 '
      'are not allowed. A transponder cannot be set to a code with the '
      'digit 8 or 9.',
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

final Rule _axNotOctalV21 = version21Warning(
  _axNotOctal,
  description: 'The AX transponder code should use only the digits 0 to 7 '
      '(version 2.1).',
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
