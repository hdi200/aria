//
//  ScoreReaderChromeBar.swift
//  MuseReaderiOS
//

import SwiftUI
import UIKit

struct ScoreReaderChromeBar: View {
    let scoreTitle: String
    let parts: [ScorePart]
    @Binding var selectedPartID: String
    @Binding var isPartsPanelPresented: Bool
    @Binding var isExportPanelPresented: Bool
    let supportsEditing: Bool
    let supportsPlayback: Bool
    let editingState: ScoreEditingState
    let playbackState: ScorePlaybackState
    let metronomeEnabled: Bool
    let isEditingBusy: Bool
    let isPlaybackBusy: Bool
    let playbackPreparationMessage: String?
    let concertPitchEnabled: Bool
    let showsConcertPitchControl: Bool
    let closeAction: () -> Void
    let selectModeAction: () -> Void
    let noteInputModeAction: () -> Void
    let togglePlaybackAction: () -> Void
    let stopPlaybackAction: () -> Void
    let toggleMetronomeAction: () -> Void
    let toggleConcertPitchAction: () -> Void
    let exportAction: () -> Void
    let selectPartAction: (Int?) -> Void
    let managePartsAction: () -> Void
    let exportPanelContent: () -> AnyView

    var body: some View {
        GeometryReader { proxy in
            let isPhoneHeader = UIDevice.current.userInterfaceIdiom == .phone
            let isPhoneLandscape = isPhoneHeader && proxy.size.width > proxy.size.height
            let isTightPhoneLandscape = isPhoneLandscape && proxy.size.width < 780
            let isCompactHeader = proxy.size.width < 920
            // iPhone and iPad share separated floating islands; phone uses tighter controls.
            let usesPhoneFloatingIslands = isPhoneHeader
            let showsPlaybackTimeOnPhone = !isPhoneLandscape || proxy.size.width >= 780

            Group {
                if usesPhoneFloatingIslands {
                    phoneFloatingIslandHeader(
                        availableWidth: proxy.size.width,
                        isPhoneLandscape: isPhoneLandscape,
                        showsPlaybackTime: showsPlaybackTimeOnPhone
                    )
                        .padding(.horizontal, isPhoneLandscape ? 10 : 12)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                } else {
                    floatingIslandHeader(
                        isCompactHeader: isCompactHeader,
                        isPhoneLandscape: isPhoneLandscape,
                        isTightPhoneLandscape: isTightPhoneLandscape
                    )
                        .padding(.horizontal, isPhoneLandscape ? 10 : (isCompactHeader ? 10 : 18))
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                }
            }
        }
        .frame(height: 62)
    }

    private func floatingIslandHeader(isCompactHeader: Bool, isPhoneLandscape: Bool, isTightPhoneLandscape: Bool) -> some View {
        Group {
            if isPhoneLandscape {
                phoneLandscapeFloatingHeader(
                    isCompactHeader: isCompactHeader,
                    showsPlaybackTime: !isTightPhoneLandscape
                )
            } else {
                tabletStyleFloatingIslandHeader(isCompactHeader: isCompactHeader)
            }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.84))
    }

    /// iPhone landscape: HStack keeps islands from overlapping in the ZStack center layer.
    private func phoneLandscapeFloatingHeader(isCompactHeader: Bool, showsPlaybackTime: Bool) -> some View {
        HStack(spacing: 8) {
            floatingIsland(horizontalPadding: 8) {
                Button(action: closeAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                        Text(scoreTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .scoreReaderChromeTapTarget(minWidth: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            .layoutPriority(1)

            if supportsPlayback {
                floatingIsland(horizontalPadding: 6) {
                    playbackIslandControls(isCompactHeader: true, showsElapsedTime: showsPlaybackTime)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 4)

            if showsConcertPitchControl || parts.count > 1 {
                floatingIsland(horizontalPadding: 6) {
                    HStack(spacing: 6) {
                        if showsConcertPitchControl {
                            concertPitchIslandButton(isCompactHeader: true, iconOnly: true)
                        }
                        if parts.count > 1 {
                            partsIslandButton(iconOnly: true)
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            floatingIsland(horizontalPadding: 5) {
                exportIslandButton(fontSize: 18, minWidth: 40)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func tabletStyleFloatingIslandHeader(isCompactHeader: Bool) -> some View {
        ZStack {
            HStack {
                floatingIsland(horizontalPadding: 10) {
                    Button(action: closeAction) {
                        HStack(spacing: 10) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .semibold))
                            Text(scoreTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                        }
                        .scoreReaderChromeTapTarget(minWidth: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }

                Spacer(minLength: 0)
            }

            if supportsPlayback {
                floatingIsland {
                    playbackIslandControls(isCompactHeader: isCompactHeader)
                }
            }

            HStack(spacing: 12) {
                Spacer(minLength: 0)

                if showsConcertPitchControl || parts.count > 1 {
                    floatingIsland {
                        HStack(spacing: isCompactHeader ? 8 : 10) {
                            if showsConcertPitchControl {
                                concertPitchIslandButton(isCompactHeader: isCompactHeader)
                            }

                            if parts.count > 1 {
                                partsIslandButton()
                            }
                        }
                    }
                }

                floatingIsland(horizontalPadding: 5) {
                    exportIslandButton(fontSize: 21, minWidth: 44)
                }
            }
        }
    }

    private func playbackIslandControls(isCompactHeader: Bool, showsElapsedTime: Bool = true) -> some View {
        HStack(spacing: isCompactHeader ? 0 : 2) {
            Button(action: togglePlaybackAction) {
                Group {
                    if isPlaybackBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .bold))
                    }
                }
                .scoreReaderChromeTapTarget(minWidth: 44)
            }
            .disabled(!supportsPlayback || !playbackState.isAvailable || playbackState.isPlaying || isPlaybackBusy)
            .opacity(supportsPlayback && playbackState.isAvailable && !playbackState.isPlaying ? 1 : 0.36)
            .accessibilityLabel("Play")

            Button(action: togglePlaybackAction) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 15, weight: .bold))
                    .scoreReaderChromeTapTarget(minWidth: 44)
            }
            .disabled(!playbackState.isAvailable || !playbackState.isPlaying || isPlaybackBusy)
            .opacity(playbackState.isAvailable && playbackState.isPlaying ? 0.92 : 0.36)
            .accessibilityLabel("Pause playback")

            Button(action: stopPlaybackAction) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .scoreReaderChromeTapTarget(minWidth: 44)
            }
            .disabled(!playbackState.isAvailable || playbackState.status == .stopped || isPlaybackBusy)
            .opacity(playbackState.isAvailable && playbackState.status != .stopped ? 0.92 : 0.36)
            .accessibilityLabel("Stop playback")

            Button(action: toggleMetronomeAction) {
                Image(systemName: "metronome")
                    .font(.system(size: isCompactHeader ? 22 : 24, weight: .medium))
                    .scaleEffect(x: 0.86, y: 1.0, anchor: .center)
                    .scoreReaderChromeTapTarget(minWidth: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(metronomeEnabled ? Color(red: 0.12, green: 0.45, blue: 0.92) : Color.black.opacity(0.84))
            .disabled(!playbackState.isAvailable || isPlaybackBusy)
            .opacity(playbackState.isAvailable ? 1 : 0.45)
            .accessibilityLabel("Metronome")

            if showsElapsedTime {
                Text(playbackPreparationMessage ?? "\(playbackState.currentTimeLabel) / \(playbackState.durationLabel)")
                    .font(.system(size: isCompactHeader ? 11 : 13, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func concertPitchIslandButton(isCompactHeader: Bool, iconOnly: Bool = false) -> some View {
        Button(action: toggleConcertPitchAction) {
            Group {
                if iconOnly {
                    Image(systemName: "music.quarternote.3")
                        .font(.system(size: 17, weight: .semibold))
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "music.quarternote.3")
                        Text("Concert")
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .font(.system(size: isCompactHeader ? 13 : 14, weight: .semibold))
                }
            }
            .scoreReaderChromeTapTarget(minWidth: iconOnly ? 40 : (isCompactHeader ? 88 : 96))
            .foregroundStyle(concertPitchEnabled ? Color.blue : Color.black.opacity(0.78))
        }
        .buttonStyle(.plain)
        .disabled(!supportsEditing || isEditingBusy)
        .opacity(supportsEditing ? 1 : 0.45)
        .accessibilityLabel("Concert Pitch")
    }

    private func partsIslandButton(iconOnly: Bool = false) -> some View {
        Button(action: togglePartsPanel) {
            Group {
                if iconOnly {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 16, weight: .semibold))
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Parts")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(isPartsPanelPresented ? Color.blue : Color.black.opacity(0.82))
            .scoreReaderChromeTapTarget(minWidth: iconOnly ? 40 : 76)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Parts")
        .popover(isPresented: $isPartsPanelPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            partsPanelContent
        }
    }

    private func exportIslandButton(fontSize: CGFloat, minWidth: CGFloat) -> some View {
        Button(action: exportAction) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: fontSize, weight: .medium))
                .scoreReaderChromeTapTarget(minWidth: minWidth)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Export Score")
        .popover(isPresented: $isExportPanelPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            exportPanelContent()
                .presentationCompactAdaptation(.popover)
        }
    }

    private var partsPanelContent: some View {
        ScoreReaderPartsPanel(
            parts: parts,
            selectedPartID: $selectedPartID,
            isPresented: $isPartsPanelPresented,
            selectPartAction: selectPartAction,
            managePartsAction: managePartsAction
        )
        .presentationCompactAdaptation(.popover)
    }

    private func togglePartsPanel() {
        if !isPartsPanelPresented {
            isExportPanelPresented = false
        }
        isPartsPanelPresented.toggle()
    }

    private func floatingIsland<Content: View>(
        horizontalPadding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .frame(height: 44)
            .scoreReaderChromeIslandBackground(cornerRadius: 18)
    }

    private func phoneFloatingIslandHeader(availableWidth: CGFloat, isPhoneLandscape: Bool, showsPlaybackTime: Bool) -> some View {
        let hasTrailingExtras = showsConcertPitchControl || parts.count > 1
        let showsCenteredPlaybackTime = showsPlaybackTime && (!hasTrailingExtras || availableWidth >= 620)
        let showsTitle = isPhoneLandscape && availableWidth >= 620

        return ZStack {
            HStack {
                floatingIsland(horizontalPadding: showsTitle ? 8 : 5) {
                    Button(action: closeAction) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))

                            if showsTitle {
                                Text(scoreTitle)
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .scoreReaderChromeTapTarget(minWidth: showsTitle ? 44 : 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                .frame(maxWidth: showsTitle ? max(96, availableWidth * 0.28) : nil, alignment: .leading)
                .fixedSize(horizontal: !showsTitle, vertical: false)

                Spacer(minLength: 0)
            }

            if supportsPlayback {
                floatingIsland(horizontalPadding: 10) {
                    compactPlaybackControls(showsElapsedTime: showsCenteredPlaybackTime)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                if hasTrailingExtras {
                    floatingIsland(horizontalPadding: 6) {
                        HStack(spacing: 6) {
                            if showsConcertPitchControl {
                                concertPitchIslandButton(isCompactHeader: true, iconOnly: true)
                            }

                            if parts.count > 1 {
                                partsIslandButton(iconOnly: true)
                            }
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                floatingIsland(horizontalPadding: 5) {
                    exportIslandButton(fontSize: 18, minWidth: 40)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.84))
    }

    private func compactPlaybackControls(showsElapsedTime: Bool) -> some View {
        HStack(spacing: 4) {
            Button(action: togglePlaybackAction) {
                Group {
                    if isPlaybackBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .frame(width: 24, height: 30)
            }
            .disabled(!supportsPlayback || !playbackState.isAvailable || playbackState.isPlaying || isPlaybackBusy)
            .opacity(supportsPlayback && playbackState.isAvailable && !playbackState.isPlaying ? 1 : 0.36)

            Button(action: togglePlaybackAction) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 22, height: 30)
            }
            .disabled(!playbackState.isAvailable || !playbackState.isPlaying || isPlaybackBusy)
            .opacity(playbackState.isAvailable && playbackState.isPlaying ? 0.92 : 0.36)

            Button(action: stopPlaybackAction) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 30)
            }
            .disabled(!playbackState.isAvailable || playbackState.status == .stopped || isPlaybackBusy)
            .opacity(playbackState.isAvailable && playbackState.status != .stopped ? 0.92 : 0.36)

            Button(action: toggleMetronomeAction) {
                Image(systemName: "metronome")
                    .font(.system(size: 19, weight: .medium))
                    .scaleEffect(x: 0.86, y: 1.0, anchor: .center)
                    .frame(width: 24, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(metronomeEnabled ? Color(red: 0.12, green: 0.45, blue: 0.92) : Color.black.opacity(0.84))
            .disabled(!playbackState.isAvailable || isPlaybackBusy)
            .opacity(playbackState.isAvailable ? 1 : 0.45)

            if showsElapsedTime {
                Text(playbackPreparationMessage ?? "\(playbackState.currentTimeLabel) / \(playbackState.durationLabel)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func scoreReaderTopBarBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
                .background(Color.white.opacity(0.20))
                .glassEffect(.regular.interactive(true))
                .shadow(color: Color.black.opacity(0.08), radius: 16, y: 6)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.34))
                        .frame(height: 0.7)
                        .allowsHitTesting(false)
                }
        } else {
            self
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.black.opacity(0.10))
                        .frame(height: 1)
                        .allowsHitTesting(false)
                }
        }
    }

    func scoreReaderChromeTapTarget(minWidth: CGFloat = 44) -> some View {
        self
            .frame(minWidth: minWidth, minHeight: 44)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    func scoreReaderChromeIslandBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            self
                .background(Color.white.opacity(0.26), in: shape)
                .glassEffect(.regular.interactive(true), in: shape)
                .overlay {
                    shape
                        .stroke(Color.white.opacity(0.36), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
                .shadow(color: Color.black.opacity(0.09), radius: 18, y: 8)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape
                        .stroke(Color.black.opacity(0.07), lineWidth: 0.7)
                        .allowsHitTesting(false)
                }
        }
    }
}

struct ScoreReaderPlaybackPreparationHUD: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.system(size: 14, weight: .semibold))
                Text("Preparing live playback stream")
                    .font(.caption2)
                    .foregroundStyle(Color.black.opacity(0.56))
            }
        }
        .foregroundStyle(Color.black.opacity(0.84))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
    }
}

struct ScoreReaderPartsPanel: View {
    let parts: [ScorePart]
    @Binding var selectedPartID: String
    @Binding var isPresented: Bool
    let selectPartAction: (Int?) -> Void
    let managePartsAction: () -> Void

    var body: some View {
        VStack(spacing: isPhone ? 8 : 12) {
            Capsule()
                .fill(Color.black.opacity(0.16))
                .frame(width: isPhone ? 36 : 44, height: 4)
                .padding(.top, isPhone ? 2 : 4)

            Text("Parts")
                .font(.system(size: isPhone ? 17 : 20, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.88))
                .padding(.bottom, isPhone ? 0 : 4)

            if !isPhone {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Linked Parts")
                            .font(.headline.weight(.semibold))

                        Text("Changes you make to notes, text and articulations will appear in all parts.")
                            .font(.caption)
                            .foregroundStyle(Color.black.opacity(0.52))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: isPhone ? 6 : 9) {
                    partRow(
                        id: "full-score",
                        title: "Full Score",
                        partIndex: nil,
                        clefSymbol: nil,
                        systemImage: "list.bullet.indent",
                        showsChevron: false
                    )

                    ForEach(parts) { part in
                        partRow(
                            id: part.id,
                            title: part.name,
                            partIndex: part.index,
                            clefSymbol: part.clef.symbol,
                            systemImage: nil,
                            showsChevron: true
                        )
                    }
                }
            }
            .frame(maxHeight: isPhone ? min(UIScreen.main.bounds.height * 0.66, 470) : min(UIScreen.main.bounds.height * 0.66, 640))

            if !isPhone {
                VStack(spacing: 9) {
                    partsActionButton(title: "Manage Parts", systemImage: "gearshape", action: managePartsAction)
                }
                .padding(.top, 4)
            }
        }
        .padding(isPhone ? 12 : 18)
        .frame(width: min(isPhone ? 300 : 330, max(UIScreen.main.bounds.width - 24, 284)))
        .frame(maxHeight: panelMaxHeight, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: isPhone ? 18 : 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isPhone ? 18 : 22, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 28, y: 14)
    }

    private var panelMaxHeight: CGFloat {
        isPhone ? min(UIScreen.main.bounds.height - 72, 560) : min(UIScreen.main.bounds.height - 110, 760)
    }

    private func partRow(id: String, title: String, partIndex: Int?, clefSymbol: String?, systemImage: String?, showsChevron: Bool) -> some View {
        let isSelected = selectedPartID == id

        return Button {
            selectedPartID = id
            selectPartAction(partIndex)
            isPresented = false
        } label: {
            HStack(spacing: isPhone ? 10 : 14) {
                Group {
                    if let clefSymbol {
                        ScoreReaderClefIcon(symbol: clefSymbol, isCompact: isPhone)
                    } else if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: isPhone ? 18 : 24, weight: .semibold))
                            .symbolVariant(isSelected ? .fill : .none)
                    }
                }
                .foregroundStyle(isSelected ? Self.selectedPartAccentColor : Color.black.opacity(0.82))
                .frame(width: isPhone ? 34 : 56, height: isPhone ? 42 : 60)

                Text(title)
                    .font(.system(size: isPhone ? 14 : 17, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Self.selectedPartAccentColor : Color.black.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: isPhone ? 11 : 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(isSelected ? 0.42 : 0.34))
                }
            }
            .padding(.horizontal, isPhone ? 10 : 14)
            .frame(height: isPhone ? 46 : 68)
            .background(rowBackground(isSelected: isSelected), in: RoundedRectangle(cornerRadius: isPhone ? 8 : 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: isPhone ? 8 : 10, style: .continuous)
                    .stroke(
                        isSelected ? Self.selectedPartAccentColor.opacity(0.42) : Color.black.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func partsActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Color.black.opacity(0.76))
            .frame(height: 48)
            .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func rowBackground(isSelected: Bool) -> Color {
        isSelected ? Self.selectedPartFillColor : Color.white.opacity(0.72)
    }

    private static let selectedPartAccentColor = Color(red: 0.0, green: 0.48, blue: 1.0)
    private static let selectedPartFillColor = Color(red: 0.86, green: 0.93, blue: 1.0)

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
}

struct ScoreReaderClefIcon: View {
    let symbol: String
    var isCompact = false

    var body: some View {
        Image(uiImage: ScoreReaderClefImage.image(for: symbol))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: isCompact ? 24 : 38, height: isCompact ? 30 : 46)
            .frame(width: isCompact ? 34 : 56, height: isCompact ? 42 : 60)
    }
}

enum ScoreReaderClefImage {
    private static var cache: [String: UIImage] = [:]

    static func image(for symbol: String) -> UIImage {
        if let cachedImage = cache[symbol] {
            return cachedImage
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false

        let canvasSize = CGSize(width: 96, height: 96)
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let image = renderer.image { _ in
            let font = UIFont(name: MusicNotationFont.postScriptName, size: 52)
                ?? UIFont.systemFont(ofSize: 52, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black
            ]
            let attributedSymbol = NSAttributedString(string: symbol, attributes: attributes)
            let bounds = attributedSymbol.boundingRect(
                with: CGSize(width: canvasSize.width * 2, height: canvasSize.height * 2),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            let drawRect = CGRect(
                x: (canvasSize.width - bounds.width) / 2 - bounds.minX,
                y: (canvasSize.height - bounds.height) / 2 - bounds.minY,
                width: bounds.width,
                height: bounds.height
            )
            attributedSymbol.draw(in: drawRect)
        }.withRenderingMode(.alwaysTemplate)

        cache[symbol] = image
        return image
    }
}

struct ScoreReaderTopToolButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(height: 22)

                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isActive ? .white : Color.white.opacity(0.78))
            .frame(minWidth: 54, minHeight: 50)
            .background(
                isActive ? Color(red: 0.20, green: 0.35, blue: 0.55).opacity(0.92) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}
