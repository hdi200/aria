msr::render::ScoreRenderSession::ScoreRenderSession(std::unique_ptr<Impl> impl)
    : m_impl(std::move(impl))
{
}

msr::render::ScoreRenderSession::ScoreRenderSession(ScoreRenderSession&&) noexcept = default;
msr::render::ScoreRenderSession& msr::render::ScoreRenderSession::operator=(ScoreRenderSession&&) noexcept = default;
msr::render::ScoreRenderSession::~ScoreRenderSession() = default;

std::unique_ptr<msr::render::ScoreRenderSession> msr::render::ScoreRenderSession::open(const std::string& scorePath,
                                                                                        std::string& errorMessage)
{
    ScoreRenderCore::initializeIfNeeded();

    if (!validateScorePath(scorePath, errorMessage)) {
        return nullptr;
    }

    std::unique_ptr<Impl> impl = Impl::open(scorePath, errorMessage);
    if (!impl) {
        return nullptr;
    }

    return std::unique_ptr<ScoreRenderSession>(new ScoreRenderSession(std::move(impl)));
}

int msr::render::ScoreRenderSession::totalPageCount() const
{
    return m_impl->totalPageCount();
}

bool msr::render::ScoreRenderSession::supportsPlayback() const
{
    return m_impl->supportsPlayback();
}

bool msr::render::ScoreRenderSession::supportsEditing() const
{
    return m_impl->supportsEditing();
}

bool msr::render::ScoreRenderSession::concertPitchEnabled() const
{
    return m_impl->concertPitchEnabled();
}

bool msr::render::ScoreRenderSession::hasConcertPitchRelevantTransposition() const
{
    return m_impl->hasConcertPitchRelevantTransposition();
}

std::vector<msr::render::ScorePartInfo> msr::render::ScoreRenderSession::partInfoList() const
{
    return m_impl->partInfoList();
}

bool msr::render::ScoreRenderSession::setActivePartIndex(const std::optional<int> partIndex,
                                                         int& totalPageCount,
                                                         std::string& errorMessage)
{
    return m_impl->setActivePartIndex(partIndex, totalPageCount, errorMessage);
}

bool msr::render::ScoreRenderSession::setConcertPitchEnabled(const bool enabled,
                                                             int& totalPageCount,
                                                             std::string& errorMessage)
{
    return m_impl->setConcertPitchEnabled(enabled, totalPageCount, errorMessage);
}

bool msr::render::ScoreRenderSession::renderPage(const int pageIndex,
                                                 const int dpi,
                                                 RenderedPage& output,
                                                 std::string& errorMessage) const
{
    return m_impl->renderPage(pageIndex, dpi, output, errorMessage);
}

bool msr::render::ScoreRenderSession::playbackMIDIData(std::vector<std::uint8_t>& output,
                                                       std::string& errorMessage) const
{
    return m_impl->playbackMIDIData(output, errorMessage);
}

bool msr::render::ScoreRenderSession::musicXMLData(std::vector<std::uint8_t>& output,
                                                   std::string& errorMessage) const
{
    return m_impl->musicXMLData(output, errorMessage);
}

bool msr::render::ScoreRenderSession::playbackEventAudioData(const std::string& soundFontPath,
                                                             const double startTimeSeconds,
                                                             const double durationSeconds,
                                                             const bool metronomeEnabled,
                                                             PlaybackAudioData& output,
                                                             std::string& errorMessage) const
{
    return m_impl->playbackEventAudioData(soundFontPath, startTimeSeconds, durationSeconds, metronomeEnabled, output, errorMessage);
}

bool msr::render::ScoreRenderSession::playbackTrackSummary(std::vector<PlaybackTrackSummary>& output,
                                                           std::string& errorMessage) const
{
    return m_impl->playbackTrackSummary(output, errorMessage);
}

bool msr::render::ScoreRenderSession::playbackMeasureRegions(std::vector<PlaybackMeasureRegion>& output,
                                                             std::string& errorMessage) const
{
    return m_impl->playbackMeasureRegions(output, errorMessage);
}

bool msr::render::ScoreRenderSession::scoreCorruptionReport(ScoreCorruptionReport& output, std::string& errorMessage)
{
    return m_impl->scoreCorruptionReport(output, errorMessage);
}

bool msr::render::ScoreRenderSession::selectCorruptionIssue(const int issueIndex,
                                                            ScoreEditState& output,
                                                            std::string& errorMessage)
{
    return m_impl->selectCorruptionIssue(issueIndex, output, errorMessage);
}

bool msr::render::ScoreRenderSession::clearCorruptionIssue(const int issueIndex,
                                                           ScoreEditState& output,
                                                           ScoreCorruptionReport& report,
                                                           std::string& errorMessage)
{
    return m_impl->clearCorruptionIssue(issueIndex, output, report, errorMessage);
}

bool msr::render::ScoreRenderSession::currentEditState(ScoreEditState& output, std::string& errorMessage) const
{
    return m_impl->currentEditState(output, errorMessage);
}

bool msr::render::ScoreRenderSession::selectElement(const int pageIndex,
                                                    const double normalizedX,
                                                    const double normalizedY,
                                                    const double hitRadiusScale,
                                                    ScoreEditState& output,
                                                    std::string& errorMessage)
{
    return m_impl->selectElement(pageIndex, normalizedX, normalizedY, hitRadiusScale, output, errorMessage);
}

bool msr::render::ScoreRenderSession::setNoteInputEnabled(const bool enabled,
                                                          ScoreEditState& output,
                                                          std::string& errorMessage)
{
    return m_impl->setNoteInputEnabled(enabled, output, errorMessage);
}

bool msr::render::ScoreRenderSession::setCurrentVoice(const int voice,
                                                      ScoreEditState& output,
                                                      std::string& errorMessage)
{
    return m_impl->setCurrentVoice(voice, output, errorMessage);
}

bool msr::render::ScoreRenderSession::applyDuration(const int durationCode,
                                                    ScoreEditState& output,
                                                    std::string& errorMessage)
{
    return m_impl->applyDuration(durationCode, output, errorMessage);
}

bool msr::render::ScoreRenderSession::toggleDot(ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->toggleDot(output, errorMessage);
}

bool msr::render::ScoreRenderSession::toggleRest(ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->toggleRest(output, errorMessage);
}

bool msr::render::ScoreRenderSession::toggleTie(ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->toggleTie(output, errorMessage);
}

bool msr::render::ScoreRenderSession::addTuplet(const int tupletCount, ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->addTuplet(tupletCount, output, errorMessage);
}

bool msr::render::ScoreRenderSession::addText(const std::string& textKind,
                                               ScoreEditState& output,
                                               std::string& errorMessage)
{
    return m_impl->addText(textKind, output, errorMessage);
}

bool msr::render::ScoreRenderSession::setSelectedText(const std::string& text,
                                                       ScoreEditState& output,
                                                       std::string& errorMessage)
{
    return m_impl->setSelectedText(text, output, errorMessage);
}

bool msr::render::ScoreRenderSession::addLyricsText(const std::string& text,
                                                     const bool advanceToNextChord,
                                                     ScoreEditState& output,
                                                     std::string& errorMessage)
{
    return m_impl->addLyricsText(text, advanceToNextChord, output, errorMessage);
}

bool msr::render::ScoreRenderSession::addRepeatJump(const std::string& repeatJumpKind,
                                                     ScoreEditState& output,
                                                     std::string& errorMessage)
{
    return m_impl->addRepeatJump(repeatJumpKind, output, errorMessage);
}

bool msr::render::ScoreRenderSession::addExpression(const std::string& expressionKind,
                                                    ScoreEditState& output,
                                                    std::string& errorMessage)
{
    return m_impl->addExpression(expressionKind, output, errorMessage);
}

bool msr::render::ScoreRenderSession::retargetSelectedExpressionEndpoint(const bool startEndpoint,
                                                                         const int pageIndex,
                                                                         const double normalizedX,
                                                                         const double normalizedY,
                                                                         ScoreEditState& output,
                                                                         std::string& errorMessage)
{
    return m_impl->retargetSelectedExpressionEndpoint(startEndpoint, pageIndex, normalizedX, normalizedY, output, errorMessage);
}

bool msr::render::ScoreRenderSession::dragSelectedChordText(const int pageIndex,
                                                            const double normalizedX,
                                                            const double normalizedY,
                                                            ScoreEditState& output,
                                                            std::string& errorMessage)
{
    return m_impl->dragSelectedChordText(pageIndex, normalizedX, normalizedY, output, errorMessage);
}

bool msr::render::ScoreRenderSession::addLayoutBreak(const std::string& breakKind,
                                                     ScoreEditState& output,
                                                     std::string& errorMessage)
{
    return m_impl->addLayoutBreak(breakKind, output, errorMessage);
}

bool msr::render::ScoreRenderSession::removeLayoutBreak(ScoreEditState& output,
                                                        std::string& errorMessage)
{
    return m_impl->removeLayoutBreak(output, errorMessage);
}

bool msr::render::ScoreRenderSession::fillSelectionWithSlashes(ScoreEditState& output,
                                                               std::string& errorMessage)
{
    return m_impl->fillSelectionWithSlashes(output, errorMessage);
}

bool msr::render::ScoreRenderSession::replaceSelectionWithRhythmicSlashes(ScoreEditState& output,
                                                                          std::string& errorMessage)
{
    return m_impl->replaceSelectionWithRhythmicSlashes(output, errorMessage);
}

bool msr::render::ScoreRenderSession::applyAutoSystemBreaks(const int measuresPerSystem,
                                                            const bool lockCurrentLayout,
                                                            const bool removeExisting,
                                                            ScoreEditState& output,
                                                            std::string& errorMessage)
{
    return m_impl->applyAutoSystemBreaks(measuresPerSystem, lockCurrentLayout, removeExisting, output, errorMessage);
}

bool msr::render::ScoreRenderSession::updateStaffSpacing(const double staffDistanceSpatium,
                                                         ScoreEditState& output,
                                                         std::string& errorMessage)
{
    return m_impl->updateStaffSpacing(staffDistanceSpatium, output, errorMessage);
}

bool msr::render::ScoreRenderSession::updatePageLayout(const double pageWidthMillimeters,
                                                       const double pageHeightMillimeters,
                                                       const double marginMillimeters,
                                                       const double staffSizeMillimeters,
                                                       const double systemSpacingSpatium,
                                                       ScoreEditState& output,
                                                       std::string& errorMessage)
{
    return m_impl->updatePageLayout(pageWidthMillimeters,
                                    pageHeightMillimeters,
                                    marginMillimeters,
                                    staffSizeMillimeters,
                                    systemSpacingSpatium,
                                    output,
                                    errorMessage);
}

bool msr::render::ScoreRenderSession::updateLayoutOptions(const bool createMultiMeasureRests,
                                                          const bool hideEmptyStaves,
                                                          ScoreEditState& output,
                                                          std::string& errorMessage)
{
    return m_impl->updateLayoutOptions(createMultiMeasureRests, hideEmptyStaves, output, errorMessage);
}

bool msr::render::ScoreRenderSession::addTempo(const std::string& beatUnit,
                                               const int bpm,
                                               ScoreEditState& output,
                                               std::string& errorMessage)
{
    return m_impl->addTempo(beatUnit, bpm, output, errorMessage);
}

bool msr::render::ScoreRenderSession::updateTimeSignature(const int numerator,
                                                          const int denominator,
                                                          const bool commonTime,
                                                          const bool cutTime,
                                                          const bool fromStart,
                                                          ScoreEditState& output,
                                                          std::string& errorMessage)
{
    return m_impl->updateTimeSignature(numerator, denominator, commonTime, cutTime, fromStart, output, errorMessage);
}

bool msr::render::ScoreRenderSession::updateKeySignature(const int keyValue,
                                                         const bool fromStart,
                                                         ScoreEditState& output,
                                                         std::string& errorMessage)
{
    return m_impl->updateKeySignature(keyValue, fromStart, output, errorMessage);
}

bool msr::render::ScoreRenderSession::insertNote(const int pageIndex,
                                                 const double normalizedX,
                                                 const double normalizedY,
                                                 ScoreEditState& output,
                                                 std::string& errorMessage)
{
    return m_impl->insertNote(pageIndex, normalizedX, normalizedY, output, errorMessage);
}

bool msr::render::ScoreRenderSession::insertNoteWithAccidental(const int pageIndex,
                                                               const double normalizedX,
                                                               const double normalizedY,
                                                               const int accidentalKind,
                                                               ScoreEditState& output,
                                                               std::string& errorMessage)
{
    return m_impl->insertNoteWithAccidental(pageIndex, normalizedX, normalizedY, accidentalKind, output, errorMessage);
}

bool msr::render::ScoreRenderSession::insertNoteWithPitch(const int pageIndex,
                                                          const double normalizedX,
                                                          const double normalizedY,
                                                          const int pitchClass,
                                                          const bool preferFlats,
                                                          ScoreEditState& output,
                                                          std::string& errorMessage)
{
    return m_impl->insertNoteWithPitch(pageIndex, normalizedX, normalizedY, pitchClass, preferFlats, output, errorMessage);
}

bool msr::render::ScoreRenderSession::insertPitchAtCursor(const int pitchClass,
                                                          const bool preferFlats,
                                                          const bool addToCurrentChord,
                                                          ScoreEditState& output,
                                                          std::string& errorMessage)
{
    return m_impl->insertPitchAtCursor(pitchClass, preferFlats, addToCurrentChord, output, errorMessage);
}

bool msr::render::ScoreRenderSession::noteEntryPreview(const int pageIndex,
                                                       const double normalizedX,
                                                       const double normalizedY,
                                                       const int durationCode,
                                                       const bool rest,
                                                       const int accidentalKind,
                                                       NoteEntryPreviewState& output,
                                                       std::string& errorMessage)
{
    return m_impl->noteEntryPreview(pageIndex, normalizedX, normalizedY, durationCode, rest, accidentalKind, output, errorMessage);
}

bool msr::render::ScoreRenderSession::insertMIDIPitchAtCursor(const int midiPitch,
                                                              const bool preferFlats,
                                                              const bool addToCurrentChord,
                                                              ScoreEditState& output,
                                                              std::string& errorMessage)
{
    return m_impl->insertMIDIPitchAtCursor(midiPitch, preferFlats, addToCurrentChord, output, errorMessage);
}

bool msr::render::ScoreRenderSession::deleteSelection(ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->deleteSelection(output, errorMessage);
}

bool msr::render::ScoreRenderSession::selectMeasureRange(const int pageIndex,
                                                         const double startNormalizedX,
                                                         const double startNormalizedY,
                                                         const double endNormalizedX,
                                                         const double endNormalizedY,
                                                         ScoreEditState& output,
                                                         std::string& errorMessage)
{
    return m_impl->selectMeasureRange(pageIndex, startNormalizedX, startNormalizedY, endNormalizedX, endNormalizedY, output, errorMessage);
}

bool msr::render::ScoreRenderSession::clearSelectedMeasure(ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->clearSelectedMeasure(output, errorMessage);
}

bool msr::render::ScoreRenderSession::removeSelectedMeasure(ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->removeSelectedMeasure(output, errorMessage);
}

bool msr::render::ScoreRenderSession::addMeasures(const int count, ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->addMeasures(count, output, errorMessage);
}

bool msr::render::ScoreRenderSession::setRegularMeasureCount(const int count, ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->setRegularMeasureCount(count, output, errorMessage);
}

bool msr::render::ScoreRenderSession::firstMeasurePickupState(PickupMeasureState& output, std::string& errorMessage)
{
    return m_impl->firstMeasurePickupState(output, errorMessage);
}

bool msr::render::ScoreRenderSession::setFirstMeasurePickup(const int numerator, const int denominator, ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->setFirstMeasurePickup(numerator, denominator, output, errorMessage);
}

bool msr::render::ScoreRenderSession::createFirstPickupMeasure(const int numerator, const int denominator, ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->createFirstPickupMeasure(numerator, denominator, output, errorMessage);
}

bool msr::render::ScoreRenderSession::clearFirstMeasurePickup(ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->clearFirstMeasurePickup(output, errorMessage);
}

bool msr::render::ScoreRenderSession::copySelectedMeasureRange(ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->copySelectedMeasureRange(output, errorMessage);
}

bool msr::render::ScoreRenderSession::cutSelectedMeasureRange(ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->cutSelectedMeasureRange(output, errorMessage);
}

bool msr::render::ScoreRenderSession::pasteMeasureRange(ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->pasteMeasureRange(output, errorMessage);
}

bool msr::render::ScoreRenderSession::transposeSelectedMeasureRange(const int mode,
                                                                    const int direction,
                                                                    const int interval,
                                                                    const int targetKey,
                                                                    ScoreEditState& output,
                                                                    std::string& errorMessage)
{
    return m_impl->transposeSelectedMeasureRange(mode, direction, interval, targetKey, output, errorMessage);
}

bool msr::render::ScoreRenderSession::moveSelectionPitch(const bool up,
                                                        ScoreEditState& output,
                                                        std::string& errorMessage)
{
    return m_impl->moveSelectionPitch(up, output, errorMessage);
}

bool msr::render::ScoreRenderSession::shiftSelectionPitchBySemitones(const int semitoneDelta,
                                                                     ScoreEditState& output,
                                                                     std::string& errorMessage)
{
    return m_impl->shiftSelectionPitchBySemitones(semitoneDelta, output, errorMessage);
}

bool msr::render::ScoreRenderSession::shiftSelectionPitchByOctaves(const int octaveDelta,
                                                                   ScoreEditState& output,
                                                                   std::string& errorMessage)
{
    return m_impl->shiftSelectionPitchByOctaves(octaveDelta, output, errorMessage);
}

bool msr::render::ScoreRenderSession::setSelectionPitchClass(const int pitchClass,
                                                             const bool preferFlats,
                                                             ScoreEditState& output,
                                                             std::string& errorMessage)
{
    return m_impl->setSelectionPitchClass(pitchClass, preferFlats, output, errorMessage);
}

bool msr::render::ScoreRenderSession::setSelectionMIDIPitch(const int midiPitch,
                                                            const bool preferFlats,
                                                            ScoreEditState& output,
                                                            std::string& errorMessage)
{
    return m_impl->setSelectionMIDIPitch(midiPitch, preferFlats, output, errorMessage);
}

bool msr::render::ScoreRenderSession::setSelectionPitchAtPagePosition(const int pageIndex,
                                                                      const double normalizedX,
                                                                      const double normalizedY,
                                                                      ScoreEditState& output,
                                                                      std::string& errorMessage)
{
    return m_impl->setSelectionPitchAtPagePosition(pageIndex, normalizedX, normalizedY, output, errorMessage);
}

bool msr::render::ScoreRenderSession::selectAdjacentElement(const bool next,
                                                           ScoreEditState& output,
                                                           std::string& errorMessage)
{
    return m_impl->selectAdjacentElement(next, output, errorMessage);
}

bool msr::render::ScoreRenderSession::undo(ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->undo(output, errorMessage);
}

bool msr::render::ScoreRenderSession::redo(ScoreEditState& output, std::string& errorMessage)
{
    return m_impl->redo(output, errorMessage);
}

bool msr::render::ScoreRenderSession::replaceInstruments(const std::vector<std::string>& instrumentIds,
                                                         ScoreEditState& output,
                                                         std::string& errorMessage)
{
    return m_impl->replaceInstruments(instrumentIds, output, errorMessage);
}

bool msr::render::ScoreRenderSession::addInstrument(const std::string& instrumentId,
                                                    ScoreEditState& output,
                                                    std::string& errorMessage)
{
    return m_impl->addInstrument(instrumentId, output, errorMessage);
}

bool msr::render::ScoreRenderSession::removeSelectedInstrument(ScoreEditState& output,
                                                               std::string& errorMessage)
{
    return m_impl->removeSelectedInstrument(output, errorMessage);
}

bool msr::render::ScoreRenderSession::removeInstrumentAtIndex(int partIndex,
                                                              ScoreEditState& output,
                                                              std::string& errorMessage)
{
    return m_impl->removeInstrumentAtIndex(partIndex, output, errorMessage);
}

bool msr::render::ScoreRenderSession::moveInstrument(int sourceIndex,
                                                     int destinationIndex,
                                                     ScoreEditState& output,
                                                     std::string& errorMessage)
{
    return m_impl->moveInstrument(sourceIndex, destinationIndex, output, errorMessage);
}

bool msr::render::ScoreRenderSession::changeClef(const std::string& clefKind,
                                                 ScoreEditState& output,
                                                 std::string& errorMessage)
{
    return m_impl->changeClef(clefKind, output, errorMessage);
}

bool msr::render::ScoreRenderSession::updateMetadata(const ScoreMetadata& metadata,
                                                     std::string& errorMessage)
{
    return m_impl->updateMetadata(metadata, errorMessage);
}

bool msr::render::ScoreRenderSession::updateInitialKeySignature(const int keyValue,
                                                                std::string& errorMessage)
{
    return m_impl->updateInitialKeySignature(keyValue, errorMessage);
}

bool msr::render::ScoreRenderSession::save(std::string& errorMessage)
{
    return m_impl->saveToPath("", errorMessage);
}

bool msr::render::ScoreRenderSession::saveToPath(const std::string& targetPath, std::string& errorMessage)
{
    return m_impl->saveToPath(targetPath, errorMessage);
}

void msr::render::ScoreRenderCore::initializeIfNeeded()
{
    RenderRuntime::initializeIfNeeded();
}

bool msr::render::ScoreRenderCore::renderDocument(const RenderRequest& request,
                                                  RenderedDocument& output,
                                                  std::string& errorMessage)
{
    if (!validateScorePath(request.scorePath, errorMessage) || !validateDpi(request.dpi, errorMessage)) {
        return false;
    }

    std::unique_ptr<ScoreRenderSession> session = ScoreRenderSession::open(request.scorePath, errorMessage);
    if (!session) {
        return false;
    }

    output.totalPageCount = session->totalPageCount();

    const int firstPage = request.fromPage.value_or(0);
    const int lastPage = request.toPage.value_or(output.totalPageCount - 1);
    if (firstPage < 0 || lastPage >= output.totalPageCount || firstPage > lastPage) {
        errorMessage = "The requested page range is outside the rendered score.";
        return false;
    }

    output.pages.clear();
    output.pages.reserve(static_cast<size_t>(lastPage - firstPage + 1));

    for (int pageIndex = firstPage; pageIndex <= lastPage; ++pageIndex) {
        RenderedPage page;
        if (!session->renderPage(pageIndex, request.dpi, page, errorMessage)) {
            return false;
        }
        output.pages.push_back(std::move(page));
    }

    return true;
}
