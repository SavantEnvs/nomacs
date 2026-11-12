# TGA: header over-read on a file shorter than 18 bytes

The `nomacs_loader_tga` harness returns -1 for inputs shorter than 18 bytes (`FUZZ_MIN_SIZE`, the size of
the fixed TGA header). That check is a **deliberate exception**, not a library precondition: it exists
because of this bug (see `mayhem/harness/fuzz_loader.cpp`). `uv run integration gate-fuzz-smoke` runs
libFuzzer with no corpus, so its first input is the 1-byte `\n`; without the filter that input aborts the
target before any iteration and the gate reports "did not iterate".

- Reproducer: `input.bin`, 1 byte (`\n`, base64 `Cg==`). Any `.tga` file shorter than 18 bytes does the same.
- Cause: `nmc::tga::DkTgaLoader::load(QSharedPointer<QByteArray>)` (`ImageLounge/src/DkCore/DkBasicLoader.cpp`,
  from line 2579) reads the 18-byte header (`idlength`, `colourmaplength`, ... through the misaligned
  `uint16_t*` reads, then `bitsperpixel`/`imagedescriptor`) straight from `ba->data()`. The only guard on
  the way in is `DkTgaLoader::load()`'s `isEmpty()` check (and `loadGeneral()` for the buffer).
- Impact: heap-buffer-overflow READ (CWE-125) of up to 17 bytes past the end of the file buffer, in the
  function that opens every `.tga` a user selects. Reachable from `DkBasicLoader::loadGeneral()`, the entry point nomacs uses
  for every file open.
- Upstream fix, one line at the top of `DkTgaLoader::load(QSharedPointer<QByteArray>)`:
  `if (ba->size() < 18) return false;`
- Replay (inside the commit image; rebuilds the harness without `FUZZ_MIN_SIZE`, in `/tmp`, and runs it on
  `input.bin`; prints the ASan report and `REPRODUCED`):

  ```
  docker run --rm -i <commit-image> bash -s < mayhem/nomacs_loader_tga/known-findings/short-header-overread/replay.sh
  ```

  Expected first frame: `nmc::tga::DkTgaLoader::load(...)` at `DkBasicLoader.cpp:2599`
  (`READ of size 2`, 2 bytes after a 19-byte region).
