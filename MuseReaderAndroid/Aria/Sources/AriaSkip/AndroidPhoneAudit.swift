// Local standalone TEST APK. Package.swift excludes this source in ordinary builds.
// Do not put its View declarations inside a custom #if: Skip must discover them
// to generate Kotlin view/state bridges, or the native views render empty.
import Foundation
import CryptoKit
import Observation
import SkipFuse
import SwiftUI
#if os(Android)
import SwiftJNI
import Bionic
#endif


// TEST-only implementation switches, selected before a disposable reader is made.
// Never change a variant while a reader is alive. A fresh process is used per run.
@MainActor
enum AndroidPhoneAuditExperiment {
    static var current = "control"
    static let variants = ["control"]
    static func select(_ value: String) {
        precondition(variants.contains(value), "Unknown TEST experiment")
        current = value
    }
}

// TEST-only scalar recorder. No JNI, JSON, image ownership or observable writes
// on the hot path. Explicit clock failures/overflow are exported with the report.
enum AndroidInteractionTrace {
    #if os(Android)
    private struct Event {
        let name: String; let value: Int; let ns: Int64; let cpu: Int64
        let mainCPU: Int64; let processCPU: Int64; let tid: Int32; let token: Int
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var events: [Event] = []
    nonisolated(unsafe) private static var enabled = false
    nonisolated(unsafe) private static var token = 0
    nonisolated(unsafe) private static var mainClock: clockid_t = 0
    nonisolated(unsafe) private static var mainClockValid = false
    nonisolated(unsafe) private static var dropped = 0
    nonisolated(unsafe) private static var clockFailures = 0
    nonisolated(unsafe) private static var calibrationWallNs: Int64 = 0
    nonisolated(unsafe) private static var calibrationCpuNs: Int64 = 0
    nonisolated private static func clock(_ id: clockid_t) -> Int64 {
        var t = timespec()
        guard clock_gettime(id, &t) == 0 else { clockFailures += 1; return -1 }
        return Int64(t.tv_sec) * 1_000_000_000 + Int64(t.tv_nsec)
    }
    #endif
    @MainActor static func reset() {
        #if os(Android)
        lock.lock(); defer { lock.unlock() }
        events.removeAll(keepingCapacity: true); events.reserveCapacity(65536)
        dropped = 0; clockFailures = 0; token = 0
        mainClockValid = pthread_getcpuclockid(pthread_self(), &mainClock) == 0
        enabled = true
        AriaFuseAudit.active = false
        AriaFuseAudit.record = { name, value in AndroidInteractionTrace.point(name, value: value) }
        lock.unlock()
        var startWall = timespec(); var startCPU = timespec()
        clock_gettime(CLOCK_MONOTONIC, &startWall); clock_gettime(CLOCK_THREAD_CPUTIME_ID, &startCPU)
        for _ in 0..<1000 { point("calibration") }
        var endWall = timespec(); var endCPU = timespec()
        clock_gettime(CLOCK_MONOTONIC, &endWall); clock_gettime(CLOCK_THREAD_CPUTIME_ID, &endCPU)
        lock.lock()
        calibrationWallNs = (Int64(endWall.tv_sec - startWall.tv_sec) * 1_000_000_000 + Int64(endWall.tv_nsec - startWall.tv_nsec)) / 1000
        calibrationCpuNs = (Int64(endCPU.tv_sec - startCPU.tv_sec) * 1_000_000_000 + Int64(endCPU.tv_nsec - startCPU.tv_nsec)) / 1000
        events.removeAll(keepingCapacity: true)
        #endif
    }
    nonisolated static func focusedPoint(_ name: String, value: Int = 0) {
        #if os(Android)
        if AriaFuseAudit.active { point(name, value: value) }
        #endif
    }
    nonisolated static func point(_ name: String, value: Int = 0) {
        #if os(Android)
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return }
        guard events.count < 65536 else { dropped += 1; return }
        let ns = clock(CLOCK_MONOTONIC)
        let cpu = clock(CLOCK_THREAD_CPUTIME_ID)
        let main = mainClockValid ? clock(mainClock) : -1
        let process = clock(CLOCK_PROCESS_CPUTIME_ID)
        events.append(Event(name: name, value: value, ns: ns, cpu: cpu,
            mainCPU: main, processCPU: process, tid: gettid(), token: token))
        #endif
    }
    @MainActor static func arm(_ token: Int, focused: Bool = false) {
        #if os(Android)
        lock.lock(); self.token = token; lock.unlock()
        AriaFuseAudit.active = focused
        point("interaction_armed", value: token)
        #endif
    }
    @MainActor static func finishFocused() {
        #if os(Android)
        AriaFuseAudit.active = false
        #endif
    }
    @MainActor static func json() -> String {
        #if os(Android)
        lock.lock(); enabled = false
        let rows = events.enumerated().map { index, e in
            ["seq": index, "name": e.name, "value": e.value, "ns": e.ns,
             "cpuNs": e.cpu, "mainCpuNs": e.mainCPU, "processCpuNs": e.processCPU,
             "tid": e.tid, "token": e.token] as [String: Any]
        }
        let result: [String: Any] = ["events": rows, "droppedEvents": dropped,
            "clockFailures": clockFailures, "mainClockAvailable": mainClockValid,
            "fuseTypes": AriaFuseAudit.typeNames(),
            "calibration": ["iterations": 1000, "meanWallNsPerMarker": calibrationWallNs, "meanCpuNsPerMarker": calibrationCpuNs],
            "clock": "CLOCK_MONOTONIC", "cpuClock": "CLOCK_THREAD_CPUTIME_ID",
            "scope": "TEST-only instrumented spans; CPU outside marked spans is not call-stack attribution"]
        lock.unlock()
        return String(data: try! JSONSerialization.data(withJSONObject: result), encoding: .utf8)!
        #else
        return "{}"
        #endif
    }
}

enum AndroidPhoneAuditLog {
    nonisolated static func trace(_ name: String, _ details: [String: Any]) {
        #if os(Android)
        guard let data = try? JSONSerialization.data(withJSONObject: details, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        try? jniContext {
            JNI.jni.withEnv { precondition($0.PushLocalFrame($1, 16) == 0) }
            defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
            try AnyDynamicObject(className: "aria.skip.AriaPhoneAudit").trace(name, text) as Void
        }
        #endif
    }
    @MainActor static func visualToken(_ kind: String) -> Int {
        #if os(Android)
        return (try? AnyDynamicObject(className: "aria.skip.AriaPhoneAudit").visualToken(kind)) ?? 0
        #else
        return 0
        #endif
    }
    nonisolated static func mark(_ name: String, value: Int = 0) {
        AndroidInteractionTrace.point("legacy_" + name, value: value)
        #if os(Android)
        try? jniContext {
            JNI.jni.withEnv { precondition($0.PushLocalFrame($1, 16) == 0) }
            defer { JNI.jni.withEnv { _ = $0.PopLocalFrame($1, nil) } }
            let type = try JClass(name: "aria/skip/AriaPhoneAudit")
            let object = try type.create(ctor: type.getMethodID(name: "<init>", sig: "()V")!, options: [], args: [])
            try object.call(method: type.getMethodID(name: "mark", sig: "(Ljava/lang/String;I)V")!, options: [],
                args: [name.toJavaParameter(options: []), Int32(value).toJavaParameter(options: [])]) as Void
        }
        #endif
    }
}

private struct PhoneAuditRestartKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var ariaPhoneAuditRestart: (() -> Void)? {
        get { self[PhoneAuditRestartKey.self] }
        set { self[PhoneAuditRestartKey.self] = newValue }
    }
}

@MainActor
enum AndroidPhoneAuditGeometry {
    static var trialStage: String { "final-ui-" + AndroidPhoneAuditExperiment.current }
    static var identityOnly = false
    // Values only: tracing must not retain a view, bitmap, PDF or JNI peer.
    private static var pageTraceSnapshots: [UUID: String] = [:]
    private static var surfaceTraceSnapshots: [Int: String] = [:]
    static func surfaceTrace(page: Int, size: CGSize, viewport: CGSize) {
        guard identityOnly else { return }
        let signature = "\(size.width),\(size.height),\(viewport.width),\(viewport.height),\(UIScreen.main.scale)"
        guard surfaceTraceSnapshots[page] != signature else { return }
        surfaceTraceSnapshots[page] = signature
        AndroidPhoneAuditLog.trace("surface_identity", ["page": page,
            "width": Double(size.width), "height": Double(size.height),
            "viewportWidth": Double(viewport.width), "viewportHeight": Double(viewport.height),
            "density": Double(UIScreen.main.scale)])
    }
    static func pageTrace(_ event: String, owner: UUID, generation: Int, pdf: Data?, image: Data?,
                          size: CGSize, bounds: CGSize, scale: CGFloat, visible: Bool, selected: Bool) {
        guard identityOnly else { return }
        let data = pdf ?? image ?? Data()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let signature = "\(generation)|\(digest)|\(size)|\(bounds)|\(scale)|\(visible)|\(selected)"
        if event == "page_evaluate", pageTraceSnapshots[owner] == signature { return }
        pageTraceSnapshots[owner] = signature
        AndroidPhoneAuditLog.trace(event, ["owner": owner.uuidString, "generation": generation,
            "dataSha256": digest, "dataBytes": data.count,
            "width": Double(size.width), "height": Double(size.height),
            "boundsWidth": Double(bounds.width), "boundsHeight": Double(bounds.height),
            "scale": Double(scale), "visible": visible, "selected": selected])
    }
    struct Key { let point: CGPoint; let pitch: Int }
    static var keys: [Key] = []
    static var readerReady = false
    static var pageFrame = CGRect.zero
    static func setPageFrame(_ frame: CGRect) {
        if frame.width > 0, frame.height > 0 { pageFrame = frame }
    }
    // Weak reference to an already displayed bitmap: hashes run outside timed
    // phases, without prolonging image lifetime or adding another raster.
    static weak var selectionImage: UIImage?
    static var selectionPDF: Data?
    static var selectionOwner: UUID?
    static func selectionRaster(owner: UUID, image: UIImage?, pdf: Data?) {
        selectionOwner = owner; selectionImage = image; selectionPDF = pdf
    }
    static func clearSelectionRaster(owner: UUID) {
        if selectionOwner == owner { selectionImage = nil; selectionPDF = nil; selectionOwner = nil }
    }
    private final class VisualImage {
        weak var image: UIImage?
        let kind: String
        let token: Int
        init(_ image: UIImage, kind: String, token: Int) { self.image = image; self.kind = kind; self.token = token }
    }
    private static var visualImages: [ObjectIdentifier: VisualImage] = [:]
    static func registerVisual(_ image: UIImage?, kind: String, token: Int) {
        visualImages = visualImages.filter { $0.value.image != nil }
        guard let image, token > 0 else { return }
        visualImages[ObjectIdentifier(image)] = VisualImage(image, kind: kind, token: token)
    }
    static func visualToken(_ image: UIImage, kind: String) -> Int {
        guard let record = visualImages[ObjectIdentifier(image)], record.image === image, record.kind == kind else { return 0 }
        return record.token
    }
    static var viewport: ScoreReaderZoomViewport?
    static var panMoves = 0
    static var viewportChanges = 0
    // Native counters: no observable writes or JNI calls during body evaluation.
    static var viewEvaluations: [String: Int] = [:]
    static func evaluate(_ name: String) {
        viewEvaluations[name, default: 0] += 1
        AndroidInteractionTrace.point("evaluate_" + name)
    }
}

struct AndroidPhoneAuditVisualProbe: View {
    let token: Int
    let kind: String
    init(image: UIImage, kind: String) {
        self.token = AndroidPhoneAuditGeometry.visualToken(image, kind: kind)
        self.kind = kind
    }
    var body: some View {
        #if os(Android)
        if token > 0, let native = try? AnyDynamicObject(className: "aria.skip.AriaPhoneAuditVisualProbe", kind, token) {
            ComposeView { native }.allowsHitTesting(false)
        }
        #endif
    }
}

struct AndroidPhoneAuditKeyboardProbe: View {
    let frame: CGRect
    let pitches: [Int]
    let keyWidth: CGFloat
    let translation: CGFloat
    var body: some View {
        Color.clear.allowsHitTesting(false)
            .task(id: "\(frame)-\(pitches)-\(translation)") {
                AndroidPhoneAuditGeometry.keys = pitches.enumerated().compactMap { index, pitch in
                    let x = keyWidth * (CGFloat(index) + 0.5) + translation
                    guard x > 4, x < frame.width - 4, frame.height > 20 else { return nil }
                    return AndroidPhoneAuditGeometry.Key(point: CGPoint(x: frame.minX + x,
                        y: frame.minY + frame.height * 0.85), pitch: pitch)
                }
            }
    }
}

struct AndroidPhoneAuditRootView: View {
    @State var session: ScoreSession?
    @State var preparing = false
    @State var experiment = "control"
    @State var failure: String?
    var body: some View {
        NavigationStack {
            if let session {
                ScoreReaderView(session: session, initialPageIndex: 0, initialToolCategory: .notes,
                    initialInteractionMode: .edit, resumesRememberedPage: false,
                    readerReadyAction: { AndroidPhoneAuditGeometry.readerReady = true })
                    .environment(\.ariaPhoneAuditRestart, { self.session = nil })
                    .id(session.id)
            } else {
                VStack(spacing: 20) {
                    Text("Aria Performance TEST").font(.title2.bold()).foregroundStyle(.orange)
                    Text("Edit latency comparison · local test only").font(.headline)
                    Text("This separate app uses a disposable piano score. It will enter notes, pan with note and bar selections, pinch, and turn pages. Leave the phone alone until it finishes. Results are saved to Downloads.")
                    Text("Your normal Aria app and its scores are separate.").font(.footnote)
                    if let failure { Text(failure).foregroundStyle(.red) }
                    if preparing { ProgressView("Preparing test score…") }
                    Text("Experiment: \(experiment.uppercased())").font(.headline)
                    Button("Run benchmark") { prepare() }.disabled(preparing)
                    Menu("Choose experiment") {
                        ForEach(AndroidPhoneAuditExperiment.variants, id: \.self) { value in
                            Button(value.uppercased()) { experiment = value }
                        }
                    }.disabled(preparing)
                    Button("Run identity probe") { prepare(identityOnly: true) }.disabled(preparing)
                }.padding(24)
            }
        }
        .task {
            #if os(Android)
            let value: String = (try? AnyDynamicObject(className: "aria.skip.AriaPhoneAudit").experiment()) ?? "control"
            if AndroidPhoneAuditExperiment.variants.contains(value) { experiment = value }
            #endif
        }
    }
    private func prepare(identityOnly: Bool = false) {
        AndroidPhoneAuditExperiment.select(experiment)
        preparing = true; failure = nil
        AndroidPhoneAuditGeometry.identityOnly = identityOnly
        AndroidPhoneAuditGeometry.readerReady = false
        AndroidPhoneAuditGeometry.keys = []
        Task { @MainActor in
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aria-phone-test-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("Performance-TEST.musicxml")
                try Data(Self.fixture.utf8).write(to: url)
                // Exercise normal autosave against a writable native score, as a
                // library import does. Editing a raw MusicXML URL cannot autosave.
                let imported = try await MuseScoreSessionService().openSession(at: url)
                guard let engine = imported.liveRenderSession else {
                    throw NSError(domain: "AriaPerformanceTest", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Could not import the disposable score"])
                }
                let nativeURL = directory.appendingPathComponent("Performance-TEST.mscz")
                try await engine.save(to: nativeURL)
                session = try await MuseScoreSessionService().openSession(at: nativeURL)
            } catch { failure = error.localizedDescription }
            preparing = false
        }
    }
    private static var fixture: String {
        let measures = (1...12).map { n in
            let printTag = n == 1 ? "" : (n % 4 == 1 ? "<print new-page=\"yes\"/>" : (n % 2 == 1 ? "<print new-system=\"yes\"/>" : ""))
            let attributes = n == 1 ? "<attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves><clef number=\"1\"><sign>G</sign><line>2</line></clef><clef number=\"2\"><sign>F</sign><line>4</line></clef></attributes>" : ""
            let rests = (1...2).map { staff in
                (staff == 2 ? "<backup><duration>4</duration></backup>" : "")
                    + "<note><rest measure=\"yes\"/><duration>4</duration><voice>\(staff == 1 ? 1 : 5)</voice><staff>\(staff)</staff></note>"
            }.joined()
            return "<measure number=\"\(n)\">\(printTag)\(attributes)\(rests)</measure>"
        }.joined()
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?><score-partwise version=\"4.0\"><work><work-title>PERFORMANCE TEST — disposable</work-title></work><defaults><scaling><millimeters>7</millimeters><tenths>40</tenths></scaling></defaults><part-list><score-part id=\"P1\"><part-name>Piano</part-name><score-instrument id=\"I1\"><instrument-name>Piano</instrument-name></score-instrument><midi-instrument id=\"I1\"><midi-channel>1</midi-channel><midi-program>1</midi-program></midi-instrument></score-part></part-list><part id=\"P1\">\(measures)</part></score-partwise>"
    }
}

struct AndroidPhoneAuditControls: View {
    let reader: ScoreReaderState
    @Binding var zoom: CGFloat
    @Binding var tool: ScoreReaderToolCategory
    @State var runner = AndroidPhoneAuditRunner()
    @Environment(\.ariaPhoneAuditRestart) var restart
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("PERFORMANCE TEST").font(.caption.bold()).foregroundStyle(.orange)
                Spacer()
                if runner.finished {
                    Button("New run") { restart?() }.font(.caption)
                }
                Button(runner.finished ? "Save again" : "Stop") {
                    if runner.finished { runner.saveAgain() } else { runner.task?.cancel() }
                }.font(.caption)
            }
            Text(runner.status).font(.caption).lineLimit(3)
        }
        .padding(6).background(Color.white.opacity(0.96))
        #if os(Android)
        .background {
            if let capture = try? AnyDynamicObject(className: "aria.skip.AriaPhoneAuditCapture") {
                ComposeView { capture }
            }
        }
        #endif
        .task {
            guard runner.task == nil else { return }
            runner.task = Task { @MainActor in await runner.run(reader, zoom: $zoom, tool: $tool) }
        }
        .onDisappear { runner.task?.cancel() }
    }
}

@MainActor @Observable
final class AndroidPhoneAuditRunner {
    var status = "Preparing reader…"
    var finished = false
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored private var extra: [String: Any] = [:]
    @ObservationIgnored private var activePhase = false
    @ObservationIgnored private var phaseEvaluations: [String: Int] = [:]
    @ObservationIgnored private var bridge: AnyDynamicObject?
    private var native: AnyDynamicObject {
        get throws {
            if let bridge { return bridge }
            let object = try AnyDynamicObject(className: "aria.skip.AriaPhoneAudit")
            bridge = object
            return object
        }
    }
    private func json(_ value: [String: Any]) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)) ?? "{}"
    }
    private func pause(_ ms: Int = 150) async throws { try await Task.sleep(for: .milliseconds(ms)); try Task.checkCancellation() }
    private func wait(_ label: String, timeout: Double = 45, until ready: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !ready() {
            if Date() > deadline { throw failure("Timed out: \(label)") }
            try await pause(25)
        }
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "AriaPerformanceTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func idle(_ reader: ScoreReaderState) async throws {
        try await wait("edit queue", until: { !reader.isEditingActionInFlight && reader.editingCommandTask == nil })
        if let error = reader.editingErrorMessage { throw failure(error) }
    }
    private func settled(_ reader: ScoreReaderState) async throws {
        try await idle(reader)
        try await wait("page PDF", until: { reader.page(at: reader.selectedPageIndex) != nil && !reader.isLoadingPage(reader.selectedPageIndex) })
        try await pause(150) // Let Compose enqueue its page/selection raster tasks.
        try await wait("page raster", until: { AndroidPageRasterScheduler.shared.phoneAuditIsIdle })
        try await pause(200) // Include the resulting UI frames in the phase window.
    }
    private func begin(_ name: String) throws {
        status = name
        phaseEvaluations = AndroidPhoneAuditGeometry.viewEvaluations
        try native.begin(name) as Void; activePhase = true
    }
    private func end(_ details: [String: Any] = [:]) throws {
        var details = details
        var counts: [String: Int] = [:]
        for (name, value) in AndroidPhoneAuditGeometry.viewEvaluations {
            counts[name] = value - (phaseEvaluations[name] ?? 0)
        }
        details["viewEvaluations"] = counts
        try native.end(json(details)) as Void; activePhase = false
    }
    private func input(_ kind: String, _ start: CGPoint, _ end: CGPoint? = nil, duration: Int = 480) async throws {
        let target = end ?? start
        try native.startInput(kind, Double(start.x), Double(start.y), Double(target.x), Double(target.y), duration) as Void
        try await wait("touch dispatch", timeout: 5, until: {
            let busy: Bool? = try? native.busy()
            return busy == false
        })
    }
    private func noteCount(_ reader: ScoreReaderState) async throws -> Int {
        guard let engine = reader.session.liveRenderSession else { throw failure("Missing engine") }
        let xml = try await engine.musicXMLData()
        guard let text = String(data: xml, encoding: .utf8), text.contains("<score-partwise") else { throw failure("Invalid test-score export") }
        return text.components(separatedBy: "<pitch>").count - 1
    }
    private func prepareCursor(_ reader: ScoreReaderState) async throws {
        reader.setNoteInputEnabled(false); try await idle(reader)
        reader.clearSelection(); try await idle(reader)
        reader.applyDuration(.quarter); try await idle(reader)
        guard let engine = reader.session.liveRenderSession,
              let region = try await engine.playbackMeasureRegions().first(where: { $0.pageIndex == 0 }) else {
            throw failure("No initial measure for note-entry cursor")
        }
        reader.selectMeasureRange(pageIndex: 0, startNormalizedPoint: region.normalizedRect.center,
            endNormalizedPoint: region.normalizedRect.center)
        try await idle(reader)
        guard reader.editingState.selection?.kind == .measure else { throw failure("Initial measure selection failed") }
        reader.setNoteInputEnabled(true); try await settled(reader)
    }
    private func notes(_ reader: ScoreReaderState, zoom: Binding<CGFloat>, scale: CGFloat, rapid: Bool) async throws {
        zoom.wrappedValue = scale
        try await prepareCursor(reader)
        try await wait("keyboard geometry", until: { AndroidPhoneAuditGeometry.keys.count >= 4 })
        let before = try await noteCount(reader)
        try begin("notes_\(rapid ? "rapid" : "paced")_zoom_\(scale)")
        var expected: [Int] = []
        for i in 0..<16 {
            let keys = AndroidPhoneAuditGeometry.keys
            guard keys.count >= 4 else { throw failure("Keyboard disappeared") }
            let key = keys[(keys.count - 4) / 2 + i % 4]
            expected.append(key.pitch)
            AndroidPhoneAuditLog.mark("planned_pitch", value: key.pitch)
            try await input("tap", key.point)
            if !rapid { try await pause(400) } else { try await pause(30) }
            if let error = reader.editingErrorMessage { throw failure(error) }
        }
        try await settled(reader)
        try end(["requestedPresses": 16, "expectedPitches": expected, "scale": Double(scale)])
        // Correctness export, selection hash and undo deliberately occur outside timing.
        try hashSelection(reader, label: "notes_\(rapid ? "rapid" : "paced")_zoom_\(scale)")
        let after = try await noteCount(reader)
        guard after - before == 16 else { throw failure("Expected 16 new notes, got \(after - before). Results retained.") }
        extra["\(rapid ? "rapid" : "paced")_\(scale)_addedNotes"] = after - before
        for _ in 0..<16 { reader.undoEdit(); try await idle(reader) }
        try await settled(reader)
        guard try await noteCount(reader) == before else { throw failure("Undo did not restore test note count") }
        reader.clearSelection(); try await idle(reader)
    }
    private func hashSelection(_ reader: ScoreReaderState, label: String) throws {
        guard let pdf = reader.editingState.selection?.overlayPDFData,
              AndroidPhoneAuditGeometry.selectionPDF == pdf,
              let image = AndroidPhoneAuditGeometry.selectionImage,
              let png = image.pngData() else { throw failure("Current selection bitmap unavailable for hash: \(label)") }
        extra["selectionRaster_\(label)"] = [
            "sha256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
            "pngBytes": png.count,
            "sourcePngBytes": reader.editingState.selection?.overlayImageData?.count ?? 0,
            "pdfBytes": pdf.count]
    }
    private func visualNotes(_ reader: ScoreReaderState, zoom: Binding<CGFloat>) async throws {
        zoom.wrappedValue = 1
        try await prepareCursor(reader)
        let before = try await noteCount(reader)
        try begin("visual_note_entry")
        for i in 0..<8 {
            let keys = AndroidPhoneAuditGeometry.keys
            guard keys.count >= 4 else { throw failure("Visual note test lost keyboard") }
            let key = keys[(keys.count - 4) / 2 + i % 4]
            let armed: Int? = try native.armVisual("note")
            guard let token = armed else { throw failure("Could not arm visual note measurement") }
            let focused = [false, true, true, false, true, false, false, true][i]
            AndroidInteractionTrace.arm(token, focused: focused)
            try native.focusedMode(token, focused) as Void
            try await input("tap", key.point)
            try await wait("new-note frame submission", timeout: 15, until: {
                let done: Bool? = try? native.visualDone(token)
                return done == true
            })
            AndroidInteractionTrace.finishFocused()
            try await idle(reader)
        }
        try end(["expectedVisualSamples": 8, "endpoint": "new bitmap drawn and frame submitted; not display scan-out"])
        guard try await noteCount(reader) == before + 8 else { throw failure("Visual note run did not enter eight notes") }
        for _ in 0..<8 { reader.undoEdit(); try await idle(reader) }
        try await settled(reader)
        guard try await noteCount(reader) == before else { throw failure("Visual-note undo did not restore score") }
    }
    private func visualSelections(_ reader: ScoreReaderState, note: ScoreSelectedElement,
                                  zoom: Binding<CGFloat>) async throws {
        zoom.wrappedValue = 1
        reader.clearSelection(); try await settled(reader)
        try begin("visual_note_selection")
        for i in 0..<8 {
            if i > 0 { reader.clearSelection(); try await settled(reader) }
            guard let viewport = AndroidPhoneAuditGeometry.viewport else { throw failure("Missing visual selection viewport") }
            let frame = AndroidPhoneAuditGeometry.pageFrame
            let normalized = note.normalizedRect.center
            let local = viewport.project(CGPoint(x: normalized.x * viewport.contentSize.width,
                                                y: normalized.y * viewport.contentSize.height))
            let point = CGPoint(x: frame.minX + local.x, y: frame.minY + local.y)
            guard frame.insetBy(dx: 2, dy: 2).contains(point) else { throw failure("Visual selection target is outside the page viewport") }
            let armed: Int? = try native.armVisual("selection")
            guard let token = armed else { throw failure("Could not arm visual selection measurement") }
            let focused = [false, true, true, false, true, false, false, true][i]
            AndroidInteractionTrace.arm(token, focused: focused)
            try native.focusedMode(token, focused) as Void
            try await input("tap", point)
            try await wait("new-selection frame submission", timeout: 15, until: {
                let done: Bool? = try? native.visualDone(token)
                return done == true
            })
            try await idle(reader)
            AndroidInteractionTrace.finishFocused()
            guard reader.editingState.selection?.kind == .note,
                  reader.editingState.selection?.midiPitch == note.midiPitch else { throw failure("Visual tap selected the wrong note") }
        }
        try end(["expectedVisualSamples": 8, "endpoint": "new bitmap drawn and frame submitted; not display scan-out"])
        reader.clearSelection(); try await settled(reader)
    }
    private func identityProbe(_ reader: ScoreReaderState, zoom: Binding<CGFloat>) async throws {
        zoom.wrappedValue = 1
        try await prepareCursor(reader)
        var notes: [ScoreSelectedElement] = []
        let before = try await noteCount(reader)
        for i in 0..<4 {
            let keys = AndroidPhoneAuditGeometry.keys
            guard keys.count >= 4 else { throw failure("Identity probe lost keyboard") }
            let key = keys[(keys.count - 4) / 2 + i]
            try await input("tap", key.point); try await settled(reader)
            guard let note = reader.editingState.selection, note.midiPitch == key.pitch else {
                throw failure("Identity fixture note did not match keyboard")
            }
            notes.append(note)
        }
        reader.setNoteInputEnabled(false); try await settled(reader)
        reader.clearSelection(); try await settled(reader)
        func tap(_ note: ScoreSelectedElement, label: String) async throws {
            try begin(label)
            AndroidPhoneAuditLog.trace("identity_step", ["label": label, "stage": "start"])
            guard let viewport = AndroidPhoneAuditGeometry.viewport else { throw failure("Missing identity viewport") }
            let local = viewport.project(CGPoint(x: note.normalizedRect.center.x * viewport.contentSize.width,
                                                y: note.normalizedRect.center.y * viewport.contentSize.height))
            let frame = AndroidPhoneAuditGeometry.pageFrame
            let point = CGPoint(x: frame.minX + local.x, y: frame.minY + local.y)
            guard frame.insetBy(dx: 2, dy: 2).contains(point) else { throw failure("Identity target outside viewport") }
            let token: Int? = try native.armVisual("selection")
            guard let token else { throw failure("Could not arm identity visual measurement") }
            try await input("tap", point)
            try await wait("identity selection frame", timeout: 15, until: {
                let done: Bool? = try? native.visualDone(token)
                return done == true
            })
            try await settled(reader)
            guard reader.editingState.selection?.midiPitch == note.midiPitch else { throw failure("Identity selected wrong pitch") }
            try end(["expectedPitch": note.midiPitch])
        }
        try await tap(notes[0], label: "identity_select_a")
        try begin("identity_clear_a")
        reader.clearSelection(); try await settled(reader)
        guard reader.editingState.selection == nil else { throw failure("Identity deselect failed") }
        try end()
        try await tap(notes[2], label: "identity_select_b")
        try await tap(notes[0], label: "identity_switch_a")
        guard let engine = reader.session.liveRenderSession,
              let bar = try await engine.playbackMeasureRegions().first(where: { $0.pageIndex == 0 }) else {
            throw failure("Identity probe has no bar")
        }
        try begin("identity_select_bar")
        reader.selectMeasureRange(pageIndex: 0, startNormalizedPoint: bar.normalizedRect.center,
            endNormalizedPoint: bar.normalizedRect.center)
        try await settled(reader)
        guard reader.editingState.selection?.kind == .measure else { throw failure("Identity whole-bar selection failed") }
        try end()
        try begin("identity_clear_bar")
        reader.clearSelection(); try await settled(reader)
        guard reader.editingState.selection == nil else { throw failure("Identity clear-bar failed") }
        try end()
        guard try await noteCount(reader) == before + 4 else { throw failure("Selection changed note count") }
        extra["identityFixtureAddedNotes"] = 4
        extra["identityOnly"] = true
    }
    private func pans(_ reader: ScoreReaderState, label: String, waitBefore: Bool = true) async throws {
        if waitBefore { try await settled(reader) }
        let frame = AndroidPhoneAuditGeometry.pageFrame
        guard frame.width > 100, frame.height > 100 else { throw failure("Page viewport unavailable") }
        let beforeMoves = AndroidPhoneAuditGeometry.panMoves
        let beforeViewports = AndroidPhoneAuditGeometry.viewportChanges
        let start = CGPoint(x: frame.minX + frame.width * 0.78, y: frame.minY + frame.height * 0.72)
        let target = CGPoint(x: frame.minX + frame.width * 0.45, y: start.y - frame.height * 0.08)
        try begin(label)
        for i in 0..<6 {
            try await input("pan", i % 2 == 0 ? start : target, i % 2 == 0 ? target : start)
            try await pause(180)
        }
        try await pause(150)
        let moves = AndroidPhoneAuditGeometry.panMoves - beforeMoves
        try end(["gestures": 6, "deliveredPanMoves": moves,
            "viewportChanges": AndroidPhoneAuditGeometry.viewportChanges - beforeViewports,
            "selection": String(describing: reader.editingState.selection?.kind)])
        guard moves > 0 else { throw failure("Pan did not reach the page recognizer") }
    }
    func run(_ reader: ScoreReaderState, zoom: Binding<CGFloat>, tool: Binding<ScoreReaderToolCategory>) async {
        do {
            AndroidInteractionTrace.reset()
            AndroidInteractionTrace.point("clock_sync_before")
            try native.reset() as Void
            AndroidPhoneAuditLog.mark("clock_sync")
            AndroidInteractionTrace.point("clock_sync_after")
            extra = ["fixture": "disposable-12-measure-piano", "input": "own-window MotionEvent through real keyboard/page recognizers",
                "trialStage": AndroidPhoneAuditGeometry.trialStage,
                "experiment": AndroidPhoneAuditExperiment.current,
                "detailedIdentityTrace": AndroidPhoneAuditGeometry.identityOnly,
                "granularTimeline": true, "focusedAudit": "balanced ABBA-BAAB; four reference and four focused actions per visual kind"]
            try await wait("initial reader", until: {
                AndroidPhoneAuditGeometry.readerReady && reader.page(at: 0) != nil && AndroidPhoneAuditGeometry.keys.count >= 4
            })
            try await settled(reader)
            guard reader.pageCount >= 3 else { throw failure("Test requires at least three pages; got \(reader.pageCount)") }
            extra["pageCount"] = reader.pageCount
            if AndroidPhoneAuditGeometry.identityOnly {
                try await identityProbe(reader, zoom: zoom)
                extra["completed"] = true
                try await save()
                finished = true
                return
            }
            for scale: CGFloat in [1, 2.2] {
                for rapid in [false, true] { try await notes(reader, zoom: zoom, scale: scale, rapid: rapid) }
            }
            try await visualNotes(reader, zoom: zoom)
            // One real keyboard note leaves a normal note selection for the pan matrix.
            try await prepareCursor(reader)
            let key = AndroidPhoneAuditGeometry.keys[AndroidPhoneAuditGeometry.keys.count / 2]
            try await input("tap", key.point); try await settled(reader)
            reader.setNoteInputEnabled(false); try await idle(reader)
            guard let note = reader.editingState.selection, note.kind == .note else { throw failure("Expected a note selection") }
            reader.clearSelection(); try await settled(reader)
            try await visualSelections(reader, note: note, zoom: zoom)
            zoom.wrappedValue = 2.2; tool.wrappedValue = .notes
            try await pans(reader, label: "pan_edit_no_selection")
            try begin("select_note")
            reader.handlePageTap(pageIndex: note.pageIndex, normalizedPoint: note.normalizedRect.center)
            try await settled(reader)
            guard reader.editingState.selection?.kind == .note else { throw failure("Note selection failed") }
            try end(["setup": "normal page-selection handler"])
            try hashSelection(reader, label: "select_note")
            try await pans(reader, label: "pan_edit_selected_note")
            try await pinch(label: "pinch_edit_selected_note", zoom: zoom)
            zoom.wrappedValue = 2.2; try await pause(350)
            let regions = try await reader.session.liveRenderSession!.playbackMeasureRegions()
            guard let region = regions.first(where: { $0.pageIndex == reader.selectedPageIndex }) else { throw failure("No measure geometry") }
            try begin("select_bar")
            reader.selectMeasureRange(pageIndex: region.pageIndex, startNormalizedPoint: region.normalizedRect.center,
                endNormalizedPoint: region.normalizedRect.center)
            try await settled(reader)
            guard reader.editingState.selection?.kind == .measure else { throw failure("Whole-bar selection failed") }
            try end(["setup": "normal measure-range handler"])
            try await pans(reader, label: "pan_edit_selected_bar")
            try await pinch(label: "pinch_edit_selected_bar", zoom: zoom)
            reader.clearSelection(); try await settled(reader)
            zoom.wrappedValue = 2.2
            try await pans(reader, label: "pan_edit_deselected")
            try await pinch(label: "pinch_edit_no_selection", zoom: zoom)
            // A final edit followed immediately by a pan includes the in-flight refresh.
            try await prepareCursor(reader)
            try await input("tap", key.point)
            try await pans(reader, label: "pan_after_edit", waitBefore: false)
            status = "Entering View mode…"
            guard await reader.finishEditingAndEnterViewMode() else { throw failure("Could not finish editing") }
            // The normal mode-change observer resets View mode to fit-page.
            // Let that transition finish before requesting the benchmark zoom.
            try await settled(reader)
            zoom.wrappedValue = 2.2; try await settled(reader)
            try await wait("View-mode zoom", until: {
                abs((AndroidPhoneAuditGeometry.viewport?.zoomScale ?? 0) - 2.2) < 0.01
            })
            try await pans(reader, label: "pan_view")
            try await pinch(label: "pinch_view", zoom: zoom)
            for page in [1, 2, 1, 0] {
                zoom.wrappedValue = 1; try await pause(200)
                let old = reader.selectedPageIndex
                let f = AndroidPhoneAuditGeometry.pageFrame
                let right = CGPoint(x: f.minX + f.width * 0.82, y: f.minY + f.height * 0.52)
                let left = CGPoint(x: f.minX + f.width * 0.20, y: right.y)
                try begin("page_swipe_\(old + 1)_to_\(page + 1)")
                try await input("pan", page > old ? right : left, page > old ? left : right, duration: 240)
                try await wait("page swipe", until: { reader.selectedPageIndex == page })
                try await settled(reader)
                try end(["from": old, "to": page, "revisit": page <= 1])
            }
            extra["completed"] = true
            try await save()
        } catch {
            print("ARIA_PHONE_TEST_FAILED: \(String(describing: error))")
            try? native.cancel() as Void
            if activePhase { try? end(["aborted": true, "reason": error.localizedDescription]) }
            extra["completed"] = false
            extra["failure"] = error is CancellationError ? "Stopped by user or reader closed" : String(describing: error)
            status = "Stopped: \(extra["failure"]!)"
            // Save partial evidence even on a timeout, failed validation or Stop.
            try? native.nativeTimeline(AndroidInteractionTrace.json()) as Void
            try? native.save(json(extra)) as Void
        }
        finished = true
    }
    private func pinch(label: String, zoom: Binding<CGFloat>) async throws {
        zoom.wrappedValue = 1; try await pause(500)
        let f = AndroidPhoneAuditGeometry.pageFrame
        let start = CGPoint(x: f.minX + f.width * 0.15, y: f.minY + f.height * 0.48)
        let end = CGPoint(x: f.minX + f.width * 0.85, y: start.y)
        try begin(label)
        let before = zoom.wrappedValue
        try await input("pinch", start, end, duration: 600)
        try await pause(500)
        try self.end(["scaleBefore": Double(before), "scaleAfter": Double(zoom.wrappedValue)])
        guard zoom.wrappedValue > before + 0.1 else { throw failure("Pinch did not change zoom") }
    }
    private func save() async throws {
        try native.nativeTimeline(AndroidInteractionTrace.json()) as Void
        try native.save(json(extra)) as Void
        try await wait("saving Downloads report", timeout: 20, until: {
            let text: String = (try? native.saveStatus()) ?? ""
            return text.hasPrefix("Saved:") || text.hasPrefix("Save failed:")
        })
        let result: String? = try native.saveStatus()
        status = result ?? "Save status unavailable"
    }
    func saveAgain() {
        Task { @MainActor in do { try await save() } catch { status = error.localizedDescription } }
    }
}
