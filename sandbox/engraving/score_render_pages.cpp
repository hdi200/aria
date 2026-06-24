    void appendLayoutBreakMarkersForPage(mu::engraving::Page* scorePage,
                                         msr::render::RenderedPage& page) const
    {
        page.layoutBreakMarkers.clear();
        if (!scorePage || scorePage->width() <= 0.0 || scorePage->height() <= 0.0) {
            return;
        }

        const double pageWidth = scorePage->width();
        const double pageHeight = scorePage->height();
        auto appendMarker = [&](const std::string& kind, const mu::engraving::RectF& rect) {
            if (kind.empty() || rect.width() <= 0.0 || rect.height() <= 0.0) {
                return;
            }

            msr::render::RenderedPage::LayoutBreakMarker marker;
            marker.kind = kind;
            marker.normalizedX = clampUnitInterval(rect.left() / pageWidth);
            marker.normalizedY = clampUnitInterval(rect.top() / pageHeight);
            marker.normalizedWidth = clampUnitInterval(rect.width() / pageWidth);
            marker.normalizedHeight = clampUnitInterval(rect.height() / pageHeight);
            page.layoutBreakMarkers.push_back(marker);
        };

        for (const mu::engraving::System* system : scorePage->systems()) {
            if (!system) {
                continue;
            }

            for (mu::engraving::MeasureBase* measureBase : system->measures()) {
                if (!measureBase) {
                    continue;
                }

                for (mu::engraving::EngravingItem* item : measureBase->el()) {
                    if (!item || !item->isLayoutBreak()) {
                        continue;
                    }

                    const mu::engraving::LayoutBreak* layoutBreak = mu::engraving::toLayoutBreak(item);
                    const std::string kind = layoutBreakKind(layoutBreak);
                    if (kind.empty()) {
                        continue;
                    }

                    const mu::engraving::RectF rect = layoutBreakMarkerRect(layoutBreak, measureBase);
                    if (rect.width() <= 0.0 || rect.height() <= 0.0) {
                        continue;
                    }

                    appendMarker(kind, rect);
                }
            }

            for (const mu::engraving::SystemLockIndicator* indicator : system->lockIndicators()) {
                appendMarker("systemLock", systemLockMarkerRect(indicator));
            }
        }
    }

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

        mu::engraving::Score* score = activeScore();
        if (!score) {
            errorMessage = "The score session is closed.";
            return false;
        }

        const SteadyClock::time_point renderStarted = SteadyClock::now();
        std::cout << "MuseReader render page begin"
                  << " page=" << pageIndex
                  << " dpi=" << dpi
                  << " activeScore=\"" << corruptionScoreLabel(score) << "\""
                  << std::endl;

        mu::engraving::rendering::IScoreRenderer::ScorePaintOptions options;
        options.fromPage = pageIndex;
        options.toPage = pageIndex;
        options.deviceDpi = dpi;
        options.printPageBackground = false;
        options.isSetViewport = true;
        options.isMultiPage = false;
        options.isPrinting = true;

        const muse::SizeF pageSizeInch = m_scoreRenderer()->pageSizeInch(score, options);
        const int width = std::lrint(pageSizeInch.width() * dpi);
        const int height = std::lrint(pageSizeInch.height() * dpi);
        if (width <= 0 || height <= 0) {
            errorMessage = "The render core produced an invalid page size.";
            return false;
        }

        page.pageIndex = pageIndex;
        page.pixelWidth = width;
        page.pixelHeight = height;
        page.pngData.clear();
        std::string pdfErrorMessage;
        if (!renderPagePdfData(pageIndex, page.pdfData, pdfErrorMessage)) {
            page.pdfData.clear();
            std::cout << "MuseReader render page PDF fallback"
                      << " page=" << pageIndex
                      << " error=\"" << pdfErrorMessage << "\""
                      << std::endl;

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

            page.pngData.assign(pngData.begin(), pngData.end());
        }
        appendLayoutBreakMarkersForPage(pageForIndex(score, pageIndex), page);
        std::cout << "MuseReader render page end"
                  << " page=" << pageIndex
                  << " pngBytes=" << page.pngData.size()
                  << " pdfBytes=" << page.pdfData.size()
                  << " layoutBreakMarkers=" << page.layoutBreakMarkers.size()
                  << " elapsed=" << elapsedSecondsSince(renderStarted)
                  << "s" << std::endl;
        return true;
    }

    bool renderPagePdfData(const int pageIndex,
                           std::vector<std::uint8_t>& output,
                           std::string& errorMessage) const
    {
        output.clear();
        if (pageIndex < 0 || pageIndex >= m_totalPageCount) {
            errorMessage = "The requested page range is outside the rendered score.";
            return false;
        }

        if (!m_scoreRenderer()) {
            errorMessage = "The score renderer is unavailable.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (!score) {
            errorMessage = "The score session is closed.";
            return false;
        }

        mu::engraving::rendering::IScoreRenderer::ScorePaintOptions options;
        options.fromPage = pageIndex;
        options.toPage = pageIndex;
        options.deviceDpi = mu::engraving::DPI;
        options.printPageBackground = true;
        options.isSetViewport = true;
        options.isMultiPage = false;
        options.isPrinting = true;

        const muse::SizeF pageSizeInch = m_scoreRenderer()->pageSizeInch(score, options);
        if (pageSizeInch.width() <= 0.0 || pageSizeInch.height() <= 0.0) {
            errorMessage = "The render core produced an invalid PDF page size.";
            return false;
        }

        QByteArray pdfBytes;
        QBuffer buffer(&pdfBytes);
        if (!buffer.open(QIODevice::WriteOnly)) {
            errorMessage = "The render core could not allocate a PDF page buffer.";
            return false;
        }

        QPdfWriter pdfWriter(&buffer);
        pdfWriter.setResolution(mu::engraving::DPI);
        pdfWriter.setPageMargins(QMarginsF());
        pdfWriter.setPageLayout(QPageLayout(
            QPageSize(QSizeF(pageSizeInch.width(), pageSizeInch.height()), QPageSize::Inch),
            QPageLayout::Orientation::Portrait,
            QMarginsF()));
        pdfWriter.setColorModel(QPdfWriter::ColorModel::Auto);

        muse::draw::Painter painter(&pdfWriter, "score_render_core_page_pdf");
        if (!painter.isActive()) {
            errorMessage = "The render core could not start the PDF page painter.";
            return false;
        }

        options.deviceDpi = pdfWriter.logicalDpiX();
        m_scoreRenderer()->paintScore(&painter, score, options);
        painter.endDraw();

        output.assign(pdfBytes.constData(), pdfBytes.constData() + pdfBytes.size());
        if (output.empty()) {
            errorMessage = "The render core produced an empty PDF page.";
            return false;
        }

        return true;
    }
