// Fuzzes nmc::DkMetaDataT: Exiv2 parsing of the file bytes (EXIF/XMP/IPTC/ICC in any container
// Exiv2 knows) and the read accessors the metadata panels and the loader call on the result.
#include "DkFileInfo.h"
#include "DkMetaData.h"
#include "qt_init.h"

#include <QSharedPointer>
#include <QVector2D>
#include <QString>
#include <QStringList>

#include <cstdint>

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
    nomacsFuzzInit();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    // readMetaData() opens the named file when the buffer is empty; there is no file here
    if (size == 0)
        return -1;

    auto ba = QSharedPointer<QByteArray>::create(reinterpret_cast<const char *>(data), (qsizetype)size);

    try {
        nmc::DkMetaDataT md;
        md.readMetaData(nmc::DkFileInfo(QStringLiteral("/nonexistent/fuzz.jpg")), ba);

        md.hasMetaData();
        md.getMimeType();
        md.getOrientationDegrees();
        md.isOrientationMirrored();
        md.getRating();
        md.getImageSize();
        md.getDescription();
        md.getResolution();
        md.getThumbnail();
        md.getPreviewImage();

        // what the metadata panel shows
        QStringList keys, values;
        md.getAllMetaData(keys, values);
        const QStringList exifKeys = md.getExifKeys();
        for (const QString &k : exifKeys) {
            md.getNativeExifValue(k, true);
            md.getNativeExifValue(k, false);
            md.getExifValue(k);
        }
        const QStringList xmpKeys = md.getXmpKeys();
        for (const QString &k : xmpKeys)
            md.getXmpValue(k);
        const QStringList iptcKeys = md.getIptcKeys();
        for (const QString &k : iptcKeys)
            md.getIptcValue(k);
    } catch (...) {
    }
    return 0;
}
