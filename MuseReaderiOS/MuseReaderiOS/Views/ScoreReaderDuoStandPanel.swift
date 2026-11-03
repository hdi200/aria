//
//  ScoreReaderDuoStandPanel.swift
//  MuseReaderiOS
//
//  Reading on an iPhone Duo standing half open: the page stands up, and this panel of
//  playback and page controls lies on the flat half.
//

import SwiftUI

struct ScoreReaderDuoStandPanel: View {
    let title: String
    let composer: String?
    let playbackState: ScorePlaybackState
    let supportsPlayback: Bool
    let isPlaybackBusy: Bool
    let isCountingIn: Bool
    let playbackPreparationMessage: String?
    let metronomeEnabled: Bool
    let countInEnabled: Bool
    let isMixerPresented: Bool
    let pageCount: Int
    let currentPageIndex: Int
    let usesTwoPageSpread: Bool
    let twoPageEnabled: Bool
    let measureRegions: [ScorePlaybackMeasureRegion]
    let activeMeasureRegion: ScorePlaybackMeasureRegion?
    let keyControl: AnyView?
    let togglePlaybackAction: () -> Void
    let stopPlaybackAction: () -> Void
    let toggleMetronomeAction: () -> Void
    let toggleCountInAction: () -> Void
    let toggleMixerAction: () -> Void
    let toggleTwoPageAction: () -> Void
    let previousPageAction: () -> Void
    let nextPageAction: () -> Void
    let showPageAction: (Int) -> Void
    let seekAction: (Double) -> Void

    private static let accentColor = Color(red: 0.12, green: 0.45, blue: 0.92)

    /// The rows share out the flat half's height, so the panel fills it however tall it is.
    var body: some View {
        VStack(spacing: 0) {
            titleRow
            Spacer(minLength: 14)
            transportRow
            Spacer(minLength: 14)
            positionRow
            Spacer(minLength: 14)
            HStack(spacing: 12) {
                settingCard(title: "Metronome", systemImage: "metronome",
                            isOn: metronomeEnabled, action: toggleMetronomeAction)
                settingCard(title: "Count-in", systemImage: "timer",
                            isOn: countInEnabled, action: toggleCountInAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(panelBackground)
    }

    // MARK: Rows

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .lineLimit(1)
                if let composer, !composer.isEmpty {
                    Text(composer)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.52))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if pageCount > 1 {
                Button(action: toggleTwoPageAction) {
                    ScoreReaderTwoPageViewIcon(isActive: twoPageEnabled)
                        .frame(width: 38, height: 34)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(twoPageEnabled ? "Use single-page view" : "Use two-page view")
            }

            if let keyControl {
                keyControl
            }
        }
    }

    private var transportRow: some View {
        HStack(alignment: .center, spacing: 12) {
            pageTurnButton(title: "Prev Page", systemImage: "chevron.left",
                           isEnabled: currentPageIndex > 0, action: previousPageAction)

            Spacer(minLength: 4)

            playButton

            VStack(alignment: .leading, spacing: 8) {
                timeLabel
                HStack(spacing: 10) {
                    stopButton
                    mixerButton
                }
            }

            Spacer(minLength: 4)

            pageTurnButton(title: "Next Page", systemImage: "chevron.right",
                           isEnabled: currentPageIndex < pageCount - (usesTwoPageSpread ? 2 : 1),
                           action: nextPageAction)
        }
    }

    /// During playback the slider picks a measure; otherwise it turns pages.
    @ViewBuilder
    private var positionRow: some View {
        if showsMeasureSelector {
            let axis = DuoMeasureAxis(regions: measureRegions)
            ScoreReaderStandScrubber(
                count: axis.measureCount,
                currentIndex: activeMeasureRegion?.measureIndex ?? 0,
                showsTicks: true,
                accentColor: Self.accentColor,
                accessibilityName: "Measure",
                markLabel: { "\($0 + 1)" },
                bubbleLabel: { "m. \($0 + 1)" },
                positionLabel: { "\($0 + 1) / \(axis.measureCount)" },
                commitAction: { measure in
                    let current = activeMeasureRegion.flatMap { measureRegions.firstIndex(of: $0) } ?? 0
                    if let index = axis.regionIndex(forMeasure: measure, from: current) {
                        seekToRegion(measureRegions[index])
                    }
                }
            )
        } else if pageCount > 1 {
            ScoreReaderStandScrubber(
                count: pageCount,
                currentIndex: currentPageIndex,
                showsTicks: false,
                accentColor: Self.accentColor,
                accessibilityName: "Page",
                markLabel: { "\($0 + 1)" },
                bubbleLabel: { pageBubbleLabel(for: $0) },
                positionLabel: { "\($0 + 1) / \(pageCount)" },
                commitAction: showPageAction
            )
        }
    }

    private func pageBubbleLabel(for pageIndex: Int) -> String {
        guard usesTwoPageSpread else {
            return "p. \(pageIndex + 1)"
        }
        let start = pageIndex - pageIndex % 2
        return start + 1 < pageCount ? "p. \(start + 1)–\(start + 2)" : "p. \(start + 1)"
    }

    private var showsMeasureSelector: Bool {
        playbackState.isAvailable
            && (playbackState.status == .playing || playbackState.status == .paused)
            && !measureRegions.isEmpty
            && activeMeasureRegion != nil
    }

    private func seekToRegion(_ region: ScorePlaybackMeasureRegion) {
        let duration = max(playbackState.durationSeconds, measureRegions.map(\.endTimeSeconds).max() ?? 0)
        guard duration > 0 else {
            return
        }
        seekAction(region.startTimeSeconds / duration)
    }

    // MARK: Pieces

    private var timeLabel: some View {
        Group {
            if isCountingIn {
                Text("Count-in")
            } else if let playbackPreparationMessage {
                Text(playbackPreparationMessage)
            } else {
                HStack(spacing: 0) {
                    Text(playbackState.currentTimeLabel)
                        .foregroundStyle(Color.black.opacity(0.88))
                    Text(" / " + playbackState.durationLabel)
                        .foregroundStyle(Color.black.opacity(0.42))
                }
            }
        }
        .font(.system(size: 28, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var playButton: some View {
        Button(action: togglePlaybackAction) {
            Group {
                if isPlaybackBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 92, height: 92)
            .background(Self.accentColor, in: Circle())
            .shadow(color: Self.accentColor.opacity(0.30), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!supportsPlayback || !playbackState.isAvailable || isPlaybackBusy)
        .opacity(supportsPlayback && playbackState.isAvailable ? 1 : 0.45)
        .accessibilityLabel(playbackState.isPlaying ? "Pause playback" : "Play playback")
    }

    private var stopButton: some View {
        let canStop = playbackState.isAvailable && playbackState.status != .stopped && !isPlaybackBusy
        return Button(action: stopPlaybackAction) {
            Image(systemName: "stop.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.84))
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canStop)
        .opacity(canStop ? 1 : 0.4)
        .accessibilityLabel("Stop playback")
    }

    private var mixerButton: some View {
        Button(action: toggleMixerAction) {
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isMixerPresented ? Self.accentColor : Color.black.opacity(0.84))
                .frame(width: 40, height: 40)
                .background(isMixerPresented ? Self.accentColor.opacity(0.14) : Color.black.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!supportsPlayback)
        .accessibilityLabel("Mixer")
        .accessibilityValue(isMixerPresented ? "Open" : "Closed")
    }

    private func pageTurnButton(title: String, systemImage: String, isEnabled: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.84))
                    .frame(width: 76, height: 64)
                    .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(title)
    }

    private func settingCard(title: String, systemImage: String, isOn: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .medium))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isOn ? Self.accentColor : Color.black.opacity(0.88))
                    Text(isOn ? "On" : "Off")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isOn ? Self.accentColor : Color.black.opacity(0.48))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isOn ? Self.accentColor : Color.black.opacity(0.80))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(isOn ? Self.accentColor.opacity(0.12) : Color.white.opacity(0.85),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isOn ? Self.accentColor.opacity(0.25) : Color.black.opacity(0.06), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(!playbackState.isAvailable || isPlaybackBusy)
        .opacity(playbackState.isAvailable ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    /// Rounded at the top only: the bottom corners run past the screen's edge.
    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.07), lineWidth: 0.7)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: -5)
            .padding(.bottom, -40)
            .ignoresSafeArea(.container, edges: .bottom)
    }
}

/// Measures by number for the Duo's measure selectors. A score with repeats plays some
/// measures more than once; the selectors count the score's measures in order.
struct DuoMeasureAxis {
    let regions: [ScorePlaybackMeasureRegion]

    var measureCount: Int {
        (regions.map(\.measureIndex).max() ?? -1) + 1
    }

    /// Where to play a measure from: its next time through from the current region, or else
    /// its first.
    func regionIndex(forMeasure measure: Int, from currentRegionIndex: Int) -> Int? {
        if let next = regions.indices.first(where: { $0 >= currentRegionIndex && regions[$0].measureIndex == measure }) {
            return next
        }
        return regions.firstIndex { $0.measureIndex == measure }
    }
}

/// Editing on a Duo held like a book: the measure selector card under the playback card.
/// The current measure and the count head the card; the track runs the card's width.
struct ScoreReaderDuoMeasureCard: View {
    let measureCount: Int
    let currentMeasure: Int
    let commitAction: (Int) -> Void

    @State var scrubMeasure: Int?

    private static let accentColor = Color(red: 0.12, green: 0.45, blue: 0.92)
    private let knobSize: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Measure \(shownMeasure + 1)")
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Self.accentColor, in: Capsule())
                Spacer()
                Text("\(shownMeasure + 1) / \(measureCount)")
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.black.opacity(0.84))
            }
            track
                .frame(height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 3)
        .accessibilityElement()
        .accessibilityLabel("Measure")
        .accessibilityValue("\(shownMeasure + 1) of \(measureCount)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                commitAction(min(currentMeasure + 1, measureCount - 1))
            case .decrement:
                commitAction(max(currentMeasure - 1, 0))
            @unknown default:
                break
            }
        }
    }

    private var shownMeasure: Int {
        min(max(scrubMeasure ?? currentMeasure, 0), max(measureCount - 1, 0))
    }

    /// Numbered every four measures from 1, and the last.
    private var numberedMeasures: [Int] {
        let numbered = Array(stride(from: 0, to: measureCount, by: 4))
        guard let last = numbered.last, last != measureCount - 1 else {
            return numbered
        }
        return measureCount - 1 - last < 2 ? Array(numbered.dropLast()) + [measureCount - 1] : numbered + [measureCount - 1]
    }

    private var track: some View {
        GeometryReader { proxy in
            let usableWidth = max(proxy.size.width - knobSize, 1)
            let lastIndex = max(measureCount - 1, 1)
            let x = { (measure: Int) in knobSize / 2 + usableWidth * CGFloat(measure) / CGFloat(lastIndex) }
            let trackY: CGFloat = 12
            let numbered = Set(numberedMeasures)

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: usableWidth, height: 4)
                    .offset(x: knobSize / 2, y: trackY - 2)
                Capsule()
                    .fill(Self.accentColor)
                    .frame(width: max(x(shownMeasure) - knobSize / 2, 0), height: 4)
                    .offset(x: knobSize / 2, y: trackY - 2)

                if measureCount <= 120 {
                    ForEach(0..<measureCount, id: \.self) { measure in
                        Rectangle()
                            .fill(Color.black.opacity(numbered.contains(measure) ? 0.30 : 0.16))
                            .frame(width: 1, height: numbered.contains(measure) ? 12 : 8)
                            .offset(x: x(measure), y: trackY - (numbered.contains(measure) ? 6 : 4))
                    }
                }

                ForEach(numberedMeasures, id: \.self) { measure in
                    Text("\(measure + 1)")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.black.opacity(0.52))
                        .fixedSize()
                        .frame(width: 30)
                        .offset(x: x(measure) - 15, y: trackY + 12)
                }

                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Self.accentColor, lineWidth: 2))
                    .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                    .frame(width: knobSize, height: knobSize)
                    .scaleEffect(scrubMeasure != nil ? 1.2 : 1)
                    .offset(x: x(shownMeasure) - knobSize / 2, y: trackY - knobSize / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = (value.location.x - knobSize / 2) / usableWidth
                        scrubMeasure = min(max(Int((fraction * CGFloat(lastIndex)).rounded()), 0), max(measureCount - 1, 0))
                    }
                    .onEnded { _ in
                        if let scrubMeasure {
                            commitAction(scrubMeasure)
                        }
                        scrubMeasure = nil
                    }
            )
        }
    }
}

/// Editing on a Duo standing half open: playback and a measure selector in one card on the
/// flat half, above the editing deck.
struct ScoreReaderDuoPlaybackStrip: View {
    let playbackState: ScorePlaybackState
    let supportsPlayback: Bool
    let isPlaybackBusy: Bool
    let isCountingIn: Bool
    let playbackPreparationMessage: String?
    let metronomeEnabled: Bool
    let isMixerPresented: Bool
    /// Measures by number from 0; nothing to pick until playback knows the measures.
    let measureCount: Int
    let currentMeasure: Int
    let togglePlaybackAction: () -> Void
    let stopPlaybackAction: () -> Void
    let toggleMetronomeAction: () -> Void
    let toggleMixerAction: () -> Void
    let seekToMeasureAction: (Int) -> Void

    private static let accentColor = Color(red: 0.12, green: 0.45, blue: 0.92)

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                circleButton(systemImage: playbackState.isPlaying ? "pause.fill" : "play.fill",
                             size: 48, isProminent: true, isActive: false,
                             isEnabled: supportsPlayback && playbackState.isAvailable && !isPlaybackBusy,
                             label: playbackState.isPlaying ? "Pause playback" : "Play playback",
                             action: togglePlaybackAction)
                circleButton(systemImage: "stop.fill", size: 40, isProminent: false, isActive: false,
                             isEnabled: playbackState.isAvailable && playbackState.status != .stopped && !isPlaybackBusy,
                             label: "Stop playback", action: stopPlaybackAction)
                circleButton(systemImage: "metronome", size: 40, isProminent: false,
                             isActive: metronomeEnabled,
                             isEnabled: playbackState.isAvailable && !isPlaybackBusy,
                             label: "Metronome", action: toggleMetronomeAction)
                    .accessibilityValue(metronomeEnabled ? "On" : "Off")
                circleButton(systemImage: "slider.vertical.3", size: 40, isProminent: false,
                             isActive: isMixerPresented, isEnabled: supportsPlayback,
                             label: "Mixer", action: toggleMixerAction)

                Spacer(minLength: 6)

                timeLabel

                Spacer(minLength: 6)

                if measureCount > 0 {
                    measureStepper
                }
            }

            if measureCount > 0 {
                ScoreReaderStandScrubber(
                    count: measureCount,
                    currentIndex: currentMeasure,
                    showsTicks: true,
                    accentColor: Self.accentColor,
                    accessibilityName: "Measure",
                    markLabel: { "\($0 + 1)" },
                    bubbleLabel: { "m. \($0 + 1)" },
                    positionLabel: { "\($0 + 1) / \(measureCount)" },
                    commitAction: seekToMeasureAction,
                    showsPositionChip: false
                )
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 3)
    }

    private var timeLabel: some View {
        Group {
            if isCountingIn {
                Text("Count-in")
            } else if let playbackPreparationMessage {
                Text(playbackPreparationMessage)
            } else {
                HStack(spacing: 0) {
                    Text(playbackState.currentTimeLabel)
                        .foregroundStyle(Color.black.opacity(0.88))
                    Text(" / " + playbackState.durationLabel)
                        .foregroundStyle(Color.black.opacity(0.42))
                }
            }
        }
        .font(.system(size: 20, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var measureStepper: some View {
        HStack(spacing: 4) {
            Button {
                seekToMeasureAction(max(currentMeasure - 1, 0))
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 40)
            }
            .accessibilityLabel("Previous measure")

            Text("m. \(currentMeasure + 1)")
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .frame(minWidth: 50)

            Button {
                seekToMeasureAction(min(currentMeasure + 1, measureCount - 1))
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 40)
            }
            .accessibilityLabel("Next measure")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.black.opacity(0.84))
        .padding(.horizontal, 4)
        .background(Color.black.opacity(0.05), in: Capsule())
    }

    private func circleButton(systemImage: String, size: CGFloat, isProminent: Bool, isActive: Bool,
                              isEnabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isProminent && isPlaybackBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: isProminent ? 20 : 15, weight: isProminent ? .bold : .semibold))
                }
            }
            .foregroundStyle(isProminent ? Color.white : (isActive ? Self.accentColor : Color.black.opacity(0.84)))
            .frame(width: size, height: size)
            .background(isProminent ? Self.accentColor : (isActive ? Self.accentColor.opacity(0.14) : Color.black.opacity(0.06)),
                        in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}

/// The panel's slider: a tall track with a big knob, a bubble naming the position and a
/// chip with the count. During playback it picks a measure (with a tick for each), otherwise
/// a page.
struct ScoreReaderStandScrubber: View {
    let count: Int
    let currentIndex: Int
    let showsTicks: Bool
    let accentColor: Color
    let accessibilityName: String
    let markLabel: (Int) -> String
    let bubbleLabel: (Int) -> String
    let positionLabel: (Int) -> String
    let commitAction: (Int) -> Void
    var showsPositionChip = true

    @State var scrubIndex: Int?

    private let knobSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 14) {
            track
                .frame(height: 64)
            if showsPositionChip {
                Text(positionLabel(shownIndex))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.black.opacity(0.84))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(Color.white.opacity(0.85), in: Capsule())
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(positionLabel(shownIndex))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                commitAction(min(currentIndex + 1, count - 1))
            case .decrement:
                commitAction(max(currentIndex - 1, 0))
            @unknown default:
                break
            }
        }
    }

    private var shownIndex: Int {
        min(max(scrubIndex ?? currentIndex, 0), max(count - 1, 0))
    }

    private var track: some View {
        GeometryReader { proxy in
            let usableWidth = max(proxy.size.width - knobSize, 1)
            let lastIndex = max(count - 1, 1)
            let knobX = usableWidth * CGFloat(shownIndex) / CGFloat(lastIndex)
            let markStride = count <= 12 ? 1 : max(1, Int((Double(count) / 9).rounded(.up)))
            let trackY = proxy.size.height * 0.52

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: usableWidth, height: 6)
                    .offset(x: knobSize / 2, y: trackY - 3)
                Capsule()
                    .fill(accentColor)
                    .frame(width: max(knobX, 0), height: 6)
                    .offset(x: knobSize / 2, y: trackY - 3)

                if showsTicks && count <= 120 {
                    ForEach(0..<count, id: \.self) { index in
                        Rectangle()
                            .fill(Color.black.opacity(index % markStride == 0 ? 0.30 : 0.14))
                            .frame(width: 1, height: index % markStride == 0 ? 12 : 8)
                            .offset(x: knobSize / 2 + usableWidth * CGFloat(index) / CGFloat(lastIndex),
                                    y: trackY - (index % markStride == 0 ? 6 : 4))
                    }
                }

                ForEach(Array(stride(from: 0, to: count, by: markStride)), id: \.self) { index in
                    Text(markLabel(index))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.black.opacity(index == shownIndex ? 0.80 : 0.50))
                        .fixedSize()
                        .frame(width: 30)
                        .offset(x: knobSize / 2 + usableWidth * CGFloat(index) / CGFloat(lastIndex) - 15,
                                y: trackY + 12)
                }

                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(accentColor, lineWidth: 2))
                    .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                    .frame(width: knobSize, height: knobSize)
                    .scaleEffect(scrubIndex != nil ? 1.2 : 1)
                    .offset(x: knobX, y: trackY - knobSize / 2)

                Text(bubbleLabel(shownIndex))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accentColor, in: Capsule())
                    .fixedSize()
                    .frame(width: 90)
                    .offset(x: knobX + knobSize / 2 - 45, y: trackY - knobSize / 2 - 30)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = (value.location.x - knobSize / 2) / usableWidth
                        scrubIndex = min(max(Int((fraction * CGFloat(lastIndex)).rounded()), 0), max(count - 1, 0))
                    }
                    .onEnded { _ in
                        if let scrubIndex {
                            commitAction(scrubIndex)
                        }
                        scrubIndex = nil
                    }
            )
        }
    }
}
