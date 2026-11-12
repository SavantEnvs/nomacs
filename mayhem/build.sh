#!/usr/bin/env bash
#
# mayhem/build.sh — builds nomacs (Image Lounge, Qt6) as a sanitized libnomacsCore.so plus the fuzz
# harnesses (and -standalone reproducers) linked against it, and, separately with the project's NORMAL
# flags, the gtest suite and the known-answer probe that mayhem/test.sh runs.
# Every dependency (Qt6, Exiv2, OpenCV, LibRaw, libtiff, GoogleTest) is an apt -dev package baked into
# the image, so a re-run needs no network. Build trees: build-fuzz/ and build-tests/ (gitignored).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
IL="$SRC/ImageLounge"
HARNESS="$SRC/mayhem/harness"

# ---- 1) the project itself, sanitized + SanCov-instrumented, DWARF 3 --------------------------------
# -fsanitize=fuzzer-no-link adds the coverage instrumentation to the library even when
# $SANITIZER_FLAGS is empty. Plugins/translations/tests are not needed by the harnesses.
# The compiler comes from the exported CC/CXX, not -DCMAKE_C_COMPILER=clang: CMake caches the full path
# and, on a re-run, treats the bare name as a compiler change and wipes the cache (losing the -D options).
# -fno-sanitize=alignment: DkTgaLoader::load() reads every header field of every TGA through a
# misaligned uint16_t* (benign on x86), which would abort on the first input; the other UBSan
# checks and ASan stay halting.
FUZZ_FLAGS="$SANITIZER_FLAGS -fno-sanitize=alignment $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
cmake -S "$IL" -B "$SRC/build-fuzz" -G Ninja -DCMAKE_BUILD_TYPE=Release -DQT_VERSION_MAJOR=6 \
    -DENABLE_PLUGINS=OFF -DENABLE_TRANSLATIONS=OFF -DENABLE_TESTING=OFF \
    -DCMAKE_C_FLAGS="$FUZZ_FLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS"
cmake --build "$SRC/build-fuzz" --target nomacsCore -j"$MAYHEM_JOBS"

# ---- 2) harnesses: fuzzer binary + standalone reproducer each ---------------------------------------
QT_MODS="Qt6Core Qt6Gui Qt6Widgets Qt6Network Qt6PrintSupport Qt6Concurrent Qt6Svg"
CXXFLAGS_H="$(pkg-config --cflags $QT_MODS exiv2 opencv4) -fPIC -std=c++17 \
    -DDK_DLL_IMPORT -DNOMINMAX -DWITH_OPENCV -DWITH_LIBRAW -DWITH_LIBTIFF -DHAVE_EXIV2_HPP -DQT_NO_DEBUG_OUTPUT \
    -I$IL/src -I$IL/src/DkCore -I$IL/src/DkGui -I$SRC/build-fuzz -I$HARNESS"
LIBS_H="-L$SRC/build-fuzz -lnomacsCore -Wl,-rpath,$SRC/build-fuzz $(pkg-config --libs $QT_MODS exiv2 opencv4)"

$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o /tmp/lsan_off.o

# name:source:suffix:mode[:min input size]  (mode: normal | fast | file)
HARNESSES=(
    "nomacs_loader_tga:fuzz_loader.cpp:tga:normal:18"
    "nomacs_loader_tiff:fuzz_loader.cpp:tif:normal"
    "nomacs_loader_psd:fuzz_loader.cpp:psd:normal"
    "nomacs_loader_raw:fuzz_loader.cpp:dng:fast"
    "nomacs_loader_drif:fuzz_loader.cpp:drif:file"
    "nomacs_loader_vec:fuzz_loader.cpp:vec:normal:12"
    "nomacs_loader_qt:fuzz_loader.cpp::normal"
    "nomacs_metadata:fuzz_metadata.cpp::normal"
)
for h in "${HARNESSES[@]}"; do
    IFS=: read -r name src suffix mode minsize <<<"$h"
    defs=()
    [ "$src" = fuzz_loader.cpp ] && defs+=("-DFUZZ_SUFFIX=\"$suffix\"")
    [ "$mode" = fast ] && defs+=(-DFUZZ_FAST)
    [ "$mode" = file ] && defs+=(-DFUZZ_VIA_FILE)
    [ -n "${minsize:-}" ] && defs+=("-DFUZZ_MIN_SIZE=$minsize")
    # shellcheck disable=SC2086
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $CXXFLAGS_H "${defs[@]}" $LIB_FUZZING_ENGINE \
        "$HARNESS/$src" /tmp/lsan_off.o $LIBS_H -o "$SRC/$name"
    # shellcheck disable=SC2086
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $CXXFLAGS_H "${defs[@]}" \
        "$HARNESS/$src" /tmp/standalone_main.o /tmp/lsan_off.o $LIBS_H -o "$SRC/$name-standalone"
done

# ---- 3) the test suite + KAT probe, NORMAL flags (no sanitizer, no -gdwarf-3) -----------------------
cmake -S "$IL" -B "$SRC/build-tests" -G Ninja -DCMAKE_BUILD_TYPE=Release -DQT_VERSION_MAJOR=6 \
    -DENABLE_PLUGINS=OFF -DENABLE_TRANSLATIONS=OFF -DENABLE_TESTING=ON \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build "$SRC/build-tests" --target nomacsCore tests_core -j"$MAYHEM_JOBS"

$CXX -O1 $(pkg-config --cflags $QT_MODS exiv2 opencv4) -fPIC -std=c++17 \
    -DDK_DLL_IMPORT -DNOMINMAX -DWITH_OPENCV -DWITH_LIBRAW -DWITH_LIBTIFF -DHAVE_EXIV2_HPP -DQT_NO_DEBUG_OUTPUT \
    -I"$IL/src" -I"$IL/src/DkCore" -I"$IL/src/DkGui" -I"$SRC/build-tests" \
    "$SRC/mayhem/kat/kat_probe.cpp" -L"$SRC/build-tests" -lnomacsCore -Wl,-rpath,"$SRC/build-tests" \
    $(pkg-config --libs $QT_MODS exiv2 opencv4) -o "$SRC/build-tests/kat_probe"
file "$SRC/build-tests/kat_probe" | grep -q 'dynamically linked'
