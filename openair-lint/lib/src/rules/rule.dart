import '../diagnostic.dart';
import '../fix.dart';
import '../lint_context.dart';
import '../model/openair_file.dart';
import '../spec_version.dart';
import '../version.dart' as v;

/// A check that runs once per file.
typedef FileCheck = void Function(LintContext context);

/// A check that runs once per airspace definition.
typedef AirspaceCheck = void Function(LintContext context, Airspace airspace);

/// A check that runs once per command.
///
/// [airspace] is null for commands before the first `AC` command.
typedef CommandCheck = void Function(
    LintContext context, Command command, Airspace? airspace);

/// One lint rule: its metadata and its checks.
///
/// A rule has one or more checks:
///
/// - [checkFile] runs once per file.
/// - [checkAirspace] runs once per airspace definition.
/// - [checkCommand] runs once per command. If [keywords] is set, it runs
///   only for commands with one of these keywords (compared in upper case,
///   so `ac` matches `AC`). This is faster than a check for every command.
///
/// The linter runs a rule only if the rule is not disabled, its severity is
/// at least the minimum severity, and [versions] contains the spec version
/// of the file. The checks call [LintContext.report] to report problems.
/// The diagnostic gets the [id] and [severity] of this rule.
///
/// ```dart
/// final exampleRule = Rule(
///   id: 'ax-not-four-digits',
///   severity: Severity.error,
///   specAnchor: 'ax-transponder-code',
///   description: 'AX must be a 4 digit transponder code.',
///   explanation: '...',
///   correctExample: 'AX 7000',
///   incorrectExample: 'AX 700',
///   keywords: {'AX'},
///   checkCommand: (ctx, command, airspace) {
///     if (!RegExp(r'^[0-7]{4}$').hasMatch(command.argument)) {
///       ctx.reportArgument(command, 'Write the transponder code with 4 digits.');
///     }
///   },
/// );
/// ```
class Rule {
  Rule({
    required this.id,
    required this.severity,
    this.versions = SpecVersion.all,
    required this.specAnchor,
    required this.description,
    required this.explanation,
    required this.correctExample,
    required this.incorrectExample,
    this.anchorInVersion21Text = false,
    this.messageNote,
    this.fixDescription,
    this.keywords,
    this.checkFile,
    this.checkAirspace,
    this.checkCommand,
  })  : assert(_idPattern.hasMatch(id), 'Rule ID must be kebab-case: $id'),
        assert(
            checkFile != null || checkAirspace != null || checkCommand != null,
            'Rule $id has no check'),
        assert(keywords == null || checkCommand != null,
            'Rule $id has keywords but no checkCommand');

  static final RegExp _idPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)+$');

  /// The stable ID, for example `header-version-missing`. The first word is
  /// the command group. Never rename or reuse an ID.
  final String id;

  /// The default severity.
  final Severity severity;

  /// The spec versions that this rule applies to.
  /// Use [SpecVersion.all], [SpecVersion.only3] or [SpecVersion.only21].
  final Set<SpecVersion> versions;

  /// The GitHub anchor of the spec section, without `#`, for example
  /// `aa-airspace-activation-times`. A test checks that it exists.
  final String specAnchor;

  /// One sentence that says what the rule checks.
  final String description;

  /// A longer explanation: why the rule exists and how to fix the problem.
  /// Plain text; several sentences or paragraphs (separated by an empty line)
  /// are fine.
  final String explanation;

  /// An example that follows the rule. Usually a few lines of OpenAir text.
  final String correctExample;

  /// An example that breaks the rule. Usually a few lines of OpenAir text.
  final String incorrectExample;

  /// True if [specAnchor] is a heading of the version 2.1 text of the
  /// specification ([v.specBaseUrl21]), not of the current text. Use this
  /// for rules that check a statement that only the 2.1 text has.
  final bool anchorInVersion21Text;

  /// A sentence that [LintContext.report] adds at the end of every message
  /// of this rule, or null. [version21Warning] uses it.
  final String? messageNote;

  /// What `--fix` changes, in one or two sentences, or null if the rule has
  /// no automatic fix. For example: "--fix writes AMSL in place of MSL."
  ///
  /// A rule with a fix gives a [Fix] only for the problems that have
  /// exactly one correct result. A rule without a fix never gives one.
  final String? fixDescription;

  /// True if the rule gives an automatic fix for some of its problems.
  bool get fixable => fixDescription != null;

  /// Upper case keywords for [checkCommand], for example `{'AA'}`.
  /// Null means: every command.
  final Set<String>? keywords;

  /// Runs once per file.
  final FileCheck? checkFile;

  /// Runs once per airspace.
  final AirspaceCheck? checkAirspace;

  /// Runs once per command (see [keywords]).
  final CommandCheck? checkCommand;

  /// The full URL of [specAnchor].
  String get specUrl => v.specUrl(specAnchor, version21: anchorInVersion21Text);

  /// True if the rule applies to [version].
  bool appliesTo(SpecVersion version) => versions.contains(version);

  /// The versions as text, for example `2.1, 3.0`.
  String get versionsLabel =>
      (versions.toList()..sort((a, b) => a.index.compareTo(b.index)))
          .map((v) => v.label)
          .join(', ');

  /// The metadata as JSON (used by `--list-rules --format json`).
  Map<String, Object?> toJson() => {
        'id': id,
        'severity': severity.label,
        'versions': [
          for (final v in SpecVersion.values)
            if (versions.contains(v)) v.label
        ],
        'description': description,
        'explanation': explanation,
        'correctExample': correctExample,
        'incorrectExample': incorrectExample,
        'specUrl': specUrl,
        'fixable': fixable,
        if (fixDescription != null) 'fixDescription': fixDescription,
      };

  @override
  String toString() => 'Rule($id)';
}

/// A copy of [base] for version 2.1 files: the ID is `<id>-v21`, the
/// severity is warning, and the rule checks only version 2.1 files.
///
/// Use it when version 3.0 adds a requirement that the 2.1 text does not
/// have, but a 2.1 reader has the same problem with the data. [base] must
/// check only version 3.0 ([SpecVersion.only3]). [description] must not
/// say "must", because the rule is a warning. Each message gets a note
/// that version 3.0 makes the problem an error.
Rule version21Warning(Rule base,
    {required String description,
    String? specAnchor,
    bool anchorInVersion21Text = false,
    String? explanation}) {
  assert(base.versions.length == 1 && base.appliesTo(SpecVersion.v3_0),
      '${base.id} must check only version 3.0');
  return Rule(
    id: '${base.id}-v21',
    severity: Severity.warning,
    versions: SpecVersion.only21,
    specAnchor: specAnchor ?? base.specAnchor,
    anchorInVersion21Text: anchorInVersion21Text,
    description: description,
    explanation: explanation ??
        '${base.explanation}\n'
            '\n'
            'The version 2.1 text does not have this rule. Version 3.0 has '
            'it, and there it is an error (${base.id}). A reader of a 2.1 '
            'file has the same problem, so openair-lint reports a warning in '
            'version 2.1 files.',
    correctExample: base.correctExample,
    incorrectExample: base.incorrectExample,
    messageNote: 'In version 3.0 this is an error.',
    fixDescription: base.fixDescription,
    keywords: base.keywords,
    checkFile: base.checkFile,
    checkAirspace: base.checkAirspace,
    checkCommand: base.checkCommand,
  );
}
