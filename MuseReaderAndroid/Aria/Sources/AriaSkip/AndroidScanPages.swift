// Scanning on Android: the pages of a PDF or picture, drawn by AriaScanPages.kt one at a time for
// ScannerCore (which has no Core Graphics there), and ScannerCore's models copied out of the app
// into a folder ONNX Runtime can open by path. Used by the shared ScoreScanService.

#if os(Android)
import Foundation
import ScannerCore
import SkipFuse

enum AndroidScanPages {
    enum Failure: LocalizedError {
        case pageUnreadable(Int)
        case modelsMissing

        var errorDescription: String? {
            switch self {
            case .pageUnreadable(let index): return "Aria could not draw page \(index + 1) of this file."
            case .modelsMissing: return "This build of Aria does not include the score reader."
            }
        }
    }

    /// Where picked files wait while they are read. Emptied each time a new file arrives.
    private nonisolated static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AriaScanPages", isDirectory: true)
    }

    /// Moves a picked file into the scan folder, dropping the previous scan's file.
    nonisolated static func keep(_ url: URL) throws -> URL {
        let manager = FileManager.default
        try? manager.removeItem(at: folder)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("page-source-\(UUID().uuidString)")
        do {
            try manager.moveItem(at: url, to: destination)
        } catch {
            try manager.copyItem(at: url, to: destination)
        }
        return destination
    }

    /// A PDF's page count, 1 for a picture Android can decode, 0 for anything else.
    nonisolated static func pageCount(of file: URL) -> Int {
        guard let pages = try? AnyDynamicObject(className: "aria.skip.AriaScanPages") else { return 0 }
        let count: Int? = try? pages.pageCount(file.path)
        return count ?? 0
    }

    /// The zero-based page as a binary PPM image.
    nonisolated static func page(_ index: Int, of file: URL) throws -> Data {
        let pages = try AnyDynamicObject(className: "aria.skip.AriaScanPages")
        guard let data: Data = try pages.page(file.path, index) else {
            throw Failure.pageUnreadable(index)
        }
        return data
    }

    /// The models in a real folder: Gradle puts them in the APK's assets, which ONNX Runtime can't
    /// open by path, so AriaScanPages.kt unpacks them once per install of the app.
    nonisolated static func modelsDirectory() throws -> URL {
        let pages = try AnyDynamicObject(className: "aria.skip.AriaScanPages")
        guard let path: String = try pages.unpackModels() else {
            throw Failure.modelsMissing
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        guard Scanner.available(models: folder) else {
            throw Failure.modelsMissing
        }
        return folder
    }
}

#endif
