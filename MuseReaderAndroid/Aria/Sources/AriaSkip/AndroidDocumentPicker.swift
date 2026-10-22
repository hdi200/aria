// Android's fileImporter (Skip doesn't have one): opens Android's document picker
// (AriaDocumentPicker.kt) and hands the copied files to the same completion handler iOS uses.

#if os(Android)
import Foundation
import SkipFuse
import SwiftUI
import UniformTypeIdentifiers

extension View {
    func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
                      onCompletion: @escaping (Result<[URL], Error>) -> Void) -> some View {
        modifier(AndroidFileImporter(isPresented: isPresented, allowedContentTypes: allowedContentTypes,
                                     allowsMultipleSelection: allowsMultipleSelection, onCompletion: onCompletion))
    }

    func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType],
                      onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View {
        fileImporter(isPresented: isPresented, allowedContentTypes: allowedContentTypes, allowsMultipleSelection: false) { result in
            onCompletion(result.flatMap { urls in
                urls.first.map { .success($0) } ?? .failure(CocoaError(.userCancelled))
            })
        }
    }
}

struct AndroidFileImporter: ViewModifier {
    @Binding var isPresented: Bool
    let allowedContentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onCompletion: (Result<[URL], Error>) -> Void

    func body(content: Content) -> some View {
        content.task(id: isPresented) {
            guard isPresented else { return }
            await pick()
            isPresented = false
        }
    }

    private func pick() async {
        guard let picker = try? AnyDynamicObject(className: "aria.skip.AriaDocumentPicker") else { return }
        // Scores have no registered MIME types, so the picker shows all documents and the
        // import checks the file extensions, as on iOS.
        let started: Bool? = try? picker.pick("*/*", allowsMultipleSelection)
        guard started == true else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
            guard let result: String = try? picker.takeResult() else { continue }
            let urls = result.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            if !urls.isEmpty {
                onCompletion(.success(urls))
            }
            return
        }
    }
}
#endif
