    bool renderPage(const int pageIndex,
                    const int dpi,
                    msr::render::RenderedPage& page,
                    std::string& errorMessage) const
    {
        if (!validateDpi(dpi, errorMessage)) {
            return false;
        }

        if (pageIndex < 0 || pageIndex >= m_totalPageCount) {
            errorMessage = "The requested page range is outside the rendered score.";
            return false;
        }

        if (!m_scoreRenderer()) {
            errorMessage = "The score renderer is unavailable.";
            return false;
        }

        mu::engraving::rendering::IScoreRenderer::ScorePaintOptions options;
        options.fromPage = pageIndex;
        options.toPage = pageIndex;
        options.deviceDpi = dpi;
        options.printPageBackground = false;
        options.isSetViewport = true;
        options.isMultiPage = false;
        options.isPrinting = true;

        mu::engraving::Score* score = activeScore();
        const SteadyClock::time_point renderStarted = SteadyClock::now();
        std::cout << "MuseReader render page begin"
                  << " page=" << pageIndex
                  << " dpi=" << dpi
                  << " activeScore=\"" << corruptionScoreLabel(score) << "\""
                  << std::endl;
        const muse::SizeF pageSizeInch = m_scoreRenderer()->pageSizeInch(score, options);
        const int width = std::lrint(pageSizeInch.width() * dpi);
        const int height = std::lrint(pageSizeInch.height() * dpi);
        if (width <= 0 || height <= 0) {
            errorMessage = "The render core produced an invalid page size.";
            return false;
        }

        QImage image(width, height, QImage::Format_ARGB32_Premultiplied);
        image.setDotsPerMeterX(std::lrint((dpi * 1000.0) / mu::engraving::INCH));
        image.setDotsPerMeterY(std::lrint((dpi * 1000.0) / mu::engraving::INCH));
        image.fill(Qt::white);

        muse::draw::Painter painter(&image, "score_render_core");
        m_scoreRenderer()->paintScore(&painter, score, options);

        QByteArray pngData;
        QBuffer buffer(&pngData);
        if (!buffer.open(QIODevice::WriteOnly) || !image.save(&buffer, "png")) {
            errorMessage = "The render core could not encode the page as PNG.";
            return false;
        }

        page.pageIndex = pageIndex;
        page.pixelWidth = width;
        page.pixelHeight = height;
        page.pngData.assign(pngData.begin(), pngData.end());
        std::cout << "MuseReader render page end"
                  << " page=" << pageIndex
                  << " bytes=" << page.pngData.size()
                  << " elapsed=" << elapsedSecondsSince(renderStarted)
                  << "s" << std::endl;
        return true;
    }

