    bool pdfData(std::vector<std::uint8_t>& output, std::string& errorMessage) const
    {
        if (!m_scoreRenderer()) {
            errorMessage = "The score renderer is unavailable.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (!score) {
            errorMessage = "The score session is closed.";
            return false;
        }

        const SteadyClock::time_point exportStarted = SteadyClock::now();
        std::cout << "MuseReader PDF export begin"
                  << " activeScore=\"" << corruptionScoreLabel(score) << "\""
                  << std::endl;

        mu::engraving::rendering::IScoreRenderer::ScorePaintOptions options;
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
            errorMessage = "The render core could not allocate a PDF export buffer.";
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

        muse::draw::Painter painter(&pdfWriter, "score_render_core_pdf");
        if (!painter.isActive()) {
            errorMessage = "The render core could not start the PDF painter.";
            return false;
        }

        options.deviceDpi = pdfWriter.logicalDpiX();
        options.onNewPage = [&pdfWriter]() { pdfWriter.newPage(); };
        m_scoreRenderer()->paintScore(&painter, score, options);
        painter.endDraw();

        output.assign(pdfBytes.constData(), pdfBytes.constData() + pdfBytes.size());
        std::cout << "MuseReader PDF export end"
                  << " bytes=" << output.size()
                  << " elapsed=" << elapsedSecondsSince(exportStarted)
                  << "s" << std::endl;
        return true;
    }
