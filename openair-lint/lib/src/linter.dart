import 'diagnostic.dart';
import 'lint_context.dart';
import 'model/openair_file.dart';
import 'parser/parser.dart';
import 'rules/registry.dart';
import 'rules/rule.dart';
import 'spec_version.dart';

/// The rule ID used when a rule throws an exception. This is a bug in the
/// linter, not in the file. It is reported as an error so that it is seen.
const String internalErrorRuleId = 'linter-internal-error';

/// Options for one lint run.
class LintOptions {
  const LintOptions({
    this.target,
    this.disabledRules = const {},
    this.minSeverity = Severity.info,
    this.rules,
  });

  /// The spec version to check against. It wins over the `*VERSION:`
  /// header. Null means: use the header.
  final SpecVersion? target;

  /// IDs of rules that do not run.
  final Set<String> disabledRules;

  /// Rules with a lower severity do not run.
  final Severity minSeverity;

  /// The rules to run. Null means all rules of the registry ([allRules]).
  /// Tests use this to run only some rules.
  final List<Rule>? rules;
}

/// The result of linting one file.
class LintResult {
  const LintResult({
    required this.file,
    required this.specVersion,
    required this.versionSource,
    required this.diagnostics,
  });

  /// The parsed file.
  final OpenAirFile file;

  /// The spec version that was used.
  final SpecVersion specVersion;

  /// Why [specVersion] was used.
  final VersionSource versionSource;

  /// All diagnostics, sorted by line and column.
  final List<Diagnostic> diagnostics;

  /// The value of the `*VERSION:` header, or null.
  String? get declaredVersion => file.header.versionValue;

  /// The number of diagnostics with this severity.
  int count(Severity severity) =>
      diagnostics.where((d) => d.severity == severity).length;

  /// True if there is at least one error.
  bool get hasErrors => diagnostics.any((d) => d.severity == Severity.error);
}

/// Runs the rules on files. Create one linter and use it for many files.
class Linter {
  Linter([this.options = const LintOptions()]) {
    for (final rule in options.rules ?? allRules) {
      if (options.disabledRules.contains(rule.id)) continue;
      if (!rule.severity.isAtLeast(options.minSeverity)) continue;
      _rules.add(rule);
    }
  }

  /// The options of this linter.
  final LintOptions options;

  final List<Rule> _rules = [];

  /// The rules that can run (not disabled, severity high enough).
  List<Rule> get activeRules => List.unmodifiable(_rules);

  /// Lints the bytes of a file (see [parseOpenAirBytes]).
  ///
  /// [fileName] is the name or path of the file, if it is known. Only the
  /// rule that checks the file extension uses it.
  LintResult lintBytes(List<int> bytes, {String? fileName}) =>
      lintParsed(parseOpenAirBytes(bytes), fileName: fileName);

  /// Lints the text of a file (see [parseOpenAir]).
  ///
  /// [fileName] is the name or path of the file, if it is known. Only the
  /// rule that checks the file extension uses it.
  LintResult lintString(String content, {String? fileName}) =>
      lintParsed(parseOpenAir(content), fileName: fileName);

  /// Lints a file that is already parsed.
  ///
  /// This method never throws. If a rule throws, the linter reports a
  /// `linter-internal-error` diagnostic and runs the other rules.
  LintResult lintParsed(OpenAirFile file, {String? fileName}) {
    ResolvedVersion resolved;
    try {
      resolved = resolveSpecVersion(file.header.versionValue, options.target);
    } catch (_) {
      // This is a bug in openair-lint. The linter must never throw for any
      // input, so it checks the file as the latest version.
      resolved = ResolvedVersion(
          SpecVersion.latest,
          options.target != null
              ? VersionSource.target
              : VersionSource.headerInvalid);
    }
    final version = resolved.version;
    final diagnostics = <Diagnostic>[];
    final ctx = LintContext(
      file: file,
      specVersion: version,
      versionSource: resolved.source,
      target: options.target,
      fileName: fileName,
      sink: diagnostics.add,
    );

    final fileRules = <Rule>[];
    final airspaceRules = <Rule>[];
    final everyCommandRules = <Rule>[];
    final byKeyword = <String, List<Rule>>{};
    for (final rule in _rules) {
      if (!rule.appliesTo(version)) continue;
      if (rule.checkFile != null) fileRules.add(rule);
      if (rule.checkAirspace != null) airspaceRules.add(rule);
      if (rule.checkCommand != null) {
        final keywords = rule.keywords;
        if (keywords == null) {
          everyCommandRules.add(rule);
        } else {
          for (final k in keywords) {
            (byKeyword[k.toUpperCase()] ??= []).add(rule);
          }
        }
      }
    }

    final crashed = <String>{};
    void onCrash(Rule rule, Object e, StackTrace st) {
      if (!crashed.add(rule.id)) return;
      final frame = st.toString().split('\n').first;
      diagnostics.add(Diagnostic(
        ruleId: internalErrorRuleId,
        severity: Severity.error,
        line: 1,
        column: 1,
        endColumn: 2,
        message: 'Rule ${rule.id} failed with an exception: $e ($frame). '
            'This is a bug in openair-lint. Please report it.',
        specUrl: rule.specUrl,
      ));
    }

    // The loops below do not create closures per call, because they run
    // for every command of large files.
    void runCommand(Command c, Airspace? a) {
      for (final rule in everyCommandRules) {
        ctx.rule = rule;
        try {
          rule.checkCommand!(ctx, c, a);
        } catch (e, st) {
          onCrash(rule, e, st);
        }
      }
      final list = byKeyword[c.upperKeyword];
      if (list != null) {
        for (final rule in list) {
          ctx.rule = rule;
          try {
            rule.checkCommand!(ctx, c, a);
          } catch (e, st) {
            onCrash(rule, e, st);
          }
        }
      }
    }

    for (final rule in fileRules) {
      ctx.rule = rule;
      try {
        rule.checkFile!(ctx);
      } catch (e, st) {
        onCrash(rule, e, st);
      }
    }
    final hasCommandRules =
        everyCommandRules.isNotEmpty || byKeyword.isNotEmpty;
    if (hasCommandRules) {
      for (final c in file.commandsOutsideAirspace) {
        runCommand(c, null);
      }
    }
    for (final a in file.airspaces) {
      for (final rule in airspaceRules) {
        ctx.rule = rule;
        try {
          rule.checkAirspace!(ctx, a);
        } catch (e, st) {
          onCrash(rule, e, st);
        }
      }
      if (hasCommandRules) {
        for (final c in a.commands) {
          runCommand(c, a);
        }
      }
    }

    diagnostics.sort();
    return LintResult(
      file: file,
      specVersion: version,
      versionSource: resolved.source,
      diagnostics: List.unmodifiable(diagnostics),
    );
  }
}

/// Lints the text of a file and returns the diagnostics, sorted by line
/// and column.
List<Diagnostic> lintString(String content,
        [LintOptions options = const LintOptions(), String? fileName]) =>
    Linter(options).lintString(content, fileName: fileName).diagnostics;

/// Lints the bytes of a file and returns the diagnostics, sorted by line
/// and column.
List<Diagnostic> lintBytes(List<int> bytes,
        [LintOptions options = const LintOptions(), String? fileName]) =>
    Linter(options).lintBytes(bytes, fileName: fileName).diagnostics;
