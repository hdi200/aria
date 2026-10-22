// Android stand-in for the PhotosUI the video export sheet uses: picking one image for a
// video background. Opens Android's document picker for images (AriaDocumentPicker.kt),
// which also lists the photo apps, and hands back the copied file.
#if os(Android)
@_exported import Foundation
import SkipFuse
import SwiftUI

public struct PHPickerFilter: Equatable, Sendable {
    let mimeType: String
    public static let images = PHPickerFilter(mimeType: "image/*")
    public static let videos = PHPickerFilter(mimeType: "video/*")
}

public final class PHPhotoLibrary: @unchecked Sendable {
    private static let library = PHPhotoLibrary()
    public static func shared() -> PHPhotoLibrary { library }
}

public struct PhotosPickerItem: Equatable, Hashable, Sendable {
    let url: URL

    /// The picked file's bytes (the shared code only asks for Data).
    public func loadTransferable<T>(type: T.Type) async throws -> T? {
        guard type == Data.self else { return nil }
        let data = try await Task.detached { try Data(contentsOf: url) }.value
        try? FileManager.default.removeItem(at: url)
        return data as? T
    }
}

public extension View {
    func photosPicker(isPresented: Binding<Bool>, selection: Binding<PhotosPickerItem?>,
                      matching filter: PHPickerFilter? = nil, photoLibrary: PHPhotoLibrary) -> some View {
        modifier(AndroidPhotosPicker(isPresented: isPresented, selection: selection, mimeType: filter?.mimeType ?? "image/*"))
    }
}

struct AndroidPhotosPicker: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selection: PhotosPickerItem?
    let mimeType: String

    func body(content: Content) -> some View {
        content.task(id: isPresented) {
            guard isPresented else { return }
            await pick()
            isPresented = false
        }
    }

    private func pick() async {
        guard let picker = try? AnyDynamicObject(className: "aria.skip.AriaDocumentPicker") else { return }
        let started: Bool? = try? picker.pick(mimeType, false)
        guard started == true else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
            guard let result: String = try? picker.takeResult() else { continue }
            if let path = result.split(separator: "\n").first {
                selection = PhotosPickerItem(url: URL(fileURLWithPath: String(path)))
            }
            return
        }
    }
}
#endif
