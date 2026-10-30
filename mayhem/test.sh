#!/usr/bin/env bash
#
# mayhem/test.sh — RUN wxWidgets' own Catch2 unit suite (wxBase tests, built by mayhem/build.sh with the
# project's normal flags in mayhem/build-test). Its ~850 test cases assert wxWidgets' behavior (string,
# datetime, archive, config, stream, regex, ... known-answer checks). The image has no en_US locale, so the
# locale-dependent cases are excluded; nothing else is.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TESTDIR="$SRC/mayhem/build-test/tests"
[ -x "$TESTDIR/test" ] || { echo "mayhem/test.sh: $TESTDIR/test missing — mayhem/build.sh must build it" >&2; exit 2; }
cd "$TESTDIR"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
# Locale-dependent cases (they need en_US/fr_FR locales, absent from the image) are excluded. Catch2's
# ~exclusion syntax only honors one name per spec (and would also pull in hidden [.] tests), so the
# run list is spelled out as an explicit comma-separated include list of every other visible test case.
EXCLUDE='^(FormatNumberTestCase::.*|wxLocale::Default|wxUILocale::GetInfo)$'
SPEC="$(./test --list-test-names-only '~[.]' | grep -v '^$' | grep -Ev "$EXCLUDE" | paste -sd, -)"
[ -n "$SPEC" ] || { echo "mayhem/test.sh: could not list test cases" >&2; exit 2; }
./test "$SPEC" >"$LOG" 2>&1
rc=$?
tail -n 25 "$LOG"

if grep -q '^All tests passed' "$LOG"; then
  p="$(sed -n 's/.*All tests passed (.* assertions\? in \([0-9]*\) test cases\?).*/\1/p' "$LOG" | tail -1)"
  emit_ctrf "catch2" "${p:-0}" 0 0
  exit $?
fi
line="$(grep -E '^test cases:' "$LOG" | tail -1)"
if [ -n "$line" ]; then
  p="$(printf '%s' "$line" | sed -n 's/.*|[[:space:]]*\([0-9]*\) passed.*/\1/p')"
  f="$(printf '%s' "$line" | sed -n 's/.*|[[:space:]]*\([0-9]*\) failed.*/\1/p')"
  s="$(printf '%s' "$line" | sed -n 's/.*|[[:space:]]*\([0-9]*\) skipped.*/\1/p')"
  emit_ctrf "catch2" "${p:-0}" "${f:-0}" "${s:-0}"
  exit $?
fi
# no summary line: the runner crashed or printed nothing parseable
emit_ctrf "catch2" 0 1 0
