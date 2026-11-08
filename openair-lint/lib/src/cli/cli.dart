/// The command line tool. This is the only part of the package that uses
/// `dart:io`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';

import '../diagnostic.dart';
import '../linter.dart';
import '../rules/registry.dart';
import '../spec_version.dart';
import '../version.dart';
import 'output.dart';

/// Exit code: no errors.
const int exitOk = 0;

/// Exit code: at least one error (or warning with `--fail-on warning`).
const int exitLintFailed = 1;

/// Exit code: wrong options, or a file that cannot be read.
const int exitUsage = 2;

/// The file extensions that are searched in directories (lower case).
const List<String> openAirExtensions = ['.openair', '.txt'];

/// Runs the command line tool and returns the exit code.
///
/// [out] and [err] default to stdout and stderr. [color] forces colour on
/// or off; null means "auto" (on for a terminal, off for pipes and when
/// the NO_COLOR environment variable is set). [readStdin] reads the input
/// for the path `-`.
class CliRunner {
  CliRunner({
    StringSink? out,
    StringSink? err,
    this.color,
    List<int> Function()? readStdin,
  })  : out = out ?? stdout,
        err = err ?? stderr,
        readStdin = readStdin ?? _readAllStdin;

  final StringSink out;
  final StringSink err;
  final bool? color;
  final List<int> Function() readStdin;

  static List<int> _readAllStdin() {
    final bytes = <int>[];
    while (true) {
      final b = stdin.readByteSync();
      if (b < 0) break;
      bytes.add(b);
    }
    return bytes;
  }

  /// The option parser.
  static ArgParser buildParser() => ArgParser()
    ..addOption('target',
        allowed: ['3.0', '2.1'],
        valueHelp: 'version',
        help: 'Check the files as this spec version. '
            'This overrides the *VERSION header.')
    ..addOption('format',
        abbr: 'f',
        allowed: ['text', 'json', 'github'],
        defaultsTo: 'text',
        help: 'The output format.',
        allowedHelp: {
          'text': 'One line per problem, and a summary.',
          'json': 'One JSON object, for other tools.',
          'github': 'GitHub Actions annotations.',
        })
    ..addMultiOption('disable',
        valueHelp: 'rule-id',
        splitCommas: true,
        help: 'Do not run this rule. Can be used more than once.')
    ..addOption('min-severity',
        allowed: ['info', 'warning', 'error'],
        defaultsTo: 'info',
        help: 'Do not show problems with a lower severity.')
    ..addOption('fail-on',
        allowed: ['error', 'warning'],
        defaultsTo: 'error',
        help: 'Exit with code 1 if there is a problem with this severity '
            'or higher.')
    ..addFlag('list-rules', negatable: false, help: 'Show all rules and exit.')
    ..addOption('explain',
        valueHelp: 'rule-id', help: 'Explain one rule with examples and exit.')
    ..addFlag('color',
        defaultsTo: null,
        help: 'Use colours in the output. By default colours are used only '
            'in a terminal. Use --no-color to turn them off.')
    ..addFlag('version', negatable: false, help: 'Show the version and exit.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  String _usage(ArgParser parser) => '''
openair-lint $packageVersion
Checks OpenAir airspace files against the OpenAir 3.0 specification by Naviter.

Usage: openair-lint [options] <files or directories>

Directories are searched for *.openair and *.txt files.
Use "-" to read from standard input.

Options:
${parser.usage}

Exit codes:
  0  No errors.
  1  At least one error (or warning, with --fail-on warning).
  2  Wrong options, a file cannot be read, or the output cannot be written.

Specification: $specBaseUrl
''';

  /// Runs the tool with [arguments] and returns the exit code.
  int run(List<String> arguments) {
    final parser = buildParser();
    ArgResults args;
    try {
      args = parser.parse(arguments);
    } on FormatException catch (e) {
      err.writeln('Error: ${e.message}');
      err.writeln('Run "openair-lint --help" to see the options.');
      return exitUsage;
    }

    final useColor = color ?? args['color'] as bool? ?? _autoColor();
    final ansi = Ansi(useColor);
    final format = OutputFormat.values.byName(args['format'] as String);

    if (args['help'] as bool) {
      out.write(_usage(parser));
      return exitOk;
    }
    if (args['version'] as bool) {
      out.writeln('openair-lint $packageVersion');
      return exitOk;
    }
    if (args['list-rules'] as bool) {
      if (format == OutputFormat.json) {
        out.writeln(prettyJson([for (final r in allRules) r.toJson()]));
      } else {
        out.write(rulesTable(allRules, ansi));
      }
      return exitOk;
    }
    final explain = args['explain'] as String?;
    if (explain != null) {
      final rule = findRule(explain);
      if (rule == null) {
        err.writeln('Error: Unknown rule ID "$explain". '
            'Run "openair-lint --list-rules" to see all rules.');
        return exitUsage;
      }
      if (format == OutputFormat.json) {
        out.writeln(prettyJson(rule.toJson()));
      } else {
        out.write(explainRule(rule, ansi));
      }
      return exitOk;
    }

    final disabled = (args['disable'] as List<String>)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    for (final id in disabled) {
      if (findRule(id) == null) {
        err.writeln('Error: Unknown rule ID "$id" in --disable. '
            'Run "openair-lint --list-rules" to see all rules.');
        return exitUsage;
      }
    }
    if (args.rest.isEmpty) {
      err.writeln('Error: No files or directories given.');
      err.writeln('Usage: openair-lint [options] <files or directories>');
      err.writeln('Run "openair-lint --help" to see the options.');
      return exitUsage;
    }

    final target = args['target'] == null
        ? null
        : SpecVersion.fromLabel(args['target'] as String);
    final minSeverity = Severity.fromLabel(args['min-severity'] as String)!;
    final failOn = Severity.fromLabel(args['fail-on'] as String)!;
    final linter = Linter(LintOptions(
      target: target,
      disabledRules: disabled,
      minSeverity: minSeverity,
    ));

    var exitCode = exitOk;
    final inputs = <_Input>[];
    for (final path in args.rest) {
      if (path == '-') {
        inputs.add(const _Input('<stdin>', null));
        continue;
      }
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        final found = _findFiles(path);
        if (found.isEmpty) {
          err.writeln('Warning: No *.openair or *.txt files in "$path".');
        }
        inputs.addAll(found.map((p) => _Input(_display(p), p)));
      } else if (type == FileSystemEntityType.notFound) {
        err.writeln('Error: "$path" does not exist.');
        exitCode = exitUsage;
      } else {
        inputs.add(_Input(_display(path), path));
      }
    }

    final totals = Totals();
    final reports = <FileReport>[];
    for (final input in inputs) {
      List<int> bytes;
      try {
        bytes = input.path == null
            ? readStdin()
            : File(input.path!).readAsBytesSync();
      } on Object catch (e) {
        err.writeln('Error: Cannot read "${input.display}": ${_ioMessage(e)}');
        exitCode = exitUsage;
        continue;
      }
      final result = linter.lintBytes(bytes, fileName: input.path);
      final shown = result.diagnostics;
      final report = FileReport(input.display, result, shown);
      totals.add(shown);
      if (shown.any((d) => d.severity.isAtLeast(failOn)) &&
          exitCode == exitOk) {
        exitCode = exitLintFailed;
      }
      switch (format) {
        case OutputFormat.text:
          writeTextFile(out, report, ansi);
        case OutputFormat.github:
          writeGithubFile(out, report);
        case OutputFormat.json:
          reports.add(report);
      }
    }

    switch (format) {
      case OutputFormat.json:
        out.writeln(prettyJson(jsonReport(reports, totals)));
      case OutputFormat.text:
      case OutputFormat.github:
        out.writeln(summaryLine(totals));
    }
    if (inputs.isEmpty && exitCode == exitOk) exitCode = exitUsage;
    return exitCode;
  }

  bool _autoColor() {
    if (Platform.environment.containsKey('NO_COLOR')) return false;
    try {
      return (identical(out, stdout) || out is StdoutSink) &&
          stdout.hasTerminal &&
          stdout.supportsAnsiEscapes;
    } on Object {
      return false;
    }
  }

  /// All OpenAir files under [dir], sorted. Hidden directories (for example
  /// `.git`) are skipped.
  static List<String> _findFiles(String dir) {
    final result = <String>[];
    void walk(Directory d) {
      List<FileSystemEntity> entries;
      try {
        entries = d.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final e in entries) {
        final name = e.path.split(RegExp(r'[\\/]')).last;
        if (e is Directory) {
          if (!name.startsWith('.')) walk(e);
        } else if (e is File) {
          final lower = name.toLowerCase();
          if (openAirExtensions.any(lower.endsWith)) result.add(e.path);
        }
      }
    }

    walk(Directory(dir));
    result.sort();
    return result;
  }

  /// The path as shown to the user: `/` as the separator, and no repeated
  /// separators (a directory argument such as `data/` gives `data/a.txt`,
  /// not `data//a.txt`). A leading `./` is removed, so that GitHub can
  /// match the annotations to the files. A leading `//` (a network path)
  /// is kept.
  static String _display(String path) {
    var p = path.replaceAll('\\', '/');
    if (p.startsWith('//')) {
      return '/${p.substring(1).replaceAll(_slashes, '/')}';
    }
    p = p.replaceAll(_slashes, '/');
    while (p.startsWith('./') && p.length > 2) {
      p = p.substring(2);
    }
    return p;
  }

  static final RegExp _slashes = RegExp('/{2,}');

  static String _ioMessage(Object e) {
    if (e is FileSystemException) {
      return e.osError?.message ?? e.message;
    }
    return e.toString();
  }
}

class _Input {
  const _Input(this.display, this.path);

  final String display;

  /// Null for standard input.
  final String? path;
}

/// A [StringSink] that writes to stdout.
///
/// When the program that reads the output closes it early (for example
/// `openair-lint airspace/ | head -1`), a write to stdout fails. Then
/// [runMain] sets [closed], and the sink drops all later output.
class StdoutSink implements StringSink {
  /// True after the output was closed by the reader.
  bool closed = false;

  @override
  void write(Object? object) {
    if (!closed) stdout.write(object);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    if (!closed) stdout.writeAll(objects, separator);
  }

  @override
  void writeCharCode(int charCode) {
    if (!closed) stdout.writeCharCode(charCode);
  }

  @override
  void writeln([Object? object = '']) {
    if (!closed) stdout.writeln(object);
  }
}

/// The OS error codes of a pipe that the reader closed: EPIPE (32) on
/// Linux and macOS, ERROR_BROKEN_PIPE (109) and ERROR_NO_DATA (232) on
/// Windows.
const Set<int> _closedPipeErrors = {32, 109, 232};

OSError? _osErrorOf(Object e) => switch (e) {
      FileSystemException(:final osError) => osError,
      StdoutException(:final osError) => osError,
      SocketException(:final osError) => osError,
      _ => null,
    };

/// Runs the command line tool with stdout and stderr and returns the exit
/// code. This is the `main` function of `bin/openair_lint.dart`.
///
/// If the reader closes stdout early, the tool stops writing and does not
/// print an error. It still checks all files, so the exit code is the
/// same as with the full output (0, 1 or 2). If stdout fails for another
/// reason, the tool prints one error line to stderr and the exit code is 2.
Future<int> runMain(List<String> arguments) async {
  final out = StdoutSink();
  var writeFailed = false;
  void onOutputError(Object e) {
    if (out.closed) return;
    out.closed = true;
    final code = _osErrorOf(e)?.errorCode;
    if (code != null && _closedPipeErrors.contains(code)) return;
    writeFailed = true;
    stderr.writeln('Error: Cannot write the output: $e');
  }

  var result = exitUsage;
  await runZonedGuarded(() async {
    final input = await _readStdinIfUsed(arguments);
    result = CliRunner(out: out, readStdin: input).run(arguments);
    try {
      await stdout.flush();
    } on IOException catch (e) {
      onOutputError(e);
    }
  }, (e, st) {
    if (e is IOException) {
      onOutputError(e);
      return;
    }
    // A bug in openair-lint. Show it like an unhandled exception.
    stderr.writeln('Unhandled exception:\n$e\n$st');
    exitCode = 255;
  });
  return writeFailed ? exitUsage : result;
}

/// If the arguments use `-` (standard input), reads all of standard input
/// in blocks and returns a function that gives the bytes. Else returns
/// null. Reading in blocks is much faster than [Stdin.readByteSync].
Future<List<int> Function()?> _readStdinIfUsed(List<String> arguments) async {
  try {
    if (!CliRunner.buildParser().parse(arguments).rest.contains('-')) {
      return null;
    }
  } on FormatException {
    return null; // CliRunner.run reports the wrong options.
  }
  try {
    final builder = BytesBuilder(copy: false);
    await for (final block in stdin) {
      builder.add(block);
    }
    final bytes = builder.takeBytes();
    return () => bytes;
  } on Object catch (e) {
    return () => throw e;
  }
}
