# PSD: header-sized allocation in libqpsd (CWE-789)

Mayhem run 1 of `nomacs_loader_psd` reports this as a "Memory Allocation with Excessive Size Value"
(defect #3607234, class `uncategorized`). The stack has **no application frame**: `malloc` called from
`QArrayData::allocate1` in the uninstrumented apt `libQt6Core.so.6`, whose caller frames are unwound to
garbage (`0xfefefefefefefefd`). The code at fault is `ImageLounge/3rdparty/libqpsd`.

- Reproducer: `input.psb`, 61 bytes (base64
  `OEJQUwACyMjIyAMAIwAAAAUAAAMAygAQAAMAysrKysrKysrKysrKysoAAAADAAAABAUAAQAAAAAAAAAAAQ==`).
  It is the input of run 1's defect, byte for byte. Header: signature `8BPS`, version 2 (PSB), 8960 channels
  (`0x2300`), height 1280, width 196810, depth 16, colour mode RGB, compression RAW.
- Cause: `QPsdHandler::read()` (`qpsdhandler.cpp`) computes `size = channels * width * height * depth / 8` from
  the header (about 4.5 TB here). `isValidWidthOrHeight()` bounds width and height (300000 for PSB) and
  `isChannelCountSupported()` only checks `channels >= 1`, so nothing bounds the product.
  `readImageData()` (`qpsdhandler_p.cpp`, RAW branch) then does `imageData.resize(size)` before reading a
  single byte; the 61-byte file cannot hold that. `QByteArray::resize` rounds up to 2^43 bytes
  (`0x80000000000`), more than ASan's 1 TiB limit, so ASan aborts with `allocation-size-too-big`. Without ASan
  the allocation fails or the process is OOM-killed.
- Impact: a 61-byte `.psd`/`.psb` makes nomacs try to allocate terabytes (denial of service on open,
  CWE-789).
- Upstream fix, in `readImageData()` before `imageData.resize(size)`:
  `if (size > (quint64)(input.device()->size() - input.device()->pos())) return QByteArray();`
  (the caller then rejects the empty buffer through its `imageData.size() != size` check).
- Replay (inside the commit image; the standalone harness is built by `build.sh`):

  ```
  docker run --rm -i <commit-image> bash -c \
    '/mayhem/nomacs_loader_psd-standalone /mayhem/mayhem/nomacs_loader_psd/known-findings/psb-excessive-allocation/input.psb'
  ```

  Expected: `AddressSanitizer: requested allocation size 0x80000000000 ... exceeds maximum supported size`,
  `SUMMARY: AddressSanitizer: allocation-size-too-big ... in malloc`.
