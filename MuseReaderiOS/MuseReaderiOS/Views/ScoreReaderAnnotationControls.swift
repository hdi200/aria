//
//  ScoreReaderAnnotationControls.swift
//  MuseReaderiOS
//

import SwiftUI

struct ScoreReaderAnnotationPalette: View {
    @Binding var tool: ScoreAnnotationTool
    @Binding var color: ScoreAnnotationColor
    @Binding var width: Double
    let annotationsVisible: Bool
    let canUndo: Bool
    let canRedo: Bool
    let hasSelection: Bool
    let undoAction: () -> Void
    let redoAction: () -> Void
    let toggleVisibilityAction: () -> Void
    let deleteSelectionAction: () -> Void
    let doneAction: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            toolControls
            sectionSpacer
            paletteDivider
            sectionSpacer
            colorControls
            sectionSpacer
            paletteDivider
            sectionSpacer
            widthControls
            sectionSpacer
            paletteDivider
            sectionSpacer
            historyControls
            sectionSpacer
            paletteButton(
                systemImage: annotationsVisible ? "eye" : "eye.slash",
                label: annotationsVisible ? "Hide annotations" : "Show annotations",
                isEnabled: true,
                action: toggleVisibilityAction
            )
            paletteButton(
                systemImage: "trash",
                label: "Delete selected annotations",
                isEnabled: hasSelection,
                action: deleteSelectionAction
            )
            sectionSpacer
            doneButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 16, y: 7)
    }

    private var toolControls: some View {
        HStack(spacing: 4) {
            ForEach(ScoreAnnotationTool.allCases, id: \.self) { candidate in
                Button {
                    tool = candidate
                } label: {
                    toolIcon(candidate)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 38, height: 40)
                        .background(
                            tool == candidate ? Color.blue : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.title)
                .accessibilityValue(tool == candidate ? "Selected" : "")
            }
        }
    }

    private var colorControls: some View {
        HStack(spacing: 2) {
            ForEach(ScoreAnnotationColor.allCases, id: \.self) { candidate in
                Button {
                    color = candidate
                    if !tool.createsStroke {
                        tool = .pen
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(color == candidate ? candidate.swiftUIColor.opacity(0.42) : Color.clear, lineWidth: 2)
                            .frame(width: 32, height: 32)
                        Circle()
                            .fill(candidate.swiftUIColor)
                            .frame(width: color == candidate ? 23 : 20, height: color == candidate ? 23 : 20)
                        if color == candidate {
                            Circle()
                                .stroke(Color.white.opacity(0.92), lineWidth: 2)
                                .frame(width: 23, height: 23)
                        }
                    }
                    .frame(width: 34, height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.accessibilityName)
                .accessibilityValue(color == candidate ? "Selected" : "")
            }
        }
    }

    private var widthControls: some View {
        HStack(spacing: 2) {
            widthButton(value: 2, diameter: 5, label: "Thin")
            widthButton(value: 4, diameter: 9, label: "Medium")
            widthButton(value: 7, diameter: 13, label: "Thick")
        }
    }

    private var historyControls: some View {
        HStack(spacing: 2) {
            paletteButton(systemImage: "arrow.uturn.backward", label: "Undo annotation", isEnabled: canUndo, action: undoAction)
            paletteButton(systemImage: "arrow.uturn.forward", label: "Redo annotation", isEnabled: canRedo, action: redoAction)
        }
    }

    private var doneButton: some View {
        Button(action: doneAction) {
            Text("Done")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Color.blue, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Finish annotating")
    }

    private var paletteDivider: some View {
        Divider()
            .frame(height: 24)
    }

    private var sectionSpacer: some View {
        Spacer(minLength: 2)
    }

    private func paletteButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.32)
        .accessibilityLabel(label)
    }

    private func widthButton(value: Double, diameter: CGFloat, label: String) -> some View {
        Button {
            width = value
            if !tool.createsStroke {
                tool = .pen
            }
        } label: {
            ZStack {
                if width == value {
                    Circle()
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: 28, height: 28)
                }
                Circle()
                    .fill(Color.black.opacity(0.90))
                    .frame(width: diameter, height: diameter)
            }
            .frame(width: 34, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) stroke")
        .accessibilityValue(width == value ? "Selected" : "")
    }

    private func toolIcon(_ candidate: ScoreAnnotationTool) -> some View {
        Image(systemName: candidate.systemImage)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tool == candidate ? Color.white : Color.black.opacity(0.80))
    }
}

struct ScoreReaderAnnotationPageNavigator: View {
    let currentPageIndex: Int
    let pageCount: Int
    let previousAction: () -> Void
    let nextAction: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            pageButton(systemImage: "chevron.left", label: "Previous page", isEnabled: currentPageIndex > 0, action: previousAction)

            Text("\(currentPageIndex + 1) of \(pageCount)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.black.opacity(0.70))
                .frame(minWidth: 62)

            pageButton(systemImage: "chevron.right", label: "Next page", isEnabled: currentPageIndex + 1 < pageCount, action: nextAction)
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(Color.black.opacity(0.07), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(0.13), radius: 14, y: 5)
    }

    private func pageButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.30)
        .accessibilityLabel(label)
    }
}

private extension ScoreAnnotationColor {
    var accessibilityName: String {
        switch self {
        case .red: return "Red"
        case .blue: return "Blue"
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .black: return "Black"
        }
    }

    var swiftUIColor: Color {
        let rgba = rgba
        return Color(red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
