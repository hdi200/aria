// Local optimized audit only. No counters, CPU probes or logs in a normal build.
#if os(Android) && ARIA_EDIT_AUDIT
import Foundation
import SkipBridge
import SwiftJNI

@MainActor
enum AndroidPanAudit {
    private static var counts: [String: Int] = [:]
    private static var revision = 0
    private static var startCounts: [String: Int] = [:]
    private static var startCPU: Int64 = 0
    private static var startTID: Int32 = 0
    private static let debug = try! JClass(name: "android/os/Debug", systemClass: true)
    private static let cpuMethod = debug.getStaticMethodID(name: "threadCpuTimeNanos", sig: "()J")!
    private static let process = try! JClass(name: "android/os/Process", systemClass: true)
    private static let tidMethod = process.getStaticMethodID(name: "myTid", sig: "()I")!

    static func hit(_ name: String) { counts[name, default: 0] += 1 }

    private static func cpu() -> Int64 {
        (try? jniContext { () throws -> Int64 in
            try debug.callStatic(method: cpuMethod, options: [], args: [])
        }) ?? -1
    }
    private static func tid() -> Int32 {
        (try? jniContext { () throws -> Int32 in
            try process.callStatic(method: tidMethod, options: [], args: [])
        }) ?? -1
    }

    static func begin(mode: Int32) {
        revision += 1
        startTID = tid()
        startCPU = cpu()
        startCounts = counts
    }

    static func end(mode: Int32, delay: Double = 0.3) {
        let expected = revision
        let before = startCounts
        let began = startCPU
        let beganTID = startTID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard expected == revision else { return }
            let endedCPU = cpu()
            let endedTID = tid()
            let values = counts.keys.sorted().map { "\($0)=\(counts[$0, default: 0] - before[$0, default: 0])" }.joined(separator: " ")
            print("ARIA_PAN_SAMPLE id=\(expected) mode=\(mode) cpu_ns=\(endedCPU - began) start_tid=\(beganTID) end_tid=\(endedTID) \(values)")
        }
    }
}
#endif
