import Foundation
#if os(Android)
import AriaEngine
#endif

enum ScoreEngineError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        }
    }
}

/// Demo of the shared bridge API: engine calls go through one serial queue, like iOS's
/// RenderCoreWorkGate, and the bridge is the same MuseScoreRenderCoreBridge iOS uses.
final class ScoreEngine: @unchecked Sendable {
    static let shared = ScoreEngine()

    private let queue = DispatchQueue(label: "com.aria.render-core-work")

    /// One page (0-based) as PDF, or PNG if the core's PDF output failed.
    func renderPage(scorePath: String, pageIndex: Int, dpi: Int = 144) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try Self.render(scorePath: scorePath, pageIndex: pageIndex, dpi: dpi) })
            }
        }
    }

    private static func render(scorePath: String, pageIndex: Int, dpi: Int) throws -> Data {
        #if os(Android)
        MuseScoreRenderCoreBridge.initializeRenderRuntimeIfNeeded()
        let session = try MuseScoreRenderCoreBridge().openSession(at: URL(fileURLWithPath: scorePath))
        let page = try session.renderPage(index: pageIndex, dpi: dpi)
        return page.pdfData.isEmpty ? page.imageData : page.pdfData
        #else
        throw ScoreEngineError.unavailable("The iOS app uses its own MuseScoreRenderCoreBridge.")
        #endif
    }
}
