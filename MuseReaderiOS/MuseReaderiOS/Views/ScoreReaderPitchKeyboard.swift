//
//  ScoreReaderPitchKeyboard.swift
//  MuseReaderiOS
//

import SwiftUI

struct ScoreReaderWidePitchKeyboard: View {
    @State private var lockedStartMIDIPitch: Int?
    @State private var naturalKeyOffset = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var dragStartNaturalKeyOffset: Int?

    let useFlats: Bool
    let activePitchClass: Int?
    let activeMIDIPitch: Int?
    var activeMIDIPitches: [Int] = []
    let followsActiveMIDIPitch: Bool
    let isEnabled: Bool
    var minimumVisibleNaturalKeyCount = 14
    var maximumVisibleNaturalKeyCount = 22
    var targetWhiteKeyWidth: CGFloat = 48
    let action: (PianoKeyboardKey) -> Void

    private let minMIDIPitch = 21
    private let maxMIDIPitch = 108
    private let defaultStartMIDIPitch = 48
    private let maximumBlackKeyWidth: CGFloat = 34
    private let blackKeyTouchHeight: CGFloat = 72

    var body: some View {
        GeometryReader { geometry in
            let visibleNaturalKeyCount = visibleNaturalKeyCountForWidth(geometry.size.width)
            let keyHeight = max(geometry.size.height, 1)
            // Render one extra natural key on each side (overscan) so keys can
            // slide into and out of the clipped window instead of popping in at
            // the edges. whiteWidth stays based on the *visible* count.
            let renderedKeys = renderedNaturalKeys(visibleNaturalKeyCount: visibleNaturalKeyCount)
            let blackKeys = visibleBlackKeys(for: renderedKeys)
            let whiteWidth = geometry.size.width / CGFloat(max(visibleNaturalKeyCount, 1))
            let blackWidth = min(whiteWidth * 0.58, maximumBlackKeyWidth)
            let leadingBufferOffset = -whiteWidth

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(renderedKeys.enumerated()), id: \.offset) { _, key in
                        VStack {
                            Spacer()
                            if key.shouldShowLabel {
                                Text(key.label)
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(Color.black.opacity(0.78))
                                    .padding(.bottom, 8)
                            }
                        }
                        .frame(width: whiteWidth, height: keyHeight)
                        .background((!key.isPlaceholder && isActive(midiPitch: key.midiPitch)) ? Color(red: 0.88, green: 0.93, blue: 1.0) : Color.white)
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(Color.black.opacity(0.18))
                                .frame(width: 1)
                        }
                    }
                }

                ForEach(blackKeys, id: \.midiPitch) { key in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isActive(midiPitch: key.midiPitch) ? Color(red: 0.12, green: 0.34, blue: 0.78) : Color(red: 0.08, green: 0.09, blue: 0.10))
                            .shadow(color: Color.black.opacity(0.30), radius: 2, y: 1)

                        if isActive(midiPitch: key.midiPitch), hasExactActiveMIDIPitch {
                            Text(label(forMIDIPitch: key.midiPitch))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.bottom, 5)
                        }
                    }
                    .frame(width: blackWidth, height: 62)
                    .offset(x: whiteWidth * CGFloat(key.leftNaturalIndex + 1) - (blackWidth / 2))
                }
            }
            .opacity(isEnabled ? 1 : 0.55)
            .offset(x: leadingBufferOffset + dragTranslation)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(keyboardGesture(geometry: geometry, naturalKeys: renderedKeys, blackKeys: blackKeys, whiteWidth: whiteWidth, blackWidth: blackWidth, visibleNaturalKeyCount: visibleNaturalKeyCount))
            .onChangeCompatible(of: activeMIDIPitch) { newValue in
                guard followsActiveMIDIPitch else {
                    return
                }
                updateLockedRange(for: newValue, visibleNaturalKeyCount: visibleNaturalKeyCount)
            }
            .onChangeCompatible(of: followsActiveMIDIPitch) { newValue in
                guard newValue else {
                    return
                }
                updateLockedRange(for: activeMIDIPitch, visibleNaturalKeyCount: visibleNaturalKeyCount)
            }
            .onChangeCompatible(of: activePitchClass) { newValue in
                keepLockedRangeIfNeeded(activePitchClass: newValue)
            }
            .onAppear {
                if followsActiveMIDIPitch {
                    updateLockedRange(for: activeMIDIPitch, visibleNaturalKeyCount: visibleNaturalKeyCount)
                }
            }
        }
    }

    private func visibleNaturalKeyCountForWidth(_ width: CGFloat) -> Int {
        guard width > 0 else {
            return minimumVisibleNaturalKeyCount
        }

        let widthBasedCount = Int((width / targetWhiteKeyWidth).rounded(.down))
        return min(max(widthBasedCount, minimumVisibleNaturalKeyCount), maximumVisibleNaturalKeyCount)
    }

    /// Visible keys plus one overscan buffer key on each side. The first
    /// element is the leading buffer (drawn just off the left edge); the view
    /// offsets the whole strip by -whiteWidth so buffer keys live outside the
    /// clipped window until a drag reveals them. Keys whose pitch falls outside
    /// the playable range are returned as non-interactive placeholders so the
    /// geometry stays uniform at the extremes.
    private func renderedNaturalKeys(visibleNaturalKeyCount: Int) -> [PianoNaturalKey] {
        let startIndex = startNaturalIndex(visibleNaturalKeyCount: visibleNaturalKeyCount)
        return (-1...visibleNaturalKeyCount).map { offset in
            let index = startIndex + offset
            let midiPitch = naturalMIDIPitch(forNaturalIndex: index)
            let inRange = midiPitch >= minMIDIPitch && midiPitch <= maxMIDIPitch
            return PianoNaturalKey(
                midiPitch: midiPitch,
                pitchClass: normalizedPitchClass(midiPitch),
                label: inRange ? label(forMIDIPitch: midiPitch) : "",
                shouldShowLabel: inRange && shouldShowLabel(forMIDIPitch: midiPitch),
                isPlaceholder: !inRange
            )
        }
    }

    private func startNaturalIndex(visibleNaturalKeyCount: Int) -> Int {
        let basePitch = lockedStartMIDIPitch ?? defaultStartMIDIPitch
        return clampedStartNaturalIndex(naturalIndex(forMIDIPitch: basePitch) + naturalKeyOffset, visibleNaturalKeyCount: visibleNaturalKeyCount)
    }

    private func naturalStartPitch(visibleNaturalKeyCount: Int) -> Int {
        naturalMIDIPitch(forNaturalIndex: startNaturalIndex(visibleNaturalKeyCount: visibleNaturalKeyCount))
    }

    private func keyboardGesture(
        geometry: GeometryProxy,
        naturalKeys: [PianoNaturalKey],
        blackKeys: [PianoBlackKey],
        whiteWidth: CGFloat,
        blackWidth: CGFloat,
        visibleNaturalKeyCount: Int
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled else {
                    return
                }

                if dragStartNaturalKeyOffset == nil {
                    dragStartNaturalKeyOffset = naturalKeyOffset
                }

                guard abs(value.translation.width) > 3 else {
                    dragTranslation = 0
                    return
                }

                updateContinuousScroll(for: value.translation.width, whiteWidth: whiteWidth, visibleNaturalKeyCount: visibleNaturalKeyCount)
            }
            .onEnded { value in
                guard isEnabled else {
                    dragTranslation = 0
                    dragStartNaturalKeyOffset = nil
                    return
                }

                let horizontalMovement = value.translation.width
                if abs(horizontalMovement) > 14 {
                    // Ease the residual sub-key offset into alignment instead of
                    // snapping it to zero, so the keyboard glides to rest.
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
                        updateContinuousScroll(for: horizontalMovement, whiteWidth: whiteWidth, visibleNaturalKeyCount: visibleNaturalKeyCount)
                        dragTranslation = 0
                    }
                    dragStartNaturalKeyOffset = nil
                    return
                }

                dragTranslation = 0
                dragStartNaturalKeyOffset = nil
                if let key = key(at: value.location, naturalKeys: naturalKeys, blackKeys: blackKeys, whiteWidth: whiteWidth, blackWidth: blackWidth, height: geometry.size.height) {
                    action(key)
                }
            }
    }

    private func updateContinuousScroll(for horizontalMovement: CGFloat, whiteWidth: CGFloat, visibleNaturalKeyCount: Int) {
        guard whiteWidth > 0 else {
            dragTranslation = 0
            return
        }

        let startingOffset = dragStartNaturalKeyOffset ?? naturalKeyOffset
        let keyDelta = Int((horizontalMovement / whiteWidth).rounded(.towardZero))
        let baseNaturalIndex = naturalIndex(forMIDIPitch: lockedStartMIDIPitch ?? defaultStartMIDIPitch)
        let targetStartIndex = clampedStartNaturalIndex(baseNaturalIndex + startingOffset - keyDelta, visibleNaturalKeyCount: visibleNaturalKeyCount)
        naturalKeyOffset = targetStartIndex - baseNaturalIndex

        let unclampedTarget = baseNaturalIndex + startingOffset - keyDelta
        if unclampedTarget == targetStartIndex {
            dragTranslation = horizontalMovement - (CGFloat(keyDelta) * whiteWidth)
        } else {
            dragTranslation = 0
        }
    }

    private func updateLockedRange(for midiPitch: Int?, visibleNaturalKeyCount: Int) {
        guard let midiPitch else {
            return
        }

        if lockedStartMIDIPitch == nil || !isMIDIPitchVisible(midiPitch, visibleNaturalKeyCount: visibleNaturalKeyCount) {
            lockedStartMIDIPitch = centeredStartPitch(forMIDIPitch: midiPitch, visibleNaturalKeyCount: visibleNaturalKeyCount)
            naturalKeyOffset = 0
        }
    }

    private func keepLockedRangeIfNeeded(activePitchClass: Int?) {
        guard activePitchClass == nil, activeMIDIPitch == nil else {
            return
        }

        dragTranslation = 0
        dragStartNaturalKeyOffset = nil
    }

    private func isMIDIPitchVisible(_ midiPitch: Int, visibleNaturalKeyCount: Int) -> Bool {
        let startPitch = naturalStartPitch(visibleNaturalKeyCount: visibleNaturalKeyCount)
        let endPitch = naturalMIDIPitch(offset: visibleNaturalKeyCount - 1, from: startPitch)
        return midiPitch >= startPitch && midiPitch <= endPitch
    }

    private func centeredStartPitch(forMIDIPitch midiPitch: Int, visibleNaturalKeyCount: Int) -> Int {
        let activeNaturalIndex = naturalIndex(forMIDIPitch: midiPitch)
        let startNaturalIndex = clampedStartNaturalIndex(activeNaturalIndex - (visibleNaturalKeyCount / 2), visibleNaturalKeyCount: visibleNaturalKeyCount)
        return naturalMIDIPitch(forNaturalIndex: startNaturalIndex)
    }

    private var minNaturalIndex: Int {
        naturalIndex(forMIDIPitch: minMIDIPitch)
    }

    private var maxNaturalIndex: Int {
        naturalIndex(forMIDIPitch: maxMIDIPitch)
    }

    private func maxStartNaturalIndex(visibleNaturalKeyCount: Int) -> Int {
        max(minNaturalIndex, maxNaturalIndex - visibleNaturalKeyCount + 1)
    }

    private func clampedStartNaturalIndex(_ index: Int, visibleNaturalKeyCount: Int) -> Int {
        min(max(index, minNaturalIndex), maxStartNaturalIndex(visibleNaturalKeyCount: visibleNaturalKeyCount))
    }

    private func key(
        at point: CGPoint,
        naturalKeys: [PianoNaturalKey],
        blackKeys: [PianoBlackKey],
        whiteWidth: CGFloat,
        blackWidth: CGFloat,
        height: CGFloat
    ) -> PianoKeyboardKey? {
        // Content is drawn offset by (-whiteWidth + dragTranslation), so map the
        // touch back into the rendered strip's local coordinate space.
        let localX = point.x - dragTranslation + whiteWidth
        guard localX >= 0, localX <= whiteWidth * CGFloat(naturalKeys.count), point.y >= 0, point.y <= height else {
            return nil
        }

        if point.y <= blackKeyTouchHeight {
            let blackTouchWidth = max(blackWidth, min(whiteWidth * 0.72, 44))
            for blackKey in blackKeys.reversed() {
                let centerX = whiteWidth * CGFloat(blackKey.leftNaturalIndex + 1)
                let minX = centerX - (blackTouchWidth / 2)
                let maxX = centerX + (blackTouchWidth / 2)
                if localX >= minX, localX <= maxX {
                    return PianoKeyboardKey(midiPitch: blackKey.midiPitch, pitchClass: blackKey.pitchClass)
                }
            }
        }

        let naturalIndex = min(max(Int(localX / whiteWidth), 0), naturalKeys.count - 1)
        let naturalKey = naturalKeys[naturalIndex]
        guard !naturalKey.isPlaceholder else {
            return nil
        }
        return PianoKeyboardKey(midiPitch: naturalKey.midiPitch, pitchClass: naturalKey.pitchClass)
    }

    private func visibleBlackKeys(for naturalKeys: [PianoNaturalKey]) -> [PianoBlackKey] {
        guard naturalKeys.count > 1 else {
            return []
        }

        var keys: [PianoBlackKey] = []
        for index in 0..<(naturalKeys.count - 1) {
            if naturalKeys[index].isPlaceholder || naturalKeys[index + 1].isPlaceholder {
                continue
            }
            let leftPitch = naturalKeys[index].midiPitch
            let rightPitch = naturalKeys[index + 1].midiPitch
            if rightPitch - leftPitch == 2 {
                let midiPitch = leftPitch + 1
                keys.append(PianoBlackKey(midiPitch: midiPitch, pitchClass: normalizedPitchClass(midiPitch), leftNaturalIndex: index))
            }
        }
        return keys
    }

    private func isActive(midiPitch: Int) -> Bool {
        if !activeMIDIPitches.isEmpty {
            return activeMIDIPitches.contains(midiPitch)
        }

        if let activeMIDIPitch {
            return activeMIDIPitch == midiPitch
        }

        return activePitchClass == normalizedPitchClass(midiPitch)
    }

    private func shouldShowLabel(forMIDIPitch midiPitch: Int) -> Bool {
        if !activeMIDIPitches.isEmpty {
            return activeMIDIPitches.contains(midiPitch) || normalizedPitchClass(midiPitch) == 0
        }

        if let activeMIDIPitch {
            return activeMIDIPitch == midiPitch || normalizedPitchClass(midiPitch) == 0
        }

        return normalizedPitchClass(midiPitch) == 0
    }

    private func label(forMIDIPitch midiPitch: Int) -> String {
        if activeMIDIPitches.contains(midiPitch) || activeMIDIPitch == midiPitch {
            return "\(Self.label(for: normalizedPitchClass(midiPitch), useFlats: useFlats))\(octave(forMIDIPitch: midiPitch))"
        }

        return normalizedPitchClass(midiPitch) == 0 ? "C\(octave(forMIDIPitch: midiPitch))" : ""
    }

    private var hasExactActiveMIDIPitch: Bool {
        activeMIDIPitch != nil || !activeMIDIPitches.isEmpty
    }

    private func octave(forMIDIPitch midiPitch: Int) -> Int {
        (midiPitch / 12) - 1
    }

    private func normalizedPitchClass(_ midiPitch: Int) -> Int {
        let value = midiPitch % 12
        return value >= 0 ? value : value + 12
    }

    private func naturalIndex(forMIDIPitch midiPitch: Int) -> Int {
        let octave = midiPitch / 12
        let naturalStep = naturalStep(forPitchClass: normalizedPitchClass(midiPitch))
        return octave * 7 + naturalStep
    }

    private func naturalStep(forPitchClass pitchClass: Int) -> Int {
        switch pitchClass {
        case 0, 1: return 0
        case 2, 3: return 1
        case 4: return 2
        case 5, 6: return 3
        case 7, 8: return 4
        case 9, 10: return 5
        default: return 6
        }
    }

    private func naturalMIDIPitch(offset: Int, from startMIDIPitch: Int) -> Int {
        naturalMIDIPitch(forNaturalIndex: naturalIndex(forMIDIPitch: startMIDIPitch) + offset)
    }

    private func naturalMIDIPitch(forNaturalIndex index: Int) -> Int {
        let pitchClasses = [0, 2, 4, 5, 7, 9, 11]
        let octave = index / 7
        let step = index % 7
        return octave * 12 + pitchClasses[step]
    }

    static func label(for pitchClass: Int, useFlats: Bool) -> String {
        switch pitchClass {
        case 0: return "C"
        case 1: return useFlats ? "D♭" : "C♯"
        case 2: return "D"
        case 3: return useFlats ? "E♭" : "D♯"
        case 4: return "E"
        case 5: return "F"
        case 6: return useFlats ? "G♭" : "F♯"
        case 7: return "G"
        case 8: return useFlats ? "A♭" : "G♯"
        case 9: return "A"
        case 10: return useFlats ? "B♭" : "A♯"
        case 11: return "B"
        default: return ""
        }
    }
}

struct PianoNaturalKey {
    let midiPitch: Int
    let pitchClass: Int
    let label: String
    let shouldShowLabel: Bool
    var isPlaceholder = false
}

struct PianoBlackKey {
    let midiPitch: Int
    let pitchClass: Int
    let leftNaturalIndex: Int
}

struct PianoKeyboardKey {
    let midiPitch: Int
    let pitchClass: Int
}

struct ScoreReaderPitchStrip: View {
    let isEnabled: Bool
    let semitoneShiftAction: (Int) -> Void
    let octaveShiftAction: (Int) -> Void

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                ScoreReaderPitchStripButton(systemImage: "chevron.up", label: "+1", isEnabled: isEnabled, action: { semitoneShiftAction(1) })
                ScoreReaderPitchStripButton(systemImage: "chevron.up.2", label: "+12", isEnabled: isEnabled, action: { octaveShiftAction(1) })
            }
            HStack(spacing: 3) {
                ScoreReaderPitchStripButton(systemImage: "chevron.down", label: "-1", isEnabled: isEnabled, action: { semitoneShiftAction(-1) })
                ScoreReaderPitchStripButton(systemImage: "chevron.down.2", label: "-12", isEnabled: isEnabled, action: { octaveShiftAction(-1) })
            }
        }
    }
}

struct ScoreReaderPitchStripButton: View {
    let systemImage: String
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Color.black.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

extension ScoreNoteDuration {
    var noteEntryTitle: String {
        switch self {
        case .whole: return "Whole"
        case .half: return "Half"
        case .quarter: return "Quarter"
        case .eighth: return "Eighth"
        case .sixteenth: return "Sixteenth"
        }
    }

    /// SF Symbol name if available for this duration
    var noteEntrySFSymbol: String? {
        switch self {
        case .whole: return "circle"
        case .half: return "music.note"
        case .quarter: return nil
        case .eighth: return nil
        case .sixteenth: return nil
        }
    }

    /// Unicode music glyphs for note duration buttons
    var noteEntryGlyph: String {
        switch self {
        case .whole: return "○"
        case .half: return "𝅗"
        case .quarter: return "♩"
        case .eighth: return "♪"
        case .sixteenth: return "♬"
        }
    }

    var bravuraTextGlyph: String {
        switch self {
        case .whole: return "\u{1D15D}"
        case .half: return "\u{1D15E}"
        case .quarter: return "\u{1D15F}"
        case .eighth: return "\u{1D160}"
        case .sixteenth: return "\u{1D161}"
        }
    }

    var paletteTextSymbol: String? {
        switch self {
        case .whole: return "o"
        case .half: return nil
        case .quarter: return nil
        case .eighth: return "♪"
        case .sixteenth: return "♬"
        }
    }

    var paletteSFSymbol: String? {
        switch self {
        case .whole: return nil
        case .half: return "music.note"
        case .quarter: return "music.quarternote.3"
        case .eighth: return nil
        case .sixteenth: return nil
        }
    }
}
