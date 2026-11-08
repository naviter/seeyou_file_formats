#!/usr/bin/env bash
# Smoke test for a compiled openair-lint binary.
#
# The CI and release workflows run this script after "dart compile exe".
# You can also run it on your computer (Git Bash on Windows works too).
#
# Usage (from the openair-lint folder):
#   tool/smoke_test.sh <path to the binary> [<expected version>]
#
# The script checks that:
#   - "--version" prints the expected version,
#   - "--help" and "--list-rules" work,
#   - every file in openair-conformance/valid has no error and no warning,
#   - the files in openair-conformance/invalid give exit code 1,
#   - the JSON and GitHub output formats work,
#   - a missing file gives exit code 2.

set -u

if [ $# -lt 1 ]; then
  echo "Usage: tool/smoke_test.sh <path to the binary> [<expected version>]" >&2
  exit 2
fi

BIN="$1"
EXPECTED_VERSION="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFORMANCE="$SCRIPT_DIR/../../openair-conformance"
FAILED=0

fail() {
  echo "FAIL: $*" >&2
  FAILED=1
}

pass() {
  echo "ok: $*"
}

if [ ! -f "$BIN" ]; then
  echo "The binary \"$BIN\" does not exist." >&2
  exit 2
fi

# 1. --version
out="$("$BIN" --version)"
code=$?
if [ $code -ne 0 ]; then
  fail "--version exited with code $code."
elif [ -n "$EXPECTED_VERSION" ] && [ "$out" != "openair-lint $EXPECTED_VERSION" ]; then
  fail "--version printed \"$out\". Expected \"openair-lint $EXPECTED_VERSION\"."
else
  pass "--version prints \"$out\"."
fi

# 2. --help and --list-rules
if "$BIN" --help > /dev/null; then
  pass "--help works."
else
  fail "--help exited with code $?."
fi
if "$BIN" --list-rules > /dev/null; then
  pass "--list-rules works."
else
  fail "--list-rules exited with code $?."
fi

# 3. Valid conformance files: no errors and no warnings.
out="$("$BIN" --no-color --fail-on warning "$CONFORMANCE/valid")"
code=$?
if [ $code -ne 0 ]; then
  echo "$out"
  fail "The valid conformance files gave exit code $code. Expected 0."
else
  pass "Valid conformance files: $(echo "$out" | tail -n 1)"
fi

# 4. Invalid conformance files: exit code 1.
out="$("$BIN" --no-color "$CONFORMANCE/invalid")"
code=$?
if [ $code -ne 1 ]; then
  echo "$out"
  fail "The invalid conformance files gave exit code $code. Expected 1."
else
  pass "Invalid conformance files: $(echo "$out" | tail -n 1)"
fi

# 5. JSON format.
out="$("$BIN" --format json "$CONFORMANCE/invalid")"
code=$?
case "$out" in
  "{"*'"summary"'*"}")
    if [ $code -eq 1 ]; then
      pass "--format json works."
    else
      fail "--format json gave exit code $code. Expected 1."
    fi
    ;;
  *)
    echo "$out"
    fail "--format json did not print a JSON object with a summary."
    ;;
esac

# 6. GitHub format.
out="$("$BIN" --format github "$CONFORMANCE/invalid")"
code=$?
if [ $code -eq 1 ] && echo "$out" | grep -q '^::error file='; then
  pass "--format github works."
else
  echo "$out"
  fail "--format github did not print an error annotation (exit code $code)."
fi

# 7. A file that does not exist: exit code 2.
"$BIN" "$CONFORMANCE/this-file-does-not-exist.openair" > /dev/null 2>&1
code=$?
if [ $code -eq 2 ]; then
  pass "A missing file gives exit code 2."
else
  fail "A missing file gave exit code $code. Expected 2."
fi

if [ $FAILED -ne 0 ]; then
  echo "The smoke test failed." >&2
  exit 1
fi
echo "The smoke test passed."
