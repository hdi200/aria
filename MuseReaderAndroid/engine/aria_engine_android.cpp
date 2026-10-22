#include "aria_engine.h"

#include <android/log.h>
#include <dlfcn.h>
#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <future>
#include <memory>
#include <mutex>
#include <thread>

#include <QCoreApplication>
#include <QFont>
#include <QString>
#include <QStringList>

namespace {

// Folder holding the app's native libraries (this one, Qt's, and Qt's plugins).
std::string nativeLibraryDir()
{
    Dl_info info {};
    if (!dladdr(reinterpret_cast<void*>(&nativeLibraryDir), &info) || !info.dli_fname) {
        return {};
    }
    std::string path(info.dli_fname);
    return path.substr(0, path.find_last_of('/'));
}

// Qt on Android normally starts from its own activity. The render core runs Qt headless
// inside our app instead, so point it at the plugins packaged with the app and at
// Android's fonts. Read when the core creates its Qt application, on the first call.
void configureQtEnvironment()
{
    const std::string libraryDir = nativeLibraryDir();
    setenv("QT_QPA_PLATFORM", "offscreen", 1);
    setenv("QT_QPA_PLATFORM_PLUGIN_PATH", libraryDir.c_str(), 1);
    setenv("QT_PLUGIN_PATH", libraryDir.c_str(), 1);
    setenv("QT_QPA_FONTDIR", "/system/fonts", 1);
}

// Scores often name desktop fonts that Android doesn't have. Map them to the engine's
// own metric-compatible fonts first (FreeSerif is a Times clone, FreeSans a Helvetica
// clone, as desktop Linux does), then to Android's system fonts. Without this, Qt picks
// an arbitrary registered font, which can be one whose letters are symbols. iOS gets
// these names from its system fonts.
void configureFontSubstitutions()
{
    const QStringList serif { "FreeSerif", "Noto Serif" };
    const QStringList sans { "FreeSans", "Roboto" };
    const QStringList mono { "Droid Sans Mono", "Cutive Mono" };

    for (const char* family : { "Times New Roman", "Times", "Georgia", "Palatino", "Palatino Linotype",
                                "Book Antiqua", "Garamond", "Cambria", "Century Schoolbook", "serif" }) {
        QFont::insertSubstitutions(family, serif);
    }
    for (const char* family : { "Arial", "Helvetica", "Helvetica Neue", "Verdana", "Tahoma", "Calibri",
                                "Segoe UI", "Lucida Grande", "Gill Sans", "sans-serif" }) {
        QFont::insertSubstitutions(family, sans);
    }
    for (const char* family : { "Courier New", "Courier", "Menlo", "Monaco", "Consolas", "monospace" }) {
        QFont::insertSubstitutions(family, mono);
    }
}

// The render core reports progress and errors on stdout/stderr, which Android discards.
// Forward both to the Android log (tag "AriaEngine").
void forwardStandardOutputToLog()
{
    int pipeFds[2];
    if (pipe(pipeFds) != 0) {
        return;
    }
    setvbuf(stdout, nullptr, _IOLBF, 0);
    setvbuf(stderr, nullptr, _IONBF, 0);
    dup2(pipeFds[1], STDOUT_FILENO);
    dup2(pipeFds[1], STDERR_FILENO);

    std::thread([readFd = pipeFds[0]] {
        char buffer[1024];
        std::string line;
        ssize_t count = 0;
        while ((count = read(readFd, buffer, sizeof(buffer))) > 0) {
            line.append(buffer, static_cast<size_t>(count));
            size_t newline = 0;
            while ((newline = line.find('\n')) != std::string::npos) {
                __android_log_write(ANDROID_LOG_INFO, "AriaEngine", line.substr(0, newline).c_str());
                line.erase(0, newline + 1);
            }
        }
    }).detach();
}

} // namespace

void aria::startEngine()
{
    static std::once_flag started;
    std::call_once(started, [] {
        forwardStandardOutputToLog();
        configureQtEnvironment();
        configureFontSubstitutions();

        auto ready = std::make_shared<std::promise<void>>();
        std::future<void> readyFuture = ready->get_future();
        std::thread([ready] {
            // Creates the engine's QGuiApplication on this thread, which makes it Qt's
            // main thread. The engine hands work to it when it opens and closes scores.
            msr::render::ScoreRenderCore::initializeIfNeeded();
            ready->set_value();
            QCoreApplication::exec();
        }).detach();
        readyFuture.wait();
    });
}

msr::render::ScoreRenderSession* aria::openSession(const std::string& scorePath, std::string& errorMessage)
{
    return msr::render::ScoreRenderSession::open(scorePath, errorMessage).release();
}

void aria::closeSession(msr::render::ScoreRenderSession* session)
{
    delete session;
}

void* aria::makeReverb(double sampleRate)
{
    return new msr::render::PlaybackReverb(sampleRate);
}

void aria::processReverb(void* reverb, float* interleavedStereo, int frameCount)
{
    static_cast<msr::render::PlaybackReverb*>(reverb)->process(interleavedStereo, frameCount);
}

void aria::resetReverb(void* reverb)
{
    static_cast<msr::render::PlaybackReverb*>(reverb)->reset();
}

void aria::destroyReverb(void* reverb)
{
    delete static_cast<msr::render::PlaybackReverb*>(reverb);
}

void aria::log(const char* message)
{
    __android_log_write(ANDROID_LOG_INFO, "AriaEngine", message);
}
