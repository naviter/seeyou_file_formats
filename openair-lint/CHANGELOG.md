# Changelog

## Unreleased

The linter follows the revised specification of 2026-11-08. The linter now
has 155 rules.

Removed rules:

- `coordinate-space-before-hemisphere`. One space between the number and
  the letter `N`, `S`, `E` or `W` is valid now. Two or more blanks or a tab
  before the letter are reported by `coordinate-space-between-parts`.
- `an-name-cut-by-comment` and `ag-station-cut-by-comment`. They are
  replaced by `an-contains-asterisk` and `ag-contains-asterisk` (version
  3.0) and `an-contains-asterisk-v21` and `ag-contains-asterisk-v21`
  (version 2.1).
- `aa-value-not-recommended-form` and `aa-interval-not-recommended-form`.
  They are replaced by the `...-form-not-allowed` rules below.
- `aa-sun-event-start-crosses-midnight`. A window with a sun event now uses
  the local solar day, so its start cannot move to another day.

New rules:

- `an-contains-asterisk` and `ag-contains-asterisk` (error, 3.0): `AN` and
  `AG` cannot contain `*`, and a comment is not allowed on these lines.
- `altitude-msl-alias` (warning): `MSL` is an alias of `AMSL`. Readers read
  it as `AMSL`. Writers should write `AMSL`.
- `aa-value-form-not-allowed` and `aa-interval-form-not-allowed` (error,
  3.0): only the date, time and interval forms in the specification are
  allowed. In version 2.1 files the same forms are warnings
  (`aa-value-form-not-allowed-v21`, `aa-interval-form-not-allowed-v21`).
- `aa-sun-event-fixed-start-near-day-start` (warning): a fixed start time
  very close to the start of the local solar day. A small difference in the
  position of the airspace can move the window by one day.
- `aa-sun-event-near-date-line` (warning): a window with a sun event in an
  airspace whose centre is less than 0.5° from longitude 180°. There the
  local solar day changes by 24 hours.
- `db-radius-mismatch-v21` (warning, 2.1): the 2.1 part of
  `db-radius-mismatch`.
- `an-contains-asterisk-v21`, `ag-contains-asterisk-v21`,
  `airspace-attribute-duplicate-v21`, `ax-not-octal-v21`,
  `af-outside-air-band-v21`, `af-invalid-channel-v21` and
  `dc-mixed-with-other-geometry-v21` (warning, 2.1): the 2.1 part of the
  rules without `-v21`. See "Spec version" in the README.

Changed severities:

- Warning to error: `airspace-attribute-duplicate`, `ax-not-octal`,
  `af-outside-air-band`, `af-invalid-channel` and
  `dc-mixed-with-other-geometry`. These rules check only version 3.0 files
  now. Version 2.1 files get the warning with the same ID and `-v21`.
- `af-not-three-decimals`: info to error. It checks only version 3.0 files,
  because version 2.1 did not define the number of decimals.
- `db-radius-mismatch`: warning to error. It checks only version 3.0 files.
  Version 2.1 files get the warning `db-radius-mismatch-v21`.
- `aa-invalid-duration` checks only version 2.1 files. In version 3.0 every
  duration is reported by `aa-interval-form-not-allowed`.

Other changes:

- Times with seconds (`hh:mm:ssZ`, `YYYY-MM-DDThh:mm:ssZ`, `24:00:00Z`) are
  allowed.
- Sun events use local solar time. The weekdays, the date range and the
  `AA EXCEPT` dates of a window with a sun event refer to the local solar
  day. In polar regions the rules of the specification table are used.
  `aa-sun-event-order-changes`, `aa-sun-event-near-fixed-time`,
  `aa-sun-event-missing-day` and `aa-weekday-never-active` use this model.
- `airspace-attribute-duplicate` does not report a second `AF`. An airspace
  can have more than one `AF`.
- `MSL` is read as `AMSL`, so it is compared with `AMSL` limits. `FL 95` is
  compared like `FL95`, and `9500 FT STD` is compared with flight levels.
  `altitude-lower-not-below-upper` compares only limits with the same kind
  of reference.
- `geometry-polygon-self-intersection`: a boundary that touches itself is
  not reported, for example a ring-shaped airspace with a connecting line
  that is used twice. A boundary that crosses itself at a point that it
  passes twice is reported.
- `geometry-center-missing` and `dy-width-missing` say that the `V` values
  are reset at every `AC`.
- Links to the specification use the new headings, for example
  `#general-requirements`, `#command-reference` and
  `#ah-upper-altitude-limit`.
- The conformance files follow the revised specification. The README of
  `openair-conformance` lists what the files cover. Cases for rules that
  only openair-lint has (for example `dp-duplicate-point`,
  `v-width-without-airway`, `altitude-zero-agl`,
  `aa-sun-event-fixed-start-near-day-start` and a polar
  `aa-weekday-never-active`) are now in `test/fixtures`.
- A negative flight level (`FL-5`) is an error
  (`altitude-flight-level-invalid`), not a warning.
- `aa-sun-event-near-fixed-time` uses 5 minutes, not 2 minutes. The
  specification says that methods can differ by a few minutes.
- A night window (`SS/SR`, `EECT/BCMT`) is active when the evening event
  happens and the morning event of the same day does not. It ends at the
  morning event of the next day. Before, such a day was "not active".
- At the start of the polar night, sunrise and sunset now agree: if one of
  them does not happen, the other does not happen either.
- `aa-sun-event-missing-day` groups the days by the events that do not
  happen.
- The sun event rules do not check version 2.1 files.
  `aa-needs-version-3` already reports these commands.
- `case-not-upper-case` does not report the text in an `AF` or `AX` value
  that `af-invalid-format` or `ax-not-four-digits` already reports.
- `altitude-flight-level-space` links to "Supported Altitude References".
- Some messages now say how to fix the problem
  (`aa-sun-event-order-changes`, `aa-sun-event-fixed-start-near-day-start`,
  `af-invalid-format` for two frequencies, a week date in an interval).

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
