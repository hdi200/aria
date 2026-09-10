import Foundation

/// Lists scores staged by the share extension in the shared App Group
/// container. The extension only copies files; every import decision happens
/// here in the containing app.
enum ShareInbox {
    private static let appGroupIdentifier = "group.com.hdi200.ariascore"
    private static let inboxDirectoryName = "ShareInbox"

    static let urlScheme = "aria-share"

    static func handles(_ url: URL) -> Bool {
        url.scheme?.lowercased() == urlScheme
    }

    // Keep the durable copy until the library confirms a successful import.
    static func drain() -> [URL] {
        guard let inbox = inboxDirectoryURL() else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func acknowledgeImport(of url: URL) {
        guard let inbox = inboxDirectoryURL(),
              url.deletingLastPathComponent().standardizedFileURL == inbox.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func inboxDirectoryURL() -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }

        let inbox = container.appendingPathComponent(inboxDirectoryName, isDirectory: true)

        return FileManager.default.fileExists(atPath: inbox.path) ? inbox : nil
    }

}
