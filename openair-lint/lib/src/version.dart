/// The version of the openair-lint package.
///
/// Keep this value the same as `version` in `pubspec.yaml`.
/// A test checks that both values match.
const String packageVersion = '3.0.0-dev.1';

/// The base URL of the OpenAir specification on GitHub.
///
/// Add `#<anchor>` to link to one section.
const String specBaseUrl =
    'https://github.com/naviter/seeyou_file_formats/blob/main/OpenAir_File_Format_Support.md';

/// The base URL of the last text of the OpenAir 2.1 specification.
///
/// The tag `v2.1.5` has the specification text version 2.1.3, the last
/// text of version 2.1. A tag does not change, so the anchors of this text
/// stay valid when the text on `main` changes.
const String specBaseUrl21 =
    'https://github.com/naviter/seeyou_file_formats/blob/v2.1.5/OpenAir_File_Format_Support.md';

/// Returns the URL of one section of the specification.
///
/// [anchor] is the GitHub anchor of the heading, without `#`.
/// An empty anchor returns the URL of the whole document.
/// With [version21], the URL is in the text of version 2.1
/// ([specBaseUrl21]).
String specUrl(String anchor, {bool version21 = false}) {
  final base = version21 ? specBaseUrl21 : specBaseUrl;
  return anchor.isEmpty ? base : '$base#$anchor';
}
