# Changelog

## 3.0.0-dev.1

The first development version. OpenAir 3.0 is still a draft, so rules and
messages can change.

- 144 rules in 5 groups. See
  [RULES.md](https://github.com/naviter/seeyou_file_formats/blob/main/openair-lint/RULES.md).
  - `header`: the encoding, the `*VERSION:` and `*WRITTEN_BY:` header, upper
    case, unknown commands and the structure of the airspace blocks.
  - `attributes`: `AC`, `AY`, `AN`, `AF`, `AG` and `AX`.
  - `altitude`: `AH` and `AL`.
  - `activation`: `AA` intervals, weekday commands, `AA EXCEPT`, `AA NONE`
    and the sun events `SR`, `SS`, `BCMT` and `EECT`.
  - `geometry`: coordinates, `DP`, `DA`, `DB`, `DC`, `DY` and `V`, and
    checks of the whole boundary (closed, clockwise, crossings).
- Each file is checked as the version in its `*VERSION:` header (2.1 or
  3.0). The option `--target` overrides the header.
- The command line tool `openair-lint`, with the output formats `text`,
  `json` and `github` (GitHub Actions annotations), and the options
  `--disable`, `--min-severity`, `--fail-on`, `--list-rules` and
  `--explain`.
- Binaries for Windows, macOS and Linux in the GitHub release, with a
  `SHA256SUMS.txt` file.
- A GitHub Action that downloads the binary and checks the files of a
  repository.
- The "OpenAir Validator" web page. It runs the same rules in the browser.
  The file is not uploaded.
- The Dart library: `lintString`, `lintBytes`, the parser and the model, so
  that other Dart programs can read OpenAir files.
- Conformance files in `openair-conformance/`: small valid and invalid
  files with the expected results, for authors of other OpenAir parsers.
