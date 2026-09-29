// Standalone dependencies for the exporter pipeline checks, not app sources.
import Foundation
import UIKit

struct ScoreNormalizedRect: Sendable, Equatable {
    let x: Double, y: Double, width: Double, height: Double
}
struct ScorePlaybackMeasureRegion: Sendable, Equatable {
    let measureIndex: Int, pageIndex: Int
    let startTimeSeconds: TimeInterval, endTimeSeconds: TimeInterval
    let normalizedRect: ScoreNormalizedRect
}
struct ScorePlaybackBeatPoint: Sendable, Equatable {
    let pageIndex: Int
    let timeSeconds: TimeInterval, normalizedX: Double
    let startsSegment: Bool
}
struct ScorePage: Sendable {
    let pdfData: Data?
    func rasterizedImage() -> UIImage? { nil }
}
enum ScoreReaderExportError: Error { case noAudio }
nonisolated final class MSRPlaybackReverb {
    init(sampleRate: Double) {}
    func processInterleavedStereo(_ samples: UnsafeMutablePointer<Float>, frameCount: Int) {}
}
nonisolated final class MSRPlaybackAudioData: @unchecked Sendable {
    let sampleRate: Int, channelCount: Int
    let interleavedFloat32Samples: Data
    init(sampleRate: Int, channelCount: Int, samples: Data) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        interleavedFloat32Samples = samples
    }
}
actor LiveScoreRenderSession {
    enum Failure: Error { case injected }
    enum Mode: Sendable { case normal, secondChunkFailure, formatChange, cancellation }
    let page: Data
    let mode: Mode
    let midi: Data
    let regionCount: Int
    let barSeconds: TimeInterval
    private(set) var continuous = false
    private(set) var requests = 0
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0
    private(set) var requestedStems = false

    init(page: Data, mode: Mode = .normal, midi: Data = Data(), regionCount: Int = 2, barSeconds: TimeInterval = 1) {
        self.page = page; self.mode = mode; self.midi = midi; self.regionCount = regionCount; self.barSeconds = barSeconds
    }
    func setContinuousLayout(_ enabled: Bool) throws -> Int { continuous = enabled; return 1 }
    /// Evenly timed bars (one second by default) across the page.
    func playbackMeasureRegions() throws -> [ScorePlaybackMeasureRegion] {
        (0..<regionCount).map { index in
            let width = 0.8 / Double(regionCount)
            return ScorePlaybackMeasureRegion(measureIndex: index, pageIndex: 0, startTimeSeconds: Double(index) * barSeconds,
                                              endTimeSeconds: Double(index + 1) * barSeconds,
                                              normalizedRect: ScoreNormalizedRect(x: 0.1 + width * Double(index), y: 0.25,
                                                                                  width: width, height: 0.5))
        }
    }
    func playbackMIDIData() throws -> Data { midi }
    func playbackBeatPoints() throws -> [ScorePlaybackBeatPoint] { [] }
    func renderPage(at index: Int, dpi: Int) throws -> ScorePage { ScorePage(pdfData: page) }
    func playbackAudioChunk(startTimeSeconds: TimeInterval, durationSeconds: TimeInterval,
                            metronomeEnabled: Bool, includePartSamples: Bool = true) async throws -> MSRPlaybackAudioData {
        requestedStems = requestedStems || includePartSamples
        requests += 1
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        // Exercise reentrancy while the next chunk is being prepared.
        try await Task.sleep(nanoseconds: mode == .cancellation ? 500_000_000 : 10_000_000)
        if mode == .secondChunkFailure && requests == 2 { throw Failure.injected }
        let sampleRate = mode == .formatChange && requests > 1 ? 44_100 : 48_000
        let samples = [Float](repeating: 0.05, count: Int(durationSeconds * Double(sampleRate)) * 2)
        let data = samples.withUnsafeBytes { Data($0) }
        return MSRPlaybackAudioData(sampleRate: sampleRate, channelCount: 2, samples: data)
    }
}
