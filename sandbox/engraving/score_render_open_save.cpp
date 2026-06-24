class msr::render::ScoreRenderSession::Impl
{
public:
    static std::unique_ptr<Impl> open(const std::string& scorePath, std::string& errorMessage)
    {
        std::unique_ptr<SessionContext> sessionContext = RenderRuntime::instance().createSessionContext();
        if (!sessionContext) {
            errorMessage = "The MuseScore score session could not create a document context.";
            return nullptr;
        }

        muse::io::path_t path(scorePath);
        auto masterScore = std::unique_ptr<mu::engraving::MasterScore>(
            mu::engraving::compat::ScoreAccess::createMasterScoreWithBaseStyle(sessionContext->context())
        );
        if (!masterScore) {
            errorMessage = "The MuseScore render core could not create a master score.";
            return nullptr;
        }

        masterScore->setFileInfoProvider(std::make_shared<mu::engraving::LocalFileInfoProvider>(path));

        const int sourceHarmonyCount = sourceHarmonyCountInScoreFile(path);

        muse::Ret loadResult = loadScoreForRenderCore(masterScore.get(), path);
        if (!loadResult) {
            errorMessage = loadResult.text().empty() ? "Failed to load score contents." : loadResult.text();
            return nullptr;
        }

        for (mu::engraving::Score* score : masterScore->scoreList()) {
            score->doLayout();
        }

        masterScore->setPlaylistDirty();

        const int totalPageCount = static_cast<int>(masterScore->npages());
        if (totalPageCount == 0) {
            errorMessage = "The score loaded, but produced no pages.";
            return nullptr;
        }

        return std::unique_ptr<Impl>(
            new Impl(std::move(sessionContext), std::move(masterScore), scorePath, totalPageCount, sourceHarmonyCount)
        );
    }

    Impl(std::unique_ptr<SessionContext> sessionContext,
         std::unique_ptr<mu::engraving::MasterScore> masterScore,
         const std::string& scorePath,
         const int totalPageCount,
         const int sourceHarmonyCount)
        : m_sessionContext(std::move(sessionContext)),
          m_masterScore(std::move(masterScore)),
          m_scorePath(scorePath),
          m_totalPageCount(totalPageCount)
    {
        if (m_masterScore) {
            m_activeScore = m_masterScore.get();
            m_maxObservedMasterHarmonyCount = std::max(sourceHarmonyCount, harmonyCountInScore(m_masterScore.get()));
            std::cout << "Aria save guard: loaded master harmonies="
                      << m_maxObservedMasterHarmonyCount
                      << " source=" << sourceHarmonyCount
                      << std::endl;
            mu::engraving::InputState& inputState = m_masterScore->inputState();
            inputState.setNoteEntryMode(false);
            inputState.setNoteEntryMethod(mu::engraving::NoteEntryMethod::BY_DURATION);
            inputState.setDuration(mu::engraving::TDuration(mu::engraving::DurationType::V_QUARTER));
            inputState.setRest(false);
        }
    }

    int totalPageCount() const
    {
        return m_totalPageCount;
    }

    bool supportsPlayback() const
    {
        return m_masterScore != nullptr;
    }

    bool supportsEditing() const
    {
        return m_masterScore != nullptr && !m_scorePath.empty();
    }

    bool concertPitchEnabled() const
    {
        const mu::engraving::Score* score = activeScore();
        return score && score->style().styleB(mu::engraving::Sid::concertPitch);
    }

    bool hasConcertPitchRelevantTransposition() const
    {
        const mu::engraving::Score* score = activeScore();
        if (!score) {
            return false;
        }

        for (const mu::engraving::Staff* staff : score->staves()) {
            if (staff->staffType(mu::engraving::Fraction(0, 1))->group() == mu::engraving::StaffGroup::PERCUSSION) {
                continue;
            }

            const mu::engraving::Part* part = staff->part();
            if (!part) {
                continue;
            }

            if (!part->instrument()->transpose().isZero() || part->instruments().size() > 1) {
                return true;
            }
        }

        return false;
    }

    std::vector<ScorePartInfo> partInfoList() const
    {
        std::vector<ScorePartInfo> output;
        if (!m_masterScore) {
            return output;
        }

        const std::vector<mu::engraving::Part*>& parts = m_masterScore->parts();
        output.reserve(parts.size());
        for (size_t index = 0; index < parts.size(); ++index) {
            const mu::engraving::Part* part = parts[index];
            if (!part) {
                continue;
            }

            const mu::engraving::Excerpt* excerpt = excerptForPart(part);
            std::string name = excerpt ? excerpt->name().toStdString() : std::string();
            if (name.empty()) {
                name = part->partName().toStdString();
            }
            if (name.empty()) {
                name = part->longName().toStdString();
            }
            if (name.empty()) {
                name = part->instrumentName().toStdString();
            }
            if (name.empty()) {
                name = "Part " + std::to_string(index + 1);
            }

            ScorePartInfo info;
            info.index = static_cast<int>(index);
            info.partId = std::to_string(part->id().toUint64());
            info.name = std::move(name);
            info.visible = part->show();
            output.push_back(std::move(info));
        }

        return output;
    }

    bool setActivePartIndex(const std::optional<int> partIndex, int& totalPageCount, std::string& errorMessage)
    {
        if (!m_masterScore) {
            errorMessage = "The MuseScore render session is no longer available.";
            return false;
        }

        if (!partIndex.has_value()) {
            m_activePartIndex.reset();
            m_activeScore = m_masterScore.get();
            relayoutActiveScore();
            totalPageCount = activePageCount();
            std::cout << "MuseReader active playback score: full score pages=" << totalPageCount << std::endl;
            return totalPageCount > 0;
        }

        const std::vector<mu::engraving::Part*>& parts = m_masterScore->parts();
        if (*partIndex < 0 || *partIndex >= static_cast<int>(parts.size())) {
            errorMessage = "The requested part is not available in this score.";
            return false;
        }

        mu::engraving::Part* part = parts.at(static_cast<size_t>(*partIndex));
        mu::engraving::Excerpt* excerpt = excerptForPart(part);
        if (!excerpt) {
            std::vector<mu::engraving::Excerpt*> createdExcerpts = mu::engraving::Excerpt::createExcerptsFromParts({ part }, m_masterScore.get());
            if (createdExcerpts.empty()) {
                errorMessage = "MuseScore could not create a linked part view for this part.";
                return false;
            }

            excerpt = createdExcerpts.front();
            m_masterScore->initAndAddExcerpt(excerpt, true);
        } else {
            m_masterScore->initExcerpt(excerpt);
        }

        if (!excerpt->excerptScore()) {
            errorMessage = "MuseScore created a linked part, but it did not produce a score.";
            return false;
        }

        m_activePartIndex = partIndex;
        m_activeScore = excerpt->excerptScore();
        relayoutActiveScore();
        totalPageCount = activePageCount();
        if (totalPageCount <= 0) {
            errorMessage = "The selected part loaded, but produced no pages.";
            return false;
        }

        std::cout << "MuseReader active playback score: partIndex=" << *partIndex
                  << " partId=" << part->id().toUint64()
                  << " pages=" << totalPageCount
                  << std::endl;

        return true;
    }

    bool setConcertPitchEnabled(const bool enabled, int& totalPageCount, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (score->style().styleB(mu::engraving::Sid::concertPitch) != enabled) {
            score->startCmd(muse::TranslatableString::untranslatable("MuseReader toggle concert pitch"));
            score->cmdConcertPitchChanged(enabled);
            score->endCmd();
            refreshAfterEdit();
        }

        totalPageCount = activePageCount();
        return totalPageCount > 0;
    }

    bool updateMetadata(const msr::render::ScoreMetadata& metadata, std::string& errorMessage)
    {
        if (!m_masterScore) {
            errorMessage = "Editing is unavailable because the score session is closed.";
            return false;
        }

        const QString title = normalizedMetadataValue(metadata.title);
        const QString subtitle = normalizedMetadataValue(metadata.subtitle);
        const QString composer = normalizedMetadataValue(metadata.composer);
        const QString lyricist = normalizedMetadataValue(metadata.lyricist);
        const QString arranger = normalizedMetadataValue(metadata.arranger);

        m_masterScore->setMetaTag(u"workTitle", title);
        m_masterScore->setMetaTag(u"subtitle", subtitle);
        m_masterScore->setMetaTag(u"composer", composer);
        m_masterScore->setMetaTag(u"lyricist", lyricist);
        m_masterScore->setMetaTag(u"arranger", arranger);

        setStyledMetadataText(m_masterScore.get(), mu::engraving::TextStyleType::TITLE, title);
        setStyledMetadataText(m_masterScore.get(), mu::engraving::TextStyleType::SUBTITLE, subtitle);
        setStyledMetadataText(m_masterScore.get(), mu::engraving::TextStyleType::COMPOSER, composer);
        setStyledMetadataText(m_masterScore.get(), mu::engraving::TextStyleType::LYRICIST, lyricist);

        for (mu::engraving::Score* score : m_masterScore->scoreList()) {
            if (!score) {
                continue;
            }

            score->setLayoutAll();
            score->doLayout();
        }

        m_masterScore->setPlaylistDirty();
        m_totalPageCount = static_cast<int>(m_masterScore->npages());
        if (m_totalPageCount <= 0) {
            errorMessage = "The edited score no longer produces any pages.";
            return false;
        }

        return true;
    }

    bool updateInitialKeySignature(const int keyValue, std::string& errorMessage)
    {
        return updateKeySignature(keyValue, true, errorMessage);
    }

    bool updateKeySignature(const int keyValue, const bool fromStart, std::string& errorMessage)
    {
        if (!m_masterScore) {
            errorMessage = "Editing is unavailable because the score session is closed.";
            return false;
        }

        if (keyValue < static_cast<int>(mu::engraving::Key::MIN) || keyValue > static_cast<int>(mu::engraving::Key::MAX)) {
            errorMessage = "The requested key signature is outside MuseScore's supported key range.";
            return false;
        }

        mu::engraving::KeySigEvent keyEvent;
        const mu::engraving::Key concertKey = static_cast<mu::engraving::Key>(keyValue);
        keyEvent.setConcertKey(concertKey);
        keyEvent.setKey(concertKey);

        mu::engraving::Measure* measure = activeMeasure(activeScore(), fromStart);
        if (!measure) {
            errorMessage = "Select a measure before changing the key signature.";
            return false;
        }
        const mu::engraving::Fraction tick = fromStart ? mu::engraving::Fraction(0, 1) : measure->tick();

        m_masterScore->startCmd(muse::TranslatableString::untranslatable("MuseReader change key signature"));
        for (size_t staffIndex = 0; staffIndex < m_masterScore->nstaves(); ++staffIndex) {
            mu::engraving::Staff* staff = m_masterScore->staff(staffIndex);
            if (!staff || staff->isDrumStaff(tick)) {
                continue;
            }

            m_masterScore->undoChangeKeySig(staff, tick, keyEvent);
        }
        m_masterScore->endCmd();

        for (mu::engraving::Score* score : m_masterScore->scoreList()) {
            if (!score) {
                continue;
            }

            score->setLayoutAll();
            score->doLayout();
        }

        m_masterScore->setPlaylistDirty();
        m_totalPageCount = static_cast<int>(m_masterScore->npages());
        if (m_totalPageCount <= 0) {
            errorMessage = "The edited score no longer produces any pages.";
            return false;
        }

        return true;
    }

    bool saveToPath(const std::string& targetPath, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        const std::string resolvedTargetPath = targetPath.empty() ? m_scorePath : targetPath;
        if (resolvedTargetPath.empty()) {
            errorMessage = "MuseReader does not know where to save this score.";
            return false;
        }

        const SteadyClock::time_point started = SteadyClock::now();
        std::cout << "Aria corruption guard: save begin"
                  << " path=\"" << resolvedTargetPath << "\""
                  << std::endl;
        if (blockDelayedSubsystemIfCorrupted(m_masterScore.get(), "saving/autosave", errorMessage)) {
            std::cout << "Aria corruption guard: save blocked"
                      << " elapsed=" << elapsedSecondsSince(started)
                      << "s" << std::endl;
            return false;
        }
        if (!validateMasterHarmonyRetainedBeforeSave(m_masterScore.get(), m_maxObservedMasterHarmonyCount, errorMessage)) {
            std::cout << "Aria save guard: save blocked"
                      << " elapsed=" << elapsedSecondsSince(started)
                      << "s" << std::endl;
            return false;
        }
        if (!validatePartHarmonyLinksBeforeSave(m_masterScore.get(), errorMessage)) {
            std::cout << "Aria save guard: save blocked"
                      << " elapsed=" << elapsedSecondsSince(started)
                      << "s" << std::endl;
            return false;
        }

        const bool saved = saveScoreToPath(m_sessionContext->context(), m_masterScore.get(), muse::io::path_t(resolvedTargetPath), errorMessage);
        std::cout << "Aria corruption guard: save end"
                  << " success=" << (saved ? "true" : "false")
                  << " elapsed=" << elapsedSecondsSince(started)
                  << "s" << std::endl;
        if (saved) {
            m_maxObservedMasterHarmonyCount = std::max(m_maxObservedMasterHarmonyCount, harmonyCountInScore(m_masterScore.get()));
        }
        return saved;
    }
