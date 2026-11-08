/// The messages between the page and the web worker.
///
/// The worker keeps the report of the last lint run. The page asks for the
/// parts that it shows.
library;

import 'dart:js_interop';

/// The kinds of [WorkerRequest].
abstract final class RequestKind {
  /// Lint [WorkerRequest.bytes] or [WorkerRequest.text]. The answer is a
  /// `ReportSummary` as JSON.
  static const String lint = 'lint';

  /// Get one page of diagnostics. The answer is a `ReportPage` as JSON.
  static const String page = 'page';

  /// Get the diagnostics in the text format. The answer is plain text.
  static const String export = 'export';
}

/// A message from the page to the worker.
extension type WorkerRequest._(JSObject _) implements JSObject {
  /// Lint a file ([bytes]) or pasted text ([text]).
  ///
  /// [target] is `3.0`, `2.1`, or an empty string to use the `*VERSION:`
  /// header. [name] is the name of the file, or null for pasted text.
  factory WorkerRequest.lint({
    required int id,
    required String target,
    JSUint8Array? bytes,
    String? text,
    String? name,
  }) =>
      WorkerRequest._create(
          kind: RequestKind.lint,
          id: id,
          target: target,
          bytes: bytes,
          text: text,
          name: name);

  /// Get [count] diagnostics from position [offset] of the report of lint
  /// request [reportId] that match [filter] (see `ReportFilter.encode`).
  factory WorkerRequest.page({
    required int id,
    required int reportId,
    required String filter,
    required int offset,
    required int count,
  }) =>
      WorkerRequest._create(
          kind: RequestKind.page,
          id: id,
          reportId: reportId,
          filter: filter,
          offset: offset,
          count: count);

  /// Get the diagnostics of lint request [reportId] that match [filter] in
  /// the text format. [name] is the file name for each line.
  factory WorkerRequest.export({
    required int id,
    required int reportId,
    required String filter,
    required String name,
  }) =>
      WorkerRequest._create(
          kind: RequestKind.export,
          id: id,
          reportId: reportId,
          filter: filter,
          text: name);

  external factory WorkerRequest._create({
    required String kind,
    required int id,
    String? target,
    JSUint8Array? bytes,
    String? text,
    int? reportId,
    String? filter,
    int? offset,
    int? count,
    String? name,
  });

  external String get kind;

  /// The number of the request. The answer has the same number.
  external int get id;
  external String? get target;
  external JSUint8Array? get bytes;

  /// The pasted text (lint), or the file name (export).
  external String? get text;
  external int? get reportId;
  external String? get filter;
  external int? get offset;
  external int? get count;

  /// The name of the file (lint), or null.
  external String? get name;
}

/// A message from the worker to the page: the answer to one request.
///
/// It has [data] (JSON or text, see [RequestKind]) or [error].
extension type WorkerResponse._(JSObject _) implements JSObject {
  external factory WorkerResponse({
    required int id,
    String? data,
    String? error,
  });

  external int get id;
  external String? get data;
  external String? get error;
}
