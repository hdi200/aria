import SwiftUI

struct ScoreReaderModeToolbar: View {
    let editingState: ScoreEditingState
    let isBusy: Bool
    var isCompact = false
    @Binding var selectedToolCategory: ScoreReaderToolCategory
    let selectModeAction: () -> Void
    let noteInputModeAction: () -> Void
    let isMeasureSelection: Bool
    let isSingleMeasureSelection: Bool

    var body: some View {
        Group {
            if isCompact {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        compactButtons
                    }
                    .frame(minHeight: 50)
                }
            } else {
                HStack(spacing: 0) {
                    regularButtons
                }
            }
        }
        .padding(.horizontal, isCompact ? 4 : 10)
        .padding(.vertical, isCompact ? 0 : 8)
        .frame(maxWidth: isCompact ? .infinity : nil)
        .modifier(ScoreReaderModeToolbarChromeModifier(isCompact: isCompact))
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        if isCompact {
            ScrollView(.horizontal, showsIndicators: false) {
                compactButtons
            }
        } else {
            regularButtons
        }
    }

    @ViewBuilder
    private var regularButtons: some View {
        ScoreReaderModeToolbarButton(title: "Note\nEntry", systemImage: "music.note.list", showsPlusBadge: true, isActive: selectedToolCategory == .notes, isEnabled: categoryEnabled(.notes), action: noteInputModeAction)
        ScoreReaderModeToolbarButton(title: "Select", systemImage: "cursorarrow", isActive: selectedToolCategory == .select, isEnabled: !isBusy, action: selectModeAction)

        Divider()
            .frame(height: 34)
            .padding(.horizontal, 6)

        categoryButton(.repeats, title: "Repeats", systemImage: "repeat")
        categoryButton(.text, title: "Text", systemImage: "textformat")
        categoryButton(.expression, title: "Expression", textSymbol: "f")
        categoryButton(.layout, title: "Layout", systemImage: "square.grid.2x2")
        categoryButton(.more, title: "More", systemImage: "ellipsis")
    }

    @ViewBuilder
    private var compactButtons: some View {
        compactCategoryButton(.notes, title: "Note", systemImage: "music.note", showsPlusBadge: true, action: noteInputModeAction)
        compactDivider
        compactSelectButton
        compactDivider
        compactCategoryButton(.text, title: "Text", systemImage: "textformat")
        compactDivider
        compactCategoryButton(.repeats, title: "Repeats", systemImage: "repeat")
        compactDivider
        compactCategoryButton(.expression, title: "Expr", textSymbol: "f")
        compactDivider
        compactCategoryButton(.layout, title: "Layout", systemImage: "square.grid.2x2")
        compactDivider
        compactCategoryButton(.more, title: "More", systemImage: "ellipsis")
    }

    private func categoryButton(_ category: ScoreReaderToolCategory, title: String, systemImage: String? = nil, textSymbol: String? = nil) -> some View {
        ScoreReaderModeToolbarButton(title: title, systemImage: systemImage, textSymbol: textSymbol, isActive: selectedToolCategory == category, isEnabled: categoryEnabled(category), action: {
            selectModeAction()
            selectedToolCategory = category
        })
    }

    private func compactCategoryButton(_ category: ScoreReaderToolCategory, title: String, systemImage: String? = nil, textSymbol: String? = nil, showsPlusBadge: Bool = false, action: (() -> Void)? = nil) -> some View {
        ScoreReaderCompactModeToolbarButton(title: title, systemImage: systemImage, textSymbol: textSymbol, showsPlusBadge: showsPlusBadge, isActive: selectedToolCategory == category, isEnabled: categoryEnabled(category), action: {
            if let action {
                selectedToolCategory = category
                action()
            } else {
                selectModeAction()
                selectedToolCategory = category
            }
        })
    }

    private var compactSelectButton: some View {
        Button {
            selectModeAction()
            selectedToolCategory = .select
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: ScoreReaderCompactModeMetrics.iconSlotHeight, height: ScoreReaderCompactModeMetrics.iconSlotHeight)

                Text("Select")
                    .font(.system(size: 10, weight: selectedToolCategory == .select ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(selectedToolCategory == .select ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color.black.opacity(0.82))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scoreReaderCompactModeCellHighlight(isActive: selectedToolCategory == .select)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: ScoreReaderCompactModeMetrics.cellWidth, height: ScoreReaderCompactModeMetrics.cellHeight)
        .disabled(isBusy)
        .opacity(isBusy ? 0.42 : 1)
    }

    private var compactDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(width: 0.5, height: 30)
    }

    private func categoryEnabled(_ category: ScoreReaderToolCategory) -> Bool {
        guard !isBusy else {
            return false
        }

        guard isMeasureSelection else {
            return true
        }

        if isSingleMeasureSelection {
            return true
        }

        return category == .repeats || category == .expression || category == .layout || category == .more
    }
}

private struct ScoreReaderModeToolbarChromeModifier: ViewModifier {
    let isCompact: Bool

    func body(content: Content) -> some View {
        if isCompact {
            content
        } else {
            content
                .scoreReaderModeChooserBackground(cornerRadius: 12)
                .shadow(color: Color.black.opacity(0.10), radius: 12, y: 4)
        }
    }
}

private enum ScoreReaderCompactModeMetrics {
    static let cellWidth: CGFloat = 68
    static let cellHeight: CGFloat = 50
    static let iconSlotHeight: CGFloat = 24
    static let highlightCornerRadius: CGFloat = 10
}

private extension View {
    @ViewBuilder
    func scoreReaderModeChooserBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        self
            .background(Color.white.opacity(0.72), in: shape)
            .overlay {
                shape
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
    }

    /// Fixed-size selection chip for compact mode tabs (same footprint for every icon/label).
    func scoreReaderCompactModeCellHighlight(isActive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: ScoreReaderCompactModeMetrics.highlightCornerRadius, style: .continuous)

        return frame(
            width: ScoreReaderCompactModeMetrics.cellWidth,
            height: ScoreReaderCompactModeMetrics.cellHeight
        )
        .background {
            if isActive {
                shape
                    .fill(Color(red: 0.88, green: 0.94, blue: 1.0))
                shape
                    .stroke(Color.blue.opacity(0.28), lineWidth: 0.8)
            }
        }
    }

    @ViewBuilder
    func scoreReaderActiveModeSelection(isActive: Bool, cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if isActive {
            self.background {
                shape
                    .fill(Color(red: 0.88, green: 0.94, blue: 1.0))
                shape
                    .stroke(Color.blue.opacity(0.28), lineWidth: 0.8)
            }
        } else {
            self
        }
    }
}

struct ScoreReaderCompactModeToolbarButton: View {
    let title: String
    var systemImage: String? = nil
    var textSymbol: String? = nil
    var showsPlusBadge: Bool = false
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: 18, weight: .semibold))
                        } else if let textSymbol {
                            Text(textSymbol)
                                .font(.system(size: 22, weight: .bold, design: .serif))
                                .italic()
                                .rotationEffect(.degrees(-3))
                        }
                    }
                    .frame(width: ScoreReaderCompactModeMetrics.iconSlotHeight, height: ScoreReaderCompactModeMetrics.iconSlotHeight)

                    if showsPlusBadge {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .background(Color.white, in: Circle())
                            .offset(x: 4, y: 2)
                    }
                }
                .frame(width: ScoreReaderCompactModeMetrics.iconSlotHeight, height: ScoreReaderCompactModeMetrics.iconSlotHeight)

                Text(title)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(isActive ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color.black.opacity(0.82))
            .scoreReaderCompactModeCellHighlight(isActive: isActive)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: ScoreReaderCompactModeMetrics.cellWidth, height: ScoreReaderCompactModeMetrics.cellHeight)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

struct ScoreReaderModeToolbarButton: View {
    let title: String
    var systemImage: String? = nil
    var textSymbol: String? = nil
    var showsPlusBadge = false
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack(alignment: .bottomTrailing) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 17, weight: .semibold))
                    } else if let textSymbol {
                        Text(textSymbol)
                            .font(.system(size: 19, weight: .bold, design: .serif))
                            .italic()
                            .rotationEffect(.degrees(-3))
                            .baselineOffset(-1)
                    }
                    if showsPlusBadge {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .background(Color.white, in: Circle())
                            .offset(x: 5, y: 4)
                    }
                }
                .frame(width: 22, height: 22)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(title.contains("\n") ? 2 : 1)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.58)
            }
            .foregroundStyle(isActive ? Color(red: 0.08, green: 0.42, blue: 0.92) : Color.black.opacity(0.78))
            .frame(height: 34)
            .padding(.horizontal, 11)
            .scoreReaderActiveModeSelection(isActive: isActive, cornerRadius: 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

struct ScoreReaderUndoRedoControls: View {
    let canUndo: Bool
    let canRedo: Bool
    let isBusy: Bool
    let undoAction: () -> Void
    let redoAction: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: undoAction) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .disabled(!canUndo || isBusy)
            .opacity(canUndo && !isBusy ? 1 : 0.38)
            .accessibilityLabel("Undo")

            Button(action: redoAction) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .disabled(!canRedo || isBusy)
            .opacity(canRedo && !isBusy ? 1 : 0.38)
            .accessibilityLabel("Redo")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.black.opacity(0.78))
    }
}

struct ScoreReaderPreviousNextControls: View {
    let isEnabled: Bool
    let previousAction: () -> Void
    let nextAction: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: previousAction) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Select Previous")

            Button(action: nextAction) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Select Next")
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .foregroundStyle(Color.black.opacity(0.78))
    }
}

struct ScoreReaderVoiceSelector: View {
    @State private var isExpanded = false

    let currentVoice: Int
    let isEnabled: Bool
    let action: (Int) -> Void

    var body: some View {
        Button {
            isExpanded = true
        } label: {
            Text("\(currentVoice + 1)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(voiceForegroundColor(currentVoice, isSelected: true))
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(voiceBackgroundColor(currentVoice, isSelected: true))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(voiceStrokeColor(currentVoice, isSelected: true), lineWidth: 0.75)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel("Voice \(currentVoice + 1)")
        .popover(isPresented: $isExpanded, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { voice in
                    if voice != currentVoice {
                        Button {
                            isExpanded = false
                            action(voice)
                        } label: {
                            Text("\(voice + 1)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(voiceForegroundColor(voice, isSelected: false))
                                .frame(width: 38, height: 38)
                                .background {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(voiceBackgroundColor(voice, isSelected: false))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(voiceStrokeColor(voice, isSelected: false), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Voice \(voice + 1)")
                    }
                }
            }
            .padding(10)
            .presentationCompactPopoverWhenAvailable()
        }
    }

    private func voiceForegroundColor(_ voice: Int, isSelected: Bool) -> Color {
        if voice == 0 {
            return Color.black.opacity(isSelected ? 0.82 : 0.72)
        }

        return isSelected ? Color.white : voiceColor(voice)
    }

    private func voiceBackgroundColor(_ voice: Int, isSelected: Bool) -> Color {
        if voice == 0 {
            return Color.white.opacity(isSelected ? 0.84 : 0.78)
        }

        return isSelected ? voiceColor(voice) : Color.white.opacity(0.82)
    }

    private func voiceStrokeColor(_ voice: Int, isSelected: Bool) -> Color {
        if voice == 0 {
            return Color.black.opacity(isSelected ? 0.18 : 0.14)
        }

        return isSelected ? Color.white.opacity(0.35) : voiceColor(voice).opacity(0.45)
    }

    private func voiceColor(_ voice: Int) -> Color {
        switch voice {
        case 1:
            return Color(red: 0.0, green: 0.50, blue: 0.0)
        case 2:
            return Color(red: 0.77, green: 0.25, blue: 0.0)
        case 3:
            return Color(red: 0.76, green: 0.10, blue: 0.54)
        default:
            return Color(red: 0.0, green: 0.40, blue: 0.75)
        }
    }
}

struct ScoreReaderSideAccidentalButton: View {
    let textSymbol: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(textSymbol)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(isSelected ? Color(red: 0.08, green: 0.35, blue: 0.88) : Color.black.opacity(0.82))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isSelected ? Color(red: 0.86, green: 0.92, blue: 1.0) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

struct ScoreReaderPitchNudgePair: View {
    let title: String
    let isEnabled: Bool
    let upAction: () -> Void
    let downAction: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.black.opacity(0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            VStack(spacing: 0) {
                nudgeButton(systemImage: "arrowtriangle.up.fill", action: upAction)

                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 0.75)

                nudgeButton(systemImage: "arrowtriangle.down.fill", action: downAction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.black.opacity(0.07), lineWidth: 0.7)
            }
        }
        .foregroundStyle(Color.black.opacity(0.74))
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }

    private func nudgeButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.001))

                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.045), in: Circle())
            }
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
    }
}

struct ScoreReaderNoteEntryGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))

            content
        }
    }
}

struct ScoreReaderNotationButton: View {
    let title: String
    var symbol: String? = nil
    var textSymbol: String? = nil
    var systemImage: String? = nil
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Group {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 18, weight: .semibold))
                    } else if let textSymbol {
                        Text(textSymbol)
                            .font(.system(size: 20, weight: .medium))
                    } else if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .frame(height: 24)

                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                }
            }
            .foregroundStyle(isSelected ? .white : Color.black.opacity(0.80))
            .frame(width: 52, height: 52)
            .background(
                isSelected ? Color(red: 0.18, green: 0.47, blue: 0.95) : Color.white,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}
