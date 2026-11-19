#if os(Android)
import Foundation
import SkipFuse

/// Play services supplies capture/review and one multi-page PDF. ScoreScanService handles
/// that PDF exactly like a picked document, using the same on-device music recognition.
enum AndroidDocumentCamera {
    private struct Reply: Decodable {
        let status: String
        let path: String?
        let message: String?
    }

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func capture() async throws -> URL? {
        let camera = try AnyDynamicObject(className: "aria.skip.AriaDocumentCamera")
        let started: Bool? = try camera.start()
        guard started == true else {
            throw Failure(message: "A camera scan is already open. Finish it, or choose a photo or PDF.")
        }
        do {
            while true {
                try await Task.sleep(for: .milliseconds(150))
                guard let result: String = try camera.takeResult() else { continue }
                let reply = try JSONDecoder().decode(Reply.self, from: Data(result.utf8))
                switch reply.status {
                case "completed":
                    guard let path = reply.path else { throw ScoreScanError.unsupportedFile }
                    return URL(fileURLWithPath: path)
                case "cancelled":
                    return nil
                default:
                    throw Failure(message: reply.message ?? "Camera scanning couldn’t start. Choose a photo or PDF instead.")
                }
            }
        } catch {
            let _: Bool? = try? camera.cancel()
            throw error
        }
    }
}
#endif
