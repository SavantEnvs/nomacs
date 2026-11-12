// Shared one-time Qt and nomacs setup for the harnesses, mirroring what main() does before it opens an image.
#pragma once

#include "DkMetaData.h"
#include "DkSettings.h"

#include <QGuiApplication>
#include <cstdlib>

static inline void nomacsFuzzInit()
{
    // no display in the fuzzing container; the offscreen platform needs no X/Wayland server
    setenv("QT_QPA_PLATFORM", "offscreen", 0);
    static int argc = 1;
    static char arg0[] = "nomacs_fuzz";
    static char *argv[] = {arg0, nullptr};
    static QGuiApplication *app = new QGuiApplication(argc, argv);
    (void)app;

    // DkSettings is uninitialised until init() loads the defaults; every loader reads it
    nmc::DkSettingsManager::instance().init();
    nmc::DkMetaDataHelper::initialize();

    // nmc logs every load; drop the messages (init() installed its own handler)
    qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &) {});
}
