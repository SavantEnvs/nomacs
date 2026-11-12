// Fuzzes nmc::DkBasicLoader::loadGeneral(), the entry point nomacs uses to open every image.
// The file suffix selects the loader, so one source is built once per suffix (FUZZ_SUFFIX):
// tga, tif, psd, dng (LibRaw), vec (OpenCV cascade samples), and "" (Qt content sniffing).
// The input bytes are passed as the file's contents ("ba ... always used first", DkBasicLoader.h),
// so nothing is read from disk, except for the drif loader, which only reads from a path
// (FUZZ_VIA_FILE: the input is written to a mkstemp() file in $TMPDIR).
#include "DkBasicLoader.h"
#include "qt_init.h"

#include <QSharedPointer>
#include <QString>

#include <cstdint>
#include <cstdio>
#include <string>
#include <unistd.h>

#ifndef FUZZ_SUFFIX
#error "define FUZZ_SUFFIX (file suffix without the dot, may be empty)"
#endif

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
    nomacsFuzzInit();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    // loadGeneral() reads the named file when the buffer is empty; there is no file here
    if (size == 0)
        return -1;
#ifdef FUZZ_MIN_SIZE
    // DELIBERATE EXCEPTION, not a library precondition: DkTgaLoader::load() and readHeader() read their fixed
    // header (TGA 18 bytes, OpenCV .vec 12 bytes) after only an isEmpty() check. This hides that one over-read
    // on a file shorter than the header, which would otherwise abort gate-fuzz-smoke's 1-byte first input.
    // Recorded in mayhem/nomacs_loader_{tga,vec}/known-findings/short-header-overread/.
    if (size < FUZZ_MIN_SIZE)
        return -1;
#endif

#ifdef FUZZ_VIA_FILE
    const char *tmp = getenv("TMPDIR");
    std::string path = std::string(tmp && *tmp ? tmp : "/tmp") + "/nomacs-fuzz-XXXXXX." FUZZ_SUFFIX;
    int fd = mkstemps(&path[0], 1 + (int)sizeof(FUZZ_SUFFIX) - 1);
    if (fd < 0)
        return 0;
    size_t off = 0;
    while (off < size) {
        ssize_t n = write(fd, data + off, size - off);
        if (n <= 0)
            break;
        off += (size_t)n;
    }
    close(fd);
    const QString filePath = QString::fromLocal8Bit(path.c_str());
    QSharedPointer<QByteArray> ba;
#else
    const QString filePath = QStringLiteral("/nonexistent/fuzz." FUZZ_SUFFIX);
    auto ba = QSharedPointer<QByteArray>::create(reinterpret_cast<const char *>(data), (qsizetype)size);
#endif

    {
        nmc::DkBasicLoader loader;
        try {
            // same options and exception contract as DkImageContainer::loadImageIntern()
#ifdef FUZZ_FAST
            loader.loadGeneral(filePath, ba, nmc::DkLoadOption::normal);
#else
            loader.loadGeneral(filePath, ba, nmc::DkLoadOption::highquality);
#endif
        } catch (...) {
        }
    }

#ifdef FUZZ_VIA_FILE
    unlink(path.c_str());
#endif
    return 0;
}
