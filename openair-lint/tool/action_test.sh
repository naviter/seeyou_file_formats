#!/usr/bin/env bash
# Test for the "Run openair-lint" step of the GitHub Action (action.yml).
#
# The CI workflow runs this script after "dart compile exe". You can also run
# it on your computer (Git Bash on Windows works too).
#
# Usage (from the openair-lint folder):
#   tool/action_test.sh <path to the binary>
#
# The script takes the shell code of the step "Run openair-lint" from
# action.yml and runs it with a local binary, in the same way as GitHub does:
# with the INPUT_* environment variables, GITHUB_WORKSPACE, RUNNER_TEMP and
# GITHUB_STEP_SUMMARY. The step "Install openair-lint" needs a GitHub
# release, so this script does not test it.
#
# The script checks the paths input (several lines, CR, blanks, "./", an
# absolute path), the disable input, fail-on and an empty paths input.

set -u

if [ $# -lt 1 ]; then
  echo "Usage: tool/action_test.sh <path to the binary>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$PACKAGE/.." && pwd)"
BIN="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The shell code of the step: the lines after "run: |" of the step
# "Run openair-lint", without the indentation of the YAML block.
awk '
  /^    - name: Run openair-lint[[:space:]]*$/ { step = 1; next }
  step && /^    - name:/ { exit }
  step && /^      run: \|[[:space:]]*$/ { code = 1; next }
  code {
    sub(/\r$/, "")
    if ($0 ~ /^        /) { print substr($0, 9) }
    else if ($0 ~ /^[[:space:]]*$/) { print "" }
    else { exit }
  }
' "$PACKAGE/action.yml" > "$TMP/step.sh"

if ! grep -q 'OPENAIR_LINT' "$TMP/step.sh"; then
  echo "Cannot find the step \"Run openair-lint\" in action.yml." >&2
  exit 2
fi

# Runs the step in the repository root, like GitHub does. The arguments are
# the inputs: paths, fail-on, disable. Sets $out and $code.
run_step() {
  local summary="$TMP/summary.md"
  : > "$summary"
  out="$(cd "$ROOT" && \
    OPENAIR_LINT="$BIN" \
    INPUT_PATHS="$1" \
    INPUT_TARGET="" \
    INPUT_FAIL_ON="${2:-error}" \
    INPUT_MIN_SEVERITY="info" \
    INPUT_DISABLE="${3:-}" \
    GITHUB_WORKSPACE="$ROOT" \
    RUNNER_TEMP="$TMP" \
    GITHUB_STEP_SUMMARY="$summary" \
    bash "$TMP/step.sh" 2>&1)"
  code=$?
  step_summary="$(cat "$summary")"
}

VALID="openair-conformance/valid/header"
INVALID="openair-conformance/invalid/header/version-missing.openair"

# 1. A valid folder: exit 0, a job summary.
run_step "$VALID"
if [ $code -eq 0 ] && [[ "$step_summary" == *"Checked "* ]]; then
  pass "a valid folder gives exit code 0 and a job summary."
else
  fail "a valid folder: exit code $code, summary \"$step_summary\". Output: $out"
fi

# 2. An invalid file: exit 1 and an annotation with a relative path.
run_step "$INVALID"
if [ $code -eq 1 ] && [[ "$out" == *"::error file=$INVALID,"* ]]; then
  pass "an invalid file gives exit code 1 and an annotation."
else
  fail "an invalid file: exit code $code. Output: $out"
fi

# 3. Several lines with CR and blanks, "./" and an absolute path.
run_step "$(printf '  ./%s\r\n\r\n%s/%s  \r\n' "$VALID" "$ROOT" "$INVALID")"
if [ $code -eq 1 ] && [[ "$out" == *"::error file=$INVALID,"* ]] \
  && [[ "$out" == *"Checked "* ]]; then
  pass "paths on several lines, with CR, blanks, \"./\" and an absolute path."
else
  fail "paths on several lines: exit code $code. Output: $out"
fi

# 4. disable with commas, blanks and new lines.
run_step "$INVALID" error "$(printf 'header-version-missing, airspace-an-missing\nfile-bom')"
if [[ "$out" != *"title=header-version-missing"* ]] && [ $code -ne 2 ]; then
  pass "the disable input turns rules off."
else
  fail "disable: exit code $code. Output: $out"
fi

# 5. fail-on with blanks. The valid files have info diagnostics only, so
# they pass also with "warning".
run_step "$VALID" " warning "
if [ $code -eq 0 ]; then
  pass "fail-on \" warning \" works."
else
  fail "fail-on \" warning \": exit code $code. Output: $out"
fi

# 6. An empty paths input: exit 2.
run_step "   "
if [ $code -eq 2 ] && [[ "$out" == *'"paths" input is empty'* ]]; then
  pass "an empty paths input gives exit code 2."
else
  fail "empty paths: exit code $code. Output: $out"
fi

if [ $FAILED -ne 0 ]; then
  echo "The action test failed." >&2
  exit 1
fi
echo "The action test passed."
