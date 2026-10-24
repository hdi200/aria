import Foundation
import SwiftUI
#if os(Android)
import SkipBridge
import SwiftJNI
#endif

/// Retain only the latest viewport/binding until the next display frame.
@MainActor
final class AndroidViewportPublisher {
    private var latest: ScoreReaderZoomViewport?
    private var binding: Binding<ScoreReaderZoomViewport>?
    private var scheduled = false
    private var generation = 0

    func request(_ viewport: ScoreReaderZoomViewport, binding: Binding<ScoreReaderZoomViewport>) {
        latest = viewport
        self.binding = binding
        guard !scheduled else { return }
        scheduled = true
        let expected = generation
        let callback: () -> Void = { [weak self] in
            Task { @MainActor [weak self] in self?.flush(generation: expected) }
        }
        #if os(Android)
        do {
            try jniContext {
                JNI.jni.withEnv { precondition($0.PushLocalFrame($1, 16) == 0) }
                defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
                let closure = SwiftClosure0.javaObject(for: callback, options: [])!
                try Self.clock.callStatic(method: Self.post, options: [],
                    args: [closure.toJavaParameter(options: [])]) as Void
            }
        } catch {
            print("Aria viewport frame callback failed: \(error)")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(17))
                callback()
            }
        }
        #else
        Task { @MainActor in await Task.yield(); callback() }
        #endif
    }

    func cancel() {
        generation &+= 1
        scheduled = false
        latest = nil
        binding = nil
    }

    private func flush(generation expected: Int) {
        guard generation == expected, scheduled else { return }
        let viewport = latest
        let target = binding
        scheduled = false
        latest = nil
        binding = nil
        if let viewport, let target, target.wrappedValue != viewport {
            target.wrappedValue = viewport
        }
    }

    #if os(Android)
    private static let clock = try! JClass(name: "aria/skip/AriaViewportFrameClock")
    private static let post = clock.getStaticMethodID(name: "post", sig: "(Lkotlin/jvm/functions/Function0;)V")!
    #endif
}
