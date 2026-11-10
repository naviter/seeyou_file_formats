# OpenAir conformance files

These files test software that reads or checks OpenAir files. They follow the
[OpenAir 3.0 file format specification](../OpenAir_File_Format_Support.md).
They do not depend on a programming language. You can use them to test your
own parser or validator.

The [openair-lint](../openair-lint) tool runs all these files in its tests.

## Folders

```
valid/<group>/<case>.openair
invalid/<group>/<case>.openair
invalid/<group>/<case>.expected
```

The groups are `header`, `attributes`, `altitude`, `activation` and
`geometry`.

### Valid files

A file in `valid/` follows the specification. A correct validator reports no
error and no warning for it. It can report info diagnostics.

### Invalid files

A file in `invalid/` has one or more problems. The `.expected` file next to it
lists every error and warning that a validator must report. It has one line
for each problem:

```
<line> <rule-id>
```

For example:

```
1 header-version-missing
```

- `<line>` is the line number in the `.openair` file. The first line is 1.
- `<rule-id>` is the ID of the openair-lint rule. See
  [RULES.md](../openair-lint/RULES.md) for all rules.
- Info diagnostics are not listed.
- Empty lines and lines that start with `#` are ignored.
- The order of the lines does not matter.

If your validator uses other rule IDs, compare only the line numbers, or map
the IDs to your own.

## How each file looks

Each file:

1. starts with the header `*VERSION: 3.0` (or `*VERSION: 2.1` for a case that
   tests version 2.1) and `*WRITTEN_BY: openair-conformance`,
2. has a comment line `* Tests: ...` that says what the case tests,
3. is small and tests one thing.

Files in the `header` group can break rule 1, because they test the header.

All files use UTF-8 and LF line endings, unless the case tests the encoding or
the line endings.

## What the files cover

The files test only rules that the specification states. Each case follows
one sentence or one table of the specification.

Covered:

- **Header and general requirements:** `*VERSION` and `*WRITTEN_BY`, UTF-8,
  line endings, upper case, unknown commands, and comments. `*` always starts
  a comment, so `AN` and `AG` cannot contain `*`, and a comment is not
  allowed on the same line as `AN` or `AG`.
- **Airspace structure:** every airspace starts with `AC`, has `AN`, `AH`,
  `AL` and a geometry (`V` alone is not a geometry). An airspace has at most
  one `AC`, `AN`, `AY`, `AG`, `AX`, `AH` and `AL`. `AF` can be used more than
  once. In version 2.1 `AN` is optional.
- **Attributes:** the classes of `AC`, the types of `AY`, and `AX` with
  exactly 4 octal digits. `AF` with exactly three decimals and no unit, in
  the VHF air band (118.000 to 136.990), as a 25 kHz or 8.33 kHz channel
  name and not as the exact radio frequency.
- **Altitude:** the unit and the reference are required, `FL`, `GND` and
  `UNL`, `MSL` as an alias of `AMSL`, `FL 95` with a space, `9500 FT STD` as
  the same altitude as `FL95`, and the lower limit below the upper limit.
- **Activation times (`AA`):** only the allowed ISO 8601 forms (also times
  with seconds), intervals, `NONE`, weekday commands, `AA EXCEPT`, 24:00Z as
  an end time only, and sun events. The specification says that the weekday
  and the date of a sun window mean the local day at the airspace. The sun
  event cases use local solar time for the local day. They test the polar
  rule of the specification for `SR/SS` and `SS/SR`, and the night from
  sunset to sunrise of the next day.
- **Geometry:** DMS and DDM coordinates (also with one space before the
  letter `N`, `S`, `E` or `W`), polygons, a boundary that crosses itself and
  a boundary that only touches itself (for example a ring-shaped airspace),
  `DA`, `DB` (both points at the same distance from the centre), `DC` as the
  only geometry of its airspace, `DY`, and `V` (the values are reset at every
  `AC`).
- **Version 2.1:** some cases use `*VERSION: 2.1`. They test what is
  different in version 2.1, for example that weekday commands, `AA EXCEPT`
  and sun events are new in version 3.0. The 2.1 text has the same comment
  syntax, so a `*` in `AN` or `AG` also cuts the text in a 2.1 file (a
  warning in openair-lint).

Not covered:

- Checks that the specification does not state. openair-lint reports them as
  warnings or info, but another validator does not have to report them. For
  example: emergency transponder codes (`7500`, `7600`, `7700`), a station
  name that is a frequency, an altitude that is not plausible, two airspaces
  that are the same, two `AA` commands that are the same, an `AA EXCEPT` that
  removes nothing, a weekday command that is never active, a fixed time that
  is very close to a sun event or to the start of the local day, a sun event
  near longitude 180°, the same point two times in a row, `V W=` without
  `DY`, `AL 0 FT AGL` in place of `AL GND`, and text that was garbled by a
  wrong encoding. openair-lint tests these checks with its own files in
  `openair-lint/test/fixtures`.
- Rules that openair-lint adds for version 2.1 files when the 3.0 text
  states the rule but the 2.1 text does not (for example
  `ax-not-octal-v21`).
- The file name extension (`.openair` or `.txt`). A conformance case is a
  file with the extension `.openair`.
- Info diagnostics. The `.expected` files list only errors and warnings.

## License

MIT License. See [LICENSE](../LICENSE).
