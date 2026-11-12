#!/usr/bin/env bash
# Replays the short-header over-read the nomacs_loader_vec harness hides behind FUZZ_MIN_SIZE.
# Run it inside the commit image (the build tree is at /mayhem):
#   docker run --rm -i <commit-image> bash -s < mayhem/nomacs_loader_vec/known-findings/short-header-overread/replay.sh
# It rebuilds the harness WITHOUT -DFUZZ_MIN_SIZE, in /tmp, against the already built libnomacsCore.so,
# and feeds it the 1-byte input.bin. Expected: an ASan heap-buffer-overflow READ in the nomacs loader.
set -uo pipefail
SRC="${SRC:-/mayhem}"
IL="$SRC/ImageLounge"
FIND="$SRC/mayhem/nomacs_loader_vec/known-findings/short-header-overread"
QT_MODS="Qt6Core Qt6Gui Qt6Widgets Qt6Network Qt6PrintSupport Qt6Concurrent Qt6Svg"
clang -c $SANITIZER_FLAGS -g -gdwarf-3 "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o || exit 2
clang++ $SANITIZER_FLAGS -g -gdwarf-3 $(pkg-config --cflags $QT_MODS exiv2 opencv4) -fPIC -std=c++17 \
    -DDK_DLL_IMPORT -DNOMINMAX -DWITH_OPENCV -DWITH_LIBRAW -DWITH_LIBTIFF -DHAVE_EXIV2_HPP -DQT_NO_DEBUG_OUTPUT \
    -I"$IL/src" -I"$IL/src/DkCore" -I"$IL/src/DkGui" -I"$SRC/build-fuzz" -I"$SRC/mayhem/harness" \
    -DFUZZ_SUFFIX='"vec"' "$SRC/mayhem/harness/fuzz_loader.cpp" /tmp/standalone_main.o "$SRC/mayhem/lsan_off.cc" \
    -L"$SRC/build-fuzz" -lnomacsCore -Wl,-rpath,"$SRC/build-fuzz" $(pkg-config --libs $QT_MODS exiv2 opencv4) \
    -o /tmp/nomin-vec || exit 2
/tmp/nomin-vec "$FIND/input.bin" > /tmp/replay.out 2>&1
rc=$?
grep -E 'ERROR: AddressSanitizer|^READ of size|^    #[0-9] .*(nmc::|DkBasicLoader)' /tmp/replay.out | head -6
[ $rc -ne 0 ] && grep -q 'heap-buffer-overflow' /tmp/replay.out && { echo "REPRODUCED (rc=$rc)"; exit 0; }
echo "NOT REPRODUCED (rc=$rc)"; exit 1
