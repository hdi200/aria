// Android's share sheets (Views/ShareSheetView.swift on iOS, UIActivityViewController):
// hands the files to Android's share chooser (AriaShare.kt) and closes the sheet they
// were shown in.

// Not limited to Android: the Skip project's own iOS build (a build step only; the iOS
// app is MuseReaderiOS/Aria.xcodeproj) compiles it in place of the held-back iOS file.
import Foundation
import SkipFuse
import SwiftUI

struct ShareSheetView: View {
    let activityItems: [Any]

    var body: some View {
        AndroidShareChooser(activityItems: activityItems)
    }
}

struct ScoreReaderShareSheetView: View {
    let activityItems: [Any]

    var body: some View {
        AndroidShareChooser(activityItems: activityItems)
    }
}

struct AndroidShareChooser: View {
    let activityItems: [Any]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ProgressView()
            .task {
                Self.share(activityItems)
                dismiss()
            }
    }

    static func share(_ items: [Any]) {
        let paths = items.compactMap { ($0 as? URL)?.path }
        let texts = items.compactMap { $0 as? String }
        do {
            let share = try AnyDynamicObject(className: "aria.skip.AriaShare")
            try share.share(paths.joined(separator: "\n"), texts.joined(separator: "\n")) as Void
        } catch {
            print("Aria share failed: \(error)")
        }
    }
}
