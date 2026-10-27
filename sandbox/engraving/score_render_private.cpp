private:
    mu::engraving::Score* activeScore() const
    {
        return m_activeScore ? m_activeScore : m_masterScore.get();
    }

    mu::engraving::Score* presentationScore() const
    {
        return m_viewTransposeActiveScore ? m_viewTransposeActiveScore : activeScore();
    }

    int activePageCount() const
    {
        mu::engraving::Score* score = presentationScore();
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

            if (excerpt->initialPartId() == part->id()) {
                return excerpt;
            }
        }

        for (mu::engraving::Excerpt* excerpt : m_masterScore->excerpts()) {
            if (!excerpt || excerpt->initialPartId().isValid()) {
                continue;
            }

            if (excerpt->containsPart(part)) {
                return excerpt;
            }
        }

        return nullptr;
    }

    void relayoutActiveScore()
    {
        const auto startedAt = SteadyClock::now();
        const int pagesBefore = activePageCount();
        if (mu::engraving::Score* score = presentationScore()) {
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
        m_playbackStream.reset();
        ++m_playbackStreamRevision;
        m_totalPageCount = activePageCount();
    }

    void discardViewTranspose()
    {
        m_playbackStream.reset();
        ++m_playbackStreamRevision;
        m_viewTransposeActiveScore = nullptr;
        m_viewTransposeMasterScore.reset();
        m_totalPageCount = activePageCount();
    }

    std::unique_ptr<SessionContext> m_sessionContext;
    std::unique_ptr<mu::engraving::MasterScore> m_masterScore;
    mu::engraving::Score* m_activeScore = nullptr;
    std::unique_ptr<mu::engraving::MasterScore> m_viewTransposeMasterScore;
    mu::engraving::Score* m_viewTransposeActiveScore = nullptr;
    std::optional<int> m_activePartIndex;
    std::string m_scorePath;
    //! Copied music, shared by every open score so it can be pasted into another one.
    struct Clipboard {
        std::mutex mutex;
        muse::ByteArray data;
        std::string mimeType;
    };
    static Clipboard& clipboard()
    {
        static Clipboard shared;
        return shared;
    }
    int m_totalPageCount = 0;
    int m_maxObservedMasterHarmonyCount = 0;
    std::unordered_map<mu::engraving::Score*, mu::engraving::LayoutMode> m_persistedLayoutModes;
    mu::engraving::Score* m_videoSpacingScore = nullptr;
    double m_videoOriginalSpacing = 0;
    // The opened file was last saved by the pre-4.7.5 engine; see scoreFileSavedByOldAriaEngine.
    bool m_savedByOldAriaEngine = false;
    // Part-only chord symbols in a file not saved by the pre-4.7.5 engine, as
    // desktop MuseScore allows. The save guard only blocks unlinked ones outside this set.
    std::unordered_set<const mu::engraving::EngravingItem*> m_fileUnlinkedPartHarmonies;
    mutable std::unique_ptr<FluidSynthPlaybackStream> m_playbackStream;
    int m_playbackStreamRevision = 0;
    // 4.7.5 declares the renderer per-context; the render core registers it globally.
    muse::ContextInject<mu::engraving::rendering::IScoreRenderer> m_scoreRenderer { muse::modularity::globalCtx() };
};
