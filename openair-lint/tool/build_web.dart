/// Builds the OpenAir Validator web page.
///
/// ```
/// dart run tool/build_web.dart [--output build/web] [-O2|-O3|-O4]
///                              [--source-maps]
/// ```
///
/// Run it from the package folder. It compiles `web/main.dart` to
/// JavaScript and copies `index.html` and `style.css`. The result is a
/// static site in `build/web`. Serve the folder with any static web server,
/// for example `python -m http.server -d build/web 8080`.
///
/// The file names in `index.html` get a `?v=<hash>` suffix, so that a
/// browser does not use an old copy after an update.
library;

import 'dart:io';

import 'package:args/args.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('output',
        abbr: 'o',
        defaultsTo: 'build/web',
        help: 'The folder for the finished site. It is deleted first.')
    ..addOption('optimization',
        abbr: 'O',
        defaultsTo: '2',
        allowed: ['2', '3', '4'],
        help: 'The dart2js optimization level. -O2 keeps all runtime '
            'checks. -O3 and -O4 are faster but remove some checks.')
    ..addFlag('source-maps',
        negatable: false, help: 'Also write main.dart.js.map.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    exit(2);
  }
  if (args.flag('help')) {
    stdout.writeln('Builds the OpenAir Validator web page.\n\n'
        'Usage: dart run tool/build_web.dart [options]\n\n${parser.usage}');
    return;
  }

  if (!File('web/main.dart').existsSync()) {
    stderr.writeln('Run this tool from the openair-lint package folder.');
    exit(2);
  }

  final out = Directory(args.option('output')!);
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);

  final sourceMaps = args.flag('source-maps');
  final level = args.option('optimization')!;
  final compileArgs = [
    'compile',
    'js',
    '-O$level',
    '--csp',
    if (!sourceMaps) '--no-source-maps',
    '-o',
    '${out.path}/main.dart.js',
    'web/main.dart',
  ];
  stdout.writeln('dart ${compileArgs.join(' ')}');
  final watch = Stopwatch()..start();
  final result = await Process.run(Platform.resolvedExecutable, compileArgs);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    stderr.writeln('The compiler failed (exit code ${result.exitCode}).');
    exit(1);
  }

  // The compiler also writes a dependency list. The site does not need it.
  final deps = File('${out.path}/main.dart.js.deps');
  if (deps.existsSync()) deps.deleteSync();

  final js = File('${out.path}/main.dart.js');
  final css = File('web/style.css');
  css.copySync('${out.path}/style.css');

  var html = File('web/index.html').readAsStringSync();
  html = _addHash(html, 'src="main.dart.js"', js.readAsBytesSync());
  html = _addHash(html, 'href="style.css"', css.readAsBytesSync());
  File('${out.path}/index.html').writeAsStringSync(html);

  watch.stop();
  stdout.writeln('Built the web page in ${watch.elapsedMilliseconds} ms:');
  final files = out.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final kb = (f.lengthSync() / 1024).toStringAsFixed(1);
    stdout.writeln('  ${f.path.replaceAll('\\', '/')}  $kb KB');
  }
}

/// Adds `?v=<hash of bytes>` to the URL in [attribute] (for example
/// `src="main.dart.js"`). Stops with an error if [html] does not contain it.
String _addHash(String html, String attribute, List<int> bytes) {
  if (!html.contains(attribute)) {
    stderr.writeln('web/index.html does not contain $attribute.');
    exit(1);
  }
  final hash = _fnv1a(bytes).toRadixString(16).padLeft(8, '0');
  final withHash = attribute.replaceFirst(RegExp(r'"$'), '?v=$hash"');
  return html.replaceFirst(attribute, withHash);
}

/// The 32-bit FNV-1a hash. It is only used to see that a file changed.
int _fnv1a(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final b in bytes) {
    hash ^= b;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}
