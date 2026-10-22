// Optional local correctness journal. No score snapshots or probes in normal builds.
#if ARIA_EDIT_AUDIT && os(Android)
import Foundation

@MainActor
enum AndroidEditingAudit {
    private static var sequence = 0
    private static let directory = URL(fileURLWithPath:
        "/sdcard/Android/data/com.hdi200.ariascore/cache/aria-edit-audit", isDirectory: true)

    static func capture(_ session: LiveScoreRenderSession, kind: String, state: ScoreEditingState? = nil) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o777])
            // The shell pre-creates these audit-only destinations with mode 0666.
            // Preserve that owner/mode when reading old app-owned captures; never
            // change permissions on the app or on the user's score storage.
            let readableRequest = directory.appendingPathComponent("make-readable")
            if FileManager.default.fileExists(atPath: readableRequest.path) {
                let source = directory
                try await Task.detached(priority: .utility) {
                    let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
                    for file in files where file.pathExtension == "musicxml" {
                        let target = source.appendingPathComponent("readable", isDirectory: true)
                            .appendingPathComponent(file.lastPathComponent)
                        guard FileManager.default.fileExists(atPath: target.path) else {
                            throw NSError(domain: "AriaEditingAudit", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Pre-create the readable audit destination: \(file.lastPathComponent)"])
                        }
                        let handle = try FileHandle(forWritingTo: target)
                        defer { try? handle.close() }
                        try handle.truncate(atOffset: 0)
                        try handle.write(contentsOf: Data(contentsOf: file))
                    }
                }.value
                try FileManager.default.removeItem(at: readableRequest)
                print("ARIA_EDIT_AUDIT_READABLE_COMPLETE")
                return
            }
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("enabled").path) else { return }
            let xml = try await session.musicXMLData()
            let name = String(format: "%05d-%@.musicxml", sequence, kind)
            sequence += 1
            // Pre-created shell-owned files remain readable by the test driver.
            // Journals are sequential, and readers wait for this completion log.
            let target = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: target.path) else {
                throw NSError(domain: "AriaEditingAudit", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Pre-create the audit snapshot: \(name)"])
            }
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: xml)
            print("ARIA_EDIT_AUDIT snapshot=\(name) pitch=\(state?.selection?.midiPitch ?? -1) voice=\(state?.currentVoice ?? -1) duration=\(state?.duration.rawValue ?? -1) tick=\(state?.selection?.tick ?? -1) undo=\(state?.canUndo ?? false)")
        } catch {
            print("ARIA_EDIT_AUDIT_FAILED \(error)")
        }
    }
}
#endif
