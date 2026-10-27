// Android's MSRRenderSession: the same Swift API as the iOS bridge's
// (MuseReaderiOS/MuseReaderiOS/Bridge/MuseScoreRenderCoreBridge.{h,mm}), calling the shared
// C++ render core directly. Each method does what its Objective-C++ counterpart does,
// including the error messages.

@_implementationOnly import AriaRenderCoreCxx
@_implementationOnly import CxxStdlib
import Foundation

// Android only: the iOS app has its own Objective-C++ bridge.

private typealias Session = msr.render.ScoreRenderSession
private typealias SessionPointer = UnsafeMutablePointer<msr.render.ScoreRenderSession>

private let sessionUnavailableMessage = "The MuseScore render session is no longer available."

open class MSRRenderSession: NSObject, @unchecked Sendable {
    // An msr::render::ScoreRenderSession, owned; stored opaque so the C++ type stays private.
    private var handle: OpaquePointer?

    public private(set) var totalPageCount: Int
    public let supportsPlayback: Bool
    public let supportsEditing: Bool

    init(session: OpaquePointer, totalPageCount: Int, supportsPlayback: Bool, supportsEditing: Bool) {
        self.handle = session
        self.totalPageCount = totalPageCount
        self.supportsPlayback = supportsPlayback
        self.supportsEditing = supportsEditing
    }

    deinit {
        if let handle {
            aria.closeSession(SessionPointer(handle))
        }
    }

    private var session: SessionPointer? {
        handle.map { SessionPointer($0) }
    }

    private func requireSession() throws -> SessionPointer {
        guard let session else {
            throw bridgeError(.renderCoreFailure, sessionUnavailableMessage)
        }
        return session
    }

    private func failure(_ message: std.string, _ fallback: String) -> NSError {
        let text = makeString(message)
        return bridgeError(.renderCoreFailure, text.isEmpty ? fallback : text)
    }

    /// Runs an edit and returns the resulting edit state.
    private func edit(_ fallback: String,
                      _ call: (SessionPointer, inout msr.render.ScoreEditState, inout std.string) -> Bool) throws -> MSREditState {
        let session = try requireSession()
        var state = msr.render.ScoreEditState()
        var message = std.string()
        guard call(session, &state, &message) else {
            throw failure(message, fallback)
        }
        return makeEditState(state)
    }

    /// Runs a view change that re-lays out the score and reports the new page count.
    private func relayout(_ totalPageCountOutput: UnsafeMutablePointer<Int>?, _ fallback: String,
                          _ call: (SessionPointer, inout Int32, inout std.string) -> Bool) throws {
        let session = try requireSession()
        var updatedPageCount: Int32 = 0
        var message = std.string()
        guard call(session, &updatedPageCount, &message) else {
            throw failure(message, fallback)
        }
        totalPageCount = Int(updatedPageCount)
        totalPageCountOutput?.pointee = Int(updatedPageCount)
    }

    private func bytes(_ fallback: String, _ call: (SessionPointer, inout aria.Bytes, inout std.string) -> Bool) throws -> Data {
        let session = try requireSession()
        var output = aria.Bytes()
        var message = std.string()
        guard call(session, &output, &message) else {
            throw failure(message, fallback)
        }
        return makeData(output)
    }

    // MARK: - Pages and views

    open var concertPitchEnabled: Bool {
        session?.pointee.concertPitchEnabled() ?? false
    }

    open var hasConcertPitchRelevantTransposition: Bool {
        session?.pointee.hasConcertPitchRelevantTransposition() ?? false
    }

    open var scoreStartKey: Int {
        session.map { Int($0.pointee.scoreStartKey()) } ?? 0
    }

    open var scoreParts: [MSRScorePartInfo] {
        session.map { makeScorePartInfos($0.pointee.partInfoList()) } ?? []
    }

    open var currentMetadata: MSRScoreMetadata {
        guard let session else {
            return MSRScoreMetadata(title: "", subtitle: "", composer: "", lyricist: "", arranger: "",
                                    titleFontFamily: "Edwin", composerFontFamily: "Edwin",
                                    titleFontBold: false, titleFontItalic: false,
                                    composerFontBold: false, composerFontItalic: false)
        }
        let metadata = session.pointee.metadata()
        return MSRScoreMetadata(title: makeString(metadata.title),
                                subtitle: makeString(metadata.subtitle),
                                composer: makeString(metadata.composer),
                                lyricist: makeString(metadata.lyricist),
                                arranger: makeString(metadata.arranger),
                                titleFontFamily: makeString(metadata.titleFontFamily),
                                composerFontFamily: makeString(metadata.composerFontFamily),
                                titleFontBold: metadata.titleFontBold,
                                titleFontItalic: metadata.titleFontItalic,
                                composerFontBold: metadata.composerFontBold,
                                composerFontItalic: metadata.composerFontItalic)
    }

    open func renderPage(index pageIndex: Int, dpi: Int) throws -> MSRRenderedPage {
        let session = try requireSession()
        var page = msr.render.RenderedPage()
        var message = std.string()
        guard session.pointee.renderPage(Int32(pageIndex), Int32(dpi), &page, &message) else {
            throw failure(message, "The MuseScore render core could not render this page.")
        }
        return makeRenderedPage(page)
    }

    open func setActivePart(index partIndex: Int, totalPageCount: UnsafeMutablePointer<Int>?) throws {
        try relayout(totalPageCount, "The MuseScore render core could not open that part.") {
            $0.pointee.setActivePartIndex(aria.someInt(Int32(partIndex)), &$1, &$2)
        }
    }

    open func setFullScoreView(totalPageCount: UnsafeMutablePointer<Int>?) throws {
        try relayout(totalPageCount, "The MuseScore render core could not return to the full score.") {
            $0.pointee.setActivePartIndex(aria.noInt(), &$1, &$2)
        }
    }

    open func setContinuousLayout(_ enabled: Bool, totalPageCount: UnsafeMutablePointer<Int>?) throws {
        try relayout(totalPageCount, "The MuseScore render core could not change the score layout.") {
            $0.pointee.setContinuousLayout(enabled, &$1, &$2)
        }
    }

    open func setViewTransposeKey(_ targetKey: Int, totalPageCount: UnsafeMutablePointer<Int>?) throws {
        try relayout(totalPageCount, "The MuseScore render core could not change the viewing key.") {
            $0.pointee.setViewTransposeKey(Int32(targetKey), &$1, &$2)
        }
    }

    open func clearViewTranspose(totalPageCount: UnsafeMutablePointer<Int>?) throws {
        try relayout(totalPageCount, "The MuseScore render core could not restore the original viewing key.") {
            $0.pointee.clearViewTranspose(&$1, &$2)
        }
    }

    open func setConcertPitchEnabled(_ enabled: Bool, totalPageCount: UnsafeMutablePointer<Int>?) throws {
        try relayout(totalPageCount, "The MuseScore render core could not change concert pitch.") {
            $0.pointee.setConcertPitchEnabled(enabled, &$1, &$2)
        }
    }

    open func refreshTotalPageCount(_ totalPageCountOutput: UnsafeMutablePointer<Int>?) throws {
        let session = try requireSession()
        totalPageCount = Int(session.pointee.totalPageCount())
        totalPageCountOutput?.pointee = totalPageCount
    }

    // MARK: - Export

    open func playbackMIDIData() throws -> Data {
        try bytes("The MuseScore render core could not export playback MIDI.") { $0.pointee.playbackMIDIData(&$1, &$2) }
    }

    open func pdfData() throws -> Data {
        try bytes("The MuseScore render core could not export PDF.") { $0.pointee.pdfData(&$1, &$2) }
    }

    open func musicXMLData() throws -> Data {
        try bytes("The MuseScore render core could not export MusicXML.") { $0.pointee.musicXMLData(&$1, &$2) }
    }

    // MARK: - Playback

    open func playbackEventAudioData(soundFontPath: String, startTimeSeconds: TimeInterval, durationSeconds: TimeInterval,
                                     metronomeEnabled: Bool) throws -> MSRPlaybackAudioData {
        try playbackEventAudioData(soundFontPath: soundFontPath, startTimeSeconds: startTimeSeconds,
                                   durationSeconds: durationSeconds, metronomeEnabled: metronomeEnabled,
                                   includePartSamples: true)
    }

    open func playbackEventAudioData(soundFontPath: String, startTimeSeconds: TimeInterval, durationSeconds: TimeInterval,
                                     metronomeEnabled: Bool, includePartSamples: Bool) throws -> MSRPlaybackAudioData {
        let session = try requireSession()
        var audio = msr.render.PlaybackAudioData()
        var message = std.string()
        guard session.pointee.playbackEventAudioData(std.string(soundFontPath), startTimeSeconds, durationSeconds,
                                                     metronomeEnabled, &audio, &message, includePartSamples) else {
            throw failure(message, "The MuseScore render core could not render event-driven playback audio.")
        }
        return makePlaybackAudioData(audio)
    }

    open func playbackMixedAudioData(soundFontPath: String, startTimeSeconds: TimeInterval, durationSeconds: TimeInterval,
                                     metronomeEnabled: Bool, partMixSettings: [String: MSRPlaybackPartMix]) throws -> MSRPlaybackAudioData {
        let session = try requireSession()
        var mix = msr.render.PlaybackMix()
        for (partID, part) in partMixSettings {
            aria.setPartMix(&mix, std.string(partID), part.volume, part.pan, part.muted, part.solo)
        }
        var audio = msr.render.PlaybackAudioData()
        var message = std.string()
        guard session.pointee.playbackMixedAudioData(std.string(soundFontPath), startTimeSeconds, durationSeconds,
                                                     metronomeEnabled, &audio, &message, mix) else {
            throw failure(message, "The MuseScore render core could not render event-driven playback audio.")
        }
        return makePlaybackAudioData(audio)
    }

    open func playbackCountIn(soundFontPath: String, startTimeSeconds: TimeInterval) throws -> MSRPlaybackCountIn {
        let session = try requireSession()
        var countIn = msr.render.PlaybackCountIn()
        var message = std.string()
        guard session.pointee.playbackCountIn(std.string(soundFontPath), startTimeSeconds, &countIn, &message) else {
            throw failure(message, "The MuseScore render core could not render the count-in.")
        }
        let clicks = countIn.clicks.map {
            MSRPlaybackCountInClick(timeSeconds: $0.timeSeconds, beatNumber: Int($0.beatNumber), isDownbeat: $0.isDownbeat)
        }
        return MSRPlaybackCountIn(audioData: makePlaybackAudioData(countIn.audio),
                                  durationSeconds: countIn.durationSeconds,
                                  clicks: clicks)
    }

    open func playbackMeasureRegions() throws -> [MSRPlaybackMeasureRegion] {
        let session = try requireSession()
        var regions = aria.PlaybackMeasureRegions()
        var message = std.string()
        guard session.pointee.playbackMeasureRegions(&regions, &message) else {
            throw failure(message, "The MuseScore render core could not resolve playback measure regions.")
        }
        return regions.map(makePlaybackMeasureRegion)
    }

    open func playbackNotes() throws -> [MSRPlaybackNote] {
        let session = try requireSession()
        var notes = aria.PlaybackNotes()
        var message = std.string()
        guard session.pointee.playbackNotes(&notes, &message) else {
            throw failure(message, "The MuseScore render core could not read the playback notes.")
        }
        return notes.map {
            MSRPlaybackNote(pitch: Int($0.pitch), startTimeSeconds: $0.startTimeSeconds,
                            endTimeSeconds: $0.endTimeSeconds, staffIndex: Int($0.staffIndex))
        }
    }

    open func playbackBeatPoints() throws -> [MSRPlaybackBeatPoint] {
        let session = try requireSession()
        var points = aria.PlaybackBeatPoints()
        var message = std.string()
        guard session.pointee.playbackBeatPoints(&points, &message) else {
            throw failure(message, "The MuseScore render core could not resolve playback beats.")
        }
        return points.map {
            MSRPlaybackBeatPoint(pageIndex: Int($0.pageIndex), timeSeconds: $0.timeSeconds,
                                 normalizedX: $0.normalizedX, startsSegment: $0.startsSegment)
        }
    }

    // MARK: - Repairs

    open func scoreCorruptionReport() throws -> MSRScoreCorruptionReport {
        let session = try requireSession()
        var report = msr.render.ScoreCorruptionReport()
        var message = std.string()
        guard session.pointee.scoreCorruptionReport(&report, &message) else {
            throw failure(message, "The MuseScore render core could not inspect score corruption.")
        }
        return makeScoreCorruptionReport(report)
    }

    open func legacyRepairIssues() throws -> [MSRLegacyRepairIssue] {
        let session = try requireSession()
        var issues = aria.LegacyRepairIssues()
        var message = std.string()
        guard session.pointee.legacyRepairIssues(&issues, &message) else {
            throw failure(message, "Aria could not inspect older score issues.")
        }
        return issues.map {
            MSRLegacyRepairIssue(index: Int($0.index), measureNumber: Int($0.measureNumber), staffIndex: Int($0.staffIndex),
                                 kind: makeString($0.kind), location: makeString($0.location), message: makeString($0.message))
        }
    }

    open func applyLegacyRepairs(indexes: [NSNumber]) throws -> MSREditState {
        var selected = aria.Ints()
        for index in indexes {
            selected.push_back(Int32(index.intValue))
        }
        return try edit("Aria could not repair this score.") { $0.pointee.applyLegacyRepairs(selected, &$1, &$2) }
    }

    open func selectCorruptionIssue(index: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not select that corrupted bar.") {
            $0.pointee.selectCorruptionIssue(Int32(index), &$1, &$2)
        }
    }

    // iOS declares editState as AutoreleasingUnsafeMutablePointer, which Android lacks; call
    // sites pass `&value` either way.
    open func clearCorruptionIssue(index: Int, editState: UnsafeMutablePointer<MSREditState?>?) throws -> MSRScoreCorruptionReport {
        let session = try requireSession()
        var state = msr.render.ScoreEditState()
        var report = msr.render.ScoreCorruptionReport()
        var message = std.string()
        guard session.pointee.clearCorruptionIssue(Int32(index), &state, &report, &message) else {
            throw failure(message, "The MuseScore render core could not clear that corrupted bar.")
        }
        editState?.pointee = makeEditState(state)
        return makeScoreCorruptionReport(report)
    }

    // MARK: - Editing

    open func currentEditState() throws -> MSREditState {
        try edit("The MuseScore render core could not resolve the current edit state.") { $0.pointee.currentEditState(&$1, &$2) }
    }

    /// Scalar input/settings state only: no selection geometry, image or PDF work.
    open func currentNoteInputState() throws -> MSREditState {
        try edit("The MuseScore render core could not resolve note input state.") { $0.pointee.currentNoteInputState(&$1, &$2) }
    }

    open func selectElement(pageIndex: Int, normalizedX: Double, normalizedY: Double, hitRadiusScale: Double) throws -> MSREditState {
        try edit("The MuseScore render core could not select an item at that location.") {
            $0.pointee.selectElement(Int32(pageIndex), normalizedX, normalizedY, hitRadiusScale, &$1, &$2)
        }
    }

    open func selectMeasureRange(pageIndex: Int, startNormalizedX: Double, startNormalizedY: Double,
                                 endNormalizedX: Double, endNormalizedY: Double) throws -> MSREditState {
        try edit("The MuseScore render core could not select that measure range.") {
            $0.pointee.selectMeasureRange(Int32(pageIndex), startNormalizedX, startNormalizedY, endNormalizedX, endNormalizedY, &$1, &$2)
        }
    }

    open func previewMeasureRange(pageIndex: Int, startNormalizedX: Double, startNormalizedY: Double,
                                  endNormalizedX: Double, endNormalizedY: Double) throws -> MSREditState {
        try edit("The MuseScore render core could not preview that measure range.") {
            $0.pointee.previewMeasureRange(Int32(pageIndex), startNormalizedX, startNormalizedY, endNormalizedX, endNormalizedY, &$1, &$2)
        }
    }

    open func setNoteInputEnabled(_ enabled: Bool) throws -> MSREditState {
        try edit("The MuseScore render core could not update note input.") { $0.pointee.setNoteInputEnabled(enabled, &$1, &$2) }
    }

    open func setCurrentVoice(_ voice: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not update the current voice.") { $0.pointee.setCurrentVoice(Int32(voice), &$1, &$2) }
    }

    open func applyDuration(code durationCode: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not change the duration.") { $0.pointee.applyDuration(Int32(durationCode), &$1, &$2) }
    }

    open func toggleDot() throws -> MSREditState {
        try edit("The MuseScore render core could not toggle the augmentation dot.") { $0.pointee.toggleDot(&$1, &$2) }
    }

    open func toggleRest() throws -> MSREditState {
        try edit("The MuseScore render core could not toggle rest mode.") { $0.pointee.toggleRest(&$1, &$2) }
    }

    open func enterRestAtCursor() throws -> MSREditState {
        try edit("The MuseScore render core could not enter a rest at the cursor.") { $0.pointee.enterRestAtCursor(&$1, &$2) }
    }

    open func toggleTie() throws -> MSREditState {
        try edit("The MuseScore render core could not toggle the tie.") { $0.pointee.toggleTie(&$1, &$2) }
    }

    open func addTuplet(_ tupletCount: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not add that tuplet.") { $0.pointee.addTuplet(Int32(tupletCount), &$1, &$2) }
    }

    open func addText(_ textKind: String) throws -> MSREditState {
        try edit("The MuseScore render core could not add that text.") { $0.pointee.addText(std.string(textKind), &$1, &$2) }
    }

    open func selectAttachedChordText() throws -> MSREditState {
        try edit("The MuseScore render core could not select the attached chord text.") { $0.pointee.selectAttachedChordText(&$1, &$2) }
    }

    open func selectAttachedLyrics() throws -> MSREditState {
        try edit("The MuseScore render core could not select the attached lyrics.") { $0.pointee.selectAttachedLyrics(&$1, &$2) }
    }

    open func setSelectedText(_ text: String) throws -> MSREditState {
        try edit("The MuseScore render core could not edit that text.") { $0.pointee.setSelectedText(std.string(text), &$1, &$2) }
    }

    open func addLyricsText(_ text: String, advanceToNextChord: Bool) throws -> MSREditState {
        try edit("The MuseScore render core could not edit lyrics.") {
            $0.pointee.addLyricsText(std.string(text), advanceToNextChord, &$1, &$2)
        }
    }

    open func addLyricsMelisma(_ text: String) throws -> MSREditState {
        try edit("The MuseScore render core could not add the lyrics extension line.") {
            $0.pointee.addLyricsMelisma(std.string(text), &$1, &$2)
        }
    }

    open func addLyricsHyphen(_ text: String) throws -> MSREditState {
        try edit("The MuseScore render core could not add the lyrics hyphen.") { $0.pointee.addLyricsHyphen(std.string(text), &$1, &$2) }
    }

    open func finishLyricsEntry() throws -> MSREditState {
        try edit("The MuseScore render core could not finish lyrics entry.") { $0.pointee.finishLyricsEntry(&$1, &$2) }
    }

    open func addRepeatJump(_ repeatJumpKind: String) throws -> MSREditState {
        try edit("The MuseScore render core could not add that repeat or jump.") {
            $0.pointee.addRepeatJump(std.string(repeatJumpKind), &$1, &$2)
        }
    }

    open func addExpression(_ expressionKind: String) throws -> MSREditState {
        try edit("The MuseScore render core could not add that expression.") {
            $0.pointee.addExpression(std.string(expressionKind), &$1, &$2)
        }
    }

    open func retargetSelectedExpressionEndpoint(start startEndpoint: Bool, pageIndex: Int, normalizedX: Double,
                                                 normalizedY: Double) throws -> MSREditState {
        try edit("The MuseScore render core could not move that expression endpoint.") {
            $0.pointee.retargetSelectedExpressionEndpoint(startEndpoint, Int32(pageIndex), normalizedX, normalizedY, &$1, &$2)
        }
    }

    open func dragSelectedChordText(pageIndex: Int, normalizedX: Double, normalizedY: Double) throws -> MSREditState {
        try edit("The MuseScore render core could not move that chord symbol.") {
            $0.pointee.dragSelectedChordText(Int32(pageIndex), normalizedX, normalizedY, &$1, &$2)
        }
    }

    open func dragSelectedMovableElement(pageIndex: Int, normalizedX: Double, normalizedY: Double) throws -> MSREditState {
        try edit("The MuseScore render core could not move that score element.") {
            $0.pointee.dragSelectedMovableElement(Int32(pageIndex), normalizedX, normalizedY, &$1, &$2)
        }
    }

    open func addLayoutBreak(_ breakKind: String) throws -> MSREditState {
        try edit("The MuseScore render core could not add that layout break.") { $0.pointee.addLayoutBreak(std.string(breakKind), &$1, &$2) }
    }

    open func removeLayoutBreak() throws -> MSREditState {
        try edit("The MuseScore render core could not remove that layout break.") { $0.pointee.removeLayoutBreak(&$1, &$2) }
    }

    open func fillSelectionWithSlashes() throws -> MSREditState {
        try edit("The MuseScore render core could not fill the selection with slashes.") { $0.pointee.fillSelectionWithSlashes(&$1, &$2) }
    }

    open func replaceSelectionWithRhythmicSlashes() throws -> MSREditState {
        try edit("The MuseScore render core could not replace the selection with rhythmic slash notation.") {
            $0.pointee.replaceSelectionWithRhythmicSlashes(&$1, &$2)
        }
    }

    open func applyAutoSystemBreaks(measuresPerSystem: Int, lockCurrentLayout: Bool, removeExisting: Bool) throws -> MSREditState {
        try edit("The MuseScore render core could not apply auto breaks.") {
            $0.pointee.applyAutoSystemBreaks(Int32(measuresPerSystem), lockCurrentLayout, removeExisting, &$1, &$2)
        }
    }

    open func updateStaffSpacing(_ staffDistanceSpatium: Double) throws -> MSREditState {
        try edit("The MuseScore render core could not update staff spacing.") {
            $0.pointee.updateStaffSpacing(staffDistanceSpatium, &$1, &$2)
        }
    }

    open func updatePageLayout(pageWidthMillimeters: Double, pageHeightMillimeters: Double, marginMillimeters: Double,
                               staffSizeMillimeters: Double, staffSpacingSpatium: Double, systemSpacingSpatium: Double) throws -> MSREditState {
        try edit("The MuseScore render core could not update page settings.") {
            $0.pointee.updatePageLayout(pageWidthMillimeters, pageHeightMillimeters, marginMillimeters,
                                        staffSizeMillimeters, staffSpacingSpatium, systemSpacingSpatium, &$1, &$2)
        }
    }

    open func updateLayoutOptions(createMultiMeasureRests: Bool, hideEmptyStaves: Bool) throws -> MSREditState {
        try edit("The MuseScore render core could not update layout options.") {
            $0.pointee.updateLayoutOptions(createMultiMeasureRests, hideEmptyStaves, &$1, &$2)
        }
    }

    open func addTempo(beatUnit: String, bpm: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not add that tempo marking.") {
            $0.pointee.addTempo(std.string(beatUnit), Int32(bpm), &$1, &$2)
        }
    }

    open func updateTimeSignature(numerator: Int, denominator: Int, commonTime: Bool, cutTime: Bool, fromStart: Bool) throws -> MSREditState {
        guard [1, 2, 4, 8, 16].contains(denominator) else {
            throw bridgeError(.renderCoreFailure, "Time signature denominator must be one of 1, 2, 4, 8, or 16.")
        }
        return try edit("The MuseScore render core could not update the time signature.") {
            $0.pointee.updateTimeSignature(Int32(numerator), Int32(denominator), commonTime, cutTime, fromStart, &$1, &$2)
        }
    }

    open func updateKeySignature(_ keyValue: Int, fromStart: Bool) throws -> MSREditState {
        try edit("The MuseScore render core could not update the key signature.") {
            $0.pointee.updateKeySignature(Int32(keyValue), fromStart, &$1, &$2)
        }
    }

    open func insertNote(pageIndex: Int, normalizedX: Double, normalizedY: Double) throws -> MSREditState {
        try edit("The MuseScore render core could not place a note there.") {
            $0.pointee.insertNote(Int32(pageIndex), normalizedX, normalizedY, &$1, &$2)
        }
    }

    open func insertNote(pageIndex: Int, normalizedX: Double, normalizedY: Double, accidentalKind: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not place a note there.") {
            $0.pointee.insertNoteWithAccidental(Int32(pageIndex), normalizedX, normalizedY, Int32(accidentalKind), &$1, &$2)
        }
    }

    open func insertNote(pageIndex: Int, normalizedX: Double, normalizedY: Double, pitchClass: Int, preferFlats: Bool) throws -> MSREditState {
        try edit("The MuseScore render core could not place a note there.") {
            $0.pointee.insertNoteWithPitch(Int32(pageIndex), normalizedX, normalizedY, Int32(pitchClass), preferFlats, &$1, &$2)
        }
    }

    open func insertPitchAtCursor(_ pitchClass: Int, preferFlats: Bool, addToCurrentChord: Bool) throws -> MSREditState {
        try edit("The MuseScore render core could not enter that pitch at the current cursor.") {
            $0.pointee.insertPitchAtCursor(Int32(pitchClass), preferFlats, addToCurrentChord, &$1, &$2)
        }
    }

    open func insertMIDIPitchAtCursor(_ midiPitch: Int, preferFlats: Bool, addToCurrentChord: Bool) throws -> MSREditState {
        try edit("The MuseScore render core could not enter that exact pitch at the current cursor.") {
            $0.pointee.insertMIDIPitchAtCursor(Int32(midiPitch), preferFlats, addToCurrentChord, &$1, &$2)
        }
    }

    open func insertMIDIChordAtCursor(_ midiPitches: [NSNumber], preferFlats: Bool) throws -> MSREditState {
        var pitches = aria.Ints()
        for pitch in midiPitches {
            pitches.push_back(Int32(pitch.intValue))
        }
        return try edit("The MuseScore render core could not enter that MIDI chord at the current cursor.") {
            $0.pointee.insertMIDIChordAtCursor(pitches, preferFlats, &$1, &$2)
        }
    }

    open func removeMIDIPitchFromCurrentChord(_ midiPitch: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not remove that note from the chord.") {
            $0.pointee.removeMIDIPitchFromCurrentChord(Int32(midiPitch), &$1, &$2)
        }
    }

    open func noteEntryPreview(pageIndex: Int, normalizedX: Double, normalizedY: Double, durationCode: Int, rest: Bool,
                               accidentalKind: Int) throws -> MSRNoteEntryPreviewInfo {
        let session = try requireSession()
        var preview = msr.render.NoteEntryPreviewState()
        var message = std.string()
        guard session.pointee.noteEntryPreview(Int32(pageIndex), normalizedX, normalizedY, Int32(durationCode), rest,
                                               Int32(accidentalKind), &preview, &message) else {
            throw failure(message, "The MuseScore render core could not preview note entry there.")
        }
        return makeNoteEntryPreviewInfo(preview)
    }

    open func deleteSelection() throws -> MSREditState {
        try edit("The MuseScore render core could not delete the selection.") { $0.pointee.deleteSelection(&$1, &$2) }
    }

    open func clearSelectedMeasure() throws -> MSREditState {
        try edit("The MuseScore render core could not clear the selected measure.") { $0.pointee.clearSelectedMeasure(&$1, &$2) }
    }

    open func removeSelectedMeasure() throws -> MSREditState {
        try edit("The MuseScore render core could not remove the selected measure.") { $0.pointee.removeSelectedMeasure(&$1, &$2) }
    }

    open func addMeasures(_ count: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not add measures.") { $0.pointee.addMeasures(Int32(count), &$1, &$2) }
    }

    open func resetTemplateMeasures(_ count: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not reset the template measures.") {
            $0.pointee.resetTemplateMeasures(Int32(count), &$1, &$2)
        }
    }

    open func setRegularMeasureCount(_ count: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not set the measure count.") {
            $0.pointee.setRegularMeasureCount(Int32(count), &$1, &$2)
        }
    }

    open func firstMeasurePickupState() throws -> MSRPickupMeasureInfo {
        let session = try requireSession()
        var pickup = msr.render.PickupMeasureState()
        var message = std.string()
        guard session.pointee.firstMeasurePickupState(&pickup, &message) else {
            throw failure(message, "The MuseScore render core could not read the pickup measure.")
        }
        return makePickupMeasureInfo(pickup)
    }

    open func setFirstMeasurePickup(numerator: Int, denominator: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not create the pickup measure.") {
            $0.pointee.setFirstMeasurePickup(Int32(numerator), Int32(denominator), &$1, &$2)
        }
    }

    open func createFirstPickupMeasure(numerator: Int, denominator: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not create the pickup measure.") {
            $0.pointee.createFirstPickupMeasure(Int32(numerator), Int32(denominator), &$1, &$2)
        }
    }

    open func clearFirstMeasurePickup() throws -> MSREditState {
        try edit("The MuseScore render core could not remove the pickup measure.") { $0.pointee.clearFirstMeasurePickup(&$1, &$2) }
    }

    open func copySelectedMeasureRange() throws -> MSREditState {
        try edit("The MuseScore render core could not copy the selected measure range.") { $0.pointee.copySelectedMeasureRange(&$1, &$2) }
    }

    open func cutSelectedMeasureRange() throws -> MSREditState {
        try edit("The MuseScore render core could not cut the selected measure range.") { $0.pointee.cutSelectedMeasureRange(&$1, &$2) }
    }

    open func pasteMeasureRange() throws -> MSREditState {
        try edit("The MuseScore render core could not paste the copied measure range.") { $0.pointee.pasteMeasureRange(&$1, &$2) }
    }

    open func selectAll() throws -> MSREditState {
        try edit("The MuseScore render core could not select the score.") { $0.pointee.selectAll(&$1, &$2) }
    }

    open func selectSimilar(sameStaff: Bool) throws -> MSREditState {
        try edit("The MuseScore render core could not select similar elements.") { $0.pointee.selectSimilar(sameStaff, &$1, &$2) }
    }

    open func clearSelection() throws -> MSREditState {
        try edit("The MuseScore render core could not clear the selection.") { $0.pointee.clearSelection(&$1, &$2) }
    }

    open func transposeScore(mode: Int, direction: Int, interval: Int, targetKey: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not transpose the score.") {
            $0.pointee.transposeScore(Int32(mode), Int32(direction), Int32(interval), Int32(targetKey), &$1, &$2)
        }
    }

    open func transposeSelectedMeasureRange(mode: Int, direction: Int, interval: Int, targetKey: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not transpose the selected measures.") {
            $0.pointee.transposeSelectedMeasureRange(Int32(mode), Int32(direction), Int32(interval), Int32(targetKey), &$1, &$2)
        }
    }

    open func moveSelectedPitchUp() throws -> MSREditState {
        try edit("The MuseScore render core could not raise the selected pitch.") { $0.pointee.moveSelectionPitch(true, &$1, &$2) }
    }

    open func moveSelectedPitchDown() throws -> MSREditState {
        try edit("The MuseScore render core could not lower the selected pitch.") { $0.pointee.moveSelectionPitch(false, &$1, &$2) }
    }

    open func shiftSelectedPitchBySemitones(_ semitoneDelta: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not shift the selected pitch.") {
            $0.pointee.shiftSelectionPitchBySemitones(Int32(semitoneDelta), &$1, &$2)
        }
    }

    open func shiftSelectedPitchByOctaves(_ octaveDelta: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not shift the selected note by an octave.") {
            $0.pointee.shiftSelectionPitchByOctaves(Int32(octaveDelta), &$1, &$2)
        }
    }

    open func changeSelectedEnharmonicSpelling() throws -> MSREditState {
        try edit("The MuseScore render core could not change the selected note spelling.") {
            $0.pointee.changeSelectionEnharmonicSpelling(&$1, &$2)
        }
    }

    open func changeSelectedAccidental(_ accidentalKind: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not change the selected note accidental.") {
            $0.pointee.changeSelectionAccidental(Int32(accidentalKind), &$1, &$2)
        }
    }

    open func flipSelectedStemDirection() throws -> MSREditState {
        try edit("The MuseScore render core could not flip the selected stem.") { $0.pointee.flipSelectionStemDirection(&$1, &$2) }
    }

    open func setSelectedPitchClass(_ pitchClass: Int, preferFlats: Bool) throws -> MSREditState {
        try edit("The MuseScore render core could not retune the selected note.") {
            $0.pointee.setSelectionPitchClass(Int32(pitchClass), preferFlats, &$1, &$2)
        }
    }

    open func setSelectedMIDIPitch(_ midiPitch: Int, preferFlats: Bool) throws -> MSREditState {
        try edit("The MuseScore render core could not retune the selected note.") {
            $0.pointee.setSelectionMIDIPitch(Int32(midiPitch), preferFlats, &$1, &$2)
        }
    }

    open func setSelectedPitch(pageIndex: Int, normalizedX: Double, normalizedY: Double) throws -> MSREditState {
        try edit("The MuseScore render core could not place the dragged note at that pitch.") {
            $0.pointee.setSelectionPitchAtPagePosition(Int32(pageIndex), normalizedX, normalizedY, &$1, &$2)
        }
    }

    open func selectPreviousElement() throws -> MSREditState {
        try edit("The MuseScore render core could not select the previous element.") { $0.pointee.selectAdjacentElement(false, &$1, &$2) }
    }

    open func selectNextElement() throws -> MSREditState {
        try edit("The MuseScore render core could not select the next element.") { $0.pointee.selectAdjacentElement(true, &$1, &$2) }
    }

    open func undoEdit() throws -> MSREditState {
        try edit("The MuseScore render core could not undo that edit.") { $0.pointee.undo(&$1, &$2) }
    }

    open func redoEdit() throws -> MSREditState {
        try edit("The MuseScore render core could not redo that edit.") { $0.pointee.redo(&$1, &$2) }
    }

    // MARK: - Instruments

    open func replacePartInstrument(partID: String, instrumentID: String) throws -> MSREditState {
        try edit("The MuseScore render core could not replace that instrument.") {
            $0.pointee.replacePartInstrument(std.string(partID), std.string(instrumentID), &$1, &$2)
        }
    }

    open func setInstrumentFromTick(partID: String, tick: Int64, instrumentID: String) throws -> MSREditState {
        try edit("The MuseScore render core could not add that instrument change.") {
            $0.pointee.setInstrumentFromTick(std.string(partID), tick, std.string(instrumentID), &$1, &$2)
        }
    }

    open func replaceInstruments(_ instrumentIds: [String]) throws -> MSREditState {
        var ids = aria.Strings()
        for instrumentId in instrumentIds {
            ids.push_back(std.string(instrumentId))
        }
        return try edit("The MuseScore render core could not update the score instruments.") {
            $0.pointee.replaceInstruments(ids, &$1, &$2)
        }
    }

    open func addInstrument(_ instrumentId: String) throws -> MSREditState {
        try edit("The MuseScore render core could not add that instrument.") { $0.pointee.addInstrument(std.string(instrumentId), &$1, &$2) }
    }

    open func removeInstrument(at partIndex: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not remove that instrument.") {
            $0.pointee.removeInstrumentAtIndex(Int32(partIndex), &$1, &$2)
        }
    }

    open func moveInstrument(from sourceIndex: Int, to destinationIndex: Int) throws -> MSREditState {
        try edit("The MuseScore render core could not move that instrument.") {
            $0.pointee.moveInstrument(Int32(sourceIndex), Int32(destinationIndex), &$1, &$2)
        }
    }

    open func setInstrument(at partIndex: Int, visible: Bool) throws -> MSREditState {
        try edit("The MuseScore render core could not update instrument visibility.") {
            $0.pointee.setInstrumentVisible(Int32(partIndex), visible, &$1, &$2)
        }
    }

    open func removeSelectedInstrument() throws -> MSREditState {
        try edit("The MuseScore render core could not remove that instrument.") { $0.pointee.removeSelectedInstrument(&$1, &$2) }
    }

    open func changeClef(_ clefKind: String) throws -> MSREditState {
        try edit("The MuseScore render core could not change that clef.") { $0.pointee.changeClef(std.string(clefKind), &$1, &$2) }
    }

    // MARK: - Score details and saving

    open func updateMetadata(title: String, subtitle: String, composer: String, lyricist: String, arranger: String) throws {
        let session = try requireSession()
        var metadata = msr.render.ScoreMetadata()
        metadata.title = std.string(title)
        metadata.subtitle = std.string(subtitle)
        metadata.composer = std.string(composer)
        metadata.lyricist = std.string(lyricist)
        metadata.arranger = std.string(arranger)
        var message = std.string()
        guard session.pointee.updateMetadata(metadata, &message) else {
            throw failure(message, "The MuseScore render core could not apply these score details.")
        }
    }

    open func updateInitialKeySignature(_ keyValue: Int) throws {
        let session = try requireSession()
        var message = std.string()
        guard session.pointee.updateInitialKeySignature(Int32(keyValue), &message) else {
            throw failure(message, "The MuseScore render core could not update the key signature.")
        }
    }

    open func save(to url: URL) throws {
        let session = try requireSession()
        guard url.isFileURL, !url.path.isEmpty else {
            throw bridgeError(.renderCoreFailure, "Aria needs a local file URL to save this score.")
        }
        var message = std.string()
        guard session.pointee.saveToPath(std.string(url.path), &message) else {
            let text = makeString(message)
            let description = text.isEmpty ? "The MuseScore render core could not save this score." : text
            throw session.pointee.chordSymbolRemovalNeedsApproval()
                ? bridgeError(.chordSymbolRemovalNeedsApproval, description)
                : bridgeError(.renderCoreFailure, description)
        }
    }

    open func acceptChordSymbolRemoval() {
        session?.pointee.acceptChordSymbolRemoval()
    }
}

