// Android's lyrics and chord text fields (Views/ScoreReaderTextInputFields.swift on iOS,
// UIKit text fields): the same initializers and key handling, in SwiftUI.
// Not yet: the chord keyboard iOS shows in place of the system keyboard.

// Not limited to Android: the Skip project's own iOS build (a build step only; the iOS
// app is MuseReaderiOS/Aria.xcodeproj) compiles it in place of the held-back iOS file.
import SwiftUI

struct ScoreReaderLyricsTextInputField: View {
    @Binding var text: String

    let placeholder: String
    let isFirstResponder: Bool
    let commitAction: () -> Void
    let spaceAction: () -> Void
    let hyphenAction: (() -> Void)?
    let melismaAction: (() -> Void)?
    let dismissAction: (() -> Void)?

    @FocusState var isFocused: Bool

    init(
        text: Binding<String>,
        placeholder: String,
        isFirstResponder: Bool,
        commitAction: @escaping () -> Void,
        spaceAction: @escaping () -> Void,
        hyphenAction: (() -> Void)? = nil,
        melismaAction: (() -> Void)? = nil,
        dismissAction: (() -> Void)? = nil
    ) {
        _text = text
        self.placeholder = placeholder
        self.isFirstResponder = isFirstResponder
        self.commitAction = commitAction
        self.spaceAction = spaceAction
        self.hyphenAction = hyphenAction
        self.melismaAction = melismaAction
        self.dismissAction = dismissAction
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            #if os(Android)
            .textFieldContentPadding(top: 10, leading: 12, bottom: 10, trailing: 12)
            #endif
            .font(.title3)
            .focused($isFocused)
            .submitLabel(.next)
            .onSubmit {
                spaceAction()
                text = ""
                isFocused = true
            }
            .onChange(of: text) { _, newValue in
                handleTyped(newValue)
            }
            .onAppear {
                if isFirstResponder { isFocused = true }
            }
    }

    /// Space, "-" and "_" end the syllable, as on iOS (ScoreReaderLyricsTextInputField.inputCommand).
    private func handleTyped(_ value: String) {
        guard let last = value.last else { return }
        let syllable = String(value.dropLast())
        switch last {
        case " ":
            text = syllable
            spaceAction()
        case "-":
            guard let hyphenAction else { return }
            text = syllable
            hyphenAction()
        case "_":
            guard let melismaAction else { return }
            text = syllable
            melismaAction()
        default:
            return
        }
        text = ""
    }
}

/// The chord field: tapping it opens the chord keyboard (iOS uses it as the field's input
/// view) in a short sheet, which shows the chord being typed above its keys.
struct ScoreReaderChordTextInputField: View {
    @Binding var text: String

    let placeholder: String
    let isFirstResponder: Bool
    let commitAction: () -> Void
    let spaceAction: (() -> Void)?
    let dismissAction: (() -> Void)?

    @State var isKeyboardPresented = false

    init(
        text: Binding<String>,
        placeholder: String,
        isFirstResponder: Bool,
        commitAction: @escaping () -> Void,
        spaceAction: (() -> Void)? = nil,
        dismissAction: (() -> Void)? = nil
    ) {
        _text = text
        self.placeholder = placeholder
        self.isFirstResponder = isFirstResponder
        self.commitAction = commitAction
        self.spaceAction = spaceAction
        self.dismissAction = dismissAction
    }

    var body: some View {
        HStack(spacing: 1) {
            Text(text.isEmpty ? placeholder : text)
                .font(.title3)
                .foregroundStyle(text.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(1)
            if isKeyboardPresented {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 22)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.15), lineWidth: 1)
        }
        .onTapGesture { isKeyboardPresented = true }
        .accessibilityLabel(text.isEmpty ? placeholder : text)
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $isKeyboardPresented) {
            AndroidChordKeyboard(text: $text, placeholder: placeholder, commitAction: commitAction,
                                 spaceAction: spaceAction, dismissAction: dismissAction) {
                isKeyboardPresented = false
            }
            .presentationDetents([.height(AndroidChordKeyboard.isCompact ? 300 : 470)])
        }
        .onAppear {
            if isFirstResponder { isKeyboardPresented = true }
        }
        .onChange(of: isFirstResponder) { _, isFirstResponder in
            if isFirstResponder { isKeyboardPresented = true }
        }
    }
}

/// The chord keyboard (iOS: ScoreReaderChordKeyboardView), with the same keys and rules
/// (ScoreReaderChordDraft) and the iPhone or iPad sizes.
struct AndroidChordKeyboard: View {
    @Binding var text: String
    let placeholder: String
    let commitAction: () -> Void
    let spaceAction: (() -> Void)?
    let dismissAction: (() -> Void)?
    let close: () -> Void

    @State var draft = ScoreReaderChordDraft()

    static var isCompact: Bool { UIDevice.current.userInterfaceIdiom != .pad }

    private var compact: Bool { Self.isCompact }

    var body: some View {
        VStack(spacing: compact ? 5 : 8) {
            Text(draft.text.isEmpty ? placeholder : draft.text)
                .font(.title2.weight(.semibold))
                .foregroundStyle(draft.text.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .frame(height: compact ? 34 : 44)
            row(ScoreReaderChordDraft.rootRowKeys, height: compact ? 36 : 54, style: .root)
            row(ScoreReaderChordDraft.qualities, height: compact ? 38 : 64, style: .secondary)
            row(ScoreReaderChordDraft.extensions, height: compact ? 38 : 78, style: .plain)
            row(ScoreReaderChordDraft.modifiers, height: compact ? 38 : 64, style: .secondary)
            GeometryReader { proxy in
                let spacing: CGFloat = compact ? 5 : 8
                let doneWidth: CGFloat = compact ? 88 : 112
                HStack(spacing: spacing) {
                    key(draft.insertTitle, press: ScoreReaderChordDraft.insertKey, style: .plain)
                        .frame(width: max(0, proxy.size.width - doneWidth - spacing))
                    key(ScoreReaderChordDraft.doneKey, style: .primary)
                        .frame(width: doneWidth)
                }
            }
            .frame(height: compact ? 40 : 64)
        }
        .padding(.horizontal, compact ? 8 : 14)
        .padding(.top, compact ? 6 : 12)
        .padding(.bottom, compact ? 8 : 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemGray6))
        .onAppear { draft = ScoreReaderChordDraft(text: text) }
        .onChange(of: text) { _, newText in
            if newText != draft.text { draft = ScoreReaderChordDraft(text: newText) }
        }
    }

    private enum KeyStyle {
        case plain, secondary, root, primary
    }

    /// Keys of equal width across the row (Skip doesn't share an HStack's width among
    /// several flexible children).
    private func row(_ keys: [String], height: CGFloat, style: KeyStyle) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = compact ? 5 : 8
            let width = max(0, (proxy.size.width - spacing * CGFloat(keys.count - 1)) / CGFloat(keys.count))
            HStack(spacing: spacing) {
                ForEach(keys, id: \.self) { title in
                    key(title, style: title == "⌫" ? .secondary : style)
                        .frame(width: width)
                }
            }
        }
        .frame(height: height)
    }

    private func key(_ title: String, press: String? = nil, style: KeyStyle) -> some View {
        let isRoot = ScoreReaderChordDraft.naturalNotes.contains(title)
        let background: Color = switch style {
        case .primary: Color.blue
        case .secondary: Color(uiColor: .secondarySystemBackground)
        case .root: isRoot && draft.highlights(root: title) ? Color.blue.opacity(0.15) : Color.white
        case .plain: Color.white
        }
        return Text(title)
            .font(font(title, style: style))
            .foregroundStyle(style == .primary ? Color.white : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: compact ? 6 : 10, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
            .onTapGesture { handle(press ?? title) }
            .onLongPressGesture(minimumDuration: 0.4) {
                guard isRoot else { return }
                draft.pressAndHold(root: title)
                text = draft.text
            }
            .accessibilityAddTraits(.isButton)
    }

    private func font(_ title: String, style: KeyStyle) -> Font {
        if style == .root {
            let natural = ScoreReaderChordDraft.naturalNotes.contains(title)
            return .system(size: compact ? (natural ? 20 : 22) : (natural ? 26 : 28),
                           weight: natural ? .semibold : .medium)
        }
        switch title {
        case "♭", "#": return .system(size: compact ? 22 : 30, weight: .medium)
        case "°", "ø", "+", "/": return .system(size: compact ? 21 : 28, weight: .medium)
        case "⌫": return .system(size: compact ? 18 : 22, weight: .medium)
        default: return .system(size: compact ? 15 : 19, weight: .medium)
        }
    }

    private func handle(_ key: String) {
        switch draft.press(key, advancesOnInsert: spaceAction != nil) {
        case .none:
            text = draft.text
        case .advance:
            text = draft.text
            spaceAction?()
            draft.clear()
            text = ""
        case .done:
            text = draft.text
            if draft.hasChord {
                commitAction()
                draft.clear()
            }
            text = draft.text
            close()
            dismissAction?()
        }
    }
}
