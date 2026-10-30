#!/usr/bin/env bash
#
# mayhem/build.sh — build wxBase (sanitized) + the tests/fuzz harnesses, and an unsanitized wxBase +
# the Catch2 unit-test runner used by mayhem/test.sh. Both builds are out of tree under mayhem/build-*
# (gitignored via mayhem/.gitignore) so `git clean -ffdX` removes them and a re-run reconfigures cleanly.
# Everything is built from the checkout (bundled zlib/expat/pcre + Catch submodules): no network.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
FUZZ_BUILD="$SRC/mayhem/build-fuzz"
TEST_BUILD="$SRC/mayhem/build-test"
HARNESSES="zip tar fileconf datetime"
BIN="$SRC/mayhem/bin"

# ---- 1) sanitized wxBase (the fuzzed code) ---------------------------------------------------------
rm -rf "$FUZZ_BUILD" "$BIN" && mkdir -p "$FUZZ_BUILD" "$BIN"
cd "$FUZZ_BUILD"
# LSan would abort configure's conftest programs on their (irrelevant) leaks; only configure sees this.
ASAN_OPTIONS=detect_leaks=0 "$SRC/configure" --without-subdirs --disable-tests --disable-shared \
    --disable-sys-libs --disable-gui \
    CC="$CC" CXX="$CXX" \
    CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" CXXFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
    LDFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS"
make -j"$MAYHEM_JOBS"

# ---- 2) harnesses: fuzzer + standalone reproducer (the project's own tests/fuzz/runner.cpp) ----------
HFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS"
WXCXX="$("$FUZZ_BUILD/wx-config" --cxxflags)"
WXLIBS="$("$FUZZ_BUILD/wx-config" --libs base)"
$CXX $HFLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$FUZZ_BUILD/lsan_off.o"
$CXX $HFLAGS $WXCXX -c "$SRC/tests/fuzz/runner.cpp" -o "$FUZZ_BUILD/runner.o"
for h in $HARNESSES; do
  $CXX $HFLAGS $WXCXX -c "$SRC/tests/fuzz/$h.cpp" -o "$FUZZ_BUILD/$h.o"
  $CXX $HFLAGS $LIB_FUZZING_ENGINE "$FUZZ_BUILD/$h.o" "$FUZZ_BUILD/lsan_off.o" $WXLIBS -o "$BIN/fuzz_$h"
  $CXX $HFLAGS "$FUZZ_BUILD/$h.o" "$FUZZ_BUILD/runner.o" "$FUZZ_BUILD/lsan_off.o" $WXLIBS -o "$BIN/fuzz_$h-standalone"
done

# ---- 3) the project's own Catch2 suite, NORMAL flags, independent build ----------------------------
rm -rf "$TEST_BUILD" && mkdir -p "$TEST_BUILD"
cd "$TEST_BUILD"
(env -u CFLAGS -u CXXFLAGS -u LDFLAGS "$SRC/configure" --disable-shared --disable-sys-libs --disable-gui \
    CC="$CC" CXX="$CXX" CFLAGS="$COVERAGE_FLAGS" CXXFLAGS="$COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS")
make -j"$MAYHEM_JOBS"
make -C tests -j"$MAYHEM_JOBS" test data data-image-sample data-images en_GB fr ja xart-dothraki
