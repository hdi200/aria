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

        std::unordered_map<mu::engraving::Score*, mu::engraving::LayoutMode> persistedLayoutModes;

        // MuseReader presents and exports physical pages. A MuseScore file can
        // persist the editor's continuous/linear view as <layoutMode>line</layoutMode>;
        // preserving that transient desktop view here turns an entire score into
        // one extremely wide "page" and makes PDF export do the same. Normalize
        // every loaded score (master and existing excerpts) to page layout before
        // the first render, while remembering the mode so save can preserve the
        // user's preferred desktop view.
        for (mu::engraving::Score* score : masterScore->scoreList()) {
            persistedLayoutModes.emplace(score, score->layoutMode());
            score->setLayoutMode(mu::engraving::LayoutMode::PAGE);
            score->doLayout();
        }

        masterScore->setPlaylistDirty();

        const int totalPageCount = static_cast<int>(masterScore->npages());
        if (totalPageCount == 0) {
            errorMessage = "The score loaded, but produced no pages.";
            return nullptr;
        }

        return std::unique_ptr<Impl>(
            new Impl(std::move(sessionContext),
                     std::move(masterScore),
                     scorePath,
                     totalPageCount,
                     sourceHarmonyCount,
                     std::move(persistedLayoutModes))
        );
    }

    Impl(std::unique_ptr<SessionContext> sessionContext,
         std::unique_ptr<mu::engraving::MasterScore> masterScore,
         const std::string& scorePath,
         const int totalPageCount,
         const int sourceHarmonyCount,
         std::unordered_map<mu::engraving::Score*, mu::engraving::LayoutMode> persistedLayoutModes)
        : m_sessionContext(std::move(sessionContext)),
          m_masterScore(std::move(masterScore)),
          m_scorePath(scorePath),
          m_totalPageCount(totalPageCount),
          m_persistedLayoutModes(std::move(persistedLayoutModes))
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

    int scoreStartKey() const
    {
        const mu::engraving::Score* score = m_masterScore.get();
        return currentKeyForSelection(score, score ? score->firstMeasure() : nullptr, 0);
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

        // Part selection belongs to the source score. The caller can reapply a
        // temporary viewing key after the requested source part is active.
        discardViewTranspose();

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

    bool setViewTransposeKey(const int targetKey, int& totalPageCount, std::string& errorMessage)
    {
        if (!m_masterScore) {
            errorMessage = "The MuseScore render session is no longer available.";
            return false;
        }

        const mu::engraving::Key key = static_cast<mu::engraving::Key>(targetKey);
        if (key < mu::engraving::Key::MIN || key > mu::engraving::Key::MAX) {
            errorMessage = "The requested viewing key is unsupported.";
            return false;
        }

        std::unique_ptr<mu::engraving::MasterScore> transposedMasterScore(m_masterScore->clone());
        if (!transposedMasterScore || !transposedMasterScore->firstMeasure() || transposedMasterScore->nstaves() == 0) {
            errorMessage = "MuseScore could not create a temporary score view.";
            return false;
        }

        transposedMasterScore->cmdSelectAll();
        transposedMasterScore->startCmd(muse::TranslatableString::untranslatable("MuseReader temporary view transpose"));
        const bool transposed = mu::engraving::Transpose::transpose(
            transposedMasterScore.get(),
            mu::engraving::TransposeMode::TO_KEY,
            mu::engraving::TransposeDirection::CLOSEST,
            key,
            0,
            true,
            true,
            true
        );
        if (!transposed) {
            transposedMasterScore->endCmd(true);
            errorMessage = "MuseScore could not transpose the temporary score view.";
            return false;
        }
        transposedMasterScore->endCmd();
        transposedMasterScore->deselectAll();
        transposedMasterScore->setLayoutAll();
        transposedMasterScore->doLayout();

        mu::engraving::Score* transposedActiveScore = transposedMasterScore.get();
        if (m_activePartIndex.has_value()) {
            const std::vector<mu::engraving::Part*>& parts = transposedMasterScore->parts();
            if (*m_activePartIndex < 0 || *m_activePartIndex >= static_cast<int>(parts.size())) {
                errorMessage = "The active part is unavailable in the temporary score view.";
                return false;
            }

            mu::engraving::Part* part = parts.at(static_cast<size_t>(*m_activePartIndex));
            mu::engraving::Excerpt* excerpt = nullptr;
            for (mu::engraving::Excerpt* candidate : transposedMasterScore->excerpts()) {
                if (candidate && candidate->initialPartId() == part->id()) {
                    excerpt = candidate;
                    break;
                }
            }
            if (!excerpt) {
                std::vector<mu::engraving::Excerpt*> createdExcerpts
                    = mu::engraving::Excerpt::createExcerptsFromParts({ part }, transposedMasterScore.get());
                if (createdExcerpts.empty()) {
                    errorMessage = "MuseScore could not create the temporary part view.";
                    return false;
                }
                excerpt = createdExcerpts.front();
                transposedMasterScore->initAndAddExcerpt(excerpt, true);
            } else {
                transposedMasterScore->initExcerpt(excerpt);
            }

            transposedActiveScore = excerpt->excerptScore();
            if (!transposedActiveScore) {
                errorMessage = "MuseScore created the temporary part, but it produced no score.";
                return false;
            }
            transposedActiveScore->setLayoutAll();
            transposedActiveScore->doLayout();
        }

        const int transposedPageCount = static_cast<int>(transposedActiveScore->npages());
        if (transposedPageCount <= 0) {
            errorMessage = "The temporary transposed view produced no pages.";
            return false;
        }

        m_playbackStream.reset();
        ++m_playbackStreamRevision;
        m_viewTransposeActiveScore = nullptr;
        m_viewTransposeMasterScore = std::move(transposedMasterScore);
        m_viewTransposeActiveScore = transposedActiveScore;
        m_totalPageCount = transposedPageCount;
        totalPageCount = transposedPageCount;
        return true;
    }

    bool clearViewTranspose(int& totalPageCount, std::string& errorMessage)
    {
        if (!m_masterScore) {
            errorMessage = "The MuseScore render session is no longer available.";
            return false;
        }

        discardViewTranspose();
        totalPageCount = activePageCount();
        if (totalPageCount <= 0) {
            errorMessage = "The score view produced no pages.";
            return false;
        }
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

        mu::engraving::MasterScore* masterScore = m_masterScore.get();

        //! NOTE Start from the existing tags so unrelated ones (creationDate, source, ...)
        //! survive, then replace the five the Score Setup sheet owns.
        std::map<muse::String, muse::String> tags = masterScore->metaTags();
        tags[u"workTitle"] = muse::String::fromQString(title);
        tags[u"subtitle"] = muse::String::fromQString(subtitle);
        tags[u"composer"] = muse::String::fromQString(composer);
        tags[u"lyricist"] = muse::String::fromQString(lyricist);
        tags[u"arranger"] = muse::String::fromQString(arranger);

        //! NOTE Everything below must sit inside one undo macro. Without it the meta tag and
        //! title-frame writes bypass the undo stack entirely (UndoStack::pushAndPerform just
        //! performs and deletes commands when no macro is active), which leaves the previous
        //! macro on top of the stack: a single undo then jumps past this change and restores
        //! the value from before the *earlier* edit.
        masterScore->startCmd(muse::TranslatableString::untranslatable("MuseReader edit score details"));

        if (tags != masterScore->metaTags()) {
            masterScore->undo(new mu::engraving::ChangeMetaTags(masterScore, tags));
        }

        setStyledMetadataText(masterScore, mu::engraving::TextStyleType::TITLE, title);
        setStyledMetadataText(masterScore, mu::engraving::TextStyleType::SUBTITLE, subtitle);
        setStyledMetadataText(masterScore, mu::engraving::TextStyleType::COMPOSER, composer);
        setStyledMetadataText(masterScore, mu::engraving::TextStyleType::LYRICIST, lyricist);

        masterScore->endCmd();

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

        // Layout mode is editor-view metadata in MuseScore files. Serialize the
        // modes that were loaded from disk, then immediately restore Aria's page
        // presentation without relayout so rendering and PDF export stay paged.
        std::vector<std::pair<mu::engraving::Score*, mu::engraving::LayoutMode> > presentationLayoutModes;
        for (mu::engraving::Score* score : m_masterScore->scoreList()) {
            const auto persisted = m_persistedLayoutModes.find(score);
            if (!score || persisted == m_persistedLayoutModes.end() || score->layoutMode() == persisted->second) {
                continue;
            }
            presentationLayoutModes.emplace_back(score, score->layoutMode());
            score->setLayoutMode(persisted->second);
        }

        const bool saved = saveScoreToPath(
            m_sessionContext->context(),
            m_masterScore.get(),
            muse::io::path_t(m_scorePath),
            muse::io::path_t(resolvedTargetPath),
            errorMessage
        );
        for (const auto& [score, presentationMode] : presentationLayoutModes) {
            score->setLayoutMode(presentationMode);
        }
        std::cout << "Aria corruption guard: save end"
                  << " success=" << (saved ? "true" : "false")
                  << " elapsed=" << elapsedSecondsSince(started)
                  << "s" << std::endl;
        if (saved) {
            m_maxObservedMasterHarmonyCount = std::max(m_maxObservedMasterHarmonyCount, harmonyCountInScore(m_masterScore.get()));
        }
        return saved;
    }
