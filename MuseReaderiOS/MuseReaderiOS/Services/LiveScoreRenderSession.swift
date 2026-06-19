//
//  LiveScoreRenderSession.swift
//  MuseReaderiOS
//
//

import Foundation
import CoreGraphics

enum LiveScoreRenderSessionError: LocalizedError {
    case missingEditState

    var errorDescription: String? {
        switch self {
        case .missingEditState:
            return "The MuseScore render core repaired the score but did not return an editing state."
        }
    }
}

actor LiveScoreRenderSession {
    private let bridgeSession: MSRRenderSession
    private var cachedPlaybackMIDIData: Data?
    private var cachedPlaybackMeasureRegions: [ScorePlaybackMeasureRegion]?
    private var cachedPlaybackSoundFontURL: URL?
    private var playbackRevision = 0
    private var playbackChunkRequestCount = 0

    let totalPageCount: Int
    let supportsPlayback: Bool
    let supportsEditing: Bool
    let parts: [ScorePart]

    init(bridgeSession: MSRRenderSession) {
        self.bridgeSession = bridgeSession
        self.totalPageCount = bridgeSession.totalPageCount
        self.supportsPlayback = bridgeSession.supportsPlayback
        self.supportsEditing = bridgeSession.supportsEditing
        self.parts = bridgeSession.scoreParts.map { part in
            let name = part.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "Part \(part.index + 1)" : name
            return ScorePart(
                id: part.partID,
                index: part.index,
                name: displayName,
                clef: ScorePartClef.inferred(for: displayName)
            )
        }
    }

    func renderPage(at index: Int, dpi: Int) throws -> ScorePage {
        if Task.isCancelled {
            print("Aria live page render canceled before bridge: page=\(index + 1) dpi=\(dpi)")
        }
        try Task.checkCancellation()
        let startedAt = Date()
        let sessionID = ObjectIdentifier(self).hashValue
        print("Aria live page render begin: session=\(sessionID) page=\(index + 1) dpi=\(dpi)")
        let renderedPage = try bridgeSession.renderPage(index: index, dpi: dpi)
        if Task.isCancelled {
            print(String(format: "Aria live page render canceled after bridge: session=%d page=%d elapsed=%.3fs",
                         sessionID,
                         index + 1,
                         Date().timeIntervalSince(startedAt)))
        }
        try Task.checkCancellation()
        print(String(format: "Aria live page render finished: session=%d page=%d bytes=%d elapsed=%.3fs", sessionID, renderedPage.pageIndex + 1, renderedPage.imageData.count, Date().timeIntervalSince(startedAt)))

        return ScorePage(
            index: renderedPage.pageIndex,
            title: "Page \(renderedPage.pageIndex + 1)",
            sourcePath: "render://page-\(renderedPage.pageIndex + 1)",
            source: .liveMuseScoreRenderer,
            imageData: renderedPage.imageData
        )
    }

    func setFullScoreView() throws -> Int {
        var pageCount = 0
        try bridgeSession.setFullScoreView(totalPageCount: &pageCount)
        invalidateCachedPlaybackArtifacts()
        return pageCount
    }

    func setActivePart(index: Int) throws -> Int {
        var pageCount = 0
        try bridgeSession.setActivePart(index: index, totalPageCount: &pageCount)
        invalidateCachedPlaybackArtifacts()
        return pageCount
    }

    func concertPitchEnabled() -> Bool {
        bridgeSession.concertPitchEnabled
    }

    func hasConcertPitchRelevantTransposition() -> Bool {
        bridgeSession.hasConcertPitchRelevantTransposition
    }

    func setConcertPitchEnabled(_ enabled: Bool) throws -> Int {
        var pageCount = 0
        try bridgeSession.setConcertPitchEnabled(enabled, totalPageCount: &pageCount)
        invalidateCachedPlaybackArtifacts()
        return pageCount
    }

    func playbackMIDIData() throws -> Data {
        guard supportsPlayback else {
            return Data()
        }

        if let cachedPlaybackMIDIData {
            return cachedPlaybackMIDIData
        }

        let midiData = try bridgeSession.playbackMIDIData()
        cachedPlaybackMIDIData = midiData
        return midiData
    }

    func musicXMLData() throws -> Data {
        try bridgeSession.musicXMLData()
    }

    func playbackAudioChunk(startTimeSeconds: TimeInterval, durationSeconds: TimeInterval, metronomeEnabled: Bool) throws -> MSRPlaybackAudioData {
        playbackChunkRequestCount += 1
        guard let soundFontURL = playbackSoundFontURL() else {
            throw NativePlaybackController.PlaybackError.soundBankUnavailable(
                "Add `MuseScore_General.sf2`, `MuseScore_General.sf3`, or `MS Basic.sf3` to the app bundle resources."
            )
        }

        print("MuseReader event playback chunk request: count=\(playbackChunkRequestCount) soundfont=\(soundFontURL.lastPathComponent) start=\(String(format: "%.2f", startTimeSeconds)) duration=\(String(format: "%.2f", durationSeconds)) revision=\(playbackRevision)")
        let audioData = try bridgeSession.playbackEventAudioData(
            soundFontPath: soundFontURL.path,
            startTimeSeconds: startTimeSeconds,
            durationSeconds: durationSeconds,
            metronomeEnabled: metronomeEnabled
        )
        print("MuseReader event playback chunk result: count=\(playbackChunkRequestCount) sampleRate=\(audioData.sampleRate) channels=\(audioData.channelCount) bytes=\(audioData.interleavedFloat32Samples.count) duration=\(String(format: "%.2f", audioData.durationSeconds)) revision=\(playbackRevision)")
        return audioData
    }

    private func playbackSoundFontURL() -> URL? {
        if let cachedPlaybackSoundFontURL {
            return cachedPlaybackSoundFontURL
        }

        let soundFontURL = Bundle.main.url(forResource: "MuseScore_General", withExtension: "sf2")
            ?? Bundle.main.url(forResource: "MuseScore_General", withExtension: "sf3")
            ?? Bundle.main.url(forResource: "MS Basic", withExtension: "sf3")
        cachedPlaybackSoundFontURL = soundFontURL
        return soundFontURL
    }

    func playbackAudioExportDurationSeconds() throws -> TimeInterval {
        let regions = try playbackMeasureRegions()
        return regions.map(\.endTimeSeconds).max() ?? 0
    }

    func playbackMeasureRegions() throws -> [ScorePlaybackMeasureRegion] {
        guard supportsPlayback else {
            return []
        }

        if let cachedPlaybackMeasureRegions {
            return cachedPlaybackMeasureRegions
        }

        let regions = try bridgeSession.playbackMeasureRegions().map { region in
            ScorePlaybackMeasureRegion(
                measureIndex: region.measureIndex,
                pageIndex: region.pageIndex,
                startTimeSeconds: region.startTimeSeconds,
                endTimeSeconds: region.endTimeSeconds,
                normalizedRect: ScoreNormalizedRect(
                    x: region.normalizedX,
                    y: region.normalizedY,
                    width: region.normalizedWidth,
                    height: region.normalizedHeight
                )
            )
        }

        cachedPlaybackMeasureRegions = regions
        return regions
    }

    func corruptionReport() throws -> ScoreCorruptionReport {
        try makeCorruptionReport(from: bridgeSession.scoreCorruptionReport())
    }

    func selectCorruptionIssue(_ issue: ScoreCorruptionIssue) throws -> ScoreEditingState {
        try makeEditingState(from: bridgeSession.selectCorruptionIssue(index: issue.index))
    }

    func clearCorruptionIssue(_ issue: ScoreCorruptionIssue) throws -> (ScoreEditingState, ScoreCorruptionReport) {
        var bridgeEditState: MSREditState?
        let bridgeReport = try bridgeSession.clearCorruptionIssue(index: issue.index, editState: &bridgeEditState)
        guard let bridgeEditState else {
            throw LiveScoreRenderSessionError.missingEditState
        }
        invalidateCachedPlaybackArtifacts()
        return (try makeEditingState(from: bridgeEditState, refreshScope: .nearby), makeCorruptionReport(from: bridgeReport))
    }

    func currentEditingState() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        return try makeEditingState(from: bridgeSession.currentEditState())
    }

    func selectElement(pageIndex: Int, normalizedPoint: CGPoint, hitRadiusScale: Double = 1.0) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        return try makeEditingState(
            from: bridgeSession.selectElement(
                pageIndex: pageIndex,
                normalizedX: normalizedPoint.x,
                normalizedY: normalizedPoint.y,
                hitRadiusScale: hitRadiusScale
            )
        )
    }

    func selectMeasureRange(pageIndex: Int, startPoint: CGPoint, endPoint: CGPoint) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        return try makeEditingState(
            from: bridgeSession.selectMeasureRange(
                pageIndex: pageIndex,
                startNormalizedX: startPoint.x,
                startNormalizedY: startPoint.y,
                endNormalizedX: endPoint.x,
                endNormalizedY: endPoint.y
            )
        )
    }

    func setNoteInputEnabled(_ enabled: Bool) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        return try makeEditingState(from: bridgeSession.setNoteInputEnabled(enabled))
    }

    func setCurrentVoice(_ voice: Int) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        return try makeEditingState(from: bridgeSession.setCurrentVoice(voice))
    }

    func applyDuration(_ duration: ScoreNoteDuration) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.applyDuration(code: duration.rawValue))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func toggleDot() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.toggleDot())
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func toggleRest() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.toggleRest())
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func toggleTie() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.toggleTie())
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func addTuplet(_ tupletCount: Int) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.addTuplet(tupletCount), refreshScope: .nearby)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func addText(_ textKind: String) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.addText(textKind))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func setSelectedText(_ text: String) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.setSelectedText(text))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func addLyricsText(_ text: String, advanceToNextChord: Bool) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.addLyricsText(text, advanceToNextChord: advanceToNextChord))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func addRepeatJump(_ repeatJumpKind: String) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.addRepeatJump(repeatJumpKind))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func addExpression(_ expressionKind: String) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.addExpression(expressionKind))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func retargetSelectedExpressionEndpoint(start: Bool, pageIndex: Int, normalizedPoint: CGPoint) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.retargetSelectedExpressionEndpoint(
            start: start,
            pageIndex: pageIndex,
            normalizedX: normalizedPoint.x,
            normalizedY: normalizedPoint.y
        ))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func dragSelectedChordText(pageIndex: Int, normalizedPoint: CGPoint) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.dragSelectedChordText(
            pageIndex: pageIndex,
            normalizedX: normalizedPoint.x,
            normalizedY: normalizedPoint.y
        ))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func addLayoutBreak(_ breakKind: String) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.addLayoutBreak(breakKind), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func removeLayoutBreak() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.removeLayoutBreak(), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func fillSelectionWithSlashes() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.fillSelectionWithSlashes(), refreshScope: .nearby)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func replaceSelectionWithRhythmicSlashes() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.replaceSelectionWithRhythmicSlashes(), refreshScope: .nearby)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func applyAutoSystemBreaks(_ request: ScoreAutoSystemBreaksRequest) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.applyAutoSystemBreaks(
            measuresPerSystem: request.measuresPerSystem,
            lockCurrentLayout: request.mode == .lockCurrentLayout,
            removeExisting: request.mode == .removeExisting
        ), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func updateStaffSpacing(_ staffDistanceSpatium: Double) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.updateStaffSpacing(staffDistanceSpatium), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func updatePageLayout(_ value: ScorePageSettingsValue) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.updatePageLayout(
            pageWidthMillimeters: value.pageWidthMillimeters,
            pageHeightMillimeters: value.pageHeightMillimeters,
            marginMillimeters: value.marginMillimeters,
            staffSizeMillimeters: value.staffSizeMillimeters,
            systemSpacingSpatium: value.systemSpacingSpatium
        ), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func updateLayoutOptions(_ value: ScoreLayoutOptionsValue) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.updateLayoutOptions(
            createMultiMeasureRests: value.createMultiMeasureRests,
            hideEmptyStaves: value.hideEmptyStaves
        ), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func addTempo(beatUnit: TempoBeatUnit, bpm: Int) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.addTempo(beatUnit: beatUnit.rawValue, bpm: bpm))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func updateTimeSignature(_ value: ScoreTimeSignatureValue, fromStart: Bool) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.updateTimeSignature(
            numerator: value.numerator,
            denominator: value.denominator,
            commonTime: value.style == .commonTime,
            cutTime: value.style == .cutTime,
            fromStart: fromStart
        ), refreshScope: fromStart ? .all : .nearby)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func updateKeySignature(_ keyValue: Int, fromStart: Bool) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(
            from: bridgeSession.updateKeySignature(keyValue, fromStart: fromStart),
            refreshScope: fromStart ? .all : .nearby
        )
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func insertNote(pageIndex: Int, normalizedPoint: CGPoint) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(
            from: bridgeSession.insertNote(
                pageIndex: pageIndex,
                normalizedX: normalizedPoint.x,
                normalizedY: normalizedPoint.y
            )
        )
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func insertNote(pageIndex: Int, normalizedPoint: CGPoint, accidentalKind: ScoreAccidentalKind?) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        guard let accidentalKind else {
            return try insertNote(pageIndex: pageIndex, normalizedPoint: normalizedPoint)
        }

        let editState = try makeEditingState(
            from: bridgeSession.insertNote(
                pageIndex: pageIndex,
                normalizedX: normalizedPoint.x,
                normalizedY: normalizedPoint.y,
                accidentalKind: accidentalKind.rawValue
            )
        )
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func insertNote(pageIndex: Int, normalizedPoint: CGPoint, pitchClass: Int, preferFlats: Bool) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(
            from: bridgeSession.insertNote(
                pageIndex: pageIndex,
                normalizedX: normalizedPoint.x,
                normalizedY: normalizedPoint.y,
                pitchClass: pitchClass,
                preferFlats: preferFlats
            )
        )
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func insertPitchAtCursor(_ pitchClass: Int, preferFlats: Bool, addToCurrentChord: Bool = false) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.insertPitchAtCursor(pitchClass, preferFlats: preferFlats, addToCurrentChord: addToCurrentChord))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func insertMIDIPitchAtCursor(_ midiPitch: Int, preferFlats: Bool, addToCurrentChord: Bool = false) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.insertMIDIPitchAtCursor(midiPitch, preferFlats: preferFlats, addToCurrentChord: addToCurrentChord))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func insertMIDIChordAtCursor(_ midiPitches: [Int], preferFlats: Bool) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.insertMIDIChordAtCursor(midiPitches.map { NSNumber(value: $0) }, preferFlats: preferFlats))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func noteEntryPreview(pageIndex: Int, normalizedPoint: CGPoint, duration: ScoreNoteDuration, isRest: Bool, accidentalKind: ScoreAccidentalKind?) throws -> ScoreNoteEntryPreview? {
        guard supportsEditing else {
            return nil
        }

        let bridgePreview = try bridgeSession.noteEntryPreview(
            pageIndex: pageIndex,
            normalizedX: Double(normalizedPoint.x),
            normalizedY: Double(normalizedPoint.y),
            durationCode: duration.rawValue,
            rest: isRest,
            accidentalKind: accidentalKind?.rawValue ?? -1
        )

        guard !bridgePreview.overlayImageData.isEmpty else {
            return nil
        }

        return ScoreNoteEntryPreview(
            pageIndex: Int(bridgePreview.pageIndex),
            overlayNormalizedRect: ScoreNormalizedRect(
                x: bridgePreview.overlayNormalizedX,
                y: bridgePreview.overlayNormalizedY,
                width: bridgePreview.overlayNormalizedWidth,
                height: bridgePreview.overlayNormalizedHeight
            ),
            overlayImageData: bridgePreview.overlayImageData
        )
    }

    func deleteSelection() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.deleteSelection())
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func clearSelectedMeasure() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.clearSelectedMeasure(), refreshScope: .nearby)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func removeSelectedMeasure() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.removeSelectedMeasure(), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func addMeasures(_ count: Int) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.addMeasures(count), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func setRegularMeasureCount(_ count: Int) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.setRegularMeasureCount(count), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func firstMeasurePickupState() throws -> ScorePickupMeasureState {
        guard supportsEditing else {
            return ScorePickupMeasureState(isPickup: false, actualNumerator: 0, actualDenominator: 0, nominalNumerator: 4, nominalDenominator: 4)
        }

        let info = try bridgeSession.firstMeasurePickupState()
        return ScorePickupMeasureState(
            isPickup: info.isPickup,
            actualNumerator: Int(info.actualNumerator),
            actualDenominator: Int(info.actualDenominator),
            nominalNumerator: Int(info.nominalNumerator),
            nominalDenominator: Int(info.nominalDenominator)
        )
    }

    func setFirstMeasurePickup(numerator: Int, denominator: Int) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(
            from: bridgeSession.setFirstMeasurePickup(numerator: numerator, denominator: denominator),
            refreshScope: .all
        )
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func createFirstPickupMeasure(numerator: Int, denominator: Int) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(
            from: bridgeSession.createFirstPickupMeasure(numerator: numerator, denominator: denominator),
            refreshScope: .all
        )
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func clearFirstMeasurePickup() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.clearFirstMeasurePickup(), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func copySelectedMeasureRange() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        return try makeEditingState(from: bridgeSession.copySelectedMeasureRange())
    }

    func cutSelectedMeasureRange() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.cutSelectedMeasureRange(), refreshScope: .nearby)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func pasteMeasureRange() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.pasteMeasureRange(), refreshScope: .nearby)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func transposeSelectedMeasureRange(_ request: ScoreTransposeRequest) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(
            from: bridgeSession.transposeSelectedMeasureRange(
                mode: request.mode.rawValue,
                direction: request.direction.rawValue,
                interval: request.interval,
                targetKey: request.targetKey
            ),
            refreshScope: .nearby
        )
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func movePitch(up: Bool) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: up ? bridgeSession.moveSelectedPitchUp() : bridgeSession.moveSelectedPitchDown())
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func shiftPitchBySemitones(_ semitoneDelta: Int) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.shiftSelectedPitchBySemitones(semitoneDelta))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func shiftPitchByOctaves(_ octaveDelta: Int) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.shiftSelectedPitchByOctaves(octaveDelta))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func setSelectedPitchClass(_ pitchClass: Int, preferFlats: Bool) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.setSelectedPitchClass(pitchClass, preferFlats: preferFlats))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func setSelectedMIDIPitch(_ midiPitch: Int, preferFlats: Bool) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.setSelectedMIDIPitch(midiPitch, preferFlats: preferFlats))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func replaceInstruments(_ instrumentIds: [String]) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.replaceInstruments(instrumentIds), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func addInstrument(_ instrumentId: String) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.addInstrument(instrumentId), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func removeInstrument(at partIndex: Int) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.removeInstrument(at: partIndex), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func moveInstrument(from sourceIndex: Int, to destinationIndex: Int) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.moveInstrument(from: sourceIndex, to: destinationIndex), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func removeSelectedInstrument() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.removeSelectedInstrument(), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func changeClef(_ clefKind: String) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.changeClef(clefKind), refreshScope: .nearby)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func setSelectedPitch(pageIndex: Int, normalizedPoint: CGPoint) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.setSelectedPitch(
            pageIndex: pageIndex,
            normalizedX: normalizedPoint.x,
            normalizedY: normalizedPoint.y
        ))
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func selectAdjacentElement(next: Bool) throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        return try makeEditingState(from: next ? bridgeSession.selectNextElement() : bridgeSession.selectPreviousElement())
    }

    func undoEdit() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.undoEdit(), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func redoEdit() throws -> ScoreEditingState {
        guard supportsEditing else {
            return inactiveEditingState()
        }

        let editState = try makeEditingState(from: bridgeSession.redoEdit(), refreshScope: .all)
        invalidateCachedPlaybackArtifacts()
        return editState
    }

    func updateMetadata(_ metadata: ScoreEditableMetadata) throws {
        guard supportsEditing else {
            throw ScoreDocumentServiceError.bridgeFailure("This score session does not support editing yet.")
        }

        try bridgeSession.updateMetadata(
            title: metadata.title,
            subtitle: metadata.subtitle,
            composer: metadata.composer,
            lyricist: metadata.lyricist,
            arranger: metadata.arranger
        )
        invalidateCachedPlaybackArtifacts()
    }

    func updateInitialKeySignature(_ keyValue: Int) throws {
        guard supportsEditing else {
            throw ScoreDocumentServiceError.bridgeFailure("This score session does not support editing yet.")
        }

        try bridgeSession.updateInitialKeySignature(keyValue)
        invalidateCachedPlaybackArtifacts()
    }

    func save(to url: URL) throws {
        guard supportsEditing else {
            throw ScoreDocumentServiceError.bridgeFailure("This score session does not support saving yet.")
        }

        try bridgeSession.save(to: url)
    }

    private func makeEditingState(from editState: MSREditState, refreshScope: ScoreEditRefreshScope = .local) throws -> ScoreEditingState {
        guard let duration = ScoreNoteDuration(rawValue: editState.durationCode) else {
            throw ScoreDocumentServiceError.bridgeFailure("Aria received an unsupported note duration from the score engine.")
        }

        let selection: ScoreSelectedElement?
        if let bridgeSelection = editState.selection {
            let kind: ScoreSelectedElementKind
            if bridgeSelection.isMeasure {
                kind = .measure
            } else if bridgeSelection.isTimeSignature {
                kind = .timeSignature
            } else if bridgeSelection.isKeySignature {
                kind = .keySignature
            } else if bridgeSelection.isTempo {
                kind = .tempo
            } else if bridgeSelection.isExpressionSpanner {
                kind = .expressionSpanner
            } else if bridgeSelection.isBar {
                kind = .bar
            } else if bridgeSelection.isChordText {
                kind = .chordText
            } else if bridgeSelection.isEditableText && bridgeSelection.textKind == "Dynamic" {
                kind = .dynamic
            } else if bridgeSelection.isEditableText {
                kind = .text
            } else if bridgeSelection.isRest {
                kind = .rest
            } else if bridgeSelection.isNote {
                kind = .note
            } else {
                kind = .other
            }
            let selectionDuration = ScoreNoteDuration(rawValue: bridgeSelection.durationCode) ?? duration
            let highlightRects = bridgeSelection.highlightRects.map {
                ScoreNormalizedRect(
                    x: $0.normalizedX,
                    y: $0.normalizedY,
                    width: $0.normalizedWidth,
                    height: $0.normalizedHeight
                )
            }
            let overlayImageData = bridgeSelection.overlayImageData.isEmpty ? nil : bridgeSelection.overlayImageData
            let overlayNormalizedRect = overlayImageData == nil ? nil : ScoreNormalizedRect(
                x: bridgeSelection.overlayNormalizedX,
                y: bridgeSelection.overlayNormalizedY,
                width: bridgeSelection.overlayNormalizedWidth,
                height: bridgeSelection.overlayNormalizedHeight
            )
            selection = ScoreSelectedElement(
                pageIndex: bridgeSelection.pageIndex,
                kind: kind,
                isSingleMeasure: bridgeSelection.isSingleMeasure,
                isFirstMeasure: bridgeSelection.isFirstMeasure,
                isPickupMeasure: bridgeSelection.isPickupMeasure,
                pickupNominalNumerator: Int(bridgeSelection.pickupNominalNumerator),
                pickupNominalDenominator: Int(bridgeSelection.pickupNominalDenominator),
                supportsBowingArticulations: bridgeSelection.supportsBowingArticulations,
                canChangePitch: bridgeSelection.canChangePitch,
                canFillWithSlashes: bridgeSelection.canFillWithSlashes,
                isDotted: bridgeSelection.isDotted,
                isTiedForward: bridgeSelection.isTiedForward,
                textContent: bridgeSelection.isEditableText ? bridgeSelection.textContent : nil,
                textKind: bridgeSelection.isEditableText ? bridgeSelection.textKind : nil,
                midiPitch: bridgeSelection.midiPitch >= 0 ? Int(bridgeSelection.midiPitch) : nil,
                chordMidiPitches: bridgeSelection.chordMidiPitches.map { Int(truncating: $0) },
                playbackBank: Int(bridgeSelection.playbackBank),
                playbackProgram: Int(bridgeSelection.playbackProgram),
                playbackSetupData: bridgeSelection.playbackSetupData,
                duration: selectionDuration,
                accidentalKind: ScoreAccidentalKind(rawValue: bridgeSelection.accidentalKind),
                diatonicStep: bridgeSelection.diatonicStep >= 0 ? Int(bridgeSelection.diatonicStep) : nil,
                currentKey: Int(bridgeSelection.currentKey),
                normalizedRect: ScoreNormalizedRect(
                    x: bridgeSelection.normalizedX,
                    y: bridgeSelection.normalizedY,
                    width: bridgeSelection.normalizedWidth,
                    height: bridgeSelection.normalizedHeight
                ),
                actionRect: ScoreNormalizedRect(
                    x: bridgeSelection.actionNormalizedX,
                    y: bridgeSelection.actionNormalizedY,
                    width: bridgeSelection.actionNormalizedWidth,
                    height: bridgeSelection.actionNormalizedHeight
                ),
                startHandlePoint: bridgeSelection.isExpressionSpanner ? CGPoint(
                    x: bridgeSelection.startHandleNormalizedX,
                    y: bridgeSelection.startHandleNormalizedY
                ) : nil,
                endHandlePoint: bridgeSelection.isExpressionSpanner ? CGPoint(
                    x: bridgeSelection.endHandleNormalizedX,
                    y: bridgeSelection.endHandleNormalizedY
                ) : nil,
                attachmentPoint: bridgeSelection.hasAttachmentPoint ? CGPoint(
                    x: bridgeSelection.attachmentNormalizedX,
                    y: bridgeSelection.attachmentNormalizedY
                ) : nil,
                attachmentTargets: bridgeSelection.attachmentTargets.map {
                    CGPoint(x: $0.normalizedX, y: $0.normalizedY)
                },
                highlightRects: highlightRects,
                overlayNormalizedRect: overlayNormalizedRect,
                overlayImageData: overlayImageData
            )
        } else {
            selection = nil
        }

        var refreshedPageCount = 0
        try bridgeSession.refreshTotalPageCount(&refreshedPageCount)

        return ScoreEditingState(
            selection: selection,
            noteInputEnabled: editState.noteInputEnabled,
            noteInputInsertsRests: editState.noteInputInsertsRests,
            noteInputIsDotted: editState.noteInputIsDotted,
            duration: duration,
            currentVoice: Int(editState.currentVoice),
            canUndo: editState.canUndo,
            canRedo: editState.canRedo,
            activeStaffIsPercussion: editState.activeStaffIsPercussion,
            createMultiMeasureRests: editState.createMultiMeasureRests,
            hideEmptyStaves: editState.hideEmptyStaves,
            refreshScope: refreshScope,
            pageCount: refreshedPageCount
        )
    }

    private func makeCorruptionReport(from bridgeReport: MSRScoreCorruptionReport) -> ScoreCorruptionReport {
        ScoreCorruptionReport(
            isCorrupted: bridgeReport.corrupted,
            details: bridgeReport.details,
            issues: bridgeReport.issues.map { issue in
                ScoreCorruptionIssue(
                    index: Int(issue.index),
                    measureNumber: Int(issue.measureNumber),
                    staffIndex: Int(issue.staffIndex),
                    voice: Int(issue.voice),
                    repairable: issue.repairable,
                    kind: issue.kind,
                    message: issue.message
                )
            }
        )
    }

    private func invalidateCachedPlaybackArtifacts() {
        cachedPlaybackMIDIData = nil
        cachedPlaybackMeasureRegions = nil
        playbackRevision += 1
        playbackChunkRequestCount = 0
        print("MuseReader playback invalidated: revision=\(playbackRevision)")
    }

    private func inactiveEditingState() -> ScoreEditingState {
        ScoreEditingState(
            selection: nil,
            noteInputEnabled: false,
            noteInputInsertsRests: false,
            noteInputIsDotted: false,
            duration: .quarter,
            currentVoice: 0,
            canUndo: false,
            canRedo: false,
            activeStaffIsPercussion: false,
            createMultiMeasureRests: false,
            hideEmptyStaves: false,
            refreshScope: .local,
            pageCount: nil
        )
    }
}
