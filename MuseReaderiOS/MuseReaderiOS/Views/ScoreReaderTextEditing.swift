//
//  ScoreReaderTextEditing.swift
//  MuseReaderiOS
//

import SwiftUI
import UIKit

enum ScoreReaderLyricsInputCommand: Equatable {
    case advance
    case hyphen
    case melisma
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
    @Environment(\.dismiss) var dismiss
    @FocusState var isTextFieldFocused: Bool

    @State var text: String
    @State var chordFieldIsFirstResponder = true

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
        commitAction(text.trimmedToNil ?? "", true)
        text = ""
    }
}
