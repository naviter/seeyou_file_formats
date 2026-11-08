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

## License

MIT License. See [LICENSE](../LICENSE).
