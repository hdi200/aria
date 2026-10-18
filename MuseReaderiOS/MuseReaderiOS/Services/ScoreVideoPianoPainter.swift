//
//  ScoreVideoPianoPainter.swift
//  MuseReaderiOS
//

import AudioToolbox
import CoreImage
import Metal
import UIKit

enum ScoreVideoPianoNotes {
    /// The notes of a MIDI file, with beats converted to seconds through its
    /// tempo map; percussion is left out. Used by the checks to render samples
    /// from MIDI. Videos read `LiveScoreRenderSession.playbackNotes()`
    /// instead: MuseScore's MIDI export applies a section break's pause and
    /// the next section's tempo to every pass of a repeat, so it drifts from
    /// the audio (goldberg ends 161 s late).
    static func notes(fromMIDI data: Data) -> [ScoreVideoPianoNote] {
        #if os(Android)
        // Only the checks read MIDI; Android has no MusicSequence.
        return []
        #else
        var sequenceRef: MusicSequence?
        guard NewMusicSequence(&sequenceRef) == noErr, let sequence = sequenceRef else { return [] }
        defer { DisposeMusicSequence(sequence) }
        guard MusicSequenceFileLoadData(sequence, data as CFData, .midiType, []) == noErr else { return [] }

        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)
        var notes: [ScoreVideoPianoNote] = []
        var noteTrack = 0
        for trackIndex in 0..<trackCount {
            var trackRef: MusicTrack?
            var iteratorRef: MusicEventIterator?
            guard MusicSequenceGetIndTrack(sequence, trackIndex, &trackRef) == noErr, let track = trackRef,
                  NewMusicEventIterator(track, &iteratorRef) == noErr, let iterator = iteratorRef
            else { continue }
            defer { DisposeMusicEventIterator(iterator) }

            var foundNotes = false
            var hasEvent: DarwinBoolean = false
            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
            while hasEvent.boolValue {
                var beat: MusicTimeStamp = 0
                var type: MusicEventType = 0
                var eventData: UnsafeRawPointer?
                var eventSize: UInt32 = 0
                MusicEventIteratorGetEventInfo(iterator, &beat, &type, &eventData, &eventSize)
                if type == kMusicEventType_MIDINoteMessage, let eventData {
                    let message = eventData.assumingMemoryBound(to: MIDINoteMessage.self).pointee
                    if message.channel != 9, message.velocity > 0 {
                        var start: Float64 = 0
                        var end: Float64 = 0
                        MusicSequenceGetSecondsForBeats(sequence, beat, &start)
                        MusicSequenceGetSecondsForBeats(sequence, beat + MusicTimeStamp(message.duration), &end)
                        notes.append(ScoreVideoPianoNote(pitch: Int(message.note), startSeconds: start,
                                                         endSeconds: max(end, start + 0.02), track: noteTrack))
                        foundNotes = true
                    }
                }
                MusicEventIteratorNextEvent(iterator)
                MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
            }
            if foundNotes { noteTrack += 1 }
        }
        return notes.sorted { ($0.startSeconds, $0.pitch) < ($1.startSeconds, $1.pitch) }
        #endif
    }
}

/// A piano-roll visualizer: the notes fall towards a keyboard and light
/// their keys while they sound. Each frame draws the notes and the keyboard
/// with Core Graphics, then Core Image blurs the notes into a glow and
/// composes everything over the cached background, on Metal where available.
#if os(Android) && !ARIA_VIDEO_MAIN_BASELINE
@AndroidVideoRenderActor
#endif
final class ScoreVideoPianoPainter: ScoreVideoPainterBase, ScoreVideoPainter {
    /// How far ahead a note first appears at the top of the frame.
    static let lookaheadSeconds: TimeInterval = 4.5
    private static let keyboardHeightFraction: CGFloat = 0.185
    private static let blackKeyHeightFraction: CGFloat = 0.63
    private static let trackColors: [UIColor] = [
        UIColor(red: 0.16, green: 0.90, blue: 0.45, alpha: 1),
        UIColor(red: 0.18, green: 0.56, blue: 1.00, alpha: 1),
        UIColor(red: 1.00, green: 0.66, blue: 0.14, alpha: 1),
        UIColor(red: 1.00, green: 0.32, blue: 0.66, alpha: 1),
        UIColor(red: 0.64, green: 0.44, blue: 1.00, alpha: 1),
        UIColor(red: 0.10, green: 0.84, blue: 0.80, alpha: 1)
    ]
    private static let scrubberColor = UIColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1)

    private nonisolated struct VisibleNote {
        let rect: CGRect
        let track: Int
        let active: Bool
    }

    private let theme: ScoreVideoPianoTheme
    private let notes: [ScoreVideoPianoNote]
    private let longestNote: TimeInterval
    private let keyboard: ScoreVideoPianoKeyboard
    private let keyboardTop: CGFloat
    /// The frame's bottom, or above the caption area on vertical video.
    private let keyboardBottom: CGFloat
    private let blackKeyHeight: CGFloat
    /// Room above the keyboard in its layer, for the flares and scrubber.
    private let flareRoom: CGFloat
    private let scale: CGFloat
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let imageContext: CIContext
    private let notesLayer: CGContext?
    private let keysLayer: CGContext?
    private lazy var background: CIImage = makeBackground()
    private lazy var idleKeyboard: CGImage? = makeKeyboardImage(whiteKeys: true)
    private lazy var blackKeys: CGImage? = makeKeyboardImage(whiteKeys: false)
    private lazy var titleOverlay: (image: CIImage, rect: CGRect)? = makeTitleOverlay()
    private lazy var fades: [CGGradient] = Self.trackColors.map { gradient($0, from: 1, to: 0) }
    private lazy var whiteFade: CGGradient = gradient(.white, from: 1, to: 0)

    init(frameSize: CGSize, notes: [ScoreVideoPianoNote], timeline: ScoreVideoTimeline, options: ScoreVideoExportOptions) {
        let keyboard = ScoreVideoPianoKeyboard(pitches: notes.map(\.pitch), width: frameSize.width)
        let shown = notes.filter { keyboard.pitches.contains($0.pitch) }
        self.keyboard = keyboard
        self.notes = shown
        longestNote = shown.map { $0.endSeconds - $0.startSeconds }.max() ?? 0
        switch options.style {
        case .pianoLight: theme = .light
        case .pianoPhoto: theme = options.backgroundImageData == nil ? .dark : .photo
        default: theme = .dark
        }
        // Sizes follow the short side, so vertical video is not drawn oversized.
        let scale = min(frameSize.width, frameSize.height) / 1080
        self.scale = scale
        // Reels and TikTok lay captions over the lower fifth of vertical video,
        // so the keyboard sits above it; its height follows the key width.
        let vertical = frameSize.height > frameSize.width
        keyboardBottom = vertical ? (frameSize.height * 0.8).rounded() : frameSize.height
        let keyboardHeight = min(frameSize.height * Self.keyboardHeightFraction, frameSize.width * 0.22)
        keyboardTop = (keyboardBottom - keyboardHeight).rounded()
        blackKeyHeight = ((keyboardBottom - keyboardTop) * Self.blackKeyHeightFraction).rounded()
        flareRoom = (80 * scale).rounded()
        imageContext = MTLCreateSystemDefaultDevice().map {
            CIContext(mtlDevice: $0, options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                               .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                               .cacheIntermediates: false])
        } ?? CIContext(options: [.cacheIntermediates: false])
        notesLayer = Self.layer(width: frameSize.width, height: frameSize.height)
        keysLayer = Self.layer(width: frameSize.width, height: keyboardBottom - keyboardTop + flareRoom)
        super.init(frameSize: frameSize, timeline: timeline, options: options)
    }

    /// A transparent bitmap drawn in top-left coordinates, reused every frame.
    private static func layer(width: CGFloat, height: CGFloat) -> CGContext? {
        let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        context?.translateBy(x: 0, y: height)
        context?.scaleBy(x: 1, y: -1)
        return context
    }

    /// When the first note sounds: the preview shows the keys lit.
    var firstNoteSeconds: TimeInterval {
        notes.first?.startSeconds ?? 0
    }

    private func y(at time: TimeInterval, now: TimeInterval) -> CGFloat {
        keyboardTop - CGFloat((time - now) / Self.lookaheadSeconds) * keyboardTop
    }

    private func color(track: Int) -> UIColor {
        Self.trackColors[track % Self.trackColors.count]
    }

    private func gradient(_ color: UIColor, from start: CGFloat, to end: CGFloat) -> CGGradient {
        CGGradient(colorsSpace: colorSpace,
                   colors: [color.withAlphaComponent(start).cgColor, color.withAlphaComponent(end).cgColor] as CFArray,
                   locations: [0, 1])!
    }

    func draw(into pixelBuffer: CVPixelBuffer, at time: TimeInterval, frameDuration: TimeInterval) {
        guard let notesLayer, let keysLayer else { return }
        let visible = visibleNotes(now: time)
        var sounding: [Int: Int] = [:]
        for note in visible.notes where note.active { sounding[note.pitch] = note.track }

        drawNotesLayer(notesLayer, now: time, visible: visible.rects, sounding: sounding)
        drawKeysLayer(keysLayer, now: time, sounding: sounding)
        guard let notesImage = notesLayer.makeImage(), let keysImage = keysLayer.makeImage() else { return }

        let bounds = CGRect(origin: .zero, size: frameSize)
        let notes = CIImage(cgImage: notesImage, options: [.colorSpace: colorSpace])
        let keys = CIImage(cgImage: keysImage, options: [.colorSpace: colorSpace])
        var frame = background
        if theme.glows {
            // A soft halo and a faint wider bloom. Additive light on black;
            // ordinary blending over a photo, which would wash out.
            let halo = Self.scaledAlpha(notes.applyingGaussianBlur(sigma: 7 * scale), by: theme == .dark ? 0.7 : 0.55)
            let bloom = Self.scaledAlpha(notes.applyingGaussianBlur(sigma: 20 * scale), by: theme == .dark ? 0.35 : 0.25)
            let glow = halo.composited(over: bloom).cropped(to: bounds)
            frame = theme == .dark
                ? glow.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: frame])
                : glow.composited(over: frame)
        }
        // The keys layer is drawn from the frame's bottom; lift it to the keyboard.
        frame = keys.transformed(by: CGAffineTransform(translationX: 0, y: frameSize.height - keyboardBottom))
            .composited(over: notes.composited(over: frame))
        if time < 4.5, let titleOverlay {
            let alpha = time < 3.5 ? 1 : max(0, 1 - CGFloat(time - 3.5))
            frame = Self.scaledAlpha(titleOverlay.image, by: alpha)
                .transformed(by: CGAffineTransform(translationX: titleOverlay.rect.minX,
                                                   y: frameSize.height - titleOverlay.rect.maxY))
                .composited(over: frame)
        }
        imageContext.render(frame.cropped(to: bounds), to: pixelBuffer, bounds: bounds, colorSpace: colorSpace)
    }

    /// Scales opacity: above 1 strengthens a soft glow, below 1 fades.
    private static func scaledAlpha(_ image: CIImage, by amount: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: amount)])
    }

    /// The notes in view, where they are, and which are sounding now.
    private func visibleNotes(now: TimeInterval) -> (notes: [(pitch: Int, track: Int, active: Bool)], rects: [VisibleNote]) {
        // Notes are sorted by start; anything starting before this ended already.
        let earliest = now - longestNote
        var low = 0
        var high = notes.count
        while low < high {
            let middle = (low + high) / 2
            if notes[middle].startSeconds < earliest { low = middle + 1 } else { high = middle }
        }
        var found: [(pitch: Int, track: Int, active: Bool)] = []
        var rects: [VisibleNote] = []
        for note in notes[low...] {
            if note.startSeconds > now + Self.lookaheadSeconds { break }
            guard note.endSeconds >= now else { continue }
            let active = note.startSeconds <= now
            found.append((note.pitch, note.track, active))
            let width = max(8 * scale, keyboard.keyWidth(of: note.pitch) * 0.82)
            let top = y(at: note.endSeconds, now: now)
            let bottom = y(at: note.startSeconds, now: now)
            rects.append(VisibleNote(rect: CGRect(x: keyboard.centerX(of: note.pitch) - width / 2, y: top,
                                                  width: width, height: max(8 * scale, bottom - top)),
                                     track: note.track, active: active))
        }
        return (found, rects)
    }

    private func drawNotesLayer(_ context: CGContext, now: TimeInterval, visible: [VisibleNote], sounding: [Int: Int]) {
        #if ARIA_VIDEO_AUDIT && os(Android)
        // Audit-only control: overlapping glows must have a repeatable draw order.
        // Production preserves the existing dictionary iteration on both platforms.
        let entries = sounding.sorted { $0.key < $1.key }
        #else
        let entries = sounding
        #endif
        context.clear(CGRect(origin: .zero, size: frameSize))
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: frameSize.width, height: keyboardTop))
        if theme == .light { drawBarLines(context, now: now) }

        // A little light rising from each sounding key.
        let riseHeight = (theme == .light ? 90 : 60) * scale
        for (pitch, track) in entries {
            let width = keyboard.keyWidth(of: pitch) * (theme == .light ? 1.6 : 1.2)
            let rect = CGRect(x: keyboard.centerX(of: pitch) - width / 2, y: keyboardTop - riseHeight,
                              width: width, height: riseHeight)
            drawFade(context, fades[track % fades.count], in: rect, downward: false, alpha: theme == .light ? 0.4 : 0.22)
        }

        let radius = 9 * scale
        for note in visible {
            let path = UIBezierPath(roundedRect: note.rect,
                                    cornerRadius: min(radius, note.rect.width / 2, note.rect.height / 2)).cgPath
            let base = color(track: note.track)
            let fill: UIColor
            let rim: UIColor
            let rimWidth: CGFloat
            switch theme {
            case .dark:
                fill = note.active ? Self.mix(.white, base, 0.2) : base.withAlphaComponent(0.92)
                rim = Self.mix(.white, base, 0.5)
                rimWidth = 2 * scale
            case .photo:
                fill = Self.mix(.white, base, note.active ? 0.25 : 0.1).withAlphaComponent(note.active ? 0.92 : 0.72)
                rim = UIColor.white.withAlphaComponent(0.9)
                rimWidth = 2.5 * scale
            case .light:
                fill = base.withAlphaComponent(note.active ? 0.95 : 0.8)
                rim = Self.mix(.black, base, 0.22).withAlphaComponent(note.active ? 0.9 : 0.55)
                rimWidth = 1.5 * scale
            }
            context.addPath(path)
            context.setFillColor(fill.cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(rim.cgColor)
            context.setLineWidth(rimWidth)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// A column of `gradient`, strongest at the top (`downward`) or bottom.
    private func drawFade(_ context: CGContext, _ gradient: CGGradient, in rect: CGRect, downward: Bool, alpha: CGFloat) {
        context.saveGState()
        context.clip(to: rect)
        context.setAlpha(alpha)
        context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: downward ? rect.minY : rect.maxY),
                                   end: CGPoint(x: rect.midX, y: downward ? rect.maxY : rect.minY), options: [])
        context.restoreGState()
    }

    /// Light theme: a faint line crosses the runway at the start of each coming bar.
    private func drawBarLines(_ context: CGContext, now: TimeInterval) {
        guard var index = timeline.regionIndex(at: now) else { return }
        context.setFillColor(UIColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 0.32).cgColor)
        let thickness = max(1, 2 * scale)
        while index < timeline.regions.count {
            let start = timeline.regions[index].startTimeSeconds
            if start > now + Self.lookaheadSeconds { break }
            if start >= now {
                let lineY = y(at: start, now: now)
                context.fill(CGRect(x: 0, y: lineY - thickness / 2, width: frameSize.width, height: thickness))
            }
            index += 1
        }
    }

    // MARK: Keyboard

    private func whiteKeyRect(_ pitch: Int) -> CGRect {
        let gap = max(1, 2 * scale)
        return CGRect(x: keyboard.centerX(of: pitch) - keyboard.whiteKeyWidth / 2 + gap / 2, y: flareRoom + 3 * scale,
                      width: keyboard.whiteKeyWidth - gap, height: keyboardBottom - keyboardTop - 3 * scale)
    }

    private func blackKeyRect(_ pitch: Int) -> CGRect {
        CGRect(x: keyboard.centerX(of: pitch) - keyboard.blackKeyWidth / 2, y: flareRoom + 3 * scale,
               width: keyboard.blackKeyWidth, height: blackKeyHeight - 3 * scale)
    }

    private func keyPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        UIBezierPath(roundedRect: rect, byRoundingCorners: [.bottomLeft, .bottomRight],
                     cornerRadii: CGSize(width: radius, height: radius)).cgPath
    }

    /// A key filled with a top-to-bottom gradient of `colors`.
    private func fillKey(_ context: CGContext, _ path: CGPath, colors: [UIColor], locations: [CGFloat]) {
        let box = path.boundingBoxOfPath
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors.map(\.cgColor) as CFArray,
                                        locations: locations) else { return }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.minY),
                                   end: CGPoint(x: box.midX, y: box.maxY), options: [])
        context.restoreGState()
    }

    private func drawBlackKey(_ context: CGContext, pitch: Int, color: UIColor?) {
        let path = keyPath(blackKeyRect(pitch), radius: 4 * scale)
        if let color {
            fillKey(context, path, colors: [Self.mix(.white, color, 0.1), Self.mix(.black, color, 0.45)], locations: [0, 1])
        } else {
            fillKey(context, path,
                    colors: [UIColor(white: 0.2, alpha: 1), UIColor(white: 0.05, alpha: 1), UIColor(white: 0.18, alpha: 1)],
                    locations: [0, 0.9, 1])
        }
    }

    /// The idle keyboard (`whiteKeys`), or only its black keys on a clear
    /// layer, to draw again over sounding white keys.
    private func makeKeyboardImage(whiteKeys: Bool) -> CGImage? {
        let size = CGSize(width: frameSize.width, height: keyboardBottom - keyboardTop + flareRoom)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            if whiteKeys {
                let gapColor = theme == .dark ? UIColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1)
                    : UIColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1)
                context.setFillColor(gapColor.cgColor)
                context.fill(CGRect(x: 0, y: flareRoom, width: size.width, height: size.height - flareRoom))
                for pitch in keyboard.pitches where !ScoreVideoPianoKeyboard.isBlack(pitch) {
                    fillKey(context, keyPath(whiteKeyRect(pitch), radius: 5 * scale),
                            colors: [UIColor(red: 0.90, green: 0.92, blue: 0.94, alpha: 1), .white,
                                     UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1),
                                     UIColor(red: 0.80, green: 0.83, blue: 0.87, alpha: 1)],
                            locations: [0, 0.18, 0.93, 1])
                }
            }
            context.setShadow(offset: CGSize(width: 0, height: 4 * scale), blur: 8 * scale,
                              color: UIColor(white: 0, alpha: 0.35).cgColor)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            for pitch in keyboard.pitches where ScoreVideoPianoKeyboard.isBlack(pitch) {
                drawBlackKey(context, pitch: pitch, color: nil)
            }
            context.endTransparencyLayer()
        }.cgImage
    }

    private func drawKeysLayer(_ context: CGContext, now: TimeInterval, sounding: [Int: Int]) {
        #if ARIA_VIDEO_AUDIT && os(Android)
        // Audit-only control: overlapping glows must have a repeatable draw order.
        // Production preserves the existing dictionary iteration on both platforms.
        let entries = sounding.sorted { $0.key < $1.key }
        #else
        let entries = sounding
        #endif
        let size = CGSize(width: frameSize.width, height: keyboardBottom - keyboardTop + flareRoom)
        context.clear(CGRect(origin: .zero, size: size))
        if let idleKeyboard { drawImage(idleKeyboard, in: CGRect(origin: .zero, size: size), context: context) }

        var anyWhite = false
        for (pitch, track) in entries where !ScoreVideoPianoKeyboard.isBlack(pitch) {
            let base = color(track: track)
            fillKey(context, keyPath(whiteKeyRect(pitch), radius: 5 * scale),
                    colors: [Self.mix(.white, base, 0.45), base, Self.mix(.black, base, 0.15)], locations: [0, 0.55, 1])
            anyWhite = true
        }
        if anyWhite, let blackKeys { drawImage(blackKeys, in: CGRect(origin: .zero, size: size), context: context) }
        for (pitch, track) in entries where ScoreVideoPianoKeyboard.isBlack(pitch) {
            drawBlackKey(context, pitch: pitch, color: color(track: track))
        }

        // The keyboard's top edge: a lit rail on dark and photo, a plain rule on light.
        let rail = CGRect(x: 0, y: flareRoom, width: size.width, height: 3 * scale)
        switch theme {
        case .dark, .photo:
            let light = theme == .dark ? UIColor(red: 0.45, green: 0.72, blue: 1, alpha: 1) : .white
            drawFade(context, gradient(light, from: 0, to: 1), in: CGRect(x: 0, y: flareRoom - 14 * scale,
                                                                          width: size.width, height: 14 * scale),
                     downward: true, alpha: 0.35)
            context.setFillColor(Self.mix(.white, light, 0.6).cgColor)
            context.fill(rail)
            drawFlares(context, sounding: sounding)
        case .light:
            context.setFillColor(UIColor(red: 0.20, green: 0.25, blue: 0.33, alpha: 1).cgColor)
            context.fill(rail)
            drawScrubber(context, now: now)
        }
    }

    /// Where a sounding note meets its key: a white-hot core in a coloured halo.
    private func drawFlares(_ context: CGContext, sounding: [Int: Int]) {
        #if ARIA_VIDEO_AUDIT && os(Android)
        // Audit-only control: overlapping glows must have a repeatable draw order.
        // Production preserves the existing dictionary iteration on both platforms.
        let entries = sounding.sorted { $0.key < $1.key }
        #else
        let entries = sounding
        #endif
        for (pitch, track) in entries {
            let x = keyboard.centerX(of: pitch)
            let width = keyboard.keyWidth(of: pitch)
            for (gradient, radius) in [(fades[track % fades.count], width * 1.3), (whiteFade, width * 0.55)] {
                context.saveGState()
                context.translateBy(x: x, y: flareRoom + 1.5 * scale)
                context.scaleBy(x: 1, y: 0.4)
                context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                           endCenter: .zero, endRadius: radius, options: [])
                context.restoreGState()
            }
        }
    }

    /// Light theme: along the top of the keyboard, a thin track, the played
    /// part filled, and a dot at the current position.
    private func drawScrubber(_ context: CGContext, now: TimeInterval) {
        let fraction = CGFloat(min(max(now / max(timeline.endTimeSeconds, 0.001), 0), 1))
        let x = frameSize.width * fraction
        let fill = 8 * scale
        context.setFillColor(Self.scrubberColor.withAlphaComponent(0.3).cgColor)
        context.addPath(UIBezierPath(roundedRect: CGRect(x: 0, y: flareRoom - fill / 2, width: x, height: fill),
                                     cornerRadius: fill / 2).cgPath)
        context.fillPath()
        let dot = 18 * scale
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 3 * scale), blur: 9 * scale,
                          color: Self.scrubberColor.withAlphaComponent(0.35).cgColor)
        context.setFillColor(Self.scrubberColor.cgColor)
        context.fillEllipse(in: CGRect(x: min(max(x, dot / 2), frameSize.width - dot / 2) - dot / 2,
                                       y: flareRoom - dot / 2, width: dot, height: dot))
        context.restoreGState()
    }

    // MARK: Cached layers

    private func makeBackground() -> CIImage {
        let bounds = CGRect(origin: .zero, size: frameSize)
        if theme == .photo, let photo = makePhotoBackground() {
            return photo
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: frameSize, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            let colors: [UIColor] = theme == .light
                ? [.white, UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)]
                : [UIColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 1), UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors.map(\.cgColor) as CFArray, locations: [0, 1]) {
                // Continues below a lifted keyboard.
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: keyboardTop),
                                           options: [.drawsAfterEndLocation])
            }
            guard theme == .light else { return }
            // Lanes: black keys' lanes slightly shaded, a hairline between
            // white keys, and a firmer line at each C to find the octaves.
            for pitch in keyboard.pitches {
                let width = keyboard.keyWidth(of: pitch)
                let left = keyboard.centerX(of: pitch) - width / 2
                if ScoreVideoPianoKeyboard.isBlack(pitch) {
                    context.setFillColor(UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 0.035).cgColor)
                    context.fill(CGRect(x: left, y: 0, width: width, height: keyboardTop))
                } else {
                    let isC = pitch % 12 == 0
                    context.setFillColor(UIColor(red: 0.80, green: 0.84, blue: 0.88, alpha: isC ? 0.7 : 0.3).cgColor)
                    context.fill(CGRect(x: left - 0.5, y: 0, width: isC ? 1.5 : 1, height: keyboardTop))
                }
            }
        }
        guard let cgImage = image.cgImage else { return CIImage(color: .black).cropped(to: bounds) }
        return CIImage(cgImage: cgImage, options: [.colorSpace: colorSpace])
    }

    /// The photo filling the frame, heavily blurred behind a light frosted veil.
    private func makePhotoBackground() -> CIImage? {
        guard let data = options.backgroundImageData, let photo = UIImage(data: data) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let filled = UIGraphicsImageRenderer(size: frameSize, format: format).image { _ in
            let fill = max(frameSize.width / photo.size.width, frameSize.height / photo.size.height)
            let size = CGSize(width: photo.size.width * fill, height: photo.size.height * fill)
            photo.draw(in: CGRect(x: (frameSize.width - size.width) / 2, y: (frameSize.height - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        guard let cgImage = filled.cgImage else { return nil }
        let bounds = CGRect(origin: .zero, size: frameSize)
        let blurred = CIImage(cgImage: cgImage, options: [.colorSpace: colorSpace])
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 28 * scale)
            .cropped(to: bounds)
        let frosted = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.3)).cropped(to: bounds)
            .composited(over: blurred)
        // Render once so frames reuse the pixels rather than re-blurring.
        guard let rendered = imageContext.createCGImage(frosted, from: bounds, format: .BGRA8, colorSpace: colorSpace) else {
            return nil
        }
        return CIImage(cgImage: rendered, options: [.colorSpace: colorSpace])
    }

    /// Title and composer on a card at the top left, for the opening.
    private func makeTitleOverlay() -> (image: CIImage, rect: CGRect)? {
        let title = options.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let onDark = theme == .dark
        let titleText = NSAttributedString(string: title, attributes: [
            .font: font(options.titleFont, size: 44 * scale),
            .foregroundColor: onDark ? UIColor.white : UIColor(red: 0.12, green: 0.16, blue: 0.23, alpha: 1)
        ])
        let composer = options.composer.trimmingCharacters(in: .whitespacesAndNewlines)
        let composerText = NSAttributedString(string: composer, attributes: [
            .font: font(options.composerFont, size: 26 * scale),
            .foregroundColor: onDark ? UIColor.white.withAlphaComponent(0.7) : UIColor(red: 0.39, green: 0.45, blue: 0.55, alpha: 1)
        ])
        let padding = 22 * scale
        let maxTextWidth = frameSize.width * 0.6
        let titleSize = titleText.boundingRect(with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                                               options: .usesLineFragmentOrigin, context: nil).integral.size
        let composerSize = composer.isEmpty ? .zero : composerText.size()
        // On vertical video, below the app bar Reels and TikTok show at the top.
        let top = frameSize.height > frameSize.width ? frameSize.height * 0.1 : 40 * scale
        let rect = CGRect(x: 40 * scale, y: top,
                          width: min(max(titleSize.width, composerSize.width), maxTextWidth) + padding * 2,
                          height: titleSize.height + (composer.isEmpty ? 0 : composerSize.height + 6 * scale) + padding * 2).integral
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            let card = CGRect(origin: .zero, size: rect.size)
            (onDark ? UIColor.black.withAlphaComponent(0.5) : UIColor.white.withAlphaComponent(0.88)).setFill()
            UIBezierPath(roundedRect: card, cornerRadius: 18 * scale).fill()
            (onDark ? UIColor.white.withAlphaComponent(0.12) : UIColor(red: 0.89, green: 0.91, blue: 0.94, alpha: 1)).setStroke()
            let outline = UIBezierPath(roundedRect: card.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 18 * scale)
            outline.lineWidth = 1.5
            outline.stroke()
            titleText.draw(with: CGRect(x: padding, y: padding, width: maxTextWidth, height: titleSize.height),
                           options: .usesLineFragmentOrigin, context: nil)
            if !composer.isEmpty {
                composerText.draw(at: CGPoint(x: padding, y: padding + titleSize.height + 6 * scale))
            }
        }.cgImage
        return image.map { (CIImage(cgImage: $0, options: [.colorSpace: colorSpace]), rect) }
    }

    /// `amount` of `color` blended into `base`.
    private static func mix(_ color: UIColor, _ base: UIColor, _ amount: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        base.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let keep = 1 - amount
        return UIColor(red: r1 * amount + r2 * keep, green: g1 * amount + g2 * keep,
                       blue: b1 * amount + b2 * keep, alpha: a1 * amount + a2 * keep)
    }
}
