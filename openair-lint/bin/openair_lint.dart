import 'dart:io';

import 'package:openair_lint/src/cli/cli.dart';

/// The `openair-lint` command. See `openair-lint --help`.
Future<void> main(List<String> arguments) async {
  exitCode = await runMain(arguments);
}
