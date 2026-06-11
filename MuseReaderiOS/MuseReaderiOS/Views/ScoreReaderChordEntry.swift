import SwiftUI
import UIKit

struct ScoreReaderChordEntryPanel: View {
    @Environment(\.scoreReaderCompactPanelEmbedded) private var embedsInCompactPanel

    @State private var chordText: String
    @State private var activeSelectionID: String?

    let selectionID: String?
    let initialText: String
    let isInsertEnabled: Bool
    let insertAction: (String) -> Void
    let insertAndAdvanceAction: (String) -> Void
    let nextAction: () -> Void
    let cancelAction: () -> Void

    init(
        selectionID: String? = nil,
        initialText: String = "",
        isInsertEnabled: Bool,
        insertAction: @escaping (String) -> Void,
        insertAndAdvanceAction: @escaping (String) -> Void,
        nextAction: @escaping () -> Void,
        cancelAction: @escaping () -> Void
    ) {
        self.selectionID = selectionID
        self.initialText = initialText
        self.isInsertEnabled = isInsertEnabled
        self.insertAction = insertAction
        self.insertAndAdvanceAction = insertAndAdvanceAction
        self.nextAction = nextAction
        self.cancelAction = cancelAction
        _chordText = State(initialValue: initialText)
        _activeSelectionID = State(initialValue: selectionID)
    }

    var body: some View {
        Group {
            if isPhoneInterface && embedsInCompactPanel {
                phoneEmbeddedBody
            } else {
                standardBody
            }
        }
        .onChange(of: selectionID) { _, newSelectionID in
            guard activeSelectionID != newSelectionID else {
                return
            }

            activeSelectionID = newSelectionID
            chordText = initialText
        }
        .onChange(of: initialText) { _, newText in
            guard chordText.isEmpty || activeSelectionID != selectionID else {
                return
            }

            chordText = newText
        }
    }

    private var standardBody: some View {
        HStack(spacing: isPhoneInterface ? 8 : 12) {
            textField
            dismissButton
        }
        .padding(isPhoneInterface ? 9 : 12)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    private var phoneEmbeddedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            textField
                .frame(maxWidth: .infinity)
                .frame(height: 44)

            Text("Return inserts chord • Space inserts and moves to next beat")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textField: some View {
        ScoreReaderChordTextInputField(
            text: $chordText,
            placeholder: "Cmaj7/G",
            isFirstResponder: true,
            commitAction: commit,
            spaceAction: commitAndAdvance,
            dismissAction: cancelAction
        )
        .frame(height: isPhoneInterface && embedsInCompactPanel ? 44 : (isPhoneInterface ? 42 : 48))
        .padding(.horizontal, embedsInCompactPanel && isPhoneInterface ? 12 : 0)
        .background(
            embedsInCompactPanel && isPhoneInterface
                ? Color.black.opacity(0.04)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            if embedsInCompactPanel && isPhoneInterface {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.7)
            }
        }
    }

    private var dismissButton: some View {
        Button(action: cancelAction) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: isPhoneInterface ? 19 : 22, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.42))
                .frame(width: isPhoneInterface ? 36 : 44, height: isPhoneInterface ? 40 : 44)
        }
        .buttonStyle(.plain)
    }

    private var panelBackground: Color {
        Color.white.opacity(0.90)
    }

    private var panelCornerRadius: CGFloat {
        isPhoneInterface ? 11 : 12
    }

    private var isPhoneInterface: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private func commit() {
        guard isInsertEnabled, let trimmedChordText = chordText.trimmedToNil else {
            return
        }

        insertAction(trimmedChordText)
        chordText = ""
    }

    private func commitAndAdvance() {
        guard isInsertEnabled else {
            return
        }

        guard let trimmedChordText = chordText.trimmedToNil else {
            nextAction()
            return
        }

        insertAndAdvanceAction(trimmedChordText)
        chordText = ""
    }
}

struct ScoreReaderLyricsEntryPanel: View {
    @Environment(\.scoreReaderCompactPanelEmbedded) private var embedsInCompactPanel

    @State private var lyricsText: String
    @State private var activeSelectionID: String?

    let selectionID: String?
    let initialText: String
    let isInsertEnabled: Bool
    let insertAction: (String, Bool) -> Void
    let cancelAction: () -> Void

    init(
        selectionID: String?,
        initialText: String,
        isInsertEnabled: Bool,
        insertAction: @escaping (String, Bool) -> Void,
        cancelAction: @escaping () -> Void
    ) {
        self.selectionID = selectionID
        self.initialText = initialText
        self.isInsertEnabled = isInsertEnabled
        self.insertAction = insertAction
        self.cancelAction = cancelAction
        _lyricsText = State(initialValue: initialText)
        _activeSelectionID = State(initialValue: selectionID)
    }

    var body: some View {
        Group {
            if isPhoneInterface && embedsInCompactPanel {
                phoneEmbeddedBody
            } else {
                standardBody
            }
        }
        .onChange(of: selectionID) { _, newSelectionID in
            guard activeSelectionID != newSelectionID else {
                return
            }

            activeSelectionID = newSelectionID
            lyricsText = initialText
        }
        .onChange(of: initialText) { _, newText in
            guard lyricsText.isEmpty || activeSelectionID != selectionID else {
                return
            }

            lyricsText = newText
        }
    }

    private var standardBody: some View {
        HStack(spacing: isPhoneInterface ? 8 : 12) {
            textField
            dismissButton
        }
        .padding(isPhoneInterface ? 9 : 12)
        .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    private var phoneEmbeddedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            textField
                .frame(maxWidth: .infinity)
                .frame(height: 44)

            Text("Return inserts line • Space inserts and moves to next note")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textField: some View {
        ScoreReaderLyricsTextInputField(
            text: $lyricsText,
            placeholder: "Type lyrics…",
            isFirstResponder: true,
            commitAction: commit,
            spaceAction: commitAndAdvance,
            dismissAction: cancelAction
        )
        .frame(height: isPhoneInterface && embedsInCompactPanel ? 44 : (isPhoneInterface ? 42 : 48))
        .padding(.horizontal, embedsInCompactPanel && isPhoneInterface ? 12 : 0)
        .background(
            embedsInCompactPanel && isPhoneInterface
                ? Color.black.opacity(0.04)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            if embedsInCompactPanel && isPhoneInterface {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.7)
            }
        }
    }

    private var dismissButton: some View {
        Button(action: cancelAction) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: isPhoneInterface ? 19 : 22, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.42))
                .frame(width: isPhoneInterface ? 36 : 44, height: isPhoneInterface ? 40 : 44)
        }
        .buttonStyle(.plain)
    }

    private var panelCornerRadius: CGFloat {
        isPhoneInterface ? 11 : 12
    }

    private var isPhoneInterface: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private func commit() {
        guard isInsertEnabled, let trimmedLyricsText = lyricsText.trimmedToNil else {
            return
        }

        insertAction(trimmedLyricsText, false)
        lyricsText = ""
    }

    private func commitAndAdvance() {
        guard isInsertEnabled, let trimmedLyricsText = lyricsText.trimmedToNil else {
            return
        }

        insertAction(trimmedLyricsText, true)
        lyricsText = ""
    }
}

struct ScoreReaderChordBuilderButton: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let minWidth: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minWidth: minWidth, minHeight: 46)
                .foregroundStyle(isSelected ? Color.blue : Color.black.opacity(isEnabled ? 0.82 : 0.34))
                .background(backgroundFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.blue.opacity(0.65) : Color.black.opacity(0.08), lineWidth: isSelected ? 1.6 : 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var backgroundFill: Color {
        if !isEnabled {
            return Color.white.opacity(0.42)
        }

        return isSelected ? Color.blue.opacity(0.10) : Color.white.opacity(0.72)
    }
}
