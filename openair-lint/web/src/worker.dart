/// The code that runs in the web worker. The worker lints files, so that
/// the page stays responsive while a large file is checked.
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' hide Report;

import 'protocol.dart';
import 'report.dart';

/// Starts the worker: answer each request of the page.
void runWorker() {
  final scope = globalContext as DedicatedWorkerGlobalScope;
  // The worker keeps only the report of the last lint request.
  int? reportId;
  Report? report;

  Report reportFor(WorkerRequest request) {
    final current = report;
    if (current == null || request.reportId != reportId) {
      throw StateError('The report ${request.reportId} is not available.');
    }
    return current;
  }

  scope.onmessage = (MessageEvent event) {
    final request = event.data as WorkerRequest;
    WorkerResponse response;
    try {
      final String data;
      switch (request.kind) {
        case RequestKind.lint:
          report = null;
          final result = runLint(
            bytes: request.bytes?.toDart,
            text: request.text,
            target: request.target ?? '',
            fileName: request.name,
          );
          report = result;
          reportId = request.id;
          data = jsonEncode(result.summary().toJson());
        case RequestKind.page:
          data = jsonEncode(reportFor(request)
              .page(ReportFilter.decode(request.filter!), request.offset!,
                  request.count!)
              .toJson());
        case RequestKind.export:
          data = reportFor(request)
              .exportText(request.text!, ReportFilter.decode(request.filter!));
        default:
          throw ArgumentError('Unknown request kind ${request.kind}');
      }
      response = WorkerResponse(id: request.id, data: data);
    } catch (e) {
      response = WorkerResponse(id: request.id, error: '$e');
    }
    scope.postMessage(response);
  }.toJS;
}
