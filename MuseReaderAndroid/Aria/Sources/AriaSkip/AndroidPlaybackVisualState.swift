// Android keeps the audio clock out of the page/reader's observation dependencies.
// Only these small children observe the values they display. A static measure
// rectangle does not need the unused fractional progress, or a clock sub-seconds.
import Foundation
import Observation
#if os(Android)
import SkipFuse
#endif
import SwiftUI
#if ARIA_PERF_DIAGNOSTICS && os(Android)
import SwiftJNI
#endif

@MainActor
@Observable
final class AndroidPlaybackVisualState {
    struct Highlight: Equatable {
        let pageIndex: Int
        let rect: ScoreNormalizedRect

        init(_ value: ScorePlaybackMeasureHighlight) {
            pageIndex = value.pageIndex
            rect = value.normalizedRect
        }
    }

    var clockText = "\(ScorePlaybackState.unavailable.currentTimeLabel) / \(ScorePlaybackState.unavailable.durationLabel)"
    var highlight: Highlight?

    func publishClock(_ state: ScorePlaybackState) {
        let text = "\(state.currentTimeLabel) / \(state.durationLabel)"
        if clockText != text { clockText = text }
    }

    func publishHighlight(_ value: ScorePlaybackMeasureHighlight?) {
        let next = value.map(Highlight.init)
        if highlight != next { highlight = next }
    }
}

private struct AriaPlaybackPageIndexKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var ariaPlaybackPageIndex: Int {
        get { self[AriaPlaybackPageIndexKey.self] }
        set { self[AriaPlaybackPageIndexKey.self] = newValue }
    }
}

struct AndroidPlaybackHighlightOverlay: View {
    @Environment(AndroidPlaybackVisualState.self) var playback: AndroidPlaybackVisualState?
    @Environment(\.ariaPlaybackPageIndex) var pageIndex
    let fallback: ScorePlaybackMeasureHighlight?
    let pageSize: CGSize

    var body: some View {
        #if ARIA_PERF_DIAGNOSTICS && os(Android)
        let _ = AriaJNILifecycle.record("HighlightEvaluate", created: true)
        #endif
        let highlight = playback == nil ? fallback.map(AndroidPlaybackVisualState.Highlight.init) : playback?.highlight
        if let highlight, highlight.pageIndex == pageIndex || playback == nil {
            AndroidPageRect(rect: highlight.rect, pageSize: pageSize) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.98, green: 0.82, blue: 0.19).opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.94, green: 0.69, blue: 0.21).opacity(0.95), lineWidth: 2))
            }
        }
    }
}

struct AndroidPlaybackTimeLabel: View {
    @Environment(AndroidPlaybackVisualState.self) var playback: AndroidPlaybackVisualState?
    let fallback: ScorePlaybackState
    let isCountingIn: Bool
    let preparationMessage: String?

    var body: some View {
        let clock = playback?.clockText ?? "\(fallback.currentTimeLabel) / \(fallback.durationLabel)"
        Text(isCountingIn ? "Count-in" : preparationMessage ?? clock)
    }
}

#if ARIA_PERF_DIAGNOSTICS && os(Android)
@MainActor
enum AndroidPerformanceDiagnostics {
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        Task.detached(priority: .utility) {
            BridgedStateBox<Int>.ariaRunLifecycleProbe()
            let directory = "/sdcard/Android/data/com.hdi200.ariascore/cache"
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await MainActor.run { AriaJNILifecycle.dumpReferenceTables("soak_ui_thread") }
                // Opt-in local ownership capture. A dump can force GC and pause
                // the process, so never request one inside a measurement gate.
                let request = directory + "/aria-heap.request"
                if FileManager.default.fileExists(atPath: request) {
                    try? FileManager.default.removeItem(atPath: request)
                    jniContext {
                        JNI.jni.withEnv { _ = $0.PushLocalFrame($1, 16) }
                        defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
                        let debug = try! JClass(name: "android/os/Debug", systemClass: true)
                        let method = debug.getStaticMethodID(name: "dumpHprofData", sig: "(Ljava/lang/String;)V")!
                        let path = directory + "/aria-heap.hprof"
                        do {
                            try debug.callStatic(method: method, options: [], args: [path.toJavaParameter(options: [])]) as Void
                            print("ARIA_HEAP_DUMP_COMPLETE")
                        } catch { print("ARIA_HEAP_DUMP_FAILED \(error)") }
                    }
                }
            }
        }
    }
}
#endif
