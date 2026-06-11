//
//  ScoreReaderTextEditing.swift
//  MuseReaderiOS
//

import SwiftUI
import UIKit

enum ScoreReaderToolCategory: String, CaseIterable {
    case select
    case notes
    case chord
    case lyrics
    case repeats
    case text
    case expression
    case layout
    case more
}

struct ScoreReaderTextEditorDraft: Identifiable {
    let selectionID: String
    let title: String
    var text: String
    let isChordText: Bool
    let isLyrics: Bool

    var id: String {
        selectionID
    }

    init(selection: ScoreSelectedElement) {
        selectionID = selection.textEditorID
        title = selection.kind == .chordText ? "Chord Text" : (selection.textKind ?? "Text")
        text = selection.textContent ?? ""
        isChordText = selection.kind == .chordText
        isLyrics = selection.textKind == "Lyrics"
    }

    init(lyricsText: String = "") {
        selectionID = "lyrics-\(UUID().uuidString)"
        title = "Lyrics"
        text = lyricsText
        isChordText = false
        isLyrics = true
    }
}

struct ScoreReaderTextEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    @State private var text: String
    @State private var chordFieldIsFirstResponder = true

    let draft: ScoreReaderTextEditorDraft
    let isBusy: Bool
    let commitAction: (String, Bool) -> Void

    init(draft: ScoreReaderTextEditorDraft, isBusy: Bool, commitAction: @escaping (String, Bool) -> Void) {
        self.draft = draft
        self.isBusy = isBusy
        self.commitAction = commitAction
        _text = State(initialValue: draft.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(draft.title) {
                    if draft.isChordText {
                        ScoreReaderChordTextInputField(
                            text: $text,
                            placeholder: "Am7",
                            isFirstResponder: chordFieldIsFirstResponder,
                            commitAction: commit,
                            dismissAction: {
                                chordFieldIsFirstResponder = false
                            }
                        )
                        .frame(height: 44)
                    } else if draft.isLyrics {
                        ScoreReaderLyricsTextInputField(
                            text: $text,
                            placeholder: "Lyrics",
                            isFirstResponder: true,
                            commitAction: commit,
                            spaceAction: commitAndAdvance
                        )
                        .frame(height: 44)
                    } else {
                        TextField("Text", text: $text, axis: .vertical)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)
                            .focused($isTextFieldFocused)
                            .submitLabel(.done)
                            .onSubmit(commit)
                    }
                }
            }
            .navigationTitle(draft.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: commit)
                        .disabled(isBusy || text.trimmedToNil == nil)
                }
            }
        }
        .presentationDetents([.height(210)])
        .onAppear {
            if !draft.isChordText && !draft.isLyrics {
                isTextFieldFocused = true
            }
        }
    }

    private func commit() {
        guard let trimmed = text.trimmedToNil else {
            return
        }

        commitAction(trimmed, false)
    }

    private func commitAndAdvance() {
        guard let trimmed = text.trimmedToNil else {
            return
        }

        commitAction(trimmed, true)
        text = ""
    }
}

struct ScoreReaderLyricsTextInputField: UIViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let isFirstResponder: Bool
    let commitAction: () -> Void
    let spaceAction: () -> Void
    let dismissAction: (() -> Void)?

    init(
        text: Binding<String>,
        placeholder: String,
        isFirstResponder: Bool,
        commitAction: @escaping () -> Void,
        spaceAction: @escaping () -> Void,
        dismissAction: (() -> Void)? = nil
    ) {
        _text = text
        self.placeholder = placeholder
        self.isFirstResponder = isFirstResponder
        self.commitAction = commitAction
        self.spaceAction = spaceAction
        self.dismissAction = dismissAction
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.borderStyle = .roundedRect
        textField.font = .preferredFont(forTextStyle: .title3)
        textField.placeholder = placeholder
        textField.clearButtonMode = .never
        textField.autocorrectionType = .yes
        textField.autocapitalizationType = .sentences
        textField.returnKeyType = .done
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        context.coordinator.text = $text
        context.coordinator.commitAction = commitAction
        context.coordinator.spaceAction = spaceAction
        context.coordinator.dismissAction = dismissAction

        if isFirstResponder && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, commitAction: commitAction, spaceAction: spaceAction, dismissAction: dismissAction)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var commitAction: () -> Void
        var spaceAction: () -> Void
        var dismissAction: (() -> Void)?

        init(
            text: Binding<String>,
            commitAction: @escaping () -> Void,
            spaceAction: @escaping () -> Void,
            dismissAction: (() -> Void)? = nil
        ) {
            self.text = text
            self.commitAction = commitAction
            self.spaceAction = spaceAction
            self.dismissAction = dismissAction
        }

        @objc func textDidChange(_ textField: UITextField) {
            text.wrappedValue = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            commitAction()
            dismissAction?()
            return true
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard string == " " else {
                return true
            }

            text.wrappedValue = textField.text ?? ""
            spaceAction()
            return false
        }
    }
}

struct ScoreReaderChordTextInputField: UIViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let isFirstResponder: Bool
    let commitAction: () -> Void
    let spaceAction: (() -> Void)?
    let dismissAction: (() -> Void)?

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

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.borderStyle = .roundedRect
        textField.font = .preferredFont(forTextStyle: .title3)
        textField.placeholder = placeholder
        textField.clearButtonMode = .never
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .allCharacters
        textField.returnKeyType = .done
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        textField.inputView = ScoreReaderChordKeyboardView(
            targetTextField: textField,
            commitAction: commitAction,
            spaceAction: spaceAction,
            dismissAction: dismissAction
        )
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
            (uiView.inputView as? ScoreReaderChordKeyboardView)?.reset(to: text)
        }

        context.coordinator.text = $text
        context.coordinator.commitAction = commitAction

        if isFirstResponder && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, commitAction: commitAction)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var commitAction: () -> Void

        init(text: Binding<String>, commitAction: @escaping () -> Void) {
            self.text = text
            self.commitAction = commitAction
        }

        @objc func textDidChange(_ textField: UITextField) {
            text.wrappedValue = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            commitAction()
            return true
        }
    }
}

final class ScoreReaderChordKeyboardView: UIView {
    private weak var targetTextField: UITextField?
    private let commitAction: () -> Void
    private let spaceAction: (() -> Void)?
    private let dismissAction: (() -> Void)?
    private let isCompactPhoneKeyboard = UIDevice.current.userInterfaceIdiom == .phone
    private let naturalNotes = ["C", "D", "E", "F", "G", "A", "B"]
    private let rootRowKeys = ["C", "D", "E", "F", "G", "A", "B", "♭", "#"]
    private let qualities = ["maj", "min", "°", "ø", "+", "sus"]
    private let extensions = ["4", "5", "6", "7", "8", "9", "11", "13"]
    private let modifiers = ["add", "no", "♭5", "#5", "/"]

    private var draftText = ""
    private var rootButtons: [UIButton] = []
    private weak var insertButton: UIButton?

    init(
        targetTextField: UITextField,
        commitAction: @escaping () -> Void,
        spaceAction: (() -> Void)? = nil,
        dismissAction: (() -> Void)? = nil
    ) {
        self.targetTextField = targetTextField
        self.commitAction = commitAction
        self.spaceAction = spaceAction
        self.dismissAction = dismissAction
        let initialKeyboardHeight: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 226 : 382
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: initialKeyboardHeight))
        backgroundColor = UIColor.systemGray6
        buildKeyboard()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func reset(to text: String) {
        draftText = text
        updateKeyboardState()
    }

    private func buildKeyboard() {
        let stackView = UIStackView(arrangedSubviews: [
            makeRootRow(),
            makeRow(qualities, style: .secondary),
            makeExtensionRow(),
            makeRow(modifiers, height: modifierRowHeight, style: .secondary),
            makeActionRow()
        ])
        stackView.axis = .vertical
        stackView.spacing = rowSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: keyboardHeight),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomInset)
        ])

        draftText = targetTextField?.text ?? ""
        updateKeyboardState()
    }

    private var keyboardHeight: CGFloat {
        isCompactPhoneKeyboard ? 226 : 382
    }

    private var horizontalInset: CGFloat {
        isCompactPhoneKeyboard ? 8 : 14
    }

    private var topInset: CGFloat {
        isCompactPhoneKeyboard ? 6 : 12
    }

    private var bottomInset: CGFloat {
        isCompactPhoneKeyboard ? 8 : 14
    }

    private var rowSpacing: CGFloat {
        isCompactPhoneKeyboard ? 5 : 8
    }

    private var standardRowHeight: CGFloat {
        isCompactPhoneKeyboard ? 38 : 64
    }

    private var rootRowHeight: CGFloat {
        isCompactPhoneKeyboard ? 36 : 54
    }

    private var extensionRowHeight: CGFloat {
        isCompactPhoneKeyboard ? 38 : 78
    }

    private var modifierRowHeight: CGFloat {
        isCompactPhoneKeyboard ? 38 : 64
    }

    private var actionRowHeight: CGFloat {
        isCompactPhoneKeyboard ? 40 : 64
    }

    private var buttonSpacing: CGFloat {
        isCompactPhoneKeyboard ? 5 : 8
    }

    private func makeRow(_ keys: [String], height: CGFloat? = nil, style: ButtonStyle = .plain) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = buttonSpacing
        row.distribution = .fillEqually

        for key in keys {
            row.addArrangedSubview(makeButton(title: key, style: key == "⌫" ? .secondary : style))
        }

        row.heightAnchor.constraint(equalToConstant: height ?? standardRowHeight).isActive = true
        return row
    }

    private func makeShortRow(_ keys: [String], height: CGFloat = 54, style: ButtonStyle = .plain) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = buttonSpacing
        row.distribution = .fill
        row.heightAnchor.constraint(equalToConstant: height).isActive = true

        for key in keys {
            let button = makeButton(title: key, style: style)
            row.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: isCompactPhoneKeyboard ? 72 : 102).isActive = true
        }

        let spacer = UIView()
        row.addArrangedSubview(spacer)
        return row
    }

    private func makeExtensionRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = buttonSpacing
        row.distribution = .fill
        row.heightAnchor.constraint(equalToConstant: extensionRowHeight).isActive = true

        for key in extensions {
            let button = makeButton(title: key)
            row.addArrangedSubview(button)
        }

        let backspaceButton = makeButton(title: "⌫", style: .secondary)
        row.addArrangedSubview(backspaceButton)
        return row
    }

    private func makeActionRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = buttonSpacing
        row.distribution = .fill
        row.heightAnchor.constraint(equalToConstant: actionRowHeight).isActive = true

        let insertButton = makeButton(title: "insert/next", style: .plain)
        let doneButton = makeButton(title: "done", style: .primary)
        self.insertButton = insertButton

        row.addArrangedSubview(insertButton)
        row.addArrangedSubview(doneButton)

        doneButton.widthAnchor.constraint(equalToConstant: isCompactPhoneKeyboard ? 88 : 112).isActive = true
        return row
    }

    private func makeRootRow() -> UIStackView {
        let row = makeRow(rootRowKeys, height: rootRowHeight, style: .root)
        rootButtons = row.arrangedSubviews.compactMap { $0 as? UIButton }.filter { button in
            guard let title = button.accessibilityIdentifier else {
                return false
            }
            return naturalNotes.contains(title)
        }

        for button in rootButtons {
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleRootLongPress(_:)))
            button.addGestureRecognizer(longPress)
        }

        return row
    }

    private enum ButtonStyle {
        case plain
        case secondary
        case root
        case primary
    }

    private func makeButton(title: String, style: ButtonStyle = .plain) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.attributedTitle = attributedTitle(for: title, style: style)
        configuration.baseBackgroundColor = backgroundColor(for: title, style: style)
        configuration.baseForegroundColor = foregroundColor(for: title, style: style)
        configuration.cornerStyle = isCompactPhoneKeyboard ? .medium : .large
        configuration.contentInsets = isCompactPhoneKeyboard
            ? NSDirectionalEdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3)
            : NSDirectionalEdgeInsets(top: 10, leading: 6, bottom: 10, trailing: 6)
        configuration.titleAlignment = .center
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .preferredFont(forTextStyle: .caption1)
            outgoing.foregroundColor = .secondaryLabel
            return outgoing
        }

        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = title
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = isCompactPhoneKeyboard ? 0.06 : (style == .root ? 0.16 : 0.10)
        button.layer.shadowRadius = isCompactPhoneKeyboard ? 2 : (style == .root ? 5 : 3)
        button.layer.shadowOffset = CGSize(width: 0, height: isCompactPhoneKeyboard ? 1 : (style == .root ? 3 : 2))
        button.addAction(UIAction { [weak self] _ in
            self?.handleKey(title)
        }, for: .touchUpInside)
        return button
    }

    private func attributedTitle(for title: String, style: ButtonStyle) -> AttributedString {
        var attributes = AttributeContainer()
        attributes.font = font(for: title, style: style)
        return AttributedString(title, attributes: attributes)
    }

    private func font(for title: String, style: ButtonStyle) -> UIFont {
        if style == .root {
            if isCompactPhoneKeyboard {
                return naturalNotes.contains(title) ? .systemFont(ofSize: 20, weight: .semibold) : .systemFont(ofSize: 22, weight: .medium)
            }
            return naturalNotes.contains(title) ? .systemFont(ofSize: 26, weight: .semibold) : .systemFont(ofSize: 28, weight: .medium)
        }

        if title == "♭" || title == "#" {
            return .systemFont(ofSize: isCompactPhoneKeyboard ? 22 : 30, weight: .medium)
        }

        if title == "°" || title == "ø" || title == "+" || title == "/" {
            return .systemFont(ofSize: isCompactPhoneKeyboard ? 21 : 28, weight: .medium)
        }

        if title == "⌫" {
            return .systemFont(ofSize: isCompactPhoneKeyboard ? 18 : 22, weight: .medium)
        }

        return .systemFont(ofSize: isCompactPhoneKeyboard ? 15 : 19, weight: .medium)
    }

    private func backgroundColor(for title: String, style: ButtonStyle) -> UIColor {
        switch style {
        case .primary:
            return .systemBlue
        case .root:
            return .systemBackground
        case .secondary:
            return .secondarySystemBackground
        case .plain:
            return .systemBackground
        }
    }

    private func foregroundColor(for title: String, style: ButtonStyle) -> UIColor {
        if style == .primary {
            return .white
        }

        if style == .root {
            return .label
        }

        return .label
    }

    private func handleKey(_ key: String) {
        switch key {
        case "insert/next":
            handleSpace()
        case "done":
            commitPendingChord()
            targetTextField?.resignFirstResponder()
            dismissAction?()
        case "⌫":
            backspace()
        case "♭", "#":
            appendKey(key == "♭" ? "b" : key)
        case "♭5":
            appendKey("b5")
        default:
            appendKey(key)
        }

        updateKeyboardState()
    }

    private func syncText() {
        targetTextField?.sendActions(for: .editingChanged)
    }

    @objc private func handleRootLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let button = recognizer.view as? UIButton else {
            return
        }

        let natural = button.accessibilityIdentifier ?? ""
        guard naturalNotes.contains(natural) else {
            return
        }

        appendKey("\(natural)#")
        updateKeyboardState()
    }

    private func appendKey(_ key: String) {
        draftText += key
    }

    private func commitCurrentChord() {
        let chord = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chord.isEmpty else {
            return
        }

        draftText = chord + " "
    }

    private func commitPendingChord() {
        guard draftText.trimmedToNil != nil else {
            return
        }

        commitAction()
        clearDraft()
    }

    private func handleSpace() {
        guard spaceAction == nil else {
            spaceAction?()
            clearDraft()
            return
        }

        commitCurrentChord()
    }

    private func backspace() {
        guard !draftText.isEmpty else {
            return
        }

        draftText.removeLast()
    }

    private func clearDraft() {
        draftText = ""
    }

    private func updateKeyboardState() {
        targetTextField?.text = draftText
        syncText()

        var insertConfiguration = insertButton?.configuration
        insertConfiguration?.attributedTitle = attributedTitle(for: draftText.trimmedToNil == nil ? "next" : "insert/next", style: .plain)
        insertButton?.configuration = insertConfiguration

        updateRootButtons()
    }

    private func updateRootButtons() {
        for button in rootButtons {
            let note = button.accessibilityIdentifier ?? ""
            var configuration = button.configuration
            configuration?.subtitle = nil
            configuration?.baseBackgroundColor = draftText.hasSuffix(note) ? .systemBlue.withAlphaComponent(0.15) : .systemBackground
            button.configuration = configuration
        }
    }
}
