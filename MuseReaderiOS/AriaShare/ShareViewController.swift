import UIKit
import UniformTypeIdentifiers

/// The share sheet's entry into Aria: takes one PDF or image (from Photos, Files, Safari, Mail...), leaves it in
/// the app group's "Shared Scans" folder under its own name, and opens Aria, which scans it. If iOS does not let
/// the extension open Aria, the file waits in the folder and Aria scans it the next time it comes to the front.
final class ShareViewController: UIViewController {
  static let appGroup = "group.com.hdi200.ariascore"
  static let openURL = URL(string: "ariascore-scan://shared")!
  static let appName = "Aria"

  private let message = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    message.text = "Sending to \(Self.appName)…"
    message.textAlignment = .center
    message.numberOfLines = 0
    message.font = .preferredFont(forTextStyle: .headline)
    message.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(message)
    NSLayoutConstraint.activate([
      message.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      message.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      message.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      message.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
    ])
    Task { await receive() }
  }

  private func receive() async {
    do {
      try await save(try await sharedItem())
      if openApp() {
        finish()
      } else {
        show("Saved. Open \(Self.appName) to scan it.")
      }
    } catch {
      show(error.localizedDescription)
    }
  }

  private struct SharedItem {
    let provider: NSItemProvider
    let type: UTType
  }

  /// The first PDF or image among the shared items.
  private func sharedItem() throws -> SharedItem {
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    for provider in providers {
      let types = provider.registeredTypeIdentifiers.compactMap(UTType.init)
      if let pdf = types.first(where: { $0.conforms(to: .pdf) }) { return SharedItem(provider: provider, type: pdf) }
      if let image = types.first(where: { $0.conforms(to: .image) }) {
        return SharedItem(provider: provider, type: image)
      }
    }
    throw ShareError.nothingToScan
  }

  /// Copies the shared file into a folder of its own in the app group, keeping its name for the score's title.
  private func save(_ item: SharedItem) async throws {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)
    else { throw ShareError.noSharedFolder }
    let folder = container.appendingPathComponent("Shared Scans", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let type = item.type
    let suggested = item.provider.suggestedName ?? (type.conforms(to: .pdf) ? "Shared Score" : "Shared Page")
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
      _ = item.provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
        guard let url else {
          done.resume(throwing: error ?? ShareError.unreadable)
          return
        }
        // the file is only there while this handler runs
        let ext = url.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "dat") : url.pathExtension
        let base = (suggested as NSString).deletingPathExtension
        let target = folder.appendingPathComponent(base.isEmpty ? "Shared Score" : base).appendingPathExtension(ext)
        do {
          try FileManager.default.copyItem(at: url, to: target)
          done.resume()
        } catch {
          done.resume(throwing: error)
        }
      }
    }
  }

  /// Asks the system to open the app. Share extensions have no supported way to do this, so the app found in the
  /// responder chain is asked directly; when that fails the file still waits for the app.
  private func openApp() -> Bool {
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    var responder: UIResponder? = self
    while let current = responder {
      if current.responds(to: selector), String(describing: type(of: current)).contains("Application") {
        typealias Open = @convention(c) (
          AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
        ) -> Void
        let open = unsafeBitCast(current.method(for: selector), to: Open.self)
        open(current, selector, Self.openURL as NSURL, NSDictionary(), nil)
        return true
      }
      responder = current.next
    }
    return false
  }

  private func show(_ text: String) {
    message.text = text
    let done = UIButton(type: .system, primaryAction: UIAction(title: "Done") { [weak self] _ in self?.finish() })
    done.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(done)
    NSLayoutConstraint.activate([
      done.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 16),
      done.centerXAnchor.constraint(equalTo: view.centerXAnchor),
    ])
  }

  private func finish() {
    extensionContext?.completeRequest(returningItems: nil)
  }

  private enum ShareError: LocalizedError {
    case nothingToScan, noSharedFolder, unreadable
    var errorDescription: String? {
      switch self {
      case .nothingToScan: "Share a PDF or an image of printed music."
      case .noSharedFolder: "\(ShareViewController.appName) could not open its shared folder."
      case .unreadable: "The shared file could not be read."
      }
    }
  }
}
