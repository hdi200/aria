    bool scoreCorruptionReport(msr::render::ScoreCorruptionReport& output, std::string& errorMessage)
    {
        if (!m_masterScore) {
            errorMessage = "The MuseScore render session is no longer available.";
            return false;
        }

        output = scanScoreCorruptions(m_masterScore.get());
        return true;
    }

    bool selectCorruptionIssue(const int issueIndex,
                               msr::render::ScoreEditState& output,
                               std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        msr::render::ScoreCorruptionReport report = scanScoreCorruptions(m_masterScore.get());
        if (issueIndex < 0 || issueIndex >= static_cast<int>(report.issues.size())) {
            errorMessage = "That corruption issue is no longer available.";
            return false;
        }

        const msr::render::ScoreCorruptionIssue& issue = report.issues.at(static_cast<size_t>(issueIndex));
        if (!issue.fullScore) {
            errorMessage = "This corruption is in a linked part. Open the full score repair lane first.";
            return false;
        }

        m_activePartIndex.reset();
        m_activeScore = m_masterScore.get();
        mu::engraving::Score* score = activeScore();
        mu::engraving::Measure* measure = measureByVisibleNumber(score, issue.measureNumber);
        if (!measure) {
            errorMessage = "MuseScore could not find the corrupted measure.";
            return false;
        }

        ::selectMeasureRange(score, measure, measure, static_cast<mu::engraving::staff_idx_t>(issue.staffIndex), static_cast<mu::engraving::staff_idx_t>(issue.staffIndex + 1));
        output = makeEditState(score);
        return true;
    }

    bool clearCorruptionIssue(const int issueIndex,
                              msr::render::ScoreEditState& output,
                              msr::render::ScoreCorruptionReport& report,
                              std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        report = scanScoreCorruptions(m_masterScore.get());
        if (issueIndex < 0 || issueIndex >= static_cast<int>(report.issues.size())) {
            errorMessage = "That corruption issue is no longer available.";
            return false;
        }

        const msr::render::ScoreCorruptionIssue issue = report.issues.at(static_cast<size_t>(issueIndex));
        if (!issue.fullScore) {
            errorMessage = "This corruption is in a linked part. Open the full score repair lane first.";
            return false;
        }

        m_activePartIndex.reset();
        m_activeScore = m_masterScore.get();
        mu::engraving::Score* score = activeScore();
        if (!score) {
            errorMessage = "The MuseScore render session is no longer available.";
            return false;
        }

        mu::engraving::Measure* measure = measureByVisibleNumber(score, issue.measureNumber);
        if (!measure) {
            errorMessage = "MuseScore could not find the corrupted measure.";
            return false;
        }

        if (issue.staffIndex < 0 || static_cast<mu::engraving::staff_idx_t>(issue.staffIndex) >= score->nstaves()) {
            errorMessage = "MuseScore could not find the corrupted staff.";
            return false;
        }

        std::cout << "Aria corruption repair: raw repair begin"
                  << " issueIndex=" << issueIndex
                  << " measure=" << issue.measureNumber
                  << " staff=" << issue.staffIndex
                  << std::endl;
        const bool didRepair = clearLinkedMeasureStaffsToRest(score, measure, static_cast<mu::engraving::staff_idx_t>(issue.staffIndex));
        if (!didRepair) {
            errorMessage = "MuseScore could not rewrite that corrupted bar.";
            return false;
        }

        std::cout << "Aria corruption repair: relayout begin" << std::endl;
        relayoutAllScores();
        std::cout << "Aria corruption repair: refresh begin" << std::endl;
        refreshAfterEdit();
        std::cout << "Aria corruption repair: rescan begin" << std::endl;
        report = scanScoreCorruptions(m_masterScore.get());
        std::cout << "Aria corruption repair: rescan end"
                  << " remainingIssues=" << report.issues.size()
                  << std::endl;
        if (report.corrupted) {
            logCorruptionReportIssues("Aria corruption repair: rescan remaining", report, 12);
        }
        output = makeEditState(score);
        std::cout << "Aria corruption repair: raw repair end" << std::endl;
        return true;
    }

