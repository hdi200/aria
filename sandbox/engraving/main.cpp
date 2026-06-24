#include <optional>

#include <QByteArray>
#include <QFile>
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QString>

#include "global/io/dir.h"
#include "global/io/fileinfo.h"

#include "score_render_core.h"

namespace {

muse::io::path_t defaultOutputDirFor(const muse::io::path_t& scorePath)
{
    const muse::io::path_t baseName = muse::io::completeBasename(scorePath);
    const muse::io::path_t folderName = baseName + "-rendered";
    return muse::io::dirpath(scorePath).appendingComponent(folderName);
}

} // namespace

int main(int argc, char* argv[])
{
    QCommandLineParser parser;
    parser.setApplicationDescription("Render real MuseScore pages to PNG files using the engraving engine.");
    parser.addHelpOption();

    QCommandLineOption outputOption({ "o", "output-dir" }, "Directory for rendered page PNGs.", "path");
    QCommandLineOption dpiOption({ "d", "dpi" }, "Raster DPI for page rendering.", "dpi", "144");
    QCommandLineOption pageOption({ "p", "page" }, "Render only a single 1-based page number.", "page");

    parser.addOption(outputOption);
    parser.addOption(dpiOption);
    parser.addOption(pageOption);
    parser.addPositionalArgument("score", "Path to an .mscz or .mscx file.");

    QStringList arguments;
    arguments.reserve(argc);
    for (int index = 0; index < argc; ++index) {
        arguments.append(QString::fromLocal8Bit(argv[index]));
    }
    parser.process(arguments);

    const QStringList positionalArguments = parser.positionalArguments();
    if (positionalArguments.size() != 1) {
        parser.showHelp(1);
    }

    bool dpiOk = false;
    const int dpi = parser.value(dpiOption).toInt(&dpiOk);
    if (!dpiOk || dpi <= 0) {
        qCritical() << "The DPI value must be a positive integer.";
        return 1;
    }

    std::optional<int> pageNumber;
    if (parser.isSet(pageOption)) {
        bool pageOk = false;
        const int parsedPage = parser.value(pageOption).toInt(&pageOk);
        if (!pageOk || parsedPage <= 0) {
            qCritical() << "The page number must be a positive integer.";
            return 1;
        }
        pageNumber = parsedPage;
    }

    const muse::io::path_t scorePath(positionalArguments.front());
    const muse::io::path_t outputDir = parser.isSet(outputOption)
        ? muse::io::path_t(parser.value(outputOption))
        : defaultOutputDirFor(scorePath);

    msr::render::RenderRequest request;
    request.scorePath = scorePath.toStdString();
    request.dpi = dpi;

    if (pageNumber) {
        request.fromPage = *pageNumber - 1;
        request.toPage = *pageNumber - 1;
    }

    msr::render::RenderedDocument document;
    std::string errorMessage;
    if (!msr::render::ScoreRenderCore::renderDocument(request, document, errorMessage)) {
        qCritical() << QString::fromStdString(errorMessage);
        return 1;
    }

    if (!muse::io::Dir::mkpath(outputDir)) {
        qCritical() << "Could not create output directory:" << outputDir.toQString();
        return 1;
    }

    for (const auto& page : document.pages) {
        const bool hasPdf = !page.pdfData.empty();
        const bool hasPng = !page.pngData.empty();
        const QString extension = hasPdf ? "pdf" : "png";
        const QString fileName = QString("page-%1.%2").arg(page.pageIndex + 1, 3, 10, QLatin1Char('0')).arg(extension);
        const muse::io::path_t outputPath = outputDir.appendingComponent(fileName);

        QFile file(outputPath.toQString());
        const std::vector<std::uint8_t>& bytes = hasPdf ? page.pdfData : page.pngData;
        if (!hasPdf && !hasPng) {
            qCritical() << "The render core produced no page output:" << outputPath.toQString();
            return 1;
        }
        if (!file.open(QIODevice::WriteOnly) || file.write(reinterpret_cast<const char*>(bytes.data()), static_cast<qint64>(bytes.size())) == -1) {
            qCritical() << "Failed to save page output:" << outputPath.toQString();
            return 1;
        }

        qInfo() << "Wrote" << outputPath.toQString();
    }

    qInfo() << "Rendered" << document.pages.size() << "page(s) to" << outputDir.toQString();
    return 0;
}
