// Android stand-in for PhotosUI, used by scanning and video backgrounds.
// Opens Android's document picker for images (AriaDocumentPicker.kt),
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
        // This shim has no skipstone plugin to generate a custom ViewModifier's
        // Java peer. Attach the bridged task directly; modifier(...) would use
        // Skip's default EmptyModifier and never run the picker.
        task(id: isPresented.wrappedValue) { @MainActor in
            guard isPresented.wrappedValue else { return }
            defer { isPresented.wrappedValue = false }
            await AndroidPhotosPicker(selection: selection, mimeType: filter?.mimeType ?? "image/*").pick()
        }
    }

    func photosPicker(isPresented: Binding<Bool>, selection: Binding<PhotosPickerItem?>,
                      matching filter: PHPickerFilter? = nil) -> some View {
        photosPicker(isPresented: isPresented, selection: selection, matching: filter, photoLibrary: .shared())
    }
}

private struct AndroidPhotosPicker {
    @Binding var selection: PhotosPickerItem?
    let mimeType: String

    @MainActor func pick() async {
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
