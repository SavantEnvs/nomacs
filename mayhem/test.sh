#!/usr/bin/env bash
#
# mayhem/test.sh — runs the nomacs gtest suite (tests_core) and a known-answer probe, both already built
# by mayhem/build.sh, and reports CTRF counts. The probe decodes committed fixtures through the
# dynamically linked libnomacsCore.so and prints pixel values and metadata, which are compared with the
# values below, so a wrong decoder, a stubbed library, or a binary that exits 0 without running fails.
# A missing binary or fixture is a failure, never a skip.
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

export QT_QPA_PLATFORM=offscreen
export QT_PLUGIN_PATH="$SRC/build-tests/nomacs-plugins"
export LD_LIBRARY_PATH="$SRC/build-tests${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export HOME="${TMPDIR:-/tmp}/nomacs-test-home"
mkdir -p "$HOME"

passed=0 failed=0 skipped=0

# --- 1) upstream gtest suite -------------------------------------------------------------------
TESTS="$SRC/build-tests/tests/unit/tests_core"
if [ ! -x "$TESTS" ]; then
  echo "FAIL: $TESTS missing (mayhem/build.sh builds it)" >&2
  failed=$((failed + 1))
else
  out="$("$TESTS" 2>&1)"; rc=$?
  printf '%s\n' "$out" | tail -n 8
  p="$(printf '%s\n' "$out" | sed -n 's/^\[  PASSED  \] \([0-9][0-9]*\) test.*/\1/p' | tail -n 1)"
  f="$(printf '%s\n' "$out" | sed -n 's/^\[  FAILED  \] \([0-9][0-9]*\) test.*/\1/p' | tail -n 1)"
  s="$(printf '%s\n' "$out" | sed -n 's/^\[  SKIPPED \] \([0-9][0-9]*\) test.*/\1/p' | tail -n 1)"
  ran="$(printf '%s\n' "$out" | sed -n 's/^\[==========\] \([0-9][0-9]*\) tests\? from .* ran\..*/\1/p' | tail -n 1)"
  p="${p:-0}"; f="${f:-0}"; s="${s:-0}"
  if [ -z "$ran" ] || [ "$p" -eq 0 ] || [ "$rc" -ne 0 -a "$f" -eq 0 ]; then
    echo "FAIL: tests_core produced no pass summary (rc=$rc)" >&2
    f=$((f + 1))
  fi
  passed=$((passed + p)); failed=$((failed + f)); skipped=$((skipped + s))
fi

# --- 2) known-answer probe -----------------------------------------------------------------------
# Fixtures: rgb24.tga / rgb8.tif encode pixel (x,y) = (60x+10, 60y+20, 30(x+y)+5) on a 4x4 grid;
# exif.jpg carries Exif Orientation=6 (rotate 90) and ImageDescription "nomacs-kat".
KAT="$SRC/build-tests/kat_probe"
FIX="$SRC/mayhem/kat/fixtures"
EXPECTED='tga size=4x4
tga pixel(0,0)=10,20,5
tga pixel(3,0)=190,20,95
tga pixel(1,2)=70,140,95
tga pixel(3,3)=190,200,185
tif size=4x4
tif pixel(0,0)=10,20,5
tif pixel(3,0)=190,20,95
tif pixel(1,2)=70,140,95
tif pixel(3,3)=190,200,185
meta has=1
meta orientation=90
meta description=nomacs-kat'
if [ ! -x "$KAT" ] || [ ! -d "$FIX" ]; then
  echo "FAIL: $KAT or $FIX missing" >&2
  failed=$((failed + 1))
else
  got="$("$KAT" "$FIX" 2>/dev/null)"
  while IFS= read -r line; do
    if printf '%s\n' "$got" | grep -qxF -- "$line"; then
      passed=$((passed + 1))
    else
      echo "KAT MISMATCH: expected '$line'" >&2
      failed=$((failed + 1))
    fi
  done <<<"$EXPECTED"
fi

emit_ctrf "gtest+kat" "$passed" "$failed" "$skipped"
