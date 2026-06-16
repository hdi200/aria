#pragma once

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace msr::render {

struct RenderRequest {
    std::string scorePath;
    int dpi = 144;
    std::optional<int> fromPage;
    std::optional<int> toPage;
};

struct RenderedPage {
    int pageIndex = 0;
    int pixelWidth = 0;
    int pixelHeight = 0;
    std::vector<std::uint8_t> pngData;
};

struct RenderedDocument {
    int totalPageCount = 0;
    std::vector<RenderedPage> pages;
};

struct PlaybackMeasureRegion {
    int measureIndex = 0;
    int pageIndex = 0;
    double startTimeSeconds = 0.0;
    double endTimeSeconds = 0.0;
    double normalizedX = 0.0;
    double normalizedY = 0.0;
    double normalizedWidth = 0.0;
    double normalizedHeight = 0.0;
};

struct NormalizedSelectionRect {
    double normalizedX = 0.0;
    double normalizedY = 0.0;
    double normalizedWidth = 0.0;
    double normalizedHeight = 0.0;
};

struct NormalizedPoint {
    double normalizedX = 0.0;
    double normalizedY = 0.0;
};

struct ScoreMetadata {
    std::string title;
    std::string subtitle;
    std::string composer;
    std::string lyricist;
    std::string arranger;
};

struct ScoreSelectionState {
    bool hasSelection = false;
    bool isNote = false;
    bool isRest = false;
    bool isBar = false;
    bool isMeasure = false;
    bool isSingleMeasure = false;
    bool isFirstMeasure = false;
    bool isPickupMeasure = false;
    int pickupActualNumerator = 0;
    int pickupActualDenominator = 0;
    int pickupNominalNumerator = 0;
    int pickupNominalDenominator = 0;
    bool isTimeSignature = false;
    bool isKeySignature = false;
    bool isTempo = false;
    bool isExpressionSpanner = false;
    bool isSlur = false;
    bool isHairpin = false;
    bool isEditableText = false;
    bool isChordText = false;
    bool canChangePitch = false;
    bool canFillWithSlashes = false;
    bool isDotted = false;
    bool isTiedForward = false;
    std::string textContent;
    std::string textKind;
    int midiPitch = -1;
    std::vector<int> chordMidiPitches;
    int playbackBank = 0;
    int playbackProgram = 0;
    std::string playbackSetupData;
    bool supportsBowingArticulations = false;
    int durationCode = 4;
    int accidentalKind = -1;
    int diatonicStep = -1;
    int currentKey = 0;
    int pageIndex = -1;
    double normalizedX = 0.0;
    double normalizedY = 0.0;
    double normalizedWidth = 0.0;
    double normalizedHeight = 0.0;
    double actionNormalizedX = 0.0;
    double actionNormalizedY = 0.0;
    double actionNormalizedWidth = 0.0;
    double actionNormalizedHeight = 0.0;
    double startHandleNormalizedX = 0.0;
    double startHandleNormalizedY = 0.0;
    double endHandleNormalizedX = 0.0;
    double endHandleNormalizedY = 0.0;
    bool hasAttachmentPoint = false;
    double attachmentNormalizedX = 0.0;
    double attachmentNormalizedY = 0.0;
    std::vector<NormalizedPoint> attachmentTargets;
    std::vector<NormalizedSelectionRect> highlightRects;
    double overlayNormalizedX = 0.0;
    double overlayNormalizedY = 0.0;
    double overlayNormalizedWidth = 0.0;
    double overlayNormalizedHeight = 0.0;
    int overlayPixelWidth = 0;
    int overlayPixelHeight = 0;
    std::vector<std::uint8_t> overlayPngData;
};

struct NoteEntryPreviewState {
    bool hasPreview = false;
    int pageIndex = -1;
    double overlayNormalizedX = 0.0;
    double overlayNormalizedY = 0.0;
    double overlayNormalizedWidth = 0.0;
    double overlayNormalizedHeight = 0.0;
    int overlayPixelWidth = 0;
    int overlayPixelHeight = 0;
    std::vector<std::uint8_t> overlayPngData;
};

struct ScoreEditState {
    ScoreSelectionState selection;
    bool noteInputEnabled = false;
    bool noteInputInsertsRests = false;
    bool noteInputIsDotted = false;
    int durationCode = 4;
    int currentVoice = 0;
    bool canUndo = false;
    bool canRedo = false;
    bool activeStaffIsPercussion = false;
    bool createMultiMeasureRests = false;
    bool hideEmptyStaves = false;
};

struct ScoreCorruptionIssue {
    int scoreIndex = 0;
    bool fullScore = true;
    int measureNumber = 0;
    int staffIndex = 0;
    int voice = 0;
    bool repairable = true;
    std::string kind;
    std::string message;
};

struct ScoreCorruptionReport {
    bool corrupted = false;
    std::string details;
    std::vector<ScoreCorruptionIssue> issues;
};

struct PlaybackAudioData {
    int sampleRate = 48000;
    int channelCount = 2;
    double durationSeconds = 0.0;
    std::vector<float> interleavedSamples;
};

struct PlaybackTrackSummary {
    std::string partId;
    std::string instrumentId;
    std::string setupData;
    int eventCount = 0;
    int noteEventCount = 0;
    int controllerEventCount = 0;
    int soundPresetEventCount = 0;
    double firstTimestampSeconds = 0.0;
    double lastTimestampSeconds = 0.0;
};

struct ScorePartInfo {
    int index = 0;
    std::string partId;
    std::string name;
};

struct PickupMeasureState {
    bool isPickup = false;
    int actualNumerator = 0;
    int actualDenominator = 0;
    int nominalNumerator = 0;
    int nominalDenominator = 0;
};

class ScoreRenderSession
{
public:
    static std::unique_ptr<ScoreRenderSession> open(const std::string& scorePath, std::string& errorMessage);

    ScoreRenderSession(ScoreRenderSession&&) noexcept;
    ScoreRenderSession& operator=(ScoreRenderSession&&) noexcept;
    ~ScoreRenderSession();

    int totalPageCount() const;
    bool supportsPlayback() const;
    bool supportsEditing() const;
    bool concertPitchEnabled() const;
    bool hasConcertPitchRelevantTransposition() const;
    std::vector<ScorePartInfo> partInfoList() const;
    bool setActivePartIndex(std::optional<int> partIndex, int& totalPageCount, std::string& errorMessage);
    bool setConcertPitchEnabled(bool enabled, int& totalPageCount, std::string& errorMessage);
    bool renderPage(int pageIndex, int dpi, RenderedPage& output, std::string& errorMessage) const;
    bool playbackMIDIData(std::vector<std::uint8_t>& output, std::string& errorMessage) const;
    bool musicXMLData(std::vector<std::uint8_t>& output, std::string& errorMessage) const;
    bool playbackEventAudioData(const std::string& soundFontPath,
                                double startTimeSeconds,
                                double durationSeconds,
                                bool metronomeEnabled,
                                PlaybackAudioData& output,
                                std::string& errorMessage) const;
    bool playbackTrackSummary(std::vector<PlaybackTrackSummary>& output, std::string& errorMessage) const;
    bool playbackMeasureRegions(std::vector<PlaybackMeasureRegion>& output, std::string& errorMessage) const;
    bool scoreCorruptionReport(ScoreCorruptionReport& output, std::string& errorMessage);
    bool selectCorruptionIssue(int issueIndex, ScoreEditState& output, std::string& errorMessage);
    bool clearCorruptionIssue(int issueIndex, ScoreEditState& output, ScoreCorruptionReport& report, std::string& errorMessage);
    bool currentEditState(ScoreEditState& output, std::string& errorMessage) const;
    bool selectElement(int pageIndex, double normalizedX, double normalizedY, double hitRadiusScale, ScoreEditState& output, std::string& errorMessage);
    bool setNoteInputEnabled(bool enabled, ScoreEditState& output, std::string& errorMessage);
    bool setCurrentVoice(int voice, ScoreEditState& output, std::string& errorMessage);
    bool applyDuration(int durationCode, ScoreEditState& output, std::string& errorMessage);
    bool toggleDot(ScoreEditState& output, std::string& errorMessage);
    bool toggleRest(ScoreEditState& output, std::string& errorMessage);
    bool toggleTie(ScoreEditState& output, std::string& errorMessage);
    bool addTuplet(int tupletCount, ScoreEditState& output, std::string& errorMessage);
    bool addText(const std::string& textKind, ScoreEditState& output, std::string& errorMessage);
    bool setSelectedText(const std::string& text, ScoreEditState& output, std::string& errorMessage);
    bool addLyricsText(const std::string& text, bool advanceToNextChord, ScoreEditState& output, std::string& errorMessage);
    bool addRepeatJump(const std::string& repeatJumpKind, ScoreEditState& output, std::string& errorMessage);
    bool addExpression(const std::string& expressionKind, ScoreEditState& output, std::string& errorMessage);
    bool retargetSelectedExpressionEndpoint(bool startEndpoint, int pageIndex, double normalizedX, double normalizedY, ScoreEditState& output, std::string& errorMessage);
    bool dragSelectedChordText(int pageIndex, double normalizedX, double normalizedY, ScoreEditState& output, std::string& errorMessage);
    bool addLayoutBreak(const std::string& breakKind, ScoreEditState& output, std::string& errorMessage);
    bool removeLayoutBreak(ScoreEditState& output, std::string& errorMessage);
    bool fillSelectionWithSlashes(ScoreEditState& output, std::string& errorMessage);
    bool replaceSelectionWithRhythmicSlashes(ScoreEditState& output, std::string& errorMessage);
    bool applyAutoSystemBreaks(int measuresPerSystem,
                               bool lockCurrentLayout,
                               bool removeExisting,
                               ScoreEditState& output,
                               std::string& errorMessage);
    bool updateStaffSpacing(double staffDistanceSpatium, ScoreEditState& output, std::string& errorMessage);
    bool updatePageLayout(double pageWidthMillimeters,
                          double pageHeightMillimeters,
                          double marginMillimeters,
                          double staffSizeMillimeters,
                          double systemSpacingSpatium,
                          ScoreEditState& output,
                          std::string& errorMessage);
    bool updateLayoutOptions(bool createMultiMeasureRests,
                             bool hideEmptyStaves,
                             ScoreEditState& output,
                             std::string& errorMessage);
    bool addTempo(const std::string& beatUnit, int bpm, ScoreEditState& output, std::string& errorMessage);
    bool updateTimeSignature(int numerator, int denominator, bool commonTime, bool cutTime, bool fromStart, ScoreEditState& output, std::string& errorMessage);
    bool updateKeySignature(int keyValue, bool fromStart, ScoreEditState& output, std::string& errorMessage);
    bool insertNote(int pageIndex, double normalizedX, double normalizedY, ScoreEditState& output, std::string& errorMessage);
    bool insertNoteWithAccidental(int pageIndex, double normalizedX, double normalizedY, int accidentalKind, ScoreEditState& output, std::string& errorMessage);
    bool insertNoteWithPitch(int pageIndex, double normalizedX, double normalizedY, int pitchClass, bool preferFlats, ScoreEditState& output, std::string& errorMessage);
    bool noteEntryPreview(int pageIndex, double normalizedX, double normalizedY, int durationCode, bool rest, int accidentalKind, NoteEntryPreviewState& output, std::string& errorMessage);
    bool insertPitchAtCursor(int pitchClass, bool preferFlats, bool addToCurrentChord, ScoreEditState& output, std::string& errorMessage);
    bool insertMIDIPitchAtCursor(int midiPitch, bool preferFlats, bool addToCurrentChord, ScoreEditState& output, std::string& errorMessage);
    bool insertMIDIChordAtCursor(const std::vector<int>& midiPitches, bool preferFlats, ScoreEditState& output, std::string& errorMessage);
    bool deleteSelection(ScoreEditState& output, std::string& errorMessage);
    bool selectMeasureRange(int pageIndex, double startNormalizedX, double startNormalizedY, double endNormalizedX, double endNormalizedY, ScoreEditState& output, std::string& errorMessage);
    bool clearSelectedMeasure(ScoreEditState& output, std::string& errorMessage);
    bool removeSelectedMeasure(ScoreEditState& output, std::string& errorMessage);
    bool addMeasures(int count, ScoreEditState& output, std::string& errorMessage);
    bool setRegularMeasureCount(int count, ScoreEditState& output, std::string& errorMessage);
    bool firstMeasurePickupState(PickupMeasureState& output, std::string& errorMessage);
    bool setFirstMeasurePickup(int numerator, int denominator, ScoreEditState& output, std::string& errorMessage);
    bool createFirstPickupMeasure(int numerator, int denominator, ScoreEditState& output, std::string& errorMessage);
    bool clearFirstMeasurePickup(ScoreEditState& output, std::string& errorMessage);
    bool copySelectedMeasureRange(ScoreEditState& output, std::string& errorMessage);
    bool cutSelectedMeasureRange(ScoreEditState& output, std::string& errorMessage);
    bool pasteMeasureRange(ScoreEditState& output, std::string& errorMessage);
    bool transposeSelectedMeasureRange(int mode, int direction, int interval, int targetKey, ScoreEditState& output, std::string& errorMessage);
    bool moveSelectionPitch(bool up, ScoreEditState& output, std::string& errorMessage);
    bool shiftSelectionPitchBySemitones(int semitoneDelta, ScoreEditState& output, std::string& errorMessage);
    bool shiftSelectionPitchByOctaves(int octaveDelta, ScoreEditState& output, std::string& errorMessage);
    bool setSelectionPitchClass(int pitchClass, bool preferFlats, ScoreEditState& output, std::string& errorMessage);
    bool setSelectionMIDIPitch(int midiPitch, bool preferFlats, ScoreEditState& output, std::string& errorMessage);
    bool setSelectionPitchAtPagePosition(int pageIndex, double normalizedX, double normalizedY, ScoreEditState& output, std::string& errorMessage);
    bool selectAdjacentElement(bool next, ScoreEditState& output, std::string& errorMessage);
    bool undo(ScoreEditState& output, std::string& errorMessage);
    bool redo(ScoreEditState& output, std::string& errorMessage);
    bool replaceInstruments(const std::vector<std::string>& instrumentIds, ScoreEditState& output, std::string& errorMessage);
    bool addInstrument(const std::string& instrumentId, ScoreEditState& output, std::string& errorMessage);
    bool removeInstrumentAtIndex(int partIndex, ScoreEditState& output, std::string& errorMessage);
    bool moveInstrument(int sourceIndex, int destinationIndex, ScoreEditState& output, std::string& errorMessage);
    bool removeSelectedInstrument(ScoreEditState& output, std::string& errorMessage);
    bool changeClef(const std::string& clefKind, ScoreEditState& output, std::string& errorMessage);
    bool updateMetadata(const ScoreMetadata& metadata, std::string& errorMessage);
    bool updateInitialKeySignature(int keyValue, std::string& errorMessage);
    bool save(std::string& errorMessage);
    bool saveToPath(const std::string& targetPath, std::string& errorMessage);

private:
    class Impl;

    explicit ScoreRenderSession(std::unique_ptr<Impl> impl);

    ScoreRenderSession(const ScoreRenderSession&) = delete;
    ScoreRenderSession& operator=(const ScoreRenderSession&) = delete;

    std::unique_ptr<Impl> m_impl;
};

class ScoreRenderCore
{
public:
    // Must be called on the main thread the first time the render core is used.
    static void initializeIfNeeded();

    static bool renderDocument(const RenderRequest& request, RenderedDocument& output, std::string& errorMessage);
};

} // namespace msr::render
