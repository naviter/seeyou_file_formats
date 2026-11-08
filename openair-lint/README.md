# openair-lint

Linter for the [OpenAir 3.0 file format specification by Naviter](https://github.com/naviter/seeyou_file_formats/blob/main/OpenAir_File_Format_Support.md).

openair-lint checks OpenAir airspace files. It finds errors (the file breaks a
"must" rule of the specification), warnings (the file breaks a "should" rule)
and hints. Each problem has a line, a column, a rule ID and a link to the
specification.

There are three ways to use it:

- the command line program `openair-lint`,
- the [OpenAir Validator](https://naviter.github.io/seeyou_file_formats/) web
  page, for people who do not use the command line (the page exists after
  the first release),
- a [GitHub Action](#github-action), to check the files of a repository on
  every push.

> [!WARNING]
> OpenAir 3.0 is a draft, and this tool is a development version.
> Rules and messages can change.

## Install

### Download a binary

Each [openair-lint release](https://github.com/naviter/seeyou_file_formats/releases?q=openair-lint&expanded=true)
has ready-to-run programs. You do not need Dart for them.

| System | File |
| --- | --- |
| Windows (x64) | `openair-lint-<version>-windows-x64.zip` |
| macOS (Apple silicon) | `openair-lint-<version>-macos-arm64.tar.gz` |
| macOS (Intel) | `openair-lint-<version>-macos-x64.tar.gz` |
| Linux (x64) | `openair-lint-<version>-linux-x64.tar.gz` |
| Linux (arm64) | `openair-lint-<version>-linux-arm64.tar.gz` |

Extract the archive and put `openair-lint` (or `openair-lint.exe`) in a
folder that is on your `PATH`. The file `SHA256SUMS.txt` in the release has
the SHA-256 checksum of each archive.

The programs are not signed yet. Your system can block a program that is
not signed:

- macOS: run `xattr -d com.apple.quarantine openair-lint` in the folder of
  the program. Then it starts normally.
- Windows: SmartScreen can show "Windows protected your PC". Click "More
  info" and then "Run anyway".

Or install openair-lint with Dart (see below).

The checksum shows that the download is complete and not damaged. To check
that the archive was built by the release workflow of this repository,
use the [GitHub CLI](https://cli.github.com/):

```
gh attestation verify openair-lint-<version>-linux-x64.tar.gz --repo naviter/seeyou_file_formats
```

### Install with Dart

You need the [Dart SDK](https://dart.dev/get-dart) 3.5 or newer.

```
dart pub global activate openair_lint
```

This works only after the package is published on pub.dev. Until then,
use a binary or run it from this folder.

Or run it from this folder without installing it:

```
dart pub get
dart run bin/openair_lint.dart <files>
```

## Usage

```
openair-lint [options] <files or directories>
```

Directories are searched for `*.openair` and `*.txt` files, also in
sub-directories. Hidden directories (for example `.git`) are skipped. Use `-`
to read from standard input. A file that you give by name is checked with
any extension, but the rule `file-extension-not-openair` reports an
extension other than `.openair` or `.txt`.

Examples:

```
openair-lint austria.openair
openair-lint airspace/
openair-lint --format json airspace/ > report.json
openair-lint --target 2.1 old_file.txt
openair-lint --disable coordinate-decimal-seconds airspace/
openair-lint --min-severity warning airspace/
openair-lint --explain header-version-missing
```

Output:

```
example.openair:3:4: error [ac-unknown-class] "Q" is an airspace type, not a class. Write "AC UNC" (or the real class) and "AY Q".
example.openair:5:8: error [altitude-unit-no-space] Write a space between the number and the unit: "1000 FT".
example.openair:9:1: warning [geometry-polygon-not-closed] The polygon is not closed. ...
Checked 1 file: 2 errors, 1 warning, 0 info.
```

### Options

| Option | Meaning |
| --- | --- |
| `--target 3.0\|2.1` | Check the files as this version. This overrides the `*VERSION:` header. |
| `--format text\|json\|github` | The output format. `github` prints GitHub Actions annotations. |
| `--disable <rule-id>` | Do not run this rule. You can use it more than once. |
| `--min-severity info\|warning\|error` | Do not show problems with a lower severity. |
| `--fail-on error\|warning` | Exit with code 1 if there is a problem with this severity or higher. The default is `error`. Problems that `--min-severity` hides are not counted. |
| `--list-rules` | Show all rules. With `--format json`, as JSON. |
| `--explain <rule-id>` | Explain one rule, with examples. With `--format json`, as JSON. |
| `--no-color` | Do not use colours. Colours are used only in a terminal. The environment variable `NO_COLOR` also turns them off. |
| `--version` | Show the version. |
| `--help` | Show the help. |

### Severities

| Severity | Meaning |
| --- | --- |
| `error` | The file breaks a rule with "must", "must not", "required" or "not allowed" in the specification. Readers can show the airspace in a wrong way, or not at all. |
| `warning` | The file breaks a rule with "should", "recommended", "avoid" or "expected" in the specification, or it has a problem that is very probably a mistake. |
| `info` | A hint about style, for example the recommended order of commands. |

Some rules do not follow this table:

- When the specification allows two values and recommends one of them,
  the other value is `info`, not `warning`. Example: an altitude in metres
  (`altitude-unit-metres`, "feet FT (recommended) or meters M").
- "Avoid using DA if possible" is in a note about `DA` arcs combined with
  `DP` points. That case is a warning (`da-combined-with-dp`). A `DA` arc in
  an airspace without `DP` points is `info` (`da-not-recommended`), because
  the problem of the note does not happen there.
- `header-version-draft` is `info`, although the specification says that
  writers "must not" write `*VERSION: 3.0` before the 3.0.0 release. As an
  error, it would also report every test file for the draft. The rule will
  be removed at the release.

### Spec version

The tool reads the version from the `*VERSION:` header of each file.

| Header | Checked as | Diagnostic |
| --- | --- | --- |
| `*VERSION: 3.0` | 3.0 | `header-version-draft` (info), while 3.0 is a draft |
| `*VERSION: 2.1` | 2.1 | |
| `*VERSION: 2.0` or older | 2.1 | `header-version-old` (info) |
| A version between 2.1 and 3.0, or newer than 3.0 | 2.1 or 3.0 | `header-version-unknown` (warning) |
| A value that is not a version number | 3.0 | `header-version-invalid` (error) |
| No `*VERSION:` header | 3.0 | `header-version-missing` (error) |

`--target 3.0` or `--target 2.1` overrides the header.

Differences between the versions:

- Weekday `AA` commands, `AA EXCEPT` and sun events (`SR`, `SS`, `BCMT`,
  `EECT`) are new in 3.0. In a 2.1 file they are errors
  (`aa-needs-version-3`).
- Version 3.0 requires upper case and a space between the number and the
  unit of an altitude (`1000 FT`). Version 2.1 allows `1000ft`.
- Version 2.1 requires that interval `AA` commands are sorted (error).
  In version 3.0 this is a recommendation (warning).
- Version 3.0 allows only some ISO 8601 forms in `AA` commands:
  `YYYY-MM-DD`, `hh:mmZ`, `hh:mm:ssZ`, `YYYY-MM-DDThh:mmZ`,
  `YYYY-MM-DDThh:mm:ssZ`, and intervals of the form
  `StartDateTime/EndDateTime`. Other forms (for example `20260704T0800Z` or
  a duration such as `PT8H`) are errors in 3.0 (`aa-value-form-not-allowed`,
  `aa-interval-form-not-allowed`). Version 2.1 did not limit the forms, so
  in a 2.1 file they are warnings (`aa-value-form-not-allowed-v21`,
  `aa-interval-form-not-allowed-v21`).
- Some rules are new in the 3.0 text. They are errors in a 3.0 file. In a
  2.1 file, openair-lint uses one policy:
  - When a 2.1 reader has the same problem with the data, the rule is a
    warning with the ID `<rule>-v21`. The message says that the problem is
    an error in version 3.0. These rules are: `an-contains-asterisk-v21`
    and `ag-contains-asterisk-v21` (readers cut the text at the `*`),
    `af-outside-air-band-v21`, `af-invalid-channel-v21`, `ax-not-octal-v21`
    (the value is not a channel or a transponder code),
    `dc-mixed-with-other-geometry-v21` and
    `airspace-attribute-duplicate-v21` (readers use the data in different
    ways), and `db-radius-mismatch-v21`.
  - When the 2.1 text allows the other form, or the other form has the same
    meaning for a reader, the rule does not check 2.1 files. These rules
    are: `case-not-upper-case` (2.1 allows lower case),
    `altitude-unit-no-space` (2.1 allows `1000ft`) and
    `af-not-three-decimals` (`AF 123.5` has the same meaning as
    `AF 123.500`).
- Rules that check a statement of the 2.1 text link to that text (tag
  `v2.1.5`), not to the current specification.

### Comments

A `*` starts a comment. The comment runs to the end of the line. This is
true on every line, also after a command:

```
AA MON-FRI 07:00Z/15:00Z   * every working day
```

For this reason, the text after `AN` and `AG` cannot contain `*`. A comment
is also not allowed on the same line as `AN` or `AG`. The rules
`an-contains-asterisk` and `ag-contains-asterisk` (errors) report every `*`
on these lines. For example, the name `AN TMA *TWR* 118.7` is only `TMA`.
Put the comment on its own line. In version 2.1 files, the rules
`an-contains-asterisk-v21` and `ag-contains-asterisk-v21` report the same
problem as a warning, because the 2.1 text has the same comment syntax.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | No errors. |
| 1 | At least one error (or warning, with `--fail-on warning`). |
| 2 | Wrong options, an unknown rule ID, a file that does not exist, a file that cannot be read, or the output cannot be written. |

If the program that reads the output stops early (for example
`openair-lint airspace/ | head`), openair-lint stops writing and prints no
error. It still checks all files, so the exit code is the same as with the
full output.

### Output formats

**text** (the default): one line per problem, and a summary line at the end.

```
<path>:<line>:<column>: <severity> [<rule-id>] <message>
```

Lines and columns start at 1. Paths always use `/`. Columns count UTF-16
code units, like most editors and the Language Server Protocol. A character
outside the Basic Multilingual Plane (for example an emoji) counts as 2.

Control characters in the messages (for example ESC) are shown in a
visible form, such as `\x1B`. A file cannot change the terminal.

**json**: one JSON object, for other tools.

```json
{
  "version": "3.0.0-dev.1",
  "files": [
    {
      "path": "example.openair",
      "specVersion": "3.0",
      "declaredVersion": "3.0",
      "diagnostics": [
        {
          "line": 3,
          "column": 4,
          "endColumn": 5,
          "severity": "error",
          "rule": "ac-unknown-class",
          "message": "\"Q\" is an airspace type, not a class. ...",
          "specUrl": "https://github.com/naviter/seeyou_file_formats/blob/main/OpenAir_File_Format_Support.md#ac-airspace-class"
        }
      ]
    }
  ],
  "summary": { "files": 1, "errors": 3, "warnings": 1, "info": 0 }
}
```

- `specVersion` is the version that the file was checked as.
  `declaredVersion` is the value of the `*VERSION:` header, or `null`.
- `endColumn` is the column after the last character of the problem.
  Columns count UTF-16 code units, like most editors.

**github**: [GitHub Actions workflow commands](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions).
GitHub shows each problem as an annotation on the file. Info problems are
notices.

```
::error file=example.openair,line=3,col=4,title=ac-unknown-class::"Q" is an airspace type, not a class. ...%0Ahttps://github.com/...#ac-airspace-class
```

### Speed

A test with real airspace files of about 60 countries (102 files, 37 MB,
1.3 million lines, 36,000 airspaces) takes about 5 seconds for the checks,
on a normal PC. Most of this time is the check of the coordinates. These
files give about 950,000 problems. Writing all of them as text takes more
time, depending on the terminal or the file system.

## GitHub Action

You can check the OpenAir files in your repository on every push and pull
request. Add this file to your repository as
`.github/workflows/openair.yml`:

```yaml
name: OpenAir

on: [push, pull_request]

permissions:
  contents: read

jobs:
  openair-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: naviter/seeyou_file_formats/openair-lint@openair-lint-v3.0.0
        with:
          paths: airspace/
```

The action downloads the openair-lint program from the release, checks its
SHA-256 checksum, and runs it with `--format github`. The checksum shows
that the download is complete. It comes from the same release as the
program, so it does not prove who built the program. See
[Download a binary](#download-a-binary) for `gh attestation verify`. GitHub shows each
problem as an annotation on the file and line. The step fails when a file
has an error (or a warning, with `fail-on: warning`).

Use a release tag after `@`, for example `@openair-lint-v3.0.0`. Then the
action always uses the same openair-lint version, and your check does not
change when a new version comes out.

### Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `paths` | (required) | The files and directories to check. Write one path per line, or separate the paths with spaces on one line. |
| `version` | the version of the tag | The openair-lint version, for example `3.0.0`. `latest` uses the newest openair-lint release. |
| `target` | (empty) | `3.0` or `2.1`. Check the files as this version. Empty: use the `*VERSION:` header. |
| `fail-on` | `error` | `error` or `warning`. The step fails when there is a problem with this severity or higher. |
| `min-severity` | `info` | `info`, `warning` or `error`. Do not show problems with a lower severity. |
| `disable` | (empty) | Rule IDs to turn off, separated by commas, spaces or new lines. |
| `repository` | `naviter/seeyou_file_formats` | The repository with the releases. Change it only for a fork. |
| `token` | `github.token` | Used only to find the newest release when `version` is `latest`. |

### Outputs

| Output | Meaning |
| --- | --- |
| `version` | The openair-lint version that the action used. |
| `path` | The full path of the openair-lint program. |

The action also adds openair-lint to the `PATH`. Later steps in the same job
can run `openair-lint` directly.

### Example with more options

```yaml
      - uses: naviter/seeyou_file_formats/openair-lint@openair-lint-v3.0.0
        with:
          paths: |
            airspace/austria.txt
            airspace/slovenia.txt
          target: '2.1'
          fail-on: warning
          disable: header-version-missing
```

### Notes

- The action works on GitHub-hosted Linux, macOS and Windows runners, with
  x64 and arm64 processors. On Windows arm64 it uses the x64 program.
  Self-hosted runners need `bash` and `curl`.
- Directories are searched for `*.openair` and `*.txt` files. Do not use
  `paths: .` if your repository has other `.txt` files.
- Use paths relative to the repository root. GitHub shows annotations only
  for these paths.
- GitHub shows only a limited number of annotations for each step (about 10
  of each type). The log of the step shows all problems. The job summary
  shows the number of problems.
- If you use the action from a branch (for example `@main`), set `version`
  to a released version. The version on a branch is often not released yet.

## Rules

See [RULES.md](RULES.md) for all rules, with examples.

## Use it as a Dart library

```dart
import 'package:openair_lint/openair_lint.dart';

void main() {
  const text = '*VERSION: 3.0\n*WRITTEN_BY: Example\nAC D\n...';
  final diagnostics = lintString(
    text,
    const LintOptions(
      target: SpecVersion.v3_0, // null: use the *VERSION header
      disabledRules: {'airspace-an-missing'},
      minSeverity: Severity.warning,
    ),
  );
  for (final d in diagnostics) {
    print('${d.line}:${d.column} ${d.severity.label} [${d.ruleId}] ${d.message}');
  }
}
```

- `lintString(String)` and `lintBytes(List<int>)` return the list of
  diagnostics. `lintBytes` also finds encoding problems (UTF-16, bytes that
  are not valid UTF-8).
- `Linter(options).lintBytes(bytes)` returns a `LintResult`. It also has the
  parsed file and the spec version that the file was checked as.
- Give the file name (`fileName:` in `Linter.lintBytes` and
  `Linter.lintString`) if you know it. Only the rule
  `file-extension-not-openair` uses it.
- The linter never throws, for any input. If a rule fails, the result has
  a `linter-internal-error` diagnostic.
- A full example is in [example/openair_lint_example.dart](example/openair_lint_example.dart).
- `allRules`, `ruleGroups` and `findRule(id)` give the rules and their
  metadata.

The library also contains the parser (`parseOpenAir`, `parseOpenAirBytes`),
the model (`OpenAirFile`, `Airspace`, `Command`), the `AA` parser and helpers
for coordinates and geometry. The parser is lenient: it never throws. It
does not use `dart:io`, so it also works on the web.

## Web validator

The folder [web](web) has the "OpenAir Validator" web page. It runs the same
rules as the command line tool, in the browser. People who do not use the
command line can check a file with it.

The release workflow publishes the page at
<https://naviter.github.io/seeyou_file_formats/>. The page exists there only
after the first release (see [Releasing](#releasing)).

- Open a file, drop a file on the page, or paste text.
- Choose the specification version: from the file header, 3.0 or 2.1.
- The page shows each problem with the line, the column, the rule (with a
  link to the specification) and the source line. You can filter by
  severity and by rule, and download the list as text.

The file stays on the computer. The page checks it in the browser and does
not upload it. The page makes no network requests, has no analytics and
loads no external fonts or scripts. A Content Security Policy in
`index.html` blocks all network connections.

Build the page:

```
dart run tool/build_web.dart
```

The tool compiles `web/main.dart` to JavaScript (`dart compile js -O2`)
and writes a static site to `build/web`: `index.html`, `style.css` and
`main.dart.js`. Options: `--output <folder>`, `-O3` or `-O4` (smaller and
faster, but with fewer runtime checks), `--source-maps`.

Test the page with any static web server, for example:

```
python -m http.server -d build/web 8080
```

Then open `http://localhost:8080` in the browser. You can also put the files of
`build/web` on any static web host, for example GitHub Pages.

How it works:

- The page lints in a web worker, so it stays responsive with large files.
  A 6 MB file with 370,000 problems takes about 1.5 seconds. The worker
  keeps the result. The page asks it for 200 problems at a time.
- Chrome does not allow web workers on a page that is opened from a local
  folder (`file://`). Then the page lints without a worker. It shows
  "Checking..." and is busy until the check ends.
- The page shows file content only as text, never as HTML, because the
  files are not trusted.
- The page reads the rules from the same registry as the command line
  tool. A new rule is on the page after the next build.

## Conformance files

The folder [openair-conformance](https://github.com/naviter/seeyou_file_formats/tree/main/openair-conformance)
has small valid and invalid OpenAir files with the expected results. Authors
of other OpenAir parsers can use them to test their software. The files do
not depend on Dart or on openair-lint.

- `valid/<group>/<case>.openair`: a correct file. A reader must accept it.
  openair-lint reports no error and no warning for it.
- `invalid/<group>/<case>.openair` and `<case>.expected`: a file with one
  or more problems. The `.expected` file lists the errors and warnings, one
  per line, as `<line> <rule-id>`. Info diagnostics are not listed.

The conformance files test only rules that the specification states. Rules
that only openair-lint has (for example `dp-duplicate-point` or
`aa-sun-event-fixed-start-near-day-start`) are tested with files of the same
format in `test/fixtures/<group>/`.

Each file starts with `*VERSION:` and `*WRITTEN_BY: openair-conformance`
(except some files of the `header` group, which test the header), and has a
`* Tests:` comment that says what it tests. The file
[README.md](https://github.com/naviter/seeyou_file_formats/tree/main/openair-conformance/README.md)
in the folder has the details.

## Development

```
dart pub get
dart format .
dart analyze --fatal-infos
dart test
dart run tool/generate_rules_doc.dart   # update RULES.md
dart run tool/corpus_stats.dart <dir>   # rule counts for a folder of files
```

The tests include:

- `test/conformance_test.dart`: runs all conformance files.
- `test/spec_examples_test.dart`: reads every code block of the
  specification, puts it into a small airspace and lints it. An example of
  the specification must not produce an error or a warning. The exceptions
  are listed in the test: examples that the specification marks as wrong,
  and the `DY` example, which gives the `dy-deprecated` warning because the
  specification does not recommend `DY`.
- `test/rule_examples_test.dart`: the correct example of each rule passes
  the rule, and the incorrect example is reported by the rule.
- `test/registry_test.dart`: rule IDs are unique, every rule has complete
  metadata, and every spec anchor exists.

The CI workflow also runs `tool/smoke_test.sh` (the compiled program on the
conformance files) and `tool/action_test.sh` (the step of the GitHub Action
that runs the program).

To test a compiled program:

```
dart compile exe bin/openair_lint.dart -o build/bin/openair-lint.exe
bash tool/smoke_test.sh build/bin/openair-lint.exe
```

The workflow [openair-lint-ci.yml](https://github.com/naviter/seeyou_file_formats/blob/main/.github/workflows/openair-lint-ci.yml)
runs all these checks on every push and pull request that changes the
linter, the conformance files or the specification.

## Releasing

The workflow [openair-lint-release.yml](https://github.com/naviter/seeyou_file_formats/blob/main/.github/workflows/openair-lint-release.yml)
makes the release. It starts when you push a tag `openair-lint-v<version>`.

> [!IMPORTANT]
> A linter release must never be the "latest" release of this repository.
> The main [README.md](https://github.com/naviter/seeyou_file_formats/blob/main/README.md) links to the specification PDFs with
> `releases/latest/download/<name>.pdf`. These links use the release that
> GitHub marks as "Latest". The workflow creates linter releases with
> `--latest=false`. Do not click "Set as the latest release" for a linter
> release. A specification release becomes "Latest" when you create it.

### One-time setup

1. GitHub Pages (for the web page):
   1. Open Settings > Pages. Set "Source" to "GitHub Actions".
   2. Open Settings > Environments > `github-pages`. Under "Deployment
      branches and tags", add the tag rule `openair-lint-v*`. Without this
      rule, GitHub does not allow the deploy from a tag.
   3. The web page is then at `https://naviter.github.io/seeyou_file_formats/`.
      The deploy replaces the whole GitHub Pages site of this repository.
2. Code signing (optional): add the signing secrets in Settings > Secrets and
   variables > Actions. The comment at the top of the release workflow lists
   the secret names. Without these secrets, the binaries are not signed.
3. pub.dev (optional):
   1. Publish the first version by hand with `dart pub publish`. Then, on
      pub.dev, move the package to the Naviter verified publisher. The
      pub.dev admin page of the package exists only after the first
      version.
   2. On pub.dev, open the package > Admin > Automated publishing. Enable
      "publishing from GitHub Actions". Repository:
      `naviter/seeyou_file_formats`. Tag pattern: `openair-lint-v{{version}}`.
      Enable "publishing from workflow_dispatch events". Set the environment
      to `pub.dev`.
   3. On GitHub, create the environment `pub.dev` (Settings > Environments)
      and add required reviewers.
   4. Add the repository variable `OPENAIR_LINT_PUB_DEV_PUBLISHING` with the
      value `true` (Settings > Secrets and variables > Actions > Variables).
      Without this variable, the workflow never publishes to pub.dev.

### Steps for each release

1. Choose the version. Use [semantic versioning](https://semver.org). A
   version with `-`, for example `3.0.0-dev.2`, becomes a GitHub
   pre-release.
2. Write the version in two places. They must be the same:
   - `version:` in `pubspec.yaml`
   - `packageVersion` in `lib/src/version.dart`
3. Add a section `## <version>` to `CHANGELOG.md`. The workflow copies this
   section into the release notes.
4. Update the version in the examples in this README (for example
   `@openair-lint-v3.0.0` in the GitHub Action section).
5. Run the checks in this folder:
   ```
   dart format .
   dart analyze --fatal-infos
   dart test
   dart run tool/generate_rules_doc.dart
   dart pub publish --dry-run
   ```
6. Commit the changes and merge them into `main` with a pull request. Wait
   until the CI workflow is green.
7. Create the tag on `main` and push it:
   ```
   git checkout main
   git pull
   git tag openair-lint-v3.0.0
   git push origin openair-lint-v3.0.0
   ```
8. Open the Actions tab and watch the "openair-lint release" workflow. It:
   - checks that the tag, `pubspec.yaml`, `lib/src/version.dart` and
     `CHANGELOG.md` have the same version,
   - runs the tests,
   - builds and tests the program on Windows, macOS and Linux,
   - creates the GitHub release with the 5 archives and `SHA256SUMS.txt`,
   - deploys the web page to GitHub Pages.
9. Check the result:
   - The new release is not marked "Latest".
   - The PDF link still works:
     https://github.com/naviter/seeyou_file_formats/releases/latest/download/OpenAir_File_Format_Support.pdf
   - The web page shows the new version.
10. Publish to pub.dev (optional). This cannot be undone: a version on
    pub.dev can never be deleted.
    - With the workflow: open Actions > "openair-lint release" > "Run
      workflow". In "Use workflow from", select the tag (for example
      `openair-lint-v3.0.0`). Tick "Publish the package to pub.dev" and run
      it.
    - Or by hand, in this folder, on the tag: `dart pub publish`.

### If the release fails

- If a build step fails because of the runner (for example a network
  problem), open the workflow run and click "Re-run failed jobs". The
  release job uploads the files again if the release exists.
- If the code or the version is wrong, fix it on `main`, then delete the tag
  and create it again:
  ```
  git push --delete origin openair-lint-v3.0.0
  git tag -d openair-lint-v3.0.0
  ```
  If the workflow already created the GitHub release, delete the release on
  GitHub first.

## License

MIT License. See [LICENSE](LICENSE).
