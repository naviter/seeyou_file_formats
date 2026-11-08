part of '../header_rules.dart';

/// The version that messages suggest when a file has no valid version.
///
/// Version 3.0 is a draft. The specification says that writers must not
/// write "*VERSION: 3.0" before the final 3.0.0 release. Change this to
/// '3.0' (and remove [_draftNote]) when 3.0 is released.
const String _suggestedVersion = '2.1';

/// A sentence for messages that suggest a version.
const String _draftNote = 'Version 3.0 is still a draft. Do not write '
    '"*VERSION: 3.0" in production files yet.';

/// The suggestion for a file without a valid version, for messages.
const String _versionExample = 'for example "*VERSION: $_suggestedVersion". '
    '$_draftNote';

/// Comment lines in the header area that look like a `*VERSION` comment but
/// have no `:` (for example `*VERSION 3.0`). The parser does not read them
/// as the version.
final RegExp _malformedVersion =
    RegExp(r'^[ \t]*\*[ \t]*VERSION[ \t]*-?[ \t]*V?\d', caseSensitive: false);

/// The same for `*WRITTEN_BY` (also `*WRITTEN BY`).
final RegExp _malformedWrittenBy =
    RegExp(r'^[ \t]*\*[ \t]*WRITTEN[ _]BY\b', caseSensitive: false);

/// The first line in the header area that matches [pattern] but is not a
/// header field, or null. A lenient `*VERSION` field that is a normal
/// comment (see [_isVersionField]) counts as "not a header field".
int? _malformedHeaderLine(LintContext ctx, RegExp pattern) {
  final file = ctx.file;
  final fieldLines = {
    for (final f in file.header.fields)
      if (!f.isVersion || _isVersionField(f)) f.line
  };
  final end = file.header.endLine;
  for (var n = 1; n <= end; n++) {
    if (fieldLines.contains(n)) continue;
    if (pattern.hasMatch(file.lineText(n))) return n;
  }
  return null;
}

/// A value that starts with a version number, for example "2.1", "3.0.0",
/// "V2.1", "2,1", "3" or "2.1 (generated 2026-01-01)". A date such as
/// "2024-03-01" or a text such as "MAR26" does not match.
final RegExp _versionStart = RegExp(r'^[vV]?\d{1,2}(?:[.,]\d+)*(?![\d.,:/-])');

/// True if [field] is a `*VERSION` header comment, and not a normal comment
/// that only starts with the word "version".
///
/// The parser is lenient: it also reads `* Version: MAR26` as a version
/// field. A field counts as the version only when it has the form of the
/// specification (`*VERSION` directly after `*`, in upper case), or when
/// its value starts with a version number (for example `* version = 2.1`).
/// Other lines, for example the banner `*   Version: MAR26 - SFVS   *`, are
/// normal comments.
bool _isVersionField(HeaderField field) =>
    field.isVersion &&
    ((field.keyColumn == 2 && field.key == 'VERSION') ||
        _versionStart.hasMatch(field.value));

/// The `*VERSION` header field that this group uses, or null.
///
/// This is the first field in the header area for which [_isVersionField]
/// is true. It can differ from `file.header.version`, which is the first
/// lenient match.
HeaderField? _versionField(LintContext ctx) =>
    ctx.memo(('header-version-field',), () {
      for (final f in ctx.file.header.fields) {
        if (_isVersionField(f)) return f;
      }
      return null;
    });

/// The `*VERSION` and `*WRITTEN_BY` comments after the first command, without
/// normal comments such as `* Version: updated 2024-02-01`.
List<HeaderField> _lateHeaderFields(LintContext ctx) => [
      for (final f in ctx.file.lateHeaderFields)
        if (f.isWrittenBy || _isVersionField(f)) f
    ];

/// How the `*VERSION:` value of the header resolves, without `--target`.
VersionSource _headerVersionSource(LintContext ctx) =>
    resolveSpecVersion(_versionField(ctx)?.value, null).source;

String _checkedAs(LintContext ctx) {
  if (ctx.target != null) return '';
  final how = ' This file is checked as version ${ctx.specVersion.label}.';
  if (!ctx.isV3) return how;
  // Most older files have no header. The 3.0 rules (for example upper
  // case) then report many problems that the user does not expect.
  return '$how To check it as version 2.1, use the option --target 2.1 '
      '(on the web page: choose version 2.1).';
}

// ---------------------------------------------------------------------------
// header-version-missing
// ---------------------------------------------------------------------------

/// `header-version-missing`: the header has no `*VERSION:` comment.
final Rule _versionMissing = Rule(
  id: 'header-version-missing',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'header',
  description: 'The header must contain a "*VERSION:" comment.',
  explanation: 'Every OpenAir file must start with a header. The header '
      'must contain the version of the specification that the file follows, '
      'for example "*VERSION: 2.1". Readers use the version to understand '
      'the file. The header is the comment lines before the first command.\n'
      '\n'
      'Version 3.0 of the specification is still a draft. The specification '
      'says that writers must not write "*VERSION: 3.0" in files before the '
      'final 3.0.0 release.\n'
      '\n'
      'Without a version, openair-lint checks the file as version 3.0. Use '
      'the option --target 2.1 to check an older file as version 2.1.\n'
      '\n'
      'If the file has a line such as "*VERSION 2.1" without ":", the '
      'problem is reported on that line, because readers do not see it as '
      'the version. A comment such as "* Version: MAR26" is a normal '
      'comment, because its value is not a version number.',
  correctExample: '*VERSION: 2.1\n'
      '*WRITTEN_BY: SeeYou\n'
      '\n'
      'AC D\n'
      'AN Example CTR',
  incorrectExample: '*WRITTEN_BY: SeeYou\n'
      '\n'
      'AC D\n'
      'AN Example CTR',
  checkFile: _checkVersionMissing,
);

final RegExp _numberInLine = RegExp(r'\d+(?:\.\d+)*');

void _checkVersionMissing(LintContext ctx) {
  final file = ctx.file;
  if (_versionField(ctx) != null) return;
  // A UTF-16 file without a byte order mark has no readable header. The
  // rule file-not-utf8 reports the real cause.
  if (_looksLikeUtf16(ctx) != null) return;
  final malformed = _malformedHeaderLine(ctx, _malformedVersion);
  if (malformed != null) {
    final number = _numberInLine.firstMatch(file.lineText(malformed))!;
    ctx.reportLine(
        malformed,
        'The header has no valid "*VERSION:" comment. This line looks like '
        'one, but it has no ":", so readers do not see it as the version. '
        'Write it as "*VERSION: ${number.group(0)}".'
        '${_checkedAs(ctx)}');
    return;
  }
  final buffer = StringBuffer('The header has no "*VERSION:" comment. '
      'Add the version as the first line, $_versionExample');
  for (final late in _lateHeaderFields(ctx)) {
    if (late.isVersion) {
      buffer.write(' The "*VERSION" comment on line ${late.line} does not '
          'count, because it is after the first command.');
      break;
    }
  }
  buffer.write(_checkedAs(ctx));
  ctx.reportLine(1, buffer.toString());
}

// ---------------------------------------------------------------------------
// header-version-invalid
// ---------------------------------------------------------------------------

/// A version number inside other text, for example "V2.1" or "2,1".
final RegExp _looseVersion = RegExp(r'^\D{0,10}?([1-3])\s*[.,]\s*(\d)(?!\d)');

/// A version with only the major number, for example "3" or "V2".
final RegExp _majorOnlyVersion = RegExp(r'^[vV]?\s*([23])$');

/// The version that a wrong value probably means, or null if the value has
/// no clear version number. Examples: "2.1" for "2.1 (generated 2026-01-01)"
/// and for "V2.1", "2.1" for "2" and "3.0" for "3".
String? _probableVersion(String value) {
  final m = _looseVersion.firstMatch(value);
  if (m != null) return '${m.group(1)}.${m.group(2)}';
  final major = _majorOnlyVersion.firstMatch(value.trim());
  if (major != null) return major.group(1) == '2' ? '2.1' : '3.0';
  return null;
}

final Rule _versionInvalid = Rule(
  id: 'header-version-invalid',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'header',
  description: 'The value of "*VERSION:" must be a version number, for '
      'example 2.1.',
  explanation: 'The "*VERSION:" comment must contain only the version '
      'number of the specification, for example "2.1" or "3.0". Readers '
      'cannot use other text. Write other information in a separate '
      'comment.\n'
      '\n'
      'When the value is not a version number, openair-lint checks the file '
      'as version 3.0. Use the option --target to choose the version.',
  correctExample: '*VERSION: 2.1\n'
      '* Data from 2026-07-01',
  incorrectExample: '*VERSION: 2026-07-01',
  checkFile: (ctx) {
    final field = _versionField(ctx);
    if (field == null) return;
    if (_headerVersionSource(ctx) != VersionSource.headerInvalid) return;
    final value = field.value;
    final String message;
    if (value.isEmpty) {
      message = 'The "*VERSION:" comment has no value. Write the version '
          'number, $_versionExample';
    } else {
      final probable = _probableVersion(value);
      final hint = probable == null
          ? 'Write the version of the specification, $_versionExample If '
              'this is the version of your data, write it in a normal '
              'comment, for example "* Data version: ...".'
          : 'Write only the number: "*VERSION: $probable".'
              '${probable == '3.0' ? ' $_draftNote' : ''}';
      message = '"${_short(value)}" is not a version number of the OpenAir '
          'specification. $hint';
    }
    ctx.report('$message${_checkedAs(ctx)}',
        line: field.line,
        column: field.value.isEmpty ? field.keyColumn : field.valueColumn,
        endColumn: field.value.isEmpty
            ? field.keyColumn + field.key.length
            : field.valueEndColumn);
  },
);

// ---------------------------------------------------------------------------
// header-version-old
// ---------------------------------------------------------------------------

final Rule _versionOld = Rule(
  id: 'header-version-old',
  severity: Severity.info,
  versions: SpecVersion.all,
  specAnchor: 'header',
  description: 'Versions older than 2.1 are checked with the rules of '
      'version 2.1.',
  explanation: 'The file declares a version older than 2.1, for example '
      '"*VERSION: 2.0". openair-lint knows only the versions 2.1 and 3.0. It '
      'checks older files with the rules of version 2.1. Most rules of 2.1 '
      'also apply to older files.',
  correctExample: '*VERSION: 2.1',
  incorrectExample: '*VERSION: 2.0',
  checkFile: (ctx) {
    final field = _versionField(ctx);
    if (field == null) return;
    final number = VersionNumber.tryParse(field.value);
    if (number == null || number.compareTo(const VersionNumber(2, 1)) >= 0) {
      return;
    }
    final how = ctx.target == null
        ? 'openair-lint checks it with the rules of version 2.1.'
        : 'openair-lint knows only the versions 2.1 and 3.0.';
    ctx.report('Version ${field.value} is older than 2.1. $how',
        line: field.line,
        column: field.valueColumn,
        endColumn: field.valueEndColumn);
  },
);

// ---------------------------------------------------------------------------
// header-version-draft
// ---------------------------------------------------------------------------

/// `header-version-draft`: the file declares version 3.0, which is a draft.
///
/// Remove this rule (and [_draftNote]) when version 3.0.0 of the
/// specification is released. Never reuse its ID.
final Rule _versionDraft = Rule(
  id: 'header-version-draft',
  severity: Severity.info,
  versions: SpecVersion.all,
  specAnchor: 'header',
  description: 'Version 3.0 is a draft. Do not write "*VERSION: 3.0" in '
      'production files yet.',
  explanation: 'The specification says: version 3.0 is a draft. Writers must '
      'not write "*VERSION: 3.0" in files before the final 3.0.0 release of '
      'the specification.\n'
      '\n'
      'This rule is info and not an error, so that test files for the draft '
      '(for example the conformance files) can use version 3.0. Do not '
      'publish a file with "*VERSION: 3.0" before the release. The rule will '
      'be removed at the 3.0.0 release.',
  correctExample: '*VERSION: 2.1',
  incorrectExample: '*VERSION: 3.0',
  checkFile: (ctx) {
    final field = _versionField(ctx);
    if (field == null) return;
    final resolved = resolveSpecVersion(field.value, null);
    if (resolved.source != VersionSource.header ||
        resolved.version != SpecVersion.v3_0) {
      return;
    }
    ctx.report(
        'Version 3.0 of the specification is still a draft. Do not write '
        '"*VERSION: 3.0" in production files before the final 3.0.0 '
        'release.',
        line: field.line,
        column: field.valueColumn,
        endColumn: field.valueEndColumn);
  },
);

// ---------------------------------------------------------------------------
// header-version-unknown
// ---------------------------------------------------------------------------

final Rule _versionUnknown = Rule(
  id: 'header-version-unknown',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'header',
  description: 'The version should be one that the specification defines: '
      '2.1 or 3.0.',
  explanation: 'The value of "*VERSION:" is a number, but it is not a '
      'version of the specification that openair-lint knows. Examples are '
      '"2.5" (there is no such version), "3.1" (newer than this linter) and '
      '"3.0.0" (write "3.0").\n'
      '\n'
      'openair-lint checks a version between 2.1 and 3.0 as 2.1, and a '
      'version newer than 3.0 as 3.0. Write the version exactly as the '
      'specification shows it, for example "*VERSION: 2.1".',
  correctExample: '*VERSION: 3.0',
  incorrectExample: '*VERSION: 3.0.0',
  checkFile: (ctx) {
    final field = _versionField(ctx);
    if (field == null) return;
    final value = field.value;
    final number = VersionNumber.tryParse(value);
    if (number == null) return;
    if (number.compareTo(const VersionNumber(2, 1)) < 0) return;
    if (value == '2.1' || value == '3.0') return;
    final known = SpecVersion.fromLabel(number.toString());
    final String message;
    if (known != null) {
      message = 'Write the version as "${known.label}", without more '
          'numbers.';
    } else if (number.compareTo(const VersionNumber(3, 0)) > 0) {
      message = 'openair-lint does not know version $value. The newest '
          'version it knows is 3.0.';
    } else {
      message = 'Version $value does not exist. The known versions are 2.1 '
          'and 3.0.';
    }
    ctx.report('$message${_checkedAs(ctx)}',
        line: field.line,
        column: field.valueColumn,
        endColumn: field.valueEndColumn);
  },
);

// ---------------------------------------------------------------------------
// header-written-by-missing
// ---------------------------------------------------------------------------

final Rule _writtenByMissing = Rule(
  id: 'header-written-by-missing',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'header',
  description: 'The header must contain a "*WRITTEN_BY:" comment.',
  explanation: 'The header must say who wrote the file: a person, an '
      'organisation or a program. Write it in a "*WRITTEN_BY:" comment, '
      'for example "*WRITTEN_BY: SeeYou". This helps users to find the '
      'source of the data and to report errors.',
  correctExample: '*VERSION: 2.1\n'
      '*WRITTEN_BY: SeeYou',
  incorrectExample: '*VERSION: 2.1\n'
      '* Written by SeeYou',
  checkFile: (ctx) {
    final file = ctx.file;
    if (file.header.writtenBy != null) return;
    if (_looksLikeUtf16(ctx) != null) return;
    final malformed = _malformedHeaderLine(ctx, _malformedWrittenBy);
    if (malformed != null) {
      ctx.reportLine(
          malformed,
          'The header has no valid "*WRITTEN_BY:" comment. This line looks '
          'like one, but readers do not see it as the author. Write it as '
          '"*WRITTEN_BY: Name", with "_" and ":".');
      return;
    }
    var message = 'The header has no "*WRITTEN_BY:" comment. Add the author '
        'or the program, for example "*WRITTEN_BY: SeeYou".';
    for (final late in _lateHeaderFields(ctx)) {
      if (late.isWrittenBy) {
        message += ' The "*WRITTEN_BY" comment on line ${late.line} does not '
            'count, because it is after the first command.';
        break;
      }
    }
    final version = _versionField(ctx);
    if (version != null) {
      ctx.report(message, line: version.line, column: 1, endColumn: 2);
    } else {
      ctx.reportLine(1, message);
    }
  },
);

// ---------------------------------------------------------------------------
// header-written-by-empty
// ---------------------------------------------------------------------------

final Rule _writtenByEmpty = Rule(
  id: 'header-written-by-empty',
  severity: Severity.error,
  versions: SpecVersion.all,
  specAnchor: 'header',
  description: 'The "*WRITTEN_BY:" comment must have a value.',
  explanation: 'The "*WRITTEN_BY:" comment is in the header, but it has no '
      'value. Write the author of the file: a person, an organisation or a '
      'program.',
  correctExample: '*WRITTEN_BY: SeeYou',
  incorrectExample: '*WRITTEN_BY:',
  checkFile: (ctx) {
    final field = ctx.file.header.writtenBy;
    if (field == null || field.value.isNotEmpty) return;
    ctx.report(
        'The "*WRITTEN_BY:" comment has no value. Write the author or the '
        'program, for example "*WRITTEN_BY: SeeYou".',
        line: field.line,
        column: field.keyColumn,
        endColumn: field.keyColumn + field.key.length);
  },
);

// ---------------------------------------------------------------------------
// header-field-format
// ---------------------------------------------------------------------------

final Rule _headerFieldFormat = Rule(
  id: 'header-field-format',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'header',
  description: 'Write header comments exactly as "*VERSION: 2.1" and '
      '"*WRITTEN_BY: Name".',
  explanation: 'The specification shows the header comments in one form: '
      '"*" at the start of the line, the key in upper case, ":" directly '
      'after the key, and one space before the value. openair-lint also '
      'reads other forms, for example "* version = 2.1", but other readers '
      'may not find the header in these forms.',
  correctExample: '*VERSION: 2.1\n'
      '*WRITTEN_BY: SeeYou',
  incorrectExample: '* VERSION: 2.1\n'
      '*Written_By:SeeYou',
  checkFile: (ctx) {
    for (final field in ctx.file.header.fields) {
      // A lenient "* Version: ..." line with free text is a normal comment.
      if (!field.isWrittenBy && !_isVersionField(field)) continue;
      // An empty value and a version that is not a number are reported by
      // other rules. One problem per line is enough.
      if (field.value.isEmpty) continue;
      if (field.isVersion &&
          _headerVersionSource(ctx) == VersionSource.headerInvalid &&
          identical(field, _versionField(ctx))) {
        continue;
      }
      final problems = _formatProblems(field);
      if (problems.isEmpty) continue;
      final canonical = '*${field.upperKey}: ${field.value}';
      ctx.reportLine(field.line,
          'Write this line as "${_short(canonical, 60)}". ${problems.join(' ')}');
    }
  },
);

List<String> _formatProblems(HeaderField field) {
  final text = field.text;
  final problems = <String>[];
  final star = text.indexOf('*');
  if (star > 0) problems.add('Remove the blanks before "*".');
  if (field.keyColumn - 1 > star + 1) {
    problems.add('Remove the blanks between "*" and "${field.upperKey}".');
  }
  if (field.key != field.upperKey) {
    problems.add('Write "${field.upperKey}" in upper case.');
  }
  final sepIndex = text.indexOf(field.separator, field.keyColumn - 1);
  if (sepIndex > field.keyColumn - 1 + field.key.length) {
    problems.add('Remove the blanks before "${field.separator}".');
  }
  if (field.separator != ':') problems.add('Use ":" in place of "=".');
  final between = text.substring(sepIndex + 1, field.valueColumn - 1);
  if (between != ' ') problems.add('Write one space after ":".');
  return problems;
}

// ---------------------------------------------------------------------------
// header-field-duplicate
// ---------------------------------------------------------------------------

final Rule _headerFieldDuplicate = Rule(
  id: 'header-field-duplicate',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'header',
  description: 'The header should have only one "*VERSION:" and one '
      '"*WRITTEN_BY:" comment.',
  explanation: 'The header has the same key more than once. Readers use '
      'only one of them, and different readers can choose different ones. '
      'openair-lint uses the first one.\n'
      '\n'
      'Keep one "*VERSION:" and one "*WRITTEN_BY:" comment. Write other '
      'information, for example other authors, in normal comments.',
  correctExample: '*VERSION: 2.1\n'
      '*WRITTEN_BY: SeeYou\n'
      '* Data: Example Aero Club',
  incorrectExample: '*VERSION: 2.1\n'
      '*WRITTEN_BY: SeeYou\n'
      '*WRITTEN_BY: Example Aero Club',
  checkFile: (ctx) {
    for (final key in const ['VERSION', 'WRITTEN_BY']) {
      final fields = [
        for (final f in ctx.file.header.fieldsWithKey(key))
          if (f.isWrittenBy || _isVersionField(f)) f
      ];
      if (fields.length < 2) continue;
      final first = fields.first;
      for (final f in fields.skip(1)) {
        final same = f.value == first.value;
        ctx.reportLine(
            f.line,
            'The header has a second "*$key:" comment. The first one is on '
            'line ${first.line}${same ? '' : ' and has another value '
                '("${_short(first.value)}")'}. Readers use only one of them. '
            'Remove this line.');
      }
    }
  },
);

// ---------------------------------------------------------------------------
// header-after-first-command
// ---------------------------------------------------------------------------

final Rule _headerAfterFirstCommand = Rule(
  id: 'header-after-first-command',
  severity: Severity.warning,
  versions: SpecVersion.all,
  specAnchor: 'header',
  description: '"*VERSION:" and "*WRITTEN_BY:" belong in the header, before '
      'the first command.',
  explanation: 'The header is the comment lines at the start of the file, '
      'before the first command. A "*VERSION:" or "*WRITTEN_BY:" comment '
      'later in the file is not part of the header. Readers ignore it.\n'
      '\n'
      'If the file already has a header, this comment is often the header '
      'of another file that was joined to this one. Remove it, or move it '
      'to the top of the file. Check that both files use the same version.\n'
      '\n'
      'A normal comment such as "* Version: updated in May" is not '
      'reported, because its value is not a version number.',
  correctExample: '*VERSION: 2.1\n'
      '*WRITTEN_BY: SeeYou\n'
      '\n'
      'AC D\n'
      'AN Example CTR',
  incorrectExample: '*WRITTEN_BY: SeeYou\n'
      '\n'
      'AC D\n'
      '*VERSION: 2.1\n'
      'AN Example CTR',
  checkFile: (ctx) {
    final header = ctx.file.header;
    for (final f in _lateHeaderFields(ctx)) {
      final key = f.upperKey;
      final inHeader = key == 'VERSION' ? _versionField(ctx) : header.writtenBy;
      final String advice;
      if (inHeader == null) {
        advice = 'Move it to the top of the file.';
      } else if (key == 'VERSION' && inHeader.value != f.value) {
        advice = 'It has another version than the header '
            '("${_short(inHeader.value)}" on line ${inHeader.line}). '
            'Files with different versions were probably joined.';
      } else {
        advice = 'It is probably the header of another file that was joined '
            'to this one. Remove it.';
      }
      ctx.reportLine(
          f.line,
          'This "*$key" comment is after the first command, so it is not '
          'part of the header. Readers ignore it. $advice');
    }
  },
);
