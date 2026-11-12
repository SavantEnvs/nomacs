# OpenCV `.vec`: header over-read on a file shorter than 12 bytes

The `nomacs_loader_vec` harness returns -1 for inputs shorter than 12 bytes (`FUZZ_MIN_SIZE`, the size of
the fixed `.vec` header). That check is a **deliberate exception**, not a library precondition: it exists
because of this bug (see `mayhem/harness/fuzz_loader.cpp`). `uv run integration gate-fuzz-smoke` runs
libFuzzer with no corpus, so its first input is the 1-byte `\n`; without the filter that input aborts the
target before any iteration and the gate reports "did not iterate".

- Reproducer: `input.bin`, 1 byte (`\n`, base64 `Cg==`). Any `.vec` file shorter than 12 bytes does the same.
- Cause: `nmc::DkBasicLoader::loadOpenCVVecFile()` (`ImageLounge/src/DkCore/DkBasicLoader.cpp`, line 1771)
  calls `readHeader()` after only an `isEmpty()` check. `readHeader()` (line 1850) casts the buffer to
  `const int *` and reads `fileCount` and `vecSize` (and then skips 12 header bytes) without checking that
  the buffer holds them.
- Impact: heap-buffer-overflow READ (CWE-125) of up to 11 bytes past the end of the file buffer when a user
  opens a short `.vec` file; reachable from `DkBasicLoader::loadGeneral()`. The over-read values then drive
  the rest of the parse (`fileCount`, `vecSize`).
- Upstream fix, one line before `readHeader()` in `loadOpenCVVecFile()`:
  `if (ba->size() < 12) return false;`
- Replay (inside the commit image; rebuilds the harness without `FUZZ_MIN_SIZE`, in `/tmp`, and runs it on
  `input.bin`; prints the ASan report and `REPRODUCED`):

  ```
  docker run --rm -i <commit-image> bash -s < mayhem/nomacs_loader_vec/known-findings/short-header-overread/replay.sh
  ```

  Expected first frame: `nmc::DkBasicLoader::readHeader(...)` at `DkBasicLoader.cpp:1857`
  (`READ of size 4`, 1 byte after a 19-byte region).
