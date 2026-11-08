/// The user interface of the OpenAir Validator page.
///
/// Security: the page shows untrusted files. File text is only put into
/// the page with `textContent` and text nodes, never as HTML.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:openair_lint/openair_lint.dart';
import 'package:web/web.dart' hide Report;

import 'example.dart';
import 'protocol.dart';
import 'report.dart';

/// The number of diagnostics that are added to the list at one time.
const int _pageSize = 200;

/// Pasted text up to this length is checked while the user types.
const int _liveCheckLimit = 200000;

/// The help text below the text box.
const String _liveHelp =
    'The text is checked while you type. Press Ctrl+Enter to check it now.';

/// Characters shown before and after the marked part of a source line.
const int _contextBefore = 60;
const int _contextAfter = 60;

/// The longest marked part of a source line that is shown.
const int _maxMarkLength = 160;

/// Source lines up to this length are shown completely.
const int _shortLine = 120;

/// Starts the page.
void runPage() {
  _Page().start();
}

/// The file or text that the user wants to check.
class _Input {
  _Input.bytes(this.name, Uint8List this.bytes) : text = null;
  _Input.text(this.name, String this.text) : bytes = null;

  final String name;
  final Uint8List? bytes;
  final String? text;
}

class _Page {
  // Elements of index.html.
  final _chooseFile = _el<HTMLButtonElement>('choose-file');
  final _fileInput = _el<HTMLInputElement>('file-input');
  final _dropZone = _el<HTMLElement>('drop-zone');
  final _pastePanel = _el<HTMLDetailsElement>('paste-panel');
  final _pasteText = _el<HTMLTextAreaElement>('paste-text');
  final _pasteHelp = _el<HTMLElement>('paste-help');
  final _checkText = _el<HTMLButtonElement>('check-text');
  final _clearText = _el<HTMLButtonElement>('clear-text');
  final _target = _el<HTMLSelectElement>('target');
  final _example = _el<HTMLButtonElement>('example');
  final _status = _el<HTMLElement>('status');
  final _statusText = _el<HTMLElement>('status-text');
  final _results = _el<HTMLElement>('results');
  final _fileInfo = _el<HTMLElement>('file-info');
  final _filters = _el<HTMLElement>('filters');
  final _showError = _el<HTMLInputElement>('show-error');
  final _showWarning = _el<HTMLInputElement>('show-warning');
  final _showInfo = _el<HTMLInputElement>('show-info');
  final _countError = _el<HTMLElement>('count-error');
  final _countWarning = _el<HTMLElement>('count-warning');
  final _countInfo = _el<HTMLElement>('count-info');
  final _ruleFilter = _el<HTMLSelectElement>('rule-filter');
  final _listInfo = _el<HTMLElement>('list-info');
  final _list = _el<HTMLOListElement>('list');
  final _more = _el<HTMLButtonElement>('more');
  final _download = _el<HTMLButtonElement>('download');
  final _version = _el<HTMLElement>('linter-version');

  final _checker = _Checker();

  /// The number of the newest check. Older results are ignored.
  int _checkId = 0;

  /// The number of the newest list view (a new report or new filters).
  /// Older pages are ignored.
  int _viewId = 0;

  /// The input of the shown report.
  _Input? _input;

  /// The shown report.
  _ReportHandle? _report;

  /// The filter of the list.
  ReportFilter _filter = ReportFilter(Severity.values.toSet(), '');

  /// The number of diagnostics in the list, and the number that match the
  /// filter.
  int _rendered = 0;
  int _matching = 0;

  Timer? _typingTimer;

  void start() {
    _version.textContent =
        'openair-lint $packageVersion, ${_plural(allRules.length, 'rule')}';

    _chooseFile.on('click', (_) => _fileInput.click());
    _fileInput.on('change', (_) {
      final files = _fileInput.files;
      if (files != null && files.length > 0) _openFile(files.item(0)!);
      // Allow to open the same file again (it can have changed).
      _fileInput.value = '';
    });

    document.on('dragover', (e) {
      final event = e as DragEvent;
      if (!_hasFiles(event)) return;
      event.preventDefault();
      event.dataTransfer?.dropEffect = 'copy';
      _dropZone.classList.add('dragging');
    });
    document.on('dragleave', (e) {
      // relatedTarget is null when the pointer leaves the window.
      if ((e as DragEvent).relatedTarget == null) {
        _dropZone.classList.remove('dragging');
      }
    });
    document.on('drop', (e) {
      final event = e as DragEvent;
      _dropZone.classList.remove('dragging');
      if (!_hasFiles(event)) return;
      event.preventDefault();
      final files = event.dataTransfer!.files;
      if (files.length == 0) return;
      _openFile(files.item(0)!,
          note: files.length > 1
              ? 'You dropped ${files.length} files. Only the first file '
                  'is checked.'
              : null);
    });

    _checkText.on('click', (_) => _checkPasted());
    _clearText.on('click', (_) {
      _pasteText.value = '';
      _pasteText.focus();
    });
    _pasteText.on('keydown', (e) {
      final event = e as KeyboardEvent;
      if (event.key == 'Enter' && (event.ctrlKey || event.metaKey)) {
        event.preventDefault();
        _checkPasted();
      }
    });
    _pasteText.on('input', (_) {
      _typingTimer?.cancel();
      final length = _pasteText.value.length;
      final live = length <= _liveCheckLimit;
      _pasteHelp.textContent = live
          ? _liveHelp
          : 'The text is long, so it is not checked while you type. '
              'Press "Check text" or Ctrl+Enter.';
      if (length == 0 || !live) return;
      _typingTimer =
          Timer(const Duration(milliseconds: 600), () => _checkPasted());
    });

    _target.on('change', (_) {
      final input = _input;
      if (input != null) _check(input);
    });
    _example.on('click', (_) {
      _pastePanel.open = true;
      _pasteText.value = exampleText;
      _check(_Input.text(exampleName, exampleText));
    });

    for (final box in [_showError, _showWarning, _showInfo]) {
      box.on('change', (_) => _applyFilters());
    }
    _ruleFilter.on('change', (_) => _applyFilters());
    _more.on('click', (_) => _loadMore());
    _download.on('click', (_) => _downloadText());

    for (final b in [_chooseFile, _checkText, _example]) {
      b.disabled = false;
    }
    _setStatus('Ready. Choose a file, drop a file on this page, '
        'or paste text.');
  }

  // ---------------------------------------------------------------------
  // Input

  bool _hasFiles(DragEvent event) {
    final types = event.dataTransfer?.types.toDart;
    if (types == null) return false;
    return types.any((t) => t.toDart == 'Files');
  }

  Future<void> _openFile(File file, {String? note}) async {
    final id = ++_checkId;
    _setBusy('Reading ${file.name}...');
    final Uint8List bytes;
    try {
      bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
    } catch (e) {
      if (id == _checkId) {
        _setStatus('The file ${file.name} cannot be read: $e', error: true);
      }
      return;
    }
    if (id != _checkId) return;
    await _check(_Input.bytes(file.name, bytes), note: note);
  }

  void _checkPasted() {
    _typingTimer?.cancel();
    _check(_Input.text('Pasted text', _pasteText.value));
  }

  // ---------------------------------------------------------------------
  // Checking

  Future<void> _check(_Input input, {String? note}) async {
    final id = ++_checkId;
    _setBusy('Checking ${input.name}...');
    // The old list stays visible, but it cannot load more pages: the
    // worker keeps only the newest report.
    _report = null;
    _viewId++;
    final target = _target.value == 'auto' ? '' : _target.value;
    final watch = Stopwatch()..start();
    final _ReportHandle report;
    try {
      report = await _checker.lint(input, target);
    } on _Cancelled {
      return;
    } catch (e) {
      if (id == _checkId) _showFailure(e);
      return;
    }
    if (id != _checkId) return;
    watch.stop();
    _input = input;
    _report = report;
    _show(input, report.summary, watch.elapsedMilliseconds, note);
  }

  void _showFailure(Object e) {
    _setStatus(
        'The check failed: $e. This is a bug in openair-lint. '
        'Please report it on GitHub.',
        error: true);
  }

  void _show(_Input input, ReportSummary summary, int elapsedMs, String? note) {
    final errors = summary.count(Severity.error);
    final warnings = summary.count(Severity.warning);
    final info = summary.count(Severity.info);

    final time = elapsedMs < 1000
        ? '${elapsedMs < 1 ? 1 : elapsedMs} ms'
        : '${(elapsedMs / 1000).toStringAsFixed(1)} s';
    final result = summary.total == 0
        ? 'No problems found.'
        : '${_plural(errors, 'error')}, ${_plural(warnings, 'warning')}, '
            '${_n(info)} info.';
    _setStatus('Checked ${input.name} in $time. $result'
        '${note == null ? '' : ' $note'}');

    _fileInfo.textContent = [
      '${_plural(summary.lineCount, 'line')}, '
          '${_plural(summary.airspaceCount, 'airspace')}, '
          '${summary.encoding}'
          '${summary.hasBom ? ' with a byte order mark' : ''}.',
      _versionText(summary),
    ].join(' ');

    _countError.textContent = _plural(errors, 'error');
    _countWarning.textContent = _plural(warnings, 'warning');
    _countInfo.textContent = '${_n(info)} info';

    _fillRuleFilter(summary);
    _filters.hidden = (summary.total == 0).toJS;
    _results.hidden = false.toJS;
    _applyFilters();
  }

  String _versionText(ReportSummary summary) {
    final v = summary.specVersion;
    final declared = summary.declaredVersion;
    return switch (summary.versionSource) {
      'target' => 'Checked as version $v, because you chose this version.',
      'header' => 'Checked as version $v. The file header says '
          '"*VERSION: $declared".',
      'headerOld' => 'The file header says version $declared. Files with '
          'an older version are checked as version $v.',
      'headerNewer' => 'The file header says version $declared. This '
          'validator does not know this version. The file is checked as '
          'version $v.',
      'headerInvalid' => 'The *VERSION value "$declared" is not a version '
          'number. The file is checked as version $v.',
      'missing' => 'The file has no *VERSION header. It is checked as '
          'version $v.',
      _ => 'Checked as version $v.',
    };
  }

  // ---------------------------------------------------------------------
  // Status

  void _setBusy(String message) {
    _status.classList.add('busy');
    _status.classList.remove('error');
    _statusText.textContent = message;
    _results.setAttribute('aria-busy', 'true');
  }

  void _setStatus(String message, {bool error = false}) {
    _status.classList.remove('busy');
    _status.classList.toggle('error', error);
    _statusText.textContent = message;
    _results.removeAttribute('aria-busy');
  }

  // ---------------------------------------------------------------------
  // Filters and list

  void _fillRuleFilter(ReportSummary summary) {
    final old = _ruleFilter.value;
    _ruleFilter.textContent = '';
    _ruleFilter.appendChild(_option('', 'All rules'));
    var found = false;
    for (final (id, count) in summary.rules) {
      _ruleFilter.appendChild(_option(id, '$id (${_n(count)})'));
      if (id == old) found = true;
    }
    _ruleFilter.value = found ? old : '';
  }

  HTMLOptionElement _option(String value, String label) => HTMLOptionElement()
    ..value = value
    ..textContent = label;

  /// Reads the filters and shows the first page of the list.
  void _applyFilters() {
    if (_report == null) return;
    _filter = ReportFilter({
      if (_showError.checked) Severity.error,
      if (_showWarning.checked) Severity.warning,
      if (_showInfo.checked) Severity.info,
    }, _ruleFilter.value);
    _viewId++;
    _list.textContent = '';
    _rendered = 0;
    _matching = 0;
    _loadMore();
  }

  /// Adds the next page of diagnostics to the list.
  Future<void> _loadMore() async {
    final report = _report;
    if (report == null) return;
    final view = _viewId;
    _more.disabled = true;
    final ReportPage page;
    try {
      page = await report.page(_filter, _rendered, _pageSize);
    } on _Cancelled {
      return;
    } catch (e) {
      if (view == _viewId) _showFailure(e);
      return;
    } finally {
      _more.disabled = false;
    }
    if (view != _viewId) return;

    final fragment = document.createDocumentFragment();
    for (var i = 0; i < page.items.length; i++) {
      fragment.appendChild(_renderItem(page.items[i], page.snippets[i]));
    }
    _list.appendChild(fragment);
    _rendered += page.items.length;
    _matching = page.total;
    _updateListInfo();
  }

  void _updateListInfo() {
    final total = _summary.total;
    final hidden = _matching - _rendered;
    if (total == 0) {
      _listInfo.textContent = 'The file follows all rules of the '
          'specification that this validator checks.';
    } else if (_matching == 0) {
      _listInfo.textContent = 'No problems match the filter. '
          '${_plural(total, 'problem')} are not shown.';
    } else if (_matching == total) {
      _listInfo.textContent = hidden == 0
          ? 'Showing all ${_plural(total, 'problem')}.'
          : 'Showing ${_n(_rendered)} of ${_plural(total, 'problem')}.';
    } else {
      _listInfo.textContent = 'Showing ${_n(_rendered)} of '
          '${_n(_matching)} problems that match the filter '
          '(${_n(total)} in total).';
    }
    _list.hidden = (_matching == 0).toJS;
    _more.hidden = (hidden <= 0).toJS;
    _more.textContent = hidden > _pageSize
        ? 'Show ${_n(_pageSize)} more (${_n(hidden)} not shown)'
        : 'Show the last ${_n(hidden)}';
    _download.hidden = (_matching == 0).toJS;
  }

  ReportSummary get _summary => _report!.summary;

  HTMLLIElement _renderItem(Diagnostic d, Snippet? snippet) {
    final item = HTMLLIElement()..className = 'diag sev-${d.severity.label}';

    final head = HTMLDivElement()..className = 'diag-head';
    head.appendChild(HTMLSpanElement()
      ..className = 'badge badge-${d.severity.label}'
      ..textContent = _severityName(d.severity));
    head.appendChild(HTMLSpanElement()
      ..className = 'pos'
      ..textContent = 'Line ${d.line}, column ${d.column}');
    head.appendChild(HTMLAnchorElement()
      ..className = 'rule'
      ..href = d.specUrl
      ..target = '_blank'
      ..rel = 'noopener noreferrer'
      ..title = 'Open the section of the specification for this rule '
          '(opens in a new tab)'
      ..textContent = d.ruleId);
    item.appendChild(head);

    item.appendChild(HTMLParagraphElement()
      ..className = 'msg'
      ..textContent = d.message);

    if (snippet != null) item.appendChild(_renderSource(d, snippet));

    final rule = findRule(d.ruleId);
    if (rule != null) item.appendChild(_renderRuleHelp(rule));
    return item;
  }

  /// The source line of [d], with the part of the problem marked.
  HTMLElement _renderSource(Diagnostic d, Snippet s) {
    final box = HTMLDivElement()..className = 'src';
    box.appendChild(HTMLSpanElement()
      ..className = 'ln'
      ..textContent = '${d.line}');

    var a = d.column - 1;
    var b = d.endColumn - 1;
    if (b - a > _maxMarkLength) b = a + _maxMarkLength;
    a = a.clamp(s.start, s.end);
    b = b.clamp(a, s.end);
    var from = (a - _contextBefore).clamp(s.start, a);
    var to = (b + _contextAfter).clamp(b, s.end);
    if (s.text.length <= _shortLine) {
      from = s.start;
      to = s.end;
    }
    String part(int x, int y) =>
        _visibleControls(s.text.substring(x - s.start, y - s.start));

    final code = HTMLElement.code();
    if (from > 0) code.appendChild(_span('cut', '…'));
    code.appendChild(document.createTextNode(part(from, a)));
    final mark = HTMLElement.mark();
    if (b > a) {
      mark.textContent = part(a, b);
    } else {
      // The problem is at the end of the line, or has no length.
      mark
        ..className = 'empty'
        ..textContent = ' ';
    }
    code.appendChild(mark);
    code.appendChild(document.createTextNode(part(b, to)));
    if (to < s.lineLength) code.appendChild(_span('cut', '…'));
    box.appendChild(code);
    return box;
  }

  /// A "About this rule" section. Its content is created when it is opened.
  HTMLDetailsElement _renderRuleHelp(Rule rule) {
    final details = HTMLDetailsElement()..className = 'rule-help';
    details.appendChild(HTMLElement.summary()..textContent = 'About this rule');
    var filled = false;
    details.on('toggle', (_) {
      if (filled || !details.open) return;
      filled = true;
      final body = HTMLDivElement()..className = 'rule-body';
      body.appendChild(HTMLParagraphElement()
        ..className = 'rule-desc'
        ..textContent = rule.description);
      body.appendChild(HTMLParagraphElement()
        ..className = 'rule-meta'
        ..textContent = 'Severity: ${rule.severity.label}. '
            'Versions: ${rule.versionsLabel}.');
      for (final paragraph in rule.explanation.split('\n\n')) {
        if (paragraph.trim().isEmpty) continue;
        body.appendChild(HTMLParagraphElement()..textContent = paragraph);
      }
      body.appendChild(_exampleBlock('Correct', rule.correctExample, 'good'));
      body.appendChild(
          _exampleBlock('Incorrect', rule.incorrectExample, 'bad'));
      details.appendChild(body);
    });
    return details;
  }

  HTMLElement _exampleBlock(String title, String text, String kind) {
    final figure = HTMLElement.figure()..className = 'example example-$kind';
    figure.appendChild(HTMLElement.figcaption()..textContent = title);
    figure.appendChild(HTMLPreElement.pre()..textContent = text);
    return figure;
  }

  // ---------------------------------------------------------------------
  // Download

  Future<void> _downloadText() async {
    final input = _input;
    final report = _report;
    if (input == null || report == null) return;
    final view = _viewId;
    _download.disabled = true;
    final String text;
    try {
      text = await report.exportText(input.name, _filter);
    } on _Cancelled {
      return;
    } catch (e) {
      if (view == _viewId) _showFailure(e);
      return;
    } finally {
      _download.disabled = false;
    }
    final blob = Blob(
      [text.toJS].toJS,
      BlobPropertyBag(type: 'text/plain;charset=utf-8'),
    );
    final url = URL.createObjectURL(blob);
    final link = HTMLAnchorElement()
      ..href = url
      ..download = '${input.name}.lint.txt';
    document.body!.appendChild(link);
    link.click();
    link.remove();
    Timer(const Duration(seconds: 30), () => URL.revokeObjectURL(url));
  }
}

/// A report that the page can show. It is in the worker, or on the page.
abstract class _ReportHandle {
  ReportSummary get summary;

  Future<ReportPage> page(ReportFilter filter, int offset, int count);

  Future<String> exportText(String name, ReportFilter filter);
}

/// A report that was created on the page.
class _LocalReport implements _ReportHandle {
  _LocalReport(this.report) : summary = report.summary();

  final Report report;

  @override
  final ReportSummary summary;

  @override
  Future<ReportPage> page(ReportFilter filter, int offset, int count) async =>
      report.page(filter, offset, count);

  @override
  Future<String> exportText(String name, ReportFilter filter) async =>
      report.exportText(name, filter);
}

/// A report that is kept in the web worker.
class _WorkerReport implements _ReportHandle {
  _WorkerReport(this.checker, this.id, this.summary);

  final _Checker checker;

  /// The ID of the lint request.
  final int id;

  @override
  final ReportSummary summary;

  @override
  Future<ReportPage> page(ReportFilter filter, int offset, int count) async {
    final data = await checker.send((requestId) => WorkerRequest.page(
        id: requestId,
        reportId: id,
        filter: filter.encode(),
        offset: offset,
        count: count));
    return ReportPage.fromJson(jsonDecode(data) as Map<String, Object?>);
  }

  @override
  Future<String> exportText(String name, ReportFilter filter) =>
      checker.send((requestId) => WorkerRequest.export(
          id: requestId, reportId: id, filter: filter.encode(), name: name));
}

/// Lints in a web worker, so that the page stays responsive. If the
/// browser cannot start the worker (for example, Chrome does not allow
/// workers for pages opened from a local `file://` folder), it lints on
/// the page.
class _Checker {
  Worker? _worker;
  bool _workerFailed = false;
  int _nextId = 0;

  /// The requests that wait for an answer of the worker.
  final Map<int, Completer<String>> _pending = {};

  /// The lint request that waits for an answer, with its input. If the
  /// worker fails, the page lints the input itself.
  int? _lintId;
  _Input? _lintInput;
  String _lintTarget = '';
  Completer<_ReportHandle>? _lintCompleter;

  Future<_ReportHandle> lint(_Input input, String target) async {
    // A running lint is not needed any more. Stop the worker; a new worker
    // starts below.
    if (_lintCompleter != null) _stopWorker();
    final worker = _workerFailed ? null : _startWorker();
    if (worker == null) return _lintHere(input, target);

    final id = ++_nextId;
    final completer = Completer<_ReportHandle>();
    _lintId = id;
    _lintInput = input;
    _lintTarget = target;
    _lintCompleter = completer;
    final answer = Completer<String>();
    _pending[id] = answer;
    // The bytes are copied to the worker. The page keeps its copy, so that
    // it can check the file again with another version.
    worker.postMessage(WorkerRequest.lint(
      id: id,
      target: target,
      bytes: input.bytes?.toJS,
      text: input.text,
      name: input.bytes == null ? null : input.name,
    ));
    unawaited(answer.future.then((data) {
      if (_lintId == id) _clearLint();
      if (completer.isCompleted) return;
      try {
        final summary =
            ReportSummary.fromJson(jsonDecode(data) as Map<String, Object?>);
        completer.complete(_WorkerReport(this, id, summary));
      } catch (e) {
        completer.completeError(e);
      }
    }, onError: (Object e) {
      if (_lintId == id) _clearLint();
      if (!completer.isCompleted) completer.completeError(e);
    }));
    return completer.future;
  }

  /// Sends a request to the worker and returns the answer.
  Future<String> send(WorkerRequest Function(int id) create) {
    final worker = _worker;
    if (worker == null) {
      return Future.error(StateError('The worker stopped.'));
    }
    final id = ++_nextId;
    final answer = Completer<String>();
    _pending[id] = answer;
    worker.postMessage(create(id));
    return answer.future;
  }

  void _clearLint() {
    _lintId = null;
    _lintInput = null;
    _lintCompleter = null;
  }

  /// Stops the worker. All open requests end with [_Cancelled].
  void _stopWorker() {
    _worker?.terminate();
    _worker = null;
    final pending = _pending.values.toList();
    _pending.clear();
    final lint = _lintCompleter;
    _clearLint();
    for (final c in pending) {
      c.completeError(const _Cancelled());
    }
    if (lint != null && !lint.isCompleted) {
      lint.completeError(const _Cancelled());
    }
  }

  Worker? _startWorker() {
    final existing = _worker;
    if (existing != null) return existing;
    final script = document.getElementById('app-script') as HTMLScriptElement?;
    if (script == null) {
      _workerFailed = true;
      return null;
    }
    try {
      final worker = Worker(script.src.toJS);
      worker.onmessage = (MessageEvent e) {
        _onMessage(e.data as WorkerResponse);
      }.toJS;
      worker.onerror = (Event e) {
        e.preventDefault();
        _onWorkerError();
      }.toJS;
      _worker = worker;
      return worker;
    } catch (_) {
      _workerFailed = true;
      return null;
    }
  }

  void _onMessage(WorkerResponse response) {
    final answer = _pending.remove(response.id);
    if (answer == null) return;
    final error = response.error;
    if (error != null) {
      answer.completeError(error);
    } else {
      answer.complete(response.data ?? '');
    }
  }

  /// The worker did not start, or it stopped. Lint on the page from now on.
  void _onWorkerError() {
    _workerFailed = true;
    final lint = _lintCompleter;
    final input = _lintInput;
    final target = _lintTarget;
    // Do not cancel the open lint request: it is done on the page.
    _pending.remove(_lintId);
    _clearLint();
    _stopWorker();
    if (lint == null || input == null || lint.isCompleted) return;
    lint.complete(_lintHere(input, target));
  }

  Future<_ReportHandle> _lintHere(_Input input, String target) async {
    // Wait a moment, so that the browser can show "Checking..." before
    // the page is busy.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return _LocalReport(runLint(
        bytes: input.bytes,
        text: input.text,
        target: target,
        fileName: input.bytes == null ? null : input.name));
  }
}

/// The error of a request that was stopped because a new check started.
class _Cancelled implements Exception {
  const _Cancelled();

  @override
  String toString() => 'The request was stopped.';
}

// -----------------------------------------------------------------------
// Helpers

T _el<T extends JSObject>(String id) {
  final element = document.getElementById(id);
  if (element == null) throw StateError('The page has no element #$id');
  return element as T;
}

extension on EventTarget {
  void on(String type, void Function(Event event) listener) {
    addEventListener(type, listener.toJS);
  }
}

HTMLSpanElement _span(String className, String text) => HTMLSpanElement()
  ..className = className
  ..textContent = text;

String _severityName(Severity s) => switch (s) {
      Severity.error => 'Error',
      Severity.warning => 'Warning',
      Severity.info => 'Info',
    };

/// Replaces control characters with visible symbols (for example U+2400
/// for NUL). Each character stays one UTF-16 unit, so columns do not move.
/// Tabs stay tabs.
String _visibleControls(String text) {
  var hasControl = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if ((c < 0x20 && c != 0x09) || c == 0x7F) {
      hasControl = true;
      break;
    }
  }
  if (!hasControl) return text;
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c < 0x20 && c != 0x09) {
      out.writeCharCode(0x2400 + c);
    } else if (c == 0x7F) {
      out.writeCharCode(0x2421);
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

/// Formats [n] with a comma between groups of 3 digits.
String _n(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

String _plural(int n, String word) => '${_n(n)} $word${n == 1 ? '' : 's'}';
