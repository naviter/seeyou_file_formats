/// The rule group "header": the file as a whole, the header comments, the
/// upper case rule and the structure of the airspace blocks.
///
/// The rules are in several part files under `header/`, so that each file
/// stays small:
///
/// - `header/common.dart`: keyword lists and helpers for this group.
/// - `header/file_rules.dart`: encoding, line endings, empty file, text.
/// - `header/header_field_rules.dart`: `*VERSION:` and `*WRITTEN_BY:`.
/// - `header/case_rules.dart`: the upper case rule of version 3.0.
/// - `header/structure_rules.dart`: commands and airspace blocks.
library;

import '../altitude/altitude.dart';
import '../diagnostic.dart';
import '../lint_context.dart';
import '../model/openair_file.dart';
import '../spec_version.dart';
import 'rule.dart';

part 'header/case_rules.dart';
part 'header/common.dart';
part 'header/file_rules.dart';
part 'header/header_field_rules.dart';
part 'header/structure_rules.dart';

/// Rules for the file header (`*VERSION:`, `*WRITTEN_BY:`), the file as a
/// whole and the structure of the airspace blocks.
final List<Rule> headerRules = [
  // File and encoding.
  _fileNotUtf8,
  _fileInvalidUtf8,
  _fileReplacementCharacter,
  _fileBom,
  _fileMixedLineEndings,
  _fileNoAirspace,
  _fileGarbledText,
  _fileStreplaBlock,
  _fileExtensionNotOpenAir,
  // Header comments.
  _versionMissing,
  _versionInvalid,
  _versionOld,
  _versionDraft,
  _versionUnknown,
  _writtenByMissing,
  _writtenByEmpty,
  _headerFieldFormat,
  _headerFieldDuplicate,
  _headerAfterFirstCommand,
  // Upper case.
  _caseNotUpperCase,
  // Commands.
  _commandOutsideAirspace,
  _commandUnknown,
  _commandNotInSpec,
  // Airspace blocks.
  _airspaceAcMissing,
  _airspaceAhMissing,
  _airspaceAlMissing,
  _airspaceAhDuplicate,
  _airspaceAlDuplicate,
  _airspaceGeometryMissing,
  _airspaceAttributeDuplicate,
  _airspaceCommandOrder,
  _airspaceAnMissing,
  _airspaceDuplicate,
];
