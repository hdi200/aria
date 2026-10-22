import SwiftUI

struct DemoContentView: View {
    var body: some View {
        TabView {
            ScoreDemoView()
                .tabItem { Label("Score", systemImage: "music.note") }
            KeyboardDemoView()
                .tabItem { Label("Keyboard", systemImage: "pianokeys") }
            PlaybackDemoView()
                .tabItem { Label("Playback", systemImage: "play.fill") }
        }
    }
}

/// Renders the bundled Amazing Grace through the shared engine.
struct ScoreDemoView: View {
    @State var status = "Rendering…"
    @State var pageURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let pageURL {
                        AsyncImage(url: pageURL) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                        .background(Color.white)
                    }
                }
                .padding()
            }
            .navigationTitle("Aria (Skip)")
        }
        .task { await renderFirstPage() }
    }

    private func renderFirstPage() async {
        let started = Date()
        do {
            let score = try copyBundledScore(named: "Amazing_grace", extension: "mscz")
            let page = try await ScoreEngine.shared.renderPage(scorePath: score.path, pageIndex: 0)
            let isPDF = page.prefix(4) == Data("%PDF".utf8)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(isPDF ? "page.pdf" : "page.png")
            try page.write(to: url)
            pageURL = url
            status = String(format: "Amazing Grace page 1 rendered from Swift in %.0f ms", Date().timeIntervalSince(started) * 1000)
        } catch {
            status = "Render failed: \(error.localizedDescription)"
        }
    }

    /// The engine reads real files, and bundle resources on Android live inside the APK.
    private func copyBundledScore(named name: String, extension ext: String) throws -> URL {
        guard let resource = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw ScoreEngineError.unavailable("\(name).\(ext) is missing from the app bundle.")
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).\(ext)")
        try? FileManager.default.removeItem(at: destination)
        try Data(contentsOf: resource).write(to: destination)
        return destination
    }
}
