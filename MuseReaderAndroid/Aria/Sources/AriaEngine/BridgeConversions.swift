// Converts the render core's C++ results into the bridge's Swift objects, as the iOS
// bridge's Make* functions do (MuseScoreRenderCoreBridge.mm).

@_implementationOnly import AriaRenderCoreCxx
@_implementationOnly import CxxStdlib
import Foundation

// Android only: the iOS app has its own Objective-C++ bridge.

func makeString(_ value: std.string) -> String {
    String(value)
}

func makeData(_ bytes: aria.Bytes) -> Data {
    bytes.empty() ? Data() : Data(bytes: bytes.__dataUnsafe(), count: bytes.size())
}

func makeFloatData(_ samples: aria.Floats) -> Data {
    samples.empty() ? Data() : Data(bytes: samples.__dataUnsafe(), count: samples.size() * MemoryLayout<Float>.size)
}

func makeRenderedPage(_ page: msr.render.RenderedPage) -> MSRRenderedPage {
    var markers: [MSRLayoutBreakMarker] = []
    for marker in page.layoutBreakMarkers {
        markers.append(MSRLayoutBreakMarker(kind: makeString(marker.kind),
                                            normalizedX: marker.normalizedX,
                                            normalizedY: marker.normalizedY,
                                            normalizedWidth: marker.normalizedWidth,
                                            normalizedHeight: marker.normalizedHeight))
    }
    return MSRRenderedPage(pageIndex: Int(page.pageIndex),
                           pixelWidth: Int(page.pixelWidth),
                           pixelHeight: Int(page.pixelHeight),
                           imageData: makeData(page.pngData),
                           pdfData: makeData(page.pdfData),
                           layoutBreakMarkers: markers)
}

func makeScorePartInfos(_ parts: aria.ScorePartInfos) -> [MSRScorePartInfo] {
    parts.map {
        MSRScorePartInfo(index: Int($0.index), partID: makeString($0.partId), name: makeString($0.name), visible: $0.visible)
    }
}

func makePlaybackMeasureRegion(_ region: msr.render.PlaybackMeasureRegion) -> MSRPlaybackMeasureRegion {
    MSRPlaybackMeasureRegion(measureEID: makeString(region.measureEid),
                             measure: Int(region.measureIndex),
                             pageIndex: Int(region.pageIndex),
                             startTimeSeconds: region.startTimeSeconds,
                             endTimeSeconds: region.endTimeSeconds,
                             normalizedX: region.normalizedX,
                             normalizedY: region.normalizedY,
                             normalizedWidth: region.normalizedWidth,
                             normalizedHeight: region.normalizedHeight)
}

func makeScoreCorruptionReport(_ report: msr.render.ScoreCorruptionReport) -> MSRScoreCorruptionReport {
    var issues: [MSRScoreCorruptionIssue] = []
    for issue in report.issues {
        issues.append(MSRScoreCorruptionIssue(index: issues.count,
                                              measureNumber: Int(issue.measureNumber),
                                              staffIndex: Int(issue.staffIndex),
                                              voice: Int(issue.voice),
                                              repairable: issue.repairable,
                                              kind: makeString(issue.kind),
                                              message: makeString(issue.message)))
    }
    return MSRScoreCorruptionReport(corrupted: report.corrupted, details: makeString(report.details), issues: issues)
}

func makeNoteEntryPreviewInfo(_ preview: msr.render.NoteEntryPreviewState) -> MSRNoteEntryPreviewInfo {
    guard preview.hasPreview, !preview.overlayPngData.empty() else {
        return MSRNoteEntryPreviewInfo(pageIndex: -1, overlayNormalizedX: 0, overlayNormalizedY: 0,
                                       overlayNormalizedWidth: 0, overlayNormalizedHeight: 0,
                                       overlayPixelWidth: 0, overlayPixelHeight: 0, overlayImageData: Data())
    }
    return MSRNoteEntryPreviewInfo(pageIndex: Int(preview.pageIndex),
                                   overlayNormalizedX: preview.overlayNormalizedX,
                                   overlayNormalizedY: preview.overlayNormalizedY,
                                   overlayNormalizedWidth: preview.overlayNormalizedWidth,
                                   overlayNormalizedHeight: preview.overlayNormalizedHeight,
                                   overlayPixelWidth: Int(preview.overlayPixelWidth),
                                   overlayPixelHeight: Int(preview.overlayPixelHeight),
                                   overlayImageData: makeData(preview.overlayPngData))
}

func makePlaybackAudioData(_ audio: msr.render.PlaybackAudioData) -> MSRPlaybackAudioData {
    var stems: [String: Data] = [:]
    for partId in aria.partSampleIds(audio) {
        var count = 0
        if let samples = aria.partSampleData(audio, partId, &count), count > 0 {
            stems[makeString(partId)] = Data(bytes: samples, count: count * MemoryLayout<Float>.size)
        }
    }
    return MSRPlaybackAudioData(sampleRate: Int(audio.sampleRate),
                                channelCount: Int(audio.channelCount),
                                durationSeconds: audio.durationSeconds,
                                interleavedFloat32Samples: makeFloatData(audio.interleavedSamples),
                                partSamples: stems)
}

func makeSelectionInfo(_ selection: msr.render.ScoreSelectionState) -> MSRSelectionInfo? {
    guard selection.hasSelection else {
        return nil
    }
    let chordMidiPitches = selection.chordMidiPitches.map { NSNumber(value: Int($0)) }
    let highlightRects = selection.highlightRects.map {
        MSRNormalizedRectInfo(normalizedX: $0.normalizedX, normalizedY: $0.normalizedY,
                              normalizedWidth: $0.normalizedWidth, normalizedHeight: $0.normalizedHeight)
    }
    let attachmentTargets = selection.attachmentTargets.map {
        MSRNormalizedPointInfo(normalizedX: $0.normalizedX, normalizedY: $0.normalizedY)
    }
    let info = MSRSelectionInfo(pageIndex: Int(selection.pageIndex),
                                isNote: selection.isNote,
                                isRest: selection.isRest,
                                isBar: selection.isBar,
                                isMeasure: selection.isMeasure,
                                isSingleMeasure: selection.isSingleMeasure,
                                isTimeSignature: selection.isTimeSignature,
                                isKeySignature: selection.isKeySignature,
                                isTempo: selection.isTempo,
                                isLayoutBreak: selection.isLayoutBreak,
                                layoutBreakType: makeString(selection.layoutBreakType),
                                isExpressionSpanner: selection.isExpressionSpanner,
                                isSlur: selection.isSlur,
                                isTie: selection.isTie,
                                isHairpin: selection.isHairpin,
                                isInstrumentName: selection.isInstrumentName,
                                isInstrumentChange: selection.isInstrumentChange,
                                isEditableText: selection.isEditableText,
                                isChordText: selection.isChordText,
                                canDragMovableElement: selection.canDragMovableElement,
                                canChangePitch: selection.canChangePitch,
                                canFillWithSlashes: selection.canFillWithSlashes,
                                isDotted: selection.isDotted,
                                isTiedForward: selection.isTiedForward,
                                textContent: makeString(selection.textContent),
                                textKind: makeString(selection.textKind),
                                partID: makeString(selection.partId),
                                instrumentID: makeString(selection.instrumentId),
                                instrumentName: makeString(selection.instrumentName),
                                measure: Int(selection.measureIndex),
                                tick: Int64(selection.tick),
                                midiPitch: Int(selection.midiPitch),
                                chordMidiPitches: chordMidiPitches,
                                playbackBank: Int(selection.playbackBank),
                                playbackProgram: Int(selection.playbackProgram),
                                playbackSetupData: makeString(selection.playbackSetupData),
                                supportsBowingArticulations: selection.supportsBowingArticulations,
                                durationCode: Int(selection.durationCode),
                                accidentalKind: Int(selection.accidentalKind),
                                diatonicStep: Int(selection.diatonicStep),
                                currentKey: Int(selection.currentKey),
                                currentTimeSignatureNumerator: Int(selection.currentTimeSignatureNumerator),
                                currentTimeSignatureDenominator: Int(selection.currentTimeSignatureDenominator),
                                normalizedX: selection.normalizedX,
                                normalizedY: selection.normalizedY,
                                normalizedWidth: selection.normalizedWidth,
                                normalizedHeight: selection.normalizedHeight,
                                actionNormalizedX: selection.actionNormalizedX,
                                actionNormalizedY: selection.actionNormalizedY,
                                actionNormalizedWidth: selection.actionNormalizedWidth,
                                actionNormalizedHeight: selection.actionNormalizedHeight,
                                startHandleNormalizedX: selection.startHandleNormalizedX,
                                startHandleNormalizedY: selection.startHandleNormalizedY,
                                endHandleNormalizedX: selection.endHandleNormalizedX,
                                endHandleNormalizedY: selection.endHandleNormalizedY,
                                hasAttachmentPoint: selection.hasAttachmentPoint,
                                attachmentNormalizedX: selection.attachmentNormalizedX,
                                attachmentNormalizedY: selection.attachmentNormalizedY,
                                attachmentTargets: attachmentTargets,
                                highlightRects: highlightRects,
                                overlayNormalizedX: selection.overlayNormalizedX,
                                overlayNormalizedY: selection.overlayNormalizedY,
                                overlayNormalizedWidth: selection.overlayNormalizedWidth,
                                overlayNormalizedHeight: selection.overlayNormalizedHeight,
                                overlayPixelWidth: Int(selection.overlayPixelWidth),
                                overlayPixelHeight: Int(selection.overlayPixelHeight),
                                overlayImageData: makeData(selection.overlayPngData),
                                overlayPdfData: makeData(selection.overlayPdfData))
    info.isFirstMeasure = selection.isFirstMeasure
    info.isPickupMeasure = selection.isPickupMeasure
    info.pickupActualNumerator = Int(selection.pickupActualNumerator)
    info.pickupActualDenominator = Int(selection.pickupActualDenominator)
    info.pickupNominalNumerator = Int(selection.pickupNominalNumerator)
    info.pickupNominalDenominator = Int(selection.pickupNominalDenominator)
    var otherRects: [MSRNormalizedRectInfo] = []
    var otherPageIndexes: [NSNumber] = []
    for pageRect in selection.otherPageHighlightRects {
        otherRects.append(MSRNormalizedRectInfo(normalizedX: pageRect.rect.normalizedX,
                                                normalizedY: pageRect.rect.normalizedY,
                                                normalizedWidth: pageRect.rect.normalizedWidth,
                                                normalizedHeight: pageRect.rect.normalizedHeight))
        otherPageIndexes.append(NSNumber(value: Int(pageRect.pageIndex)))
    }
    info.otherPageHighlightRects = otherRects
    info.otherPageHighlightPageIndexes = otherPageIndexes
    return info
}

func makePickupMeasureInfo(_ pickup: msr.render.PickupMeasureState) -> MSRPickupMeasureInfo {
    MSRPickupMeasureInfo(isPickup: pickup.isPickup,
                         actualNumerator: Int(pickup.actualNumerator),
                         actualDenominator: Int(pickup.actualDenominator),
                         nominalNumerator: Int(pickup.nominalNumerator),
                         nominalDenominator: Int(pickup.nominalDenominator))
}

func makeEditState(_ state: msr.render.ScoreEditState) -> MSREditState {
    MSREditState(selection: makeSelectionInfo(state.selection),
                 noteInputEnabled: state.noteInputEnabled,
                 noteInputInsertsRests: state.noteInputInsertsRests,
                 noteInputIsDotted: state.noteInputIsDotted,
                 durationCode: Int(state.durationCode),
                 currentVoice: Int(state.currentVoice),
                 canUndo: state.canUndo,
                 canRedo: state.canRedo,
                 activeStaffIsPercussion: state.activeStaffIsPercussion,
                 createMultiMeasureRests: state.createMultiMeasureRests,
                 hideEmptyStaves: state.hideEmptyStaves,
                 pageWidthMillimeters: state.pageWidthMillimeters,
                 pageHeightMillimeters: state.pageHeightMillimeters,
                 pageMarginMillimeters: state.pageMarginMillimeters,
                 staffSizeMillimeters: state.staffSizeMillimeters,
                 staffSpacingSpatium: state.staffSpacingSpatium,
                 systemSpacingSpatium: state.systemSpacingSpatium)
}

