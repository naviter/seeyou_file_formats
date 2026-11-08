/// The OpenAir Validator web page.
///
/// The same compiled script runs in two places:
///
/// - On the page, it shows the user interface.
/// - In a web worker, it lints the files. The page starts the worker with
///   the same script file.
///
/// Build the page with `dart run tool/build_web.dart`.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'src/page.dart';
import 'src/worker.dart';

void main() {
  if (globalContext.has('document')) {
    runPage();
  } else {
    runWorker();
  }
}
