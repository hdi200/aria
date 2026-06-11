private:
    mu::engraving::Score* activeScore() const
    {
        return m_activeScore ? m_activeScore : m_masterScore.get();
    }

    int activePageCount() const
    {
        mu::engraving::Score* score = activeScore();
        return score ? static_cast<int>(score->npages()) : 0;
    }

    mu::engraving::Excerpt* excerptForPart(const mu::engraving::Part* part) const
    {
        if (!m_masterScore || !part) {
            return nullptr;
        }

        for (mu::engraving::Excerpt* excerpt : m_masterScore->excerpts()) {
            if (!excerpt) {
                continue;
            }

            if (excerpt->initialPartId() == part->id() || excerpt->containsPart(part)) {
                return excerpt;
            }
        }

        return nullptr;
    }

    void relayoutActiveScore()
    {
        const auto startedAt = SteadyClock::now();
        const int pagesBefore = activePageCount();
        if (mu::engraving::Score* score = activeScore()) {
            std::cout << "Aria render core relayout begin: mode=all pagesBefore=" << pagesBefore << std::endl;
            score->setLayoutAll();
            score->doLayout();
        }

        m_totalPageCount = activePageCount();
        std::cout << "Aria render core relayout finished: mode=all pagesBefore=" << pagesBefore
                  << " pagesAfter=" << m_totalPageCount
                  << " elapsed=" << elapsedSecondsSince(startedAt) << "s"
                  << std::endl;
    }

    void relayoutActiveScoreRange(const mu::engraving::Fraction& startTick, const mu::engraving::Fraction& endTick)
    {
        const auto startedAt = SteadyClock::now();
        const int pagesBefore = activePageCount();
        if (mu::engraving::Score* score = activeScore()) {
            std::cout << "Aria render core relayout begin: mode=range startTick=" << startTick.ticks()
                      << " endTick=" << endTick.ticks()
                      << " pagesBefore=" << pagesBefore
                      << std::endl;
            score->doLayoutRange(startTick, endTick);
        }

        m_totalPageCount = activePageCount();
        std::cout << "Aria render core relayout finished: mode=range startTick=" << startTick.ticks()
                  << " endTick=" << endTick.ticks()
                  << " pagesBefore=" << pagesBefore
                  << " pagesAfter=" << m_totalPageCount
                  << " elapsed=" << elapsedSecondsSince(startedAt) << "s"
                  << std::endl;
    }

    void relayoutAllScores()
    {
        if (!m_masterScore) {
            return;
        }

        for (mu::engraving::Score* score : m_masterScore->scoreList()) {
            if (!score) {
                continue;
            }

            const auto startedAt = SteadyClock::now();
            std::cout << "Aria corruption repair: relayout score"
                      << " score=\"" << corruptionScoreLabel(score) << "\""
                      << std::endl;
            score->setLayoutAll();
            score->doLayout();
            std::cout << "Aria corruption repair: relayout score finished"
                      << " score=\"" << corruptionScoreLabel(score) << "\""
                      << " elapsed=" << elapsedSecondsSince(startedAt) << "s"
                      << std::endl;
        }

        m_totalPageCount = activePageCount();
    }

    void refreshAfterEdit()
    {
        if (!m_masterScore) {
            return;
        }

        m_masterScore->setPlaylistDirty();
        m_maxObservedMasterHarmonyCount = std::max(m_maxObservedMasterHarmonyCount, harmonyCountInScore(m_masterScore.get()));
        m_totalPageCount = activePageCount();
    }

    std::unique_ptr<SessionContext> m_sessionContext;
    std::unique_ptr<mu::engraving::MasterScore> m_masterScore;
    mu::engraving::Score* m_activeScore = nullptr;
    std::optional<int> m_activePartIndex;
    std::string m_scorePath;
    muse::ByteArray m_measureClipboard;
    std::string m_measureClipboardMimeType;
    int m_totalPageCount = 0;
    int m_maxObservedMasterHarmonyCount = 0;
    muse::GlobalInject<mu::engraving::rendering::IScoreRenderer> m_scoreRenderer;
};
