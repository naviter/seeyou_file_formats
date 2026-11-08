/// A version of the OpenAir specification that the linter knows.
enum SpecVersion {
  /// OpenAir 2.1. Files with version 2.0 or older are also checked as 2.1.
  v2_1('2.1'),

  /// OpenAir 3.0, the current version of the specification.
  v3_0('3.0');

  const SpecVersion(this.label);

  /// The version as written in the header, for example `3.0`.
  final String label;

  /// The newest version that the linter knows.
  static const SpecVersion latest = SpecVersion.v3_0;

  /// All versions, as a set. Use this for rules that apply to every version.
  static const Set<SpecVersion> all = {SpecVersion.v2_1, SpecVersion.v3_0};

  /// Only version 3.0.
  static const Set<SpecVersion> only3 = {SpecVersion.v3_0};

  /// Only version 2.1.
  static const Set<SpecVersion> only21 = {SpecVersion.v2_1};

  /// Returns the version with exactly this [label] (`2.1` or `3.0`),
  /// or null. Use this for the `--target` option.
  static SpecVersion? fromLabel(String label) {
    for (final v in values) {
      if (v.label == label.trim()) return v;
    }
    return null;
  }

  @override
  String toString() => label;
}

/// The numbers of a version string such as `3.0` or `2.1.2`.
class VersionNumber {
  const VersionNumber(this.major, this.minor);

  final int major;
  final int minor;

  static final RegExp _pattern = RegExp(r'^(\d+)\.(\d+)(?:\.\d+)*$');

  /// Parses `major.minor` (a patch number is allowed and ignored).
  /// Returns null if [text] has another form.
  static VersionNumber? tryParse(String text) {
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    // int.tryParse returns null for a number that is too large for an int.
    final major = int.tryParse(m.group(1)!);
    final minor = int.tryParse(m.group(2)!);
    if (major == null || minor == null) return null;
    return VersionNumber(major, minor);
  }

  int compareTo(VersionNumber other) => major != other.major
      ? major.compareTo(other.major)
      : minor.compareTo(other.minor);

  @override
  String toString() => '$major.$minor';
}

/// How the linter chose the spec version for one file.
enum VersionSource {
  /// The `--target` option (or [LintOptions.target]) was used.
  target,

  /// The `*VERSION:` header gave a version that the linter knows (2.1 or 3.0).
  header,

  /// The header gave an older version (for example 2.0). It is checked as 2.1.
  headerOld,

  /// The header gave a version newer than 3.0. It is checked as 3.0.
  headerNewer,

  /// The header value is not a version number. The file is checked as 3.0.
  headerInvalid,

  /// The file has no `*VERSION:` header. The file is checked as 3.0.
  missing,
}

/// The result of [resolveSpecVersion].
class ResolvedVersion {
  const ResolvedVersion(this.version, this.source);

  /// The version that the rules use.
  final SpecVersion version;

  /// Why this version was chosen.
  final VersionSource source;
}

/// Chooses the spec version for a file.
///
/// [declared] is the value of the `*VERSION:` header (null if there is no
/// header). [target] is the version that the user asked for; it wins.
ResolvedVersion resolveSpecVersion(String? declared, SpecVersion? target) {
  if (target != null) return ResolvedVersion(target, VersionSource.target);
  if (declared == null) {
    return const ResolvedVersion(SpecVersion.latest, VersionSource.missing);
  }
  final number = VersionNumber.tryParse(declared);
  if (number == null) {
    return const ResolvedVersion(
        SpecVersion.latest, VersionSource.headerInvalid);
  }
  final known = SpecVersion.fromLabel(number.toString());
  if (known != null) return ResolvedVersion(known, VersionSource.header);
  if (number.compareTo(const VersionNumber(2, 1)) < 0) {
    return const ResolvedVersion(SpecVersion.v2_1, VersionSource.headerOld);
  }
  if (number.compareTo(const VersionNumber(3, 0)) > 0) {
    return const ResolvedVersion(SpecVersion.latest, VersionSource.headerNewer);
  }
  // Between 2.1 and 3.0, for example 2.5. Check with the older rules.
  return const ResolvedVersion(SpecVersion.v2_1, VersionSource.headerOld);
}
