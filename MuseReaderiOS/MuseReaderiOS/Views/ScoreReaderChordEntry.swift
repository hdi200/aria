import SwiftUI
import UIKit

struct ScoreReaderChordEntryPanel: View {
    @State var draft: ScoreReaderChordBuilderDraft
    @State var activeSelectionID: String?

    let selectionID: String?
    let initialText: String
    let isInsertEnabled: Bool
    let positionText: String
    let insertAction: (String) -> Void
    let insertAndAdvanceAction: (String) -> Void
    let insertAndGoBackAction: (String) -> Void
    let removeAction: (Bool?) -> Void
    let previousAction: () -> Void
    let nextAction: () -> Void
    let doneAction: () -> Void
    let cancelAction: () -> Void

    init(
        selectionID: String? = nil,
        initialText: String = "",
        isInsertEnabled: Bool,
        positionText: String,
        insertAction: @escaping (String) -> Void,
        insertAndAdvanceAction: @escaping (String) -> Void,
        insertAndGoBackAction: @escaping (String) -> Void,
        removeAction: @escaping (Bool?) -> Void,
        previousAction: @escaping () -> Void,
        nextAction: @escaping () -> Void,
        doneAction: @escaping () -> Void,
        cancelAction: @escaping () -> Void
    ) {
        self.selectionID = selectionID
        self.initialText = initialText
        self.isInsertEnabled = isInsertEnabled
        self.positionText = positionText
        self.insertAction = insertAction
        self.insertAndAdvanceAction = insertAndAdvanceAction
        self.insertAndGoBackAction = insertAndGoBackAction
        self.removeAction = removeAction
        self.previousAction = previousAction
        self.nextAction = nextAction
        self.doneAction = doneAction
        self.cancelAction = cancelAction
        _draft = State(initialValue: ScoreReaderChordBuilderDraft(text: initialText))
        _activeSelectionID = State(initialValue: selectionID)
    }

    private var isCompact: Bool { AriaWindowLayout.shared.usesPhoneLayout }
    private var usesIOSLayout: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }
    private var advanceTitle: String { usesIOSLayout ? "Enter" : "Next" }
    private var hasChanges: Bool { draft.text != initialText && draft.isComplete }
    /// An existing chord erased to nothing is deleted on Done, Previous or Next.
    private var removesChord: Bool { draft.text.isEmpty && !initialText.isEmpty }
    private var hasIncompleteDraft: Bool { draft.text != initialText && !draft.isComplete && !draft.text.isEmpty }
    private var spacing: CGFloat { isCompact ? 4 : 8 }

    var body: some View {
        VStack(spacing: spacing) {
            header
            keys
        }
        .foregroundStyle(Color.black.opacity(0.86))
        .onChangeCompatible(of: selectionID) { newID in
            guard activeSelectionID != newID else { return }
            activeSelectionID = newID
            draft = ScoreReaderChordBuilderDraft(text: initialText)
        }
        .onChangeCompatible(of: initialText) { newText in
            draft = ScoreReaderChordBuilderDraft(text: newText)
        }
    }

    private var keys: some View {
        VStack(spacing: spacing) {
            keyRow {
                ForEach(ScoreReaderChordDraft.naturalNotes, id: \.self) { root in
                    key(root, selected: draft.selectedRoot == root) { draft.chooseRoot(root) }
                }
                if usesIOSLayout {
                    Rectangle()
                        .fill(Color.black.opacity(0.10))
                        .frame(width: 1, height: 22)
                        .accessibilityHidden(true)
                    modifierKey("♭")
                    modifierKey("#")
                }
                if !isCompact && !usesIOSLayout { eraseKey }
            }
            keyRow {
                ForEach(["maj", "min", "dim", "ø", "aug", "sus", "°"], id: \.self) { quality in
                    key(quality, selected: draft.hasChord && draft.selectedQuality == quality, enabled: draft.hasChord) {
                        draft.chooseQuality(quality)
                    }
                }
            }
            if isCompact {
                extensionRow(Array(ScoreReaderChordDraft.extensions.prefix(5)))
                extensionRow(Array(ScoreReaderChordDraft.extensions.dropFirst(5)))
            } else {
                extensionRow(ScoreReaderChordDraft.extensions)
            }
            keyRow {
                ForEach(usesIOSLayout ? ["add", "no", "♭5", "#5", "/"] : ["♭", "#", "add", "no", "♭5", "#5", "/"], id: \.self) { modifier in
                    modifierKey(modifier)
                }
                if usesIOSLayout { eraseKey }
            }
            navigation
                .padding(.top, 4)
        }
        .disabled(!isInsertEnabled)
        .opacity(isInsertEnabled ? 1 : 0.45)
    }

    private var header: some View {
        HStack(spacing: isCompact ? 6 : 12) {
            Button(action: cancelAction) {
                if usesIOSLayout {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.80))
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Label("Text", systemImage: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.blue)
                        .frame(minWidth: isCompact ? 64 : 80, minHeight: 44)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(usesIOSLayout ? "Back to Text" : "Text")
            Spacer(minLength: 4)
            chordPreview
            Spacer(minLength: 4)
            if isCompact && !usesIOSLayout { headerEraseKey }
            Button {
                if hasChanges { insertAction(draft.text) } else if removesChord { removeAction(nil) }
                doneAction()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(minWidth: isCompact ? 64 : 76, minHeight: 44)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            // Without a selection Done just returns, unless it would have to save something.
            .disabled(hasIncompleteDraft || (!isInsertEnabled && (hasChanges || removesChord)))
        }
    }

    private var chordPreview: some View {
        Text(draft.text.isEmpty ? "Chord Entry" : draft.text)
            .font(.system(size: isCompact ? 22 : 26, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel("Chord preview")
            .accessibilityValue(draft.text)
    }

    private var headerEraseKey: some View {
        eraseKey
            .frame(width: isCompact ? 44 : 48)
            .disabled(!isInsertEnabled)
            .opacity(isInsertEnabled ? 1 : 0.45)
    }

    @ViewBuilder private func keyRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: spacing, content: content)
            .padding(.vertical, 2)
    }

    private func extensionRow(_ degrees: [String]) -> some View {
        keyRow {
            ForEach(degrees, id: \.self) { degree in
                key(degree, selected: draft.selectedExtension == degree, enabled: draft.hasChord) {
                    draft.chooseExtension(degree)
                }
            }
        }
    }

    private func modifierKey(_ title: String) -> some View {
        let token = title.replacingOccurrences(of: "♭", with: "b")
        return key(title, selected: modifierIsSelected(token), enabled: draft.hasChord) {
            if usesIOSLayout && token == "/" && draft.editsBass {
                draft.clearSlashBass()
            } else {
                draft.pressModifier(token)
            }
        }
    }

    private var eraseKey: some View {
        Button { draft.backspace() } label: {
            Image(systemName: "delete.left")
                .font(.system(size: isCompact ? 21 : 25, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Erase chord character")
        .onLongPressGesture { draft = ScoreReaderChordBuilderDraft() }
    }

    private func key(_ title: String, selected: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        let fontSize: CGFloat = usesIOSLayout && title == "♭" ? (isCompact ? 24 : 28) : (isCompact ? 17 : 20)
        return Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? Color.white : Color.black.opacity(0.86))
                .background(selected ? Color.blue : Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black.opacity(0.035), lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(title == "♭" ? "Chord flat" : title == "#" ? "Chord sharp" : title)
        .accessibilityValue(selected ? "Selected" : "")
    }

    private var navigation: some View {
        HStack {
            Button {
                if hasChanges { insertAndGoBackAction(draft.text) } else if removesChord { removeAction(false) } else { previousAction() }
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .frame(minHeight: 44)
                    .padding(.horizontal, isCompact ? 10 : 20)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Previous chord position")
            .disabled(hasIncompleteDraft)
            Spacer(minLength: 4)
            Text(positionText)
                .font(.system(size: isCompact ? 11 : 13, weight: .medium))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                if hasChanges { insertAndAdvanceAction(draft.text) } else if removesChord { removeAction(true) } else { nextAction() }
            } label: {
                HStack {
                    Text(advanceTitle)
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(Color.white)
                .frame(minHeight: 44)
                .padding(.horizontal, isCompact ? 16 : 32)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel(advanceTitle == "Enter" ? "Enter chord and advance" : "Next chord position")
            .disabled(hasIncompleteDraft)
        }
        .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
        .buttonStyle(.plain)
    }

    private func modifierIsSelected(_ token: String) -> Bool {
        if token == "/" { return draft.editsBass }
        if token == "b" || token == "#" { return draft.hasAccidental(token) }
        return draft.hasModifier(token)
    }
}

struct ScoreReaderLyricsEntryPanel: View {
    @Environment(\.scoreReaderCompactPanelEmbedded) var embedsInCompactPanel

    @State var lyricsText: String
    @State var activeSelectionID: String?
    /// Space, "-" or "_" sent and not yet answered. Text typed meanwhile belongs to the next
    /// note, so the selection moving there must not clear it.
    @State var pendingAdvances = 0

    let selectionID: String?
    let initialText: String
    let isInsertEnabled: Bool
    let insertAction: (String, Bool) -> Void
    let hyphenAction: (String) -> Void
    let melismaAction: (String) -> Void
    let cancelAction: () -> Void

    init(
        selectionID: String?,
        initialText: String,
        isInsertEnabled: Bool,
        insertAction: @escaping (String, Bool) -> Void,
        hyphenAction: @escaping (String) -> Void,
        melismaAction: @escaping (String) -> Void,
        cancelAction: @escaping () -> Void
    ) {
        self.selectionID = selectionID
        self.initialText = initialText
        self.isInsertEnabled = isInsertEnabled
        self.insertAction = insertAction
        self.hyphenAction = hyphenAction
        self.melismaAction = melismaAction
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
        .onChangeCompatible(of: selectionID) { newSelectionID in
            guard activeSelectionID != newSelectionID else {
                return
            }

            activeSelectionID = newSelectionID
            if pendingAdvances > 0 {
                pendingAdvances -= 1
                if lyricsText.isEmpty {
                    lyricsText = initialText
                }
                return
            }
            lyricsText = initialText
        }
        .onChangeCompatible(of: initialText) { newText in
            guard lyricsText.isEmpty || activeSelectionID != selectionID else {
                return
            }

            lyricsText = newText
        }
    }

    private var standardBody: some View {
        HStack(spacing: isPhoneInterface ? 8 : 12) {
            textField
            extensionButton
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
            HStack(spacing: 8) {
                textField
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                extensionButton
            }

            Text("Space: next note • - joins syllables • _ extends")
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
            hyphenAction: commitHyphen,
            melismaAction: commitMelisma,
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

    private var extensionButton: some View {
        Button(action: commitMelisma) {
            VStack(spacing: 1) {
                Text("_")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Extend")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Color.black.opacity(isInsertEnabled ? 0.72 : 0.30))
            .frame(width: isPhoneInterface ? 52 : 58, height: isPhoneInterface ? 44 : 48)
            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isInsertEnabled)
        .accessibilityLabel("Extend lyric syllable")
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
        AriaWindowLayout.shared.usesPhoneLayout
    }

    private func commit() {
        guard isInsertEnabled, let trimmedLyricsText = lyricsText.trimmedToNil else {
            return
        }

        insertAction(trimmedLyricsText, false)
        lyricsText = ""
    }

    private func commitAndAdvance() {
        guard isInsertEnabled else {
            return
        }

        pendingAdvances += 1
        insertAction(lyricsText.trimmedToNil ?? "", true)
        lyricsText = ""
    }

    private func commitHyphen() {
        guard isInsertEnabled else {
            return
        }

        pendingAdvances += 1
        hyphenAction(lyricsText.trimmedToNil ?? "")
        lyricsText = ""
    }

    private func commitMelisma() {
        guard isInsertEnabled else {
            return
        }

        pendingAdvances += 1
        melismaAction(lyricsText.trimmedToNil ?? "")
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
