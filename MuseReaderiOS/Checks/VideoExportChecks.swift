import Foundation
import UIKit
import AVFoundation

// A short correctness check, not a rendering benchmark. Compile together with
// VideoExportStubs.swift and the real Services/ScoreVideoExporter.swift.
@main
struct VideoExportChecks {
    struct CheckFailure: Error { let message: String }
    static func expect(_ value: Bool, _ message: String) throws {
        if !value { throw CheckFailure(message: message) }
    }

    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 900, height: 240)).pdfData { renderer in
            renderer.beginPage()
            UIColor.white.setFill()
            renderer.cgContext.fill(CGRect(x: 0, y: 0, width: 900, height: 240))
            UIColor.black.setStroke()
            renderer.cgContext.setLineWidth(1)
            for y in stride(from: 70, through: 110, by: 10) {
                renderer.cgContext.move(to: CGPoint(x: 70, y: y))
                renderer.cgContext.addLine(to: CGPoint(x: 850, y: y))
            }
            renderer.cgContext.strokePath()
            UIColor.black.setFill()
            renderer.cgContext.fillEllipse(in: CGRect(x: 200, y: 96, width: 18, height: 12))
        }
        let output = directory.appendingPathComponent("pipeline.mp4")
        let options = ScoreVideoExportOptions(style: .scrolling, title: "Pipeline check", composer: "",
                                             reverbSendLevel: 0)
        let session = LiveScoreRenderSession(page: pdf)
        try await ScoreVideoExporter.export(liveRenderSession: session, pageCount: 1, to: output,
                                            options: options, progress: { _ in })
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        try expect(abs(duration.seconds - 4) < 0.1, "Duration/tail changed")
        try expect(video.count == 1 && audio.count == 1, "Missing audio or video track")
        let dimensions = try await video[0].load(.naturalSize)
        let frameRate = try await video[0].load(.nominalFrameRate)
        try expect(dimensions == CGSize(width: 1920, height: 1080) && frameRate == 30, "Output quality changed")
        try expect(await session.maxInFlight == 1, "Concurrent synth requests")
        try expect(await session.requests == 4, "Unexpected unbounded audio prefetch")
        try expect(await !session.requestedStems, "Video requested stems")
        let continuous = await session.continuous
        let inFlight = await session.inFlight
        try expect(!continuous && inFlight == 0, "Layout restored before audio drained")

        for mode in [LiveScoreRenderSession.Mode.secondChunkFailure, .formatChange, .cancellation] {
            let failing = LiveScoreRenderSession(page: pdf, mode: mode)
            let failedOutput = directory.appendingPathComponent("\(mode).mp4")
            let task = Task {
                try await ScoreVideoExporter.export(liveRenderSession: failing, pageCount: 1, to: failedOutput,
                                                    options: options, progress: { _ in })
            }
            if mode == .cancellation {
                // Cancel during prefetch, after the first chunk starts writing.
                while await failing.requests < 2 { try await Task.sleep(nanoseconds: 2_000_000) }
                task.cancel()
            }
            do {
                try await task.value
                throw CheckFailure(message: "Expected \(mode) to fail")
            } catch is CheckFailure { throw CheckFailure(message: "Failure was not propagated") }
            catch { }
            try expect(!FileManager.default.fileExists(atPath: failedOutput.path), "Partial output was retained")
            let continuous = await failing.continuous
            let inFlight = await failing.inFlight
            try expect(!continuous && inFlight == 0, "Failed export leaked prefetch/layout")
        }
        print("Video export pipeline checks passed: A/V tracks, quality, bounded prefetch, errors and cancellation")
    }
}
