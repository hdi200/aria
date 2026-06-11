//
//  ScoreSessionService.swift
//  MuseReaderiOS
//
//  Created on 4/13/26.
//

import Foundation

protocol ScoreSessionService: Sendable {
    nonisolated func openSession(at url: URL) async throws -> ScoreSession
}

/// Serializes MuseScore render-core *session opens* across the whole app.
///
/// The render core lazily fills global, non-thread-safe state (font/symbol
/// tables, IoC registries, style defaults) on the worker thread during the
/// first `open`. If a second open overlaps before that state is warm — e.g. the
/// user taps a second score immediately after launch — two threads mutate the
/// same `std::map` and the engine crashes (`EXC_BAD_ACCESS` in tree nodes).
///
/// This gate only serializes opens; page rendering and playback continue to run
/// concurrently through `LiveScoreRenderSession`, so the existing multithreaded
/// behavior is preserved.
actor RenderCoreOpenGate {
    static let shared = RenderCoreOpenGate()

    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    func withExclusiveAccess<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let result = try await body()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }
}

struct MuseScoreSessionService: ScoreSessionService {
    nonisolated init() {}

    nonisolated func openSession(at url: URL) async throws -> ScoreSession {
        let requestID = UUID().uuidString.prefix(8)
        let startedAt = Date()
        print("Aria open session requested: id=\(requestID) file=\(url.lastPathComponent)")

        do {
            let session = try await RenderCoreOpenGate.shared.withExclusiveAccess {
                await MainActor.run {
                    MuseScoreRenderCoreBridge.initializeRenderRuntimeIfNeeded()
                }
                return try await Task.detached(priority: .userInitiated) {
                    try Self.makeSession(at: url, requestID: String(requestID))
                }.value
            }
            let elapsed = Date().timeIntervalSince(startedAt)
            print(String(format: "Aria open session finished: id=%@ file=%@ pages=%d live=%@ elapsed=%.3fs", String(requestID), url.lastPathComponent, session.pageCount, String(session.capabilities.supportsLivePageRendering), elapsed))
            return session
        } catch {
            let elapsed = Date().timeIntervalSince(startedAt)
            print(String(format: "Aria open session failed: id=%@ file=%@ elapsed=%.3fs error=%@", String(requestID), url.lastPathComponent, elapsed, error.localizedDescription))
            throw error
        }
    }

    nonisolated private static func makeSession(at url: URL, requestID: String) throws -> ScoreSession {
        let inspectionStartedAt = Date()
        let documentService = MuseScoreDocumentService()
        let inspection = try documentService.inspectPackage(at: url)
        print(String(format: "Aria open session inspected package: id=%@ file=%@ elapsed=%.3fs", requestID, url.lastPathComponent, Date().timeIntervalSince(inspectionStartedAt)))
        let embeddedPreviewPages = makePreviewPages(from: inspection.embeddedPreviews)
        let liveRendering = try liveRenderSessionIfAvailable(at: url, requestID: requestID)

        let previewPages: [ScorePage]
        let renderPipeline: ScoreRenderPipeline
        let supportsLivePageRendering: Bool
        let liveRenderSession: LiveScoreRenderSession?
        let totalPageCount: Int
        let corruptionReport: ScoreCorruptionReport

        switch liveRendering {
        case .rendered(let session, let detectedCorruptionReport):
            previewPages = embeddedPreviewPages
            renderPipeline = .liveMuseScoreRenderer
            supportsLivePageRendering = true
            liveRenderSession = session
            totalPageCount = session.totalPageCount
            corruptionReport = detectedCorruptionReport
        case .unavailable(let reason):
            if !embeddedPreviewPages.isEmpty {
                previewPages = embeddedPreviewPages
                renderPipeline = .embeddedPackagePreview(reason: reason)
                supportsLivePageRendering = false
                liveRenderSession = nil
                totalPageCount = embeddedPreviewPages.count
                corruptionReport = .clean
            } else {
                previewPages = []
                renderPipeline = .waitingForLiveRenderer(reason: reason)
                supportsLivePageRendering = false
                liveRenderSession = nil
                totalPageCount = 0
                corruptionReport = .clean
            }
        case .failed(let reason):
            if !embeddedPreviewPages.isEmpty {
                previewPages = embeddedPreviewPages
                renderPipeline = .embeddedPackagePreview(reason: reason)
                supportsLivePageRendering = false
                liveRenderSession = nil
                totalPageCount = embeddedPreviewPages.count
                corruptionReport = .clean
            } else {
                throw ScoreDocumentServiceError.bridgeFailure(reason)
            }
        }

        let capabilities = ScoreSessionCapabilities(
            supportsPackageInspection: true,
            supportsEmbeddedPreviews: !embeddedPreviewPages.isEmpty,
            supportsLivePageRendering: supportsLivePageRendering,
            supportsPlayback: liveRenderSession?.supportsPlayback ?? false,
            supportsEditing: liveRenderSession?.supportsEditing ?? false
        )
        let document = liveRenderSession?.parts.isEmpty == false
            ? inspection.document.replacingParts(liveRenderSession?.parts ?? [])
            : inspection.document

        return ScoreSession(
            document: document,
            previewPages: previewPages,
            renderPipeline: renderPipeline,
            capabilities: capabilities,
            liveRenderSession: liveRenderSession,
            corruptionReport: corruptionReport,
            totalPageCount: totalPageCount
        )
    }

    nonisolated private static func makePreviewPages(from previews: [ScorePackagePreviewAsset]) -> [ScorePage] {
        previews.enumerated().map { index, preview in
            ScorePage(
                index: index,
                title: previews.count == 1 ? "Embedded Preview" : "Preview \(index + 1)",
                sourcePath: preview.path,
                source: .embeddedPackagePreview,
                imageData: preview.imageData
            )
        }
    }

    nonisolated private static func liveRenderSessionIfAvailable(at url: URL, requestID: String) throws -> LiveRenderResult {
        let renderCoreUnavailableBridgeCode = 6
        let renderCoreFailureBridgeCode = 7
        let renderCoreBridge = MuseScoreRenderCoreBridge()

        do {
            let startedAt = Date()
            print("Aria live render open begin: id=\(requestID) file=\(url.lastPathComponent)")
            let renderSession = try renderCoreBridge.openSession(at: url)
            let corruptionReport = try makeCorruptionReport(from: renderSession.scoreCorruptionReport())
            print(String(format: "Aria live render open finished: id=%@ file=%@ pages=%d elapsed=%.3fs", requestID, url.lastPathComponent, renderSession.totalPageCount, Date().timeIntervalSince(startedAt)))
            if corruptionReport.isCorrupted {
                print("Aria score corruption detected: id=\(requestID) file=\(url.lastPathComponent) issues=\(corruptionReport.issues.count)")
            }
            return .rendered(LiveScoreRenderSession(bridgeSession: renderSession), corruptionReport)
        } catch let error as NSError where error.domain == MSRBridgeErrorDomain && error.code == renderCoreUnavailableBridgeCode {
            print("Aria live render open unavailable: id=\(requestID) file=\(url.lastPathComponent) error=\(error.localizedDescription)")
            return .unavailable(
                "Aria asks the reusable MuseScore render core for a live score session first. \(error.localizedDescription)"
            )
        } catch let error as NSError where error.domain == MSRBridgeErrorDomain && error.code == renderCoreFailureBridgeCode {
            print("Aria live render open failed: id=\(requestID) file=\(url.lastPathComponent) error=\(error.localizedDescription)")
            return .failed(
                "Aria tried to open a live score session before falling back, but the render core failed: \(error.localizedDescription)"
            )
        } catch {
            print("Aria live render open threw: id=\(requestID) file=\(url.lastPathComponent) error=\(error.localizedDescription)")
            throw error
        }
    }

    nonisolated private static func makeCorruptionReport(from bridgeReport: MSRScoreCorruptionReport) -> ScoreCorruptionReport {
        ScoreCorruptionReport(
            isCorrupted: bridgeReport.corrupted,
            details: bridgeReport.details,
            issues: bridgeReport.issues.map { issue in
                ScoreCorruptionIssue(
                    index: Int(issue.index),
                    measureNumber: Int(issue.measureNumber),
                    staffIndex: Int(issue.staffIndex),
                    voice: Int(issue.voice),
                    repairable: issue.repairable,
                    kind: issue.kind,
                    message: issue.message
                )
            }
        )
    }
}

private enum LiveRenderResult {
    case rendered(LiveScoreRenderSession, ScoreCorruptionReport)
    case unavailable(String)
    case failed(String)
}
