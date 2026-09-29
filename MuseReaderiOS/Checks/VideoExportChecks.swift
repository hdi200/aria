import Foundation
import UIKit
import AVFoundation
import AudioToolbox

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

        try await checkPiano(directory: directory)
        if CommandLine.arguments.count > 3 {
            try await renderPianoSamples(midi: URL(fileURLWithPath: CommandLine.arguments[2]),
                                         to: URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true))
        }
    }

    /// One track at 120 bpm: C4, E4, G4 half a second each, plus a drum hit
    /// on channel 10 that has no key and must be left out.
    static func syntheticMIDI() -> Data {
        var events: [UInt8] = [0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]
        events += [0x00, 0x99, 36, 100]
        for pitch in [60, 64, 67] {
            events += [0x00, 0x90, UInt8(pitch), 90]
            events += [0x83, 0x60, 0x80, UInt8(pitch), 0]  // 480 ticks later
        }
        events += [0x00, 0x89, 36, 0, 0x00, 0xFF, 0x2F, 0x00]
        let length = UInt32(events.count)
        let header: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
        let track: [UInt8] = Array("MTrk".utf8) + [UInt8(length >> 24), UInt8(length >> 16 & 0xFF),
                                                   UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)]
        return Data(header + track + events)
    }

    static func checkPiano(directory: URL) async throws {
        let notes = ScoreVideoPianoNotes.notes(fromMIDI: syntheticMIDI())
        try expect(notes.map(\.pitch) == [60, 64, 67], "Piano notes misread or drums kept: \(notes)")
        try expect(zip(notes.map(\.startSeconds), [0, 0.5, 1.0]).allSatisfy { abs($0 - $1) < 0.001 }
                   && notes.allSatisfy { abs($0.endSeconds - $0.startSeconds - 0.5) < 0.001 }, "Piano note timing wrong")

        let narrow = ScoreVideoPianoKeyboard(pitches: [60, 67], width: 1920)
        try expect(narrow.highestPitch - narrow.lowestPitch >= 36, "Keyboard narrower than three octaves")
        try expect(!ScoreVideoPianoKeyboard.isBlack(narrow.lowestPitch) && !ScoreVideoPianoKeyboard.isBlack(narrow.highestPitch),
                   "Keyboard ends on a black key")
        let wide = ScoreVideoPianoKeyboard(pitches: [10, 120], width: 1920)
        try expect(wide.lowestPitch == 21 && wide.highestPitch == 108, "Keyboard exceeds a real piano")
        try expect(abs(wide.centerX(of: 21) - wide.whiteKeyWidth / 2) < 0.01
                   && abs(wide.centerX(of: 108) + wide.whiteKeyWidth / 2 - 1920) < 0.01, "Keys do not fill the width")

        let output = directory.appendingPathComponent("piano.mp4")
        let session = LiveScoreRenderSession(page: Data(), midi: syntheticMIDI())
        try await ScoreVideoExporter.export(liveRenderSession: session, pageCount: 0, to: output,
                                            options: ScoreVideoExportOptions(style: .piano, title: "Piano check", composer: "",
                                                                             reverbSendLevel: 0),
                                            progress: { _ in })
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        let video = try await asset.loadTracks(withMediaType: .video)
        try expect(abs(duration.seconds - 4) < 0.1 && video.count == 1, "Piano video duration or track wrong")
        try expect(await !session.continuous, "Piano export changed the layout")

        let silent = LiveScoreRenderSession(page: Data(), midi: Data())
        do {
            try await ScoreVideoExporter.export(liveRenderSession: silent, pageCount: 0, to: output,
                                                options: ScoreVideoExportOptions(style: .piano, title: "", composer: ""),
                                                progress: { _ in })
            throw CheckFailure(message: "Piano export without notes succeeded")
        } catch ScoreVideoExportError.noPianoNotes { }
        print("Piano video checks passed: MIDI notes and timing, keyboard range, export")
    }

    /// Stills and a short MP4 from a real score's playback MIDI, to look at.
    /// The stub's audio is silent; bars are taken as four beats at the
    /// opening tempo.
    static func renderPianoSamples(midi: URL, to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Data(contentsOf: midi)
        let notes = ScoreVideoPianoNotes.notes(fromMIDI: data)
        try expect(!notes.isEmpty, "No notes in \(midi.lastPathComponent)")
        let barSeconds = openingBarSeconds(data)
        let bars = Int((min(notes.map(\.endSeconds).max() ?? 1, 40) / barSeconds).rounded(.up))
        let seconds = Int((Double(bars) * barSeconds).rounded())
        let session = LiveScoreRenderSession(page: Data(), midi: data, regionCount: bars, barSeconds: barSeconds)
        let photo = samplePhoto()
        for style in [ScoreVideoStyle.piano, .pianoLight, .pianoPhoto] {
            let options = ScoreVideoExportOptions(style: style, title: midi.deletingPathExtension().lastPathComponent,
                                                  composer: "Piano sample", reverbSendLevel: 0,
                                                  backgroundImageData: style.usesPhoto ? photo : nil)
            let timeline = ScoreVideoTimeline(regions: try await session.playbackMeasureRegions())
            let painter = ScoreVideoPianoPainter(frameSize: options.style.frameSize, notes: notes, timeline: timeline, options: options)
            let first = painter.firstNoteSeconds
            for time in [first, first + 2.3, first + 9.6] {
                var buffer: CVPixelBuffer?
                CVPixelBufferCreate(nil, 1920, 1080, kCVPixelFormatType_32BGRA,
                                    [kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                                     kCVPixelBufferMetalCompatibilityKey as String: true] as CFDictionary, &buffer)
                guard let buffer else { throw CheckFailure(message: "No pixel buffer") }
                painter.draw(into: buffer, at: time, frameDuration: 1 / 30)
                // Timed again once the cached layers exist, as in an export.
                let start = Date()
                painter.draw(into: buffer, at: time, frameDuration: 1 / 30)
                let milliseconds = Date().timeIntervalSince(start) * 1000
                CVPixelBufferLockBaseAddress(buffer, .readOnly)
                let image = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 1920, height: 1080, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?.makeImage()
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
                guard let image, let png = UIImage(cgImage: image).pngData() else { throw CheckFailure(message: "No still") }
                try png.write(to: directory.appendingPathComponent(String(format: "%@-%04.1fs.png", style.rawValue, time)))
                print(String(format: "%@ still at %.1fs drawn in %.1f ms", style.rawValue, time, milliseconds))
            }
            let video = directory.appendingPathComponent("\(style.rawValue)-sample.mp4")
            let start = Date()
            try await ScoreVideoExporter.export(liveRenderSession: session, pageCount: 0, to: video, options: options, progress: { _ in })
            print(String(format: "%@ sample: %d s of music rendered in %.1f s", style.rawValue, seconds, Date().timeIntervalSince(start)))
        }
    }

    /// A stand-in photo: a soft sky with a few pale shapes.
    static func samplePhoto() -> Data? {
        UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1000)).image { context in
            let colors = [UIColor(red: 0.72, green: 0.80, blue: 0.90, alpha: 1).cgColor,
                          UIColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 1000), options: [])
            for (x, y, radius, white) in [(300.0, 500.0, 260.0, 0.55), (1250, 380, 320, 0.95), (800, 820, 200, 0.7)] {
                UIColor(white: white, alpha: 0.8).setFill()
                UIBezierPath(ovalIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
            }
        }.jpegData(compressionQuality: 0.9)
    }

    static func openingBarSeconds(_ midi: Data) -> TimeInterval {
        var sequence: MusicSequence?
        NewMusicSequence(&sequence)
        guard let sequence, MusicSequenceFileLoadData(sequence, midi as CFData, .midiType, []) == noErr else { return 2 }
        defer { DisposeMusicSequence(sequence) }
        var seconds: Float64 = 2
        MusicSequenceGetSecondsForBeats(sequence, 4, &seconds)
        return seconds
    }
}
