import UIKit
import UniformTypeIdentifiers

/// Receives scores shared from other apps and stages them in the shared App
/// Group container. The extension deliberately does no rendering: share
/// extensions run under a tight memory limit that MuseScoreRenderCore and its
/// Qt dependencies cannot fit inside, so the containing app does the import.
final class ShareViewController: UIViewController {
    private var started = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        view.backgroundColor = .systemBackground
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        spinner.startAnimating()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        Task {
            let saved = await SharedScoreStaging.stage(providers)
            spinner.stopAnimating()
            let failed = providers.count - saved
            let message = saved == 0
                ? "No scores were saved. Share a .musicxml, .xml, .mxl, .mscz, or .mscx file and try again."
                : "Saved \(saved) score(s). Open Aria to import them." +
                    (failed > 0 ? " \(failed) attachment(s) could not be saved." : "")
            let alert = UIAlertController(title: saved > 0 ? "Saved to Aria" : "Unable to Save",
                                          message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            })
            present(alert, animated: true)
        }
    }

}

/// File handling for shared scores. Kept off the view controller so none of it
/// inherits `UIViewController`'s main-actor isolation.
enum SharedScoreStaging {
    private static let appGroupIdentifier = "group.com.hdi200.ariascore"
    private static let inboxDirectoryName = "ShareInbox"

    /// Type identifiers declared in the containing app's Info.plist.
    private static let supportedTypeIdentifiers = [
        "org.musescore.mscz",
        "org.musescore.mscx",
        "com.recordare.musicxml",
        "com.recordare.mxl"
    ]

    /// Fallback used when the system hands us a generic identifier such as
    /// public.zip-archive because another app owns the MuseScore UTIs.
    private static let supportedFileExtensions: Set<String> = [
        "mscz", "mscx", "musicxml", "mxl", "xml"
    ]

    static func stage(_ providers: [NSItemProvider]) async -> Int {
        guard let inbox = inboxDirectoryURL() else {
            return 0
        }

        var saved = 0

        for provider in providers {
            guard let typeIdentifier = matchingTypeIdentifier(for: provider) else {
                continue
            }

            if await copy(provider, typeIdentifier: typeIdentifier, into: inbox) {
                saved += 1
            }
        }

        return saved
    }

    private static func copy(
        _ provider: NSItemProvider,
        typeIdentifier: String,
        into inbox: URL
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            // The URL handed to this block is only valid for its duration, so
            // the copy has to happen before returning.
            if typeIdentifier == UTType.fileURL.identifier {
                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                    let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    continuation.resume(returning: url.map { publish($0, into: inbox) } ?? false)
                }
                return
            }
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                continuation.resume(returning: url.map { publish($0, into: inbox) } ?? false)
            }
        }
    }

    private static func publish(_ source: URL, into inbox: URL) -> Bool {
        guard supportedFileExtensions.contains(source.pathExtension.lowercased()) else { return false }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let temporary = inbox.appendingPathComponent(".staging-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try FileManager.default.copyItem(at: source, to: temporary)
            // Rename publishes the complete file atomically to the app.
            try FileManager.default.moveItem(at: temporary,
                to: uniqueDestination(for: source.lastPathComponent, in: inbox))
            return true
        } catch {
            return false
        }
    }

    private static func matchingTypeIdentifier(for provider: NSItemProvider) -> String? {
        if let declared = supportedTypeIdentifiers.first(where: provider.hasItemConformingToTypeIdentifier) {
            return declared
        }

        // Nothing matched our own UTIs; fall back to a plain file and let the
        // path-extension check filter it instead.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return UTType.fileURL.identifier
        }

        return provider.hasItemConformingToTypeIdentifier(UTType.data.identifier)
            ? UTType.data.identifier
            : nil
    }

    private static func inboxDirectoryURL() -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }

        let inbox = container.appendingPathComponent(inboxDirectoryName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        return inbox
    }

    private static func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let candidate = directory.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        let unique = "\(base)-\(UUID().uuidString.prefix(8))"

        return ext.isEmpty
            ? directory.appendingPathComponent(unique)
            : directory.appendingPathComponent(unique).appendingPathExtension(ext)
    }
}
