import SwiftUI
import UIKit
#if os(Android)
import SkipFuse
#endif

struct ScoreReaderChordEntryPanel: View {
    @State var draft: ScoreReaderChordBuilderDraft
    @State var activeSelectionID: String?
    #if os(Android)
    @State var nativePreview: AnyDynamicObject?
    #endif

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
        #if os(Android)
        let fontSize: Double = AriaWindowLayout.shared.usesPhoneLayout ? 22 : 26
        _nativePreview = State(initialValue: try? AnyDynamicObject(
            className: "aria.skip.AriaChordPreviewText", initialText, fontSize
        ))
        #endif
    }

    private var isCompact: Bool { AriaWindowLayout.shared.usesPhoneLayout }
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
            updateDraft { $0 = ScoreReaderChordBuilderDraft(text: initialText) }
        }
        .onChangeCompatible(of: initialText) { newText in
            updateDraft { $0 = ScoreReaderChordBuilderDraft(text: newText) }
        }
    }

    private func updateDraft(_ edit: (inout ScoreReaderChordBuilderDraft) -> Void) {
        edit(&draft)
        #if os(Android)
        if let nativePreview {
            try? nativePreview.updateText(draft.text) as Void
        }
        #endif
    }

    private var keys: some View {
        VStack(spacing: spacing) {
            keyRow(keyCount: 9, hasDivider: true, verticalPadding: isCompact ? 4 : 2) { width in
                ForEach(ScoreReaderChordDraft.naturalNotes, id: \.self) { root in
                    key(root, selected: draft.selectedRoot == root,
                        weight: isCompact ? .bold : .semibold) {
                        updateDraft { $0.chooseRoot(root) }
                    }
                    .frame(width: width)
                }
                Rectangle()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: 1, height: 22)
                    .accessibilityHidden(true)
                modifierKey("♭")
                    .frame(width: width)
                modifierKey("#")
                    .frame(width: width)
            }
            keyRow(keyCount: 6, verticalPadding: isCompact ? 4 : 2) { width in
                ForEach(["maj", "min", "°", "ø", "aug", "sus"], id: \.self) { quality in
                    qualityKey(quality)
                        .frame(width: width)
                }
            }
            extensionRow
            keyRow(keyCount: 6) { width in
                ForEach(["add", "no", "♭5", "#5", "/"], id: \.self) { modifier in
                    modifierKey(modifier)
                        .frame(width: width)
                }
                eraseKey
                    .frame(width: width)
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
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.80))
                    .frame(width: 44, height: 44)
                    .background(keyFill, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Text")
            .frame(minWidth: doneButtonWidth, alignment: .leading)
            Spacer(minLength: 4)
            #if os(Android)
            ScoreReaderChordPreview(draft: $draft, isCompact: isCompact, nativeText: nativePreview)
            #else
            ScoreReaderChordPreview(draft: $draft, isCompact: isCompact)
            #endif
            Spacer(minLength: 4)
            Button {
                if hasChanges { insertAction(draft.text) } else if removesChord { removeAction(nil) }
                doneAction()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(minWidth: doneButtonWidth, minHeight: 44)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            // Without a selection Done just returns, unless it would have to save something.
            .disabled(hasIncompleteDraft || (!isInsertEnabled && (hasChanges || removesChord)))
        }
    }

    private var doneButtonWidth: CGFloat { isCompact ? 64 : 76 }

    @ViewBuilder
    private func keyRow<Content: View>(
        keyCount: Int,
        hasDivider: Bool = false,
        gap: CGFloat? = nil,
        verticalPadding: CGFloat = 2,
        @ViewBuilder content: @escaping (CGFloat?) -> Content
    ) -> some View {
        #if os(Android)
        // Give every key its width before drawing. Flexible bridged HStack children
        // otherwise briefly give the first key the full row before redistributing it.
        GeometryReader { proxy in
            let rowGap = gap ?? spacing
            let gapCount = keyCount - 1 + (hasDivider ? 1 : 0)
            let dividerWidth: CGFloat = hasDivider ? 1 : 0
            let keyWidth = max(0, (proxy.size.width - rowGap * CGFloat(gapCount) - dividerWidth) / CGFloat(keyCount))
            HStack(spacing: rowGap) {
                content(keyWidth)
            }
        }
        .frame(height: 44)
        .padding(.vertical, verticalPadding)
        #else
        HStack(spacing: gap ?? spacing) {
            content(nil)
        }
            .padding(.vertical, verticalPadding)
        #endif
    }

    private var extensionRow: some View {
        keyRow(keyCount: ScoreReaderChordDraft.extensions.count,
               gap: isCompact ? 2 : nil, verticalPadding: isCompact ? 0 : 2) { width in
            ForEach(ScoreReaderChordDraft.extensions, id: \.self) { degree in
                key(degree, selected: draft.selectedExtension == degree, enabled: draft.hasChord,
                    fontSize: isCompact ? 16 : nil) {
                    updateDraft { $0.chooseExtension(degree) }
                }
                .frame(width: width)
            }
        }
    }

    private func qualityKey(_ quality: String) -> some View {
        // Imported dim spellings still highlight the single diminished key and can be cleared.
        let token = quality == "°" && draft.selectedQuality == "dim" ? "dim" : quality
        let title = quality == "aug" ? "+" : quality
        let spokenName = title == "+" ? "Augmented" : title == "°" ? "Diminished" : title == "ø" ? "Half-diminished" : nil
        return key(title, selected: draft.hasChord && draft.selectedQuality == token, enabled: draft.hasChord,
                   accessibilityName: spokenName) {
            updateDraft { $0.chooseQuality(token) }
        }
    }

    private func modifierKey(_ title: String) -> some View {
        let token = title.replacingOccurrences(of: "♭", with: "b")
        return key(title, selected: modifierIsSelected(token), enabled: draft.hasChord) {
            updateDraft { draft in
                if token == "/" && draft.editsBass {
                    draft.clearSlashBass()
                } else {
                    draft.pressModifier(token)
                }
            }
        }
    }

    private var eraseKey: some View {
        Button { updateDraft { $0.backspace() } } label: {
            Image(systemName: "delete.left")
                .font(.system(size: isCompact ? 21 : 25, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(keyFill, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Erase chord character")
        .onLongPressGesture { updateDraft { $0 = ScoreReaderChordBuilderDraft() } }
    }

    private var keyFill: Color { Color.black.opacity(0.045) }

    private func key(_ title: String, selected: Bool = false, enabled: Bool = true,
                     fontSize: CGFloat? = nil, weight: Font.Weight? = nil,
                     accessibilityName: String? = nil, action: @escaping () -> Void) -> some View {
        let defaultFontSize: CGFloat = title == "♭" ? (isCompact ? 24 : 28) : (isCompact ? 17 : 20)
        let defaultWeight: Font.Weight = isCompact ? .medium : .semibold
        return Button(action: action) {
            Text(title)
                .font(.system(size: fontSize ?? defaultFontSize, weight: weight ?? defaultWeight))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? Color.white : Color.black.opacity(0.86))
                .background(selected ? Color.blue : keyFill, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black.opacity(0.035), lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(accessibilityName ?? (title == "♭" ? "Chord flat" : title == "#" ? "Chord sharp" : title))
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
                    Text("Enter")
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(Color.white)
                .frame(minHeight: 44)
                .padding(.horizontal, isCompact ? 16 : 32)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Enter chord and advance")
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

struct ScoreReaderChordPreview: View {
    @Binding var draft: ScoreReaderChordBuilderDraft
    let isCompact: Bool
    #if os(Android)
    let nativeText: AnyDynamicObject?
    #endif

    var body: some View {
        let text = draft.text
        return HStack(spacing: 3) {
            #if os(Android)
            // This Compose label observes its own text so Skip cannot retain a stale glyph.
            if let nativeText {
                ComposeView { nativeText }
            }
            #else
            if !text.isEmpty {
                Text(verbatim: text)
                    .font(.system(size: isCompact ? 22 : 26, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            #endif
            ScoreReaderChordCaret(text: text, height: isCompact ? 24 : 28)
        }
        .frame(minWidth: isCompact ? 88 : 104, minHeight: isCompact ? 32 : 36)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.25))
                .frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chord preview")
        .accessibilityValue(text)
        .accessibilityHidden(text.isEmpty)
    }
}

struct ScoreReaderChordCaret: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var isVisible = true

    let text: String
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.blue)
            .frame(width: 2, height: height)
            .opacity(reduceMotion || isVisible ? 1 : 0)
            .accessibilityHidden(true)
            .task(id: reduceMotion ? nil : text) {
                isVisible = true
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .milliseconds(530))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    isVisible.toggle()
                }
            }
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
