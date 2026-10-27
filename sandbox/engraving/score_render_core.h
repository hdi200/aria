#pragma once

#include <atomic>
#include <map>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace msr::render {

//! FluidSynth is built with MuseScore's -DNO_THREADS, so its own mutexes are no-ops and
//! every synth in the process shares one unguarded sample cache. Hold this lock around
//! anything that can load or unload samples: creating or deleting a synth, loading a
//! SoundFont, program changes, note calls and rendering (a finished voice can unload
//! its samples).
std::recursive_timed_mutex& fluidSynthLock();

//! Real-time threads (Android's audio callback) waiting for fluidSynthLock(). Holders
//! that take the lock repeatedly, such as one render block at a time, wait while this
//! is above zero, so a waiting audio callback gets in within one block.
std::atomic<int>& fluidSynthRealtimeWaiters();
void yieldFluidSynthLockToRealtime();

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
    std::vector<std::uint8_t> pdfData;
    struct LayoutBreakMarker {
        std::string kind;
        double normalizedX = 0.0;
        double normalizedY = 0.0;
        double normalizedWidth = 0.0;
        double normalizedHeight = 0.0;
    };
    std::vector<LayoutBreakMarker> layoutBreakMarkers;
};

struct RenderedDocument {
    int totalPageCount = 0;
    std::vector<RenderedPage> pages;
};

struct PlaybackMeasureRegion {
    std::string measureEid;
    int measureIndex = 0;
    int pageIndex = 0;
    double startTimeSeconds = 0.0;
    double endTimeSeconds = 0.0;
    double normalizedX = 0.0;
    double normalizedY = 0.0;
    double normalizedWidth = 0.0;
    double normalizedHeight = 0.0;
};

//! A moment of playback on the page: a beat, or the end of a stretch that
//! plays straight through. Points follow playback order.
struct PlaybackBeatPoint {
    int pageIndex = 0;
    double timeSeconds = 0.0;
    double normalizedX = 0.0;
    //! The first point after a repeat or jump, where playback leaves the line.
    bool startsSegment = false;
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
    std::string titleFontFamily;
    std::string composerFontFamily;
    bool titleFontBold = false;
    bool titleFontItalic = false;
    bool composerFontBold = false;
    bool composerFontItalic = false;
};

struct PageSelectionRect {
    int pageIndex = 0;
    NormalizedSelectionRect rect;
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
    int currentTimeSignatureNumerator = 4;
    int currentTimeSignatureDenominator = 4;
    bool isTimeSignature = false;
    bool isKeySignature = false;
    bool isTempo = false;
    bool isLayoutBreak = false;
    std::string layoutBreakType;
    bool isExpressionSpanner = false;
    bool isSlur = false;
    bool isTie = false;
    bool isHairpin = false;
    bool isInstrumentName = false;
    bool isInstrumentChange = false;
    bool isEditableText = false;
    bool isChordText = false;
    bool canDragMovableElement = false;
    bool canChangePitch = false;
    bool canFillWithSlashes = false;
    bool isDotted = false;
    bool isTiedForward = false;
    std::string textContent;
    std::string textKind;
    std::string partId;
    std::string instrumentId;
    std::string instrumentName;
    int measureIndex = -1;
    int64_t tick = -1;
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
    // Range highlights on pages after pageIndex, for ranges that cross a page break.
    std::vector<PageSelectionRect> otherPageHighlightRects;
    double overlayNormalizedX = 0.0;
    double overlayNormalizedY = 0.0;
    double overlayNormalizedWidth = 0.0;
    double overlayNormalizedHeight = 0.0;
    int overlayPixelWidth = 0;
    int overlayPixelHeight = 0;
    std::vector<std::uint8_t> overlayPngData;
    std::vector<std::uint8_t> overlayPdfData;
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
    double pageWidthMillimeters = 210.0;
    double pageHeightMillimeters = 297.0;
    double pageMarginMillimeters = 15.0;
    double staffSizeMillimeters = 1.75;
    double staffSpacingSpatium = 6.5;
    double systemSpacingSpatium = 8.5;
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

struct ScoreLegacyRepairIssue {
    int index = 0;
    int measureNumber = 0;
    int staffIndex = 0;
    std::string kind;
    std::string location;
    std::string message;
};

struct PlaybackAudioData {
    int sampleRate = 48000;
    int channelCount = 2;
    double durationSeconds = 0.0;
    std::vector<float> interleavedSamples;
    // Stereo stems share the mixed buffer's sample rate, frame count and start time.
    // Numeric master-part IDs; "metronome" is independent of part solo/mute.
    std::map<std::string, std::vector<float>> partSamples;
};

struct PlaybackCountInClick {
    //! Seconds from the start of the count-in.
    double timeSeconds = 0.0;
    //! Beat within the bar, from 1.
    int beatNumber = 1;
    bool isDownbeat = false;
};

//! The clicks played before playback starts. Playback begins `durationSeconds`
//! after the first click; `audio` runs a little longer so the last click rings.
struct PlaybackCountIn {
    PlaybackAudioData audio;
    double durationSeconds = 0.0;
    std::vector<PlaybackCountInClick> clicks;
};

//! One sounding note, timed exactly as the playback audio plays it.
struct PlaybackNote {
    int pitch = 60;
    double startTimeSeconds = 0.0;
    double endTimeSeconds = 0.0;
    //! The staff that plays it, numbered from 0 in score order among the
    //! staves that sound. A piano's two hands are two staves.
    int staffIndex = 0;
    std::string partId;
};

struct PlaybackPartMix {
    float volume = 1.0f;
    float pan = 0.0f;
    bool muted = false;
    bool solo = false;
};

using PlaybackMix = std::map<std::string, PlaybackPartMix>;

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
    bool visible = true;
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
    //! Lays the displayed score out as one continuous line (one wide page), or
    //! back to pages. Used for video export; saving is unaffected.
    bool setContinuousLayout(bool enabled, int& totalPageCount, std::string& errorMessage);
    //! Saving is paused because every chord symbol was removed from the full score.
    bool chordSymbolRemovalNeedsApproval() const;
    //! Confirms that removal, so the next save goes ahead.
    void acceptChordSymbolRemoval();
    bool supportsPlayback() const;
    bool supportsEditing() const;
    bool concertPitchEnabled() const;
    bool hasConcertPitchRelevantTransposition() const;
    int scoreStartKey() const;
    std::vector<ScorePartInfo> partInfoList() const;
    ScoreMetadata metadata() const;
    bool setActivePartIndex(std::optional<int> partIndex, int& totalPageCount, std::string& errorMessage);
    bool setViewTransposeKey(int targetKey, int& totalPageCount, std::string& errorMessage);
    bool clearViewTranspose(int& totalPageCount, std::string& errorMessage);
    bool setConcertPitchEnabled(bool enabled, int& totalPageCount, std::string& errorMessage);
    bool renderPage(int pageIndex, int dpi, RenderedPage& output, std::string& errorMessage) const;
    //! Test/diagnostic: every laid-out element of the displayed score, one line per element
    //! ("page type x y w" in tenths of a staff space, sorted). Two sessions showing the same
    //! score give the same lines, so it compares a live session with its saved file reopened.
    bool layoutFingerprint(std::vector<std::string>& output, std::string& errorMessage) const;
    bool pdfData(std::vector<std::uint8_t>& output, std::string& errorMessage) const;
    bool playbackMIDIData(std::vector<std::uint8_t>& output, std::string& errorMessage) const;
    bool musicXMLData(std::vector<std::uint8_t>& output, std::string& errorMessage) const;
    //! Stem collection is optional for exports that use only mixed PCM. It does
    //! not change synth routing, sample summation, or persistent stream state.
    bool playbackEventAudioData(const std::string& soundFontPath,
                                double startTimeSeconds,
                                double durationSeconds,
                                bool metronomeEnabled,
                                PlaybackAudioData& output,
                                std::string& errorMessage,
                                bool includePartSamples = true) const;
    //! Export-only mix; normal playback uses the unchanged API above.
    bool playbackMixedAudioData(const std::string& soundFontPath,
                                double startTimeSeconds,
                                double durationSeconds,
                                bool metronomeEnabled,
                                PlaybackAudioData& output,
                                std::string& errorMessage,
                                const PlaybackMix& mix) const;
    //! Every pitched note of playback (percussion left out), in start order,
    //! with the same timing as `playbackEventAudioData`.
    bool playbackNotes(std::vector<PlaybackNote>& output, std::string& errorMessage) const;
    //! One bar of metronome clicks leading into playback at `startTimeSeconds`.
    //! Empty when there is no bar to count in from.
    bool playbackCountIn(const std::string& soundFontPath,
                         double startTimeSeconds,
                         PlaybackCountIn& output,
                         std::string& errorMessage) const;
    bool playbackTrackSummary(std::vector<PlaybackTrackSummary>& output, std::string& errorMessage) const;
    bool playbackMeasureRegions(std::vector<PlaybackMeasureRegion>& output, std::string& errorMessage) const;
    //! Where each beat falls on the line and when it sounds, for a playhead
    //! that follows the music. Includes an end point for each stretch of the line.
    bool playbackBeatPoints(std::vector<PlaybackBeatPoint>& output, std::string& errorMessage) const;
    bool scoreCorruptionReport(ScoreCorruptionReport& output, std::string& errorMessage);
    bool legacyRepairIssues(std::vector<ScoreLegacyRepairIssue>& output, std::string& errorMessage);
    bool applyLegacyRepairs(const std::vector<int>& issueIndexes, ScoreEditState& output, std::string& errorMessage);
    bool selectCorruptionIssue(int issueIndex, ScoreEditState& output, std::string& errorMessage);
    bool clearCorruptionIssue(int issueIndex, ScoreEditState& output, ScoreCorruptionReport& report, std::string& errorMessage);
    bool currentEditState(ScoreEditState& output, std::string& errorMessage) const;
    //! Read input flags without producing selection artwork. This is a live query,
    //! not a cached UI snapshot; the existing full-state API remains unchanged.
    bool currentNoteInputState(ScoreEditState& output, std::string& errorMessage) const;
    bool selectElement(int pageIndex, double normalizedX, double normalizedY, double hitRadiusScale, ScoreEditState& output, std::string& errorMessage);
    bool setNoteInputEnabled(bool enabled, ScoreEditState& output, std::string& errorMessage);
    bool setCurrentVoice(int voice, ScoreEditState& output, std::string& errorMessage);
    bool applyDuration(int durationCode, ScoreEditState& output, std::string& errorMessage);
    bool toggleDot(ScoreEditState& output, std::string& errorMessage);
    bool toggleRest(ScoreEditState& output, std::string& errorMessage);
    bool enterRestAtCursor(ScoreEditState& output, std::string& errorMessage);
    bool toggleTie(ScoreEditState& output, std::string& errorMessage);
    bool addTuplet(int tupletCount, ScoreEditState& output, std::string& errorMessage);
    bool addText(const std::string& textKind, ScoreEditState& output, std::string& errorMessage);
    bool selectAttachedChordText(ScoreEditState& output, std::string& errorMessage);
    bool selectAttachedLyrics(ScoreEditState& output, std::string& errorMessage);
    bool setSelectedText(const std::string& text, ScoreEditState& output, std::string& errorMessage);
    bool addLyricsText(const std::string& text, bool advanceToNextChord, ScoreEditState& output, std::string& errorMessage);
    bool addLyricsMelisma(const std::string& text, ScoreEditState& output, std::string& errorMessage);
    bool addLyricsHyphen(const std::string& text, ScoreEditState& output, std::string& errorMessage);
    bool finishLyricsEntry(ScoreEditState& output, std::string& errorMessage);
    bool addRepeatJump(const std::string& repeatJumpKind, ScoreEditState& output, std::string& errorMessage);
    bool addExpression(const std::string& expressionKind, ScoreEditState& output, std::string& errorMessage);
    bool retargetSelectedExpressionEndpoint(bool startEndpoint, int pageIndex, double normalizedX, double normalizedY, ScoreEditState& output, std::string& errorMessage);
    bool dragSelectedMovableElement(int pageIndex, double normalizedX, double normalizedY, ScoreEditState& output, std::string& errorMessage);
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
                          double staffSpacingSpatium,
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
    bool removeMIDIPitchFromCurrentChord(int midiPitch, ScoreEditState& output, std::string& errorMessage);
    bool deleteSelection(ScoreEditState& output, std::string& errorMessage);
    bool previewMeasureRange(int pageIndex, double startNormalizedX, double startNormalizedY, double endNormalizedX, double endNormalizedY, ScoreEditState& output, std::string& errorMessage);
    bool selectMeasureRange(int pageIndex, double startNormalizedX, double startNormalizedY, double endNormalizedX, double endNormalizedY, ScoreEditState& output, std::string& errorMessage);
    bool clearSelectedMeasure(ScoreEditState& output, std::string& errorMessage);
    bool removeSelectedMeasure(ScoreEditState& output, std::string& errorMessage);
    bool addMeasures(int count, ScoreEditState& output, std::string& errorMessage);
    bool resetTemplateMeasures(int count, ScoreEditState& output, std::string& errorMessage);
    bool setRegularMeasureCount(int count, ScoreEditState& output, std::string& errorMessage);
    bool firstMeasurePickupState(PickupMeasureState& output, std::string& errorMessage);
    bool setFirstMeasurePickup(int numerator, int denominator, ScoreEditState& output, std::string& errorMessage);
    bool createFirstPickupMeasure(int numerator, int denominator, ScoreEditState& output, std::string& errorMessage);
    bool clearFirstMeasurePickup(ScoreEditState& output, std::string& errorMessage);
    bool copySelectedMeasureRange(ScoreEditState& output, std::string& errorMessage);
    bool cutSelectedMeasureRange(ScoreEditState& output, std::string& errorMessage);
    bool pasteMeasureRange(ScoreEditState& output, std::string& errorMessage);
    bool selectAll(ScoreEditState& output, std::string& errorMessage);
    bool clearSelection(ScoreEditState& output, std::string& errorMessage);
    bool transposeScore(int mode, int direction, int interval, int targetKey, ScoreEditState& output, std::string& errorMessage);
    bool transposeSelectedMeasureRange(int mode, int direction, int interval, int targetKey, ScoreEditState& output, std::string& errorMessage);
    bool moveSelectionPitch(bool up, ScoreEditState& output, std::string& errorMessage);
    bool shiftSelectionPitchBySemitones(int semitoneDelta, ScoreEditState& output, std::string& errorMessage);
    bool shiftSelectionPitchByOctaves(int octaveDelta, ScoreEditState& output, std::string& errorMessage);
    bool changeSelectionEnharmonicSpelling(ScoreEditState& output, std::string& errorMessage);
    bool changeSelectionAccidental(int accidentalKind, ScoreEditState& output, std::string& errorMessage);
    bool flipSelectionStemDirection(ScoreEditState& output, std::string& errorMessage);
    bool setSelectionPitchClass(int pitchClass, bool preferFlats, ScoreEditState& output, std::string& errorMessage);
    bool setSelectionMIDIPitch(int midiPitch, bool preferFlats, ScoreEditState& output, std::string& errorMessage);
    bool setSelectionPitchAtPagePosition(int pageIndex, double normalizedX, double normalizedY, ScoreEditState& output, std::string& errorMessage);
    bool selectAdjacentElement(bool next, ScoreEditState& output, std::string& errorMessage);
    bool undo(ScoreEditState& output, std::string& errorMessage);
    bool redo(ScoreEditState& output, std::string& errorMessage);
    bool replacePartInstrument(const std::string& partId, const std::string& instrumentId, ScoreEditState& output, std::string& errorMessage);
    bool setInstrumentFromTick(const std::string& partId, int64_t tick, const std::string& instrumentId, ScoreEditState& output, std::string& errorMessage);
    bool replaceInstruments(const std::vector<std::string>& instrumentIds, ScoreEditState& output, std::string& errorMessage);
    bool addInstrument(const std::string& instrumentId, ScoreEditState& output, std::string& errorMessage);
    bool removeInstrumentAtIndex(int partIndex, ScoreEditState& output, std::string& errorMessage);
    bool moveInstrument(int sourceIndex, int destinationIndex, ScoreEditState& output, std::string& errorMessage);
    bool setInstrumentVisible(int partIndex, bool visible, ScoreEditState& output, std::string& errorMessage);
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

//! MuseScore Studio's "Muse Reverb" with the default settings desktop loads on
//! its reverb aux channel. Processes an interleaved stereo send bus in place,
//! returning the wet signal. Calls must be contiguous in playback order.
class PlaybackReverb
{
public:
    explicit PlaybackReverb(double sampleRate);
    ~PlaybackReverb();

    void process(float* interleavedStereo, int frameCount);
    //! Clears the reverb tail, e.g. after a seek.
    void reset();

private:
    struct Impl;

    PlaybackReverb(const PlaybackReverb&) = delete;
    PlaybackReverb& operator=(const PlaybackReverb&) = delete;

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
