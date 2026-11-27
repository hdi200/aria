import Dispatch
import Foundation
import SwiftUI
#if os(Android)
import SwiftJNI
import UIKit
#endif

/// Only one bitmap is being produced or awaiting publication. Pending requests
/// hold PDF/image data, never finished bitmaps. Publication completes on MainActor
/// before the next render begins; cancellation discards stale results safely.
@MainActor
final class AndroidPageRasterScheduler {
    static let shared = AndroidPageRasterScheduler()
    #if ARIA_PHONE_AUDIT
    // Test-only readiness check; does not change scheduling or bitmap ownership.
    var phoneAuditIsIdle: Bool { active == nil && pending.isEmpty }
    #endif
    private nonisolated static let worker = DispatchQueue(label: "aria.page.raster", qos: .userInitiated)
    private nonisolated static let early = AndroidEarlyPageRaster()

    /// Starts the bitmap of a page the engine has just rendered for display, on the raster
    /// worker, right away. Without this the PDF waits for the main thread: first for the
    /// recomposition that hands it to the page view, then for the view's raster request.
    /// On a Galaxy A35 that wait was about 140 ms of every note tap. The view's request then
    /// finds the bitmap ready (`render`) or waiting on the worker (`rasterize`).
    /// Called off the main thread, from the render session.
    nonisolated static func startEarlyPageRaster(pdf: Data) {
        early.start(pdf: pdf, on: worker) { pdf, pixels in
            rasterizeOnWorker(pdf: pdf, image: nil, pixels: pixels, opaque: true, crop: fullPage)
        }
    }

    private nonisolated static let fullPage = CGRect(x: 0, y: 0, width: 1, height: 1)

    private final class Request {
        let id: UUID
        let owner: UUID
        let pdf: Data?
        let image: Data?
        let pixels: CGSize
        let opaque: Bool
        let crop: CGRect
        let publish: @MainActor (UIImage?) -> Void
        let continuation: CheckedContinuation<Void, Never>
        var cancelled = false

        init(id: UUID, owner: UUID, pdf: Data?, image: Data?, pixels: CGSize, opaque: Bool,
             crop: CGRect, publish: @escaping @MainActor (UIImage?) -> Void,
             continuation: CheckedContinuation<Void, Never>) {
            self.id = id; self.owner = owner; self.pdf = pdf; self.image = image
            self.pixels = pixels; self.opaque = opaque; self.crop = crop
            self.publish = publish; self.continuation = continuation
        }
    }

    private var pending: [Request] = []
    private var active: Request?
    private var drain: Task<Void, Never>?

    func render(owner: UUID, pdf: Data?, image: Data?, pixels: CGSize, opaque: Bool = true,
                crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
                publish: @escaping @MainActor (UIImage?) -> Void) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(); return }
                // A caller may replace a queued request before cancellation reaches us.
                let superseded = pending.filter { $0.owner == owner }
                pending.removeAll { $0.owner == owner }
                superseded.forEach { $0.continuation.resume() }
                if active?.owner == owner { active?.cancelled = true }
                if opaque, crop == Self.fullPage, let pdf, !pdf.isEmpty {
                    // The next early page bitmap is made at this size: every page of a score
                    // is shown at the same size.
                    Self.early.setPixels(pixels)
                    if let ready = Self.early.take(pdf: pdf, pixels: pixels) {
                        publish(ready)
                        continuation.resume()
                        return
                    }
                }
                pending.append(Request(id: id, owner: owner, pdf: pdf, image: image, pixels: pixels,
                    opaque: opaque, crop: crop, publish: publish, continuation: continuation))
                #if ARIA_PHONE_AUDIT
                if let request = pending.last { trace("raster_enqueue", request) }
                #endif

                #if os(Android) && ARIA_PHONE_AUDIT
                AndroidInteractionTrace.point("raster_enqueued")
                #endif
                startIfNeeded()
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        if active?.id == id { active?.cancelled = true }
        if let index = pending.firstIndex(where: { $0.id == id }) {
            pending.remove(at: index).continuation.resume()
        }
    }

    private func startIfNeeded() {
        guard drain == nil else { return }
        drain = Task { @MainActor in
            while !pending.isEmpty {
                let request = pending.removeFirst()
                active = request
                #if ARIA_PHONE_AUDIT
                trace("raster_dispatch", request)
                #endif

                #if os(Android) && ARIA_PHONE_AUDIT
                AndroidInteractionTrace.point("raster_dispatched")
                #endif
                let image = await Self.rasterize(pdf: request.pdf, image: request.image,
                    pixels: request.pixels, opaque: request.opaque, crop: request.crop)
                #if ARIA_PHONE_AUDIT
                trace("raster_result_main", request)
                #endif

        #if os(Android) && ARIA_PHONE_AUDIT
        AndroidInteractionTrace.point("raster_main_resumed")
        #endif

                #if os(Android) && ARIA_PHONE_AUDIT
                AndroidInteractionTrace.point("raster_publish_begin")
                #endif
                if !request.cancelled { request.publish(image) }
                #if os(Android) && ARIA_PHONE_AUDIT
                AndroidInteractionTrace.point("raster_publish_end")
                #endif

                #if ARIA_PHONE_AUDIT
                trace("raster_publish_end", request)
                #endif
                request.continuation.resume()
                active = nil
            }
            drain = nil
        }
    }

    #if ARIA_PHONE_AUDIT
    private func trace(_ event: String, _ request: Request) {
        guard AndroidPhoneAuditGeometry.identityOnly else { return }
        AndroidPhoneAuditLog.trace(event, ["owner": request.owner.uuidString,
            "request": request.id.uuidString, "kind": request.opaque ? "page" : "selection",
            "width": Double(request.pixels.width), "height": Double(request.pixels.height),
            "cancelled": request.cancelled])
    }
    #endif

    private nonisolated static func rasterize(pdf: Data?, image: Data?, pixels: CGSize,
                                             opaque: Bool, crop: CGRect) async -> UIImage? {
        await withCheckedContinuation { continuation in
            worker.async {
        #if os(Android) && ARIA_PHONE_AUDIT
        AndroidInteractionTrace.point("raster_worker_begin")
        #endif
                #if os(Android) && ARIA_PHONE_AUDIT
                defer { AndroidInteractionTrace.point("raster_worker_end") }
                #endif

                // An early page bitmap started before this request ran first on this serial
                // worker; use it instead of drawing the same page again.
                if opaque, crop == fullPage, let pdf, !pdf.isEmpty,
                   let ready = early.take(pdf: pdf, pixels: pixels) {
                    continuation.resume(returning: ready)
                    return
                }
                let result = rasterizeOnWorker(pdf: pdf, image: image, pixels: pixels, opaque: opaque, crop: crop)

                #if os(Android) && ARIA_PHONE_AUDIT
                AndroidInteractionTrace.point("raster_worker_result_ready")
                #endif
                continuation.resume(returning: result)
            }
        }
    }

    /// Draws one bitmap. Runs on `worker` only.
    private nonisolated static func rasterizeOnWorker(pdf: Data?, image: Data?, pixels: CGSize,
                                                      opaque: Bool, crop: CGRect) -> UIImage? {
        let render = {
            if let pdf, !pdf.isEmpty {
                return AndroidPDFPageRenderer.image(pdfData: pdf, size: pixels, opaque: opaque, crop: crop)
            }
            guard let data = image, let decoded = UIImage(data: data, scale: 1) else { return nil }
            #if os(Android)
            AriaImageSources.remember(data, for: decoded)
            #endif
            return decoded
        }
        #if os(Android)
        return jniContext {
            JNI.jni.withEnv { precondition($0.PushLocalFrame($1, 32) == 0) }
            defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
            return render()
        }
        #else
        return render()
        #endif
    }
}

/// At most one early page bitmap (see `AndroidPageRasterScheduler.startEarlyPageRaster`):
/// a newer page replaces it, the view takes it, or it is dropped after two seconds, so it
/// never holds more than one extra page bitmap. Thread-safe.
nonisolated final class AndroidEarlyPageRaster: @unchecked Sendable {
    private struct Ready {
        let pdf: Data
        let pixels: CGSize
        let image: UIImage
        let generation: Int
    }

    private let lock = NSLock()
    private var pixels: CGSize?
    private var generation = 0
    private var ready: Ready?

    func setPixels(_ value: CGSize) {
        lock.lock(); defer { lock.unlock() }
        pixels = value
    }

    func start(pdf: Data, on queue: DispatchQueue,
               draw: @escaping @Sendable (Data, CGSize) -> UIImage?) {
        lock.lock()
        // No page has been shown yet, so there is no size to draw at.
        guard let size = pixels, size.width > 0, size.height > 0 else { lock.unlock(); return }
        generation &+= 1
        let current = generation
        ready = nil
        lock.unlock()

        queue.async { [self] in
            guard isCurrent(current) else { return }
            guard let image = draw(pdf, size) else { return }
            lock.lock()
            if generation == current {
                ready = Ready(pdf: pdf, pixels: size, image: image, generation: current)
            }
            lock.unlock()
            queue.asyncAfter(deadline: .now() + 2) { [self] in
                lock.lock(); defer { lock.unlock() }
                if ready?.generation == current { ready = nil }
            }
        }
    }

    func take(pdf: Data, pixels: CGSize) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        guard let candidate = ready, candidate.pixels == pixels, candidate.pdf == pdf else { return nil }
        ready = nil
        return candidate.image
    }

    private func isCurrent(_ value: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == value
    }
}

extension LiveScoreRenderSession {
    /// `renderPage` for the page on screen: starts its bitmap on the raster worker as soon as
    /// the engine is done, still on this actor (off the main thread).
    func renderPageForDisplay(at index: Int, dpi: Int) throws -> ScorePage {
        let page = try renderPage(at: index, dpi: dpi)
        if let pdf = page.pdfData, !pdf.isEmpty {
            AndroidPageRasterScheduler.startEarlyPageRaster(pdf: pdf)
        }
        return page
    }
}

private struct AriaRasterVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var ariaRasterVisible: Bool {
        get { self[AriaRasterVisibleKey.self] }
        set { self[AriaRasterVisibleKey.self] = newValue }
    }
}
