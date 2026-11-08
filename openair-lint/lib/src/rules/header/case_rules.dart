part of '../header_rules.dart';

// ---------------------------------------------------------------------------
// case-not-upper-case
// ---------------------------------------------------------------------------

/// The commands whose text can use any case (the name and the station).
const Set<String> _freeCaseKeywords = {'AN', 'AG'};

/// The upper case rule of version 3.0.
///
/// This is the only rule that reports lower case letters. Rules of other
/// groups read values without regard to case, so that one problem is
/// reported only once.
final Rule _caseNotUpperCase = Rule(
  id: 'case-not-upper-case',
  severity: Severity.error,
  versions: SpecVersion.only3,
  specAnchor: _generalAnchor,
  description: 'Commands and values must be in upper case (except the text '
      'after AN and AG, and comments).',
  explanation: 'Version 3.0 requires upper case for everything: commands, '
      'keywords, units and all other values. This includes weekdays, sun '
      'events, the letters "T" and "Z" in dates and times, and the letters '
      '"N", "S", "E" and "W" in coordinates.\n'
      '\n'
      'Only these parts can use any case: the name after "AN", the station '
      'name after "AG", and comments (the text after "*").\n'
      '\n'
      'openair-lint reports one problem per line, at the first lower case '
      'letter. It does not check commands that the specification does not '
      'define; other rules report them. Version 2.1 does not have this rule.',
  correctExample: 'AC D\n'
      'AN Example ctr      * any case in the name\n'
      'AH 1000 FT AMSL\n'
      'AA MON-FRI 07:00Z/15:00Z',
  incorrectExample: 'ac D\n'
      'AH 1000 ft AMSL\n'
      'AA Mon-Fri 07:00z/15:00z',
  checkCommand: (ctx, c, a) {
    final keyword = c.upperKeyword;
    if (!_specKeywords.contains(keyword)) return;
    final freeCase = _freeCaseKeywords.contains(keyword);
    final arg = c.argument;
    // The whole line in upper case (without the comment). The message
    // shows it when the line has more than one lower case part, so that
    // the user can fix all of them at once.
    final upperLine = _short(
        '$keyword ${freeCase ? arg : arg.toUpperCase()}'.trimRight(), 60);
    final lineHint = ' Write the line in upper case: "$upperLine".';
    if (!c.isUpperCaseKeyword) {
      var first = 0;
      while (!_isLowerCaseChar(c.keyword[first])) {
        first++;
      }
      final more = !freeCase && arg.split('').any(_isLowerCaseChar);
      ctx.report(
          'Write the command "${c.keyword}" in upper case: "$keyword".'
          '${more ? lineHint : ''}',
          line: c.line,
          column: c.column + first,
          endColumn: c.keywordEndColumn);
      return;
    }
    if (freeCase) return;
    // An AF or AX value with other text, for example "123.500 MHz" or
    // "7000 (mode S)", is reported by af-invalid-format or
    // ax-not-four-digits. Their fix removes the text, so the case of the
    // text is not reported here.
    if (keyword == 'AF' && frequencyFormatProblem(arg) != null) return;
    if (keyword == 'AX' && !isFourDigitCode(arg)) return;
    // A unit without a space after the number, for example "4500ft", is
    // reported by altitude-unit-no-space, with the fix in upper case
    // ("4500 FT"). It is not reported here again.
    final gluedUnits = <int>{
      if (keyword == 'AH' || keyword == 'AL')
        for (final issue in ctx
            .memo(('altitude', c), () => parseAltitude(arg)).issuesOf(
                AltitudeIssueKind.noSpaceBeforeUnit))
          issue.offset
    };
    for (var i = 0; i < arg.length; i++) {
      if (!_isLowerCaseChar(arg[i])) continue;
      // The letters around the first lower case letter, for the message.
      // For "1500ft" this is "ft", for "46:00:00n" it is "n".
      var start = i;
      while (start > 0 && _isLetter(arg[start - 1])) {
        start--;
      }
      var end = i + 1;
      while (end < arg.length && _isLetter(arg[end])) {
        end++;
      }
      if (gluedUnits.contains(start)) {
        i = end - 1;
        continue;
      }
      final letters = arg.substring(start, end);
      final more = arg.substring(end).split('').any(_isLowerCaseChar);
      ctx.reportArgument(
          c,
          'Write "${_short(letters)}" in upper case: '
          '"${_short(letters.toUpperCase())}".${more ? lineHint : ''} Only '
          'the text after AN and AG and comments can use lower case.',
          offset: i,
          length: end - i);
      return;
    }
  },
);

/// True if [c] (one UTF-16 code unit as a string) is a letter.
bool _isLetter(String c) => c.toUpperCase() != c.toLowerCase();
