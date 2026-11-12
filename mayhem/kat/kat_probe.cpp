// Known-answer probe for the nomacs core library: decodes committed fixtures through
// nmc::DkBasicLoader and reads their metadata through nmc::DkMetaDataT, then prints the values it
// got. mayhem/test.sh compares this output with the expected text, so a stubbed or broken library
// (or an executable that exits 0 without running) fails the oracle.
#include "DkBasicLoader.h"
#include "DkFileInfo.h"
#include "DkMetaData.h"

#include <QGuiApplication>
#include <QImage>
#include <QString>

#include <cstdio>
#include <cstdlib>

static int fail(const char *what)
{
    std::printf("FAIL %s\n", what);
    return 1;
}

static void printPixel(const char *tag, const QImage &img, int x, int y)
{
    const QRgb p = img.pixel(x, y);
    std::printf("%s pixel(%d,%d)=%d,%d,%d\n", tag, x, y, qRed(p), qGreen(p), qBlue(p));
}

int main(int argc, char **argv)
{
    if (argc != 2)
        return fail("usage: kat_probe <fixtures dir>");
    qputenv("QT_QPA_PLATFORM", "offscreen");
    int qargc = 1;
    char arg0[] = "kat_probe";
    char *qargv[] = {arg0, nullptr};
    QGuiApplication app(qargc, qargv);

    const QString dir = QString::fromLocal8Bit(argv[1]) + "/";

    {
        nmc::DkBasicLoader loader;
        if (!loader.loadGeneral(dir + "rgb24.tga", nmc::DkLoadOption::normal))
            return fail("load rgb24.tga");
        const QImage img = loader.image();
        std::printf("tga size=%dx%d\n", img.width(), img.height());
        printPixel("tga", img, 0, 0);
        printPixel("tga", img, 3, 0);
        printPixel("tga", img, 1, 2);
        printPixel("tga", img, 3, 3);
    }
    {
        nmc::DkBasicLoader loader;
        if (!loader.loadGeneral(dir + "rgb8.tif", nmc::DkLoadOption::normal))
            return fail("load rgb8.tif");
        const QImage img = loader.image();
        std::printf("tif size=%dx%d\n", img.width(), img.height());
        printPixel("tif", img, 0, 0);
        printPixel("tif", img, 3, 0);
        printPixel("tif", img, 1, 2);
        printPixel("tif", img, 3, 3);
    }
    {
        nmc::DkMetaDataT md;
        md.readMetaData(nmc::DkFileInfo(dir + "exif.jpg"));
        std::printf("meta has=%d\n", md.hasMetaData() ? 1 : 0);
        std::printf("meta orientation=%d\n", md.getOrientationDegrees());
        std::printf("meta description=%s\n", md.getDescription().toUtf8().constData());
    }
    return 0;
}
