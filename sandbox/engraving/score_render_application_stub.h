#pragma once

#include "global/iapplication.h"

namespace msr::render {
//! The render core runs without a MuseScore application, but the engine asks
//! IApplication for the version it writes into saved files (<programVersion>,
//! <programRevision>). Report the MuseScore release the engine is built from,
//! so Aria's saves carry the same header that release writes.
class RenderApplicationStub : public muse::IApplication
{
public:
    muse::String name() const override { return u"MuseScore Studio"; }
    muse::String title() const override { return u"MuseScore Studio"; }
    bool unstable() const override { return false; }
    muse::Version version() const override { return muse::Version(4, 7, 5); }
    muse::Version fullVersion() const override { return version(); }

    muse::String build() const override { return u""; }
    muse::String revision() const override { return u"3654226"; }

    RunMode runMode() const override { return RunMode::ConsoleApp; }
    bool noGui() const override { return true; }

    void setup() override {}
    void finish() override {}
    void restart() override {}

    muse::modularity::ContextPtr setupNewContext() override { return nullptr; }
    int contextCount() const override { return 0; }
    std::vector<muse::modularity::ContextPtr> contexts() const override { return {}; }

    const muse::modularity::ContextPtr iocContext() const override { return muse::modularity::globalCtx(); }
    muse::modularity::ModulesIoC* ioc() const override { return muse::modularity::globalIoc(); }

    void processEvents() override {}

#ifndef NO_QT_SUPPORT
    QWindow* focusWindow() const override { return nullptr; }
    bool notify(QObject*, QEvent*) override { return true; }

    Qt::KeyboardModifiers keyboardModifiers() const override { return Qt::KeyboardModifiers(); }
#endif
};
}
