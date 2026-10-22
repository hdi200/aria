// Android stand-in for the part of AVFoundation (AVFAudio) the shared playback code uses
// (NativePlaybackController): an engine with player nodes that play scheduled buffers on
// their own sample timelines, a main mixer with volume, pan and a level tap, and the audio
// session. The output is the engine's AAudio stream (AriaAudioOutput).
@_exported import Foundation
import AriaEngine

public typealias AVAudioFramePosition = Int64
public typealias AVAudioFrameCount = UInt32
public typealias AVAudioChannelCount = UInt32
public typealias AVAudioNodeBus = Int

/// Host time: nanoseconds of the monotonic clock (mach ticks on iOS).
public func mach_absolute_time() -> UInt64 {
    AriaAudioOutput.hostTimeNanos()
}

// MARK: - Session

public final class AVAudioSession: @unchecked Sendable {
    public struct Category: Hashable, Sendable {
        let name: String
        public static let playback = Category(name: "playback")
        public static let ambient = Category(name: "ambient")
    }

    public struct Mode: Hashable, Sendable {
        let name: String
        public static let `default` = Mode(name: "default")
    }

    public struct CategoryOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mixWithOthers = CategoryOptions(rawValue: 1)
    }

    private static let shared = AVAudioSession()

    public static func sharedInstance() -> AVAudioSession {
        shared
    }

    /// Set by the engine whose output is running, for the latencies below.
    private static let outputLock = NSLock()
    nonisolated(unsafe) private static weak var storedActiveOutput: AriaAudioOutput?
    static var activeOutput: AriaAudioOutput? {
        get { outputLock.withLock { storedActiveOutput } }
        set { outputLock.withLock { storedActiveOutput = newValue } }
    }

    public func setCategory(_ category: Category, mode: Mode = .default, options: CategoryOptions = []) throws {}

    public func setActive(_ active: Bool) throws {}

    public var outputLatency: TimeInterval {
        Self.activeOutput.map { max($0.latencySeconds - $0.bufferSeconds, 0) } ?? 0
    }

    public var ioBufferDuration: TimeInterval {
        Self.activeOutput?.bufferSeconds ?? 0.01
    }
}

// MARK: - Formats, buffers, times

public enum AVAudioCommonFormat: UInt, Sendable {
    case otherFormat = 0
    case pcmFormatFloat32 = 1
}

public let AVFormatIDKey = "AVFormatIDKey"
public let AVSampleRateKey = "AVSampleRateKey"
public let AVNumberOfChannelsKey = "AVNumberOfChannelsKey"
public let AVLinearPCMBitDepthKey = "AVLinearPCMBitDepthKey"
public let AVLinearPCMIsFloatKey = "AVLinearPCMIsFloatKey"
public let kAudioFormatLinearPCM: UInt32 = 0x6C70636D

public final class AVAudioFormat: @unchecked Sendable {
    public let sampleRate: Double
    public let channelCount: AVAudioChannelCount
    public let commonFormat: AVAudioCommonFormat
    public let isInterleaved: Bool

    public init?(commonFormat: AVAudioCommonFormat, sampleRate: Double, channels: AVAudioChannelCount, interleaved: Bool) {
        guard commonFormat == .pcmFormatFloat32, sampleRate > 0, channels > 0, !interleaved else {
            return nil
        }
        self.commonFormat = commonFormat
        self.sampleRate = sampleRate
        self.channelCount = channels
        self.isInterleaved = interleaved
    }

    /// File settings for this format (32-bit float linear PCM).
    public var settings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(channelCount),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
        ]
    }
}

/// Writes 32-bit float WAV files (audio export), as AVAudioFile does with float settings.
public final class AVAudioFile {
    public let url: URL
    private let handle: FileHandle
    private let sampleRate: Double
    private let channelCount: Int
    private var dataByteCount: UInt32 = 0

    public init(forWriting fileURL: URL, settings: [String: Any]) throws {
        url = fileURL
        sampleRate = settings[AVSampleRateKey] as? Double ?? 48_000
        channelCount = settings[AVNumberOfChannelsKey] as? Int ?? 2
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try FileHandle(forWritingTo: fileURL)
        try handle.write(contentsOf: header())
    }

    deinit {
        try? handle.close()
    }

    public func write(from buffer: AVAudioPCMBuffer) throws {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let sourceChannels = Int(buffer.format.channelCount)
        var interleaved = [Float](repeating: 0, count: frames * channelCount)
        for frame in 0..<frames {
            for channel in 0..<channelCount {
                interleaved[frame * channelCount + channel] = channels[min(channel, sourceChannels - 1)][frame]
            }
        }
        let data = interleaved.withUnsafeBufferPointer { Data(buffer: $0) }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        dataByteCount += UInt32(data.count)
        // Keep the header's sizes current, so the file is complete after every write.
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header())
    }

    private func header() -> Data {
        var data = Data()
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytesPerFrame = UInt32(channelCount * 4)
        append("RIFF")
        append32(36 + dataByteCount)
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(3) // IEEE float
        append16(UInt16(channelCount))
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate) * bytesPerFrame)
        append16(UInt16(bytesPerFrame))
        append16(32)
        append("data")
        append32(dataByteCount)
        return data
    }
}

/// Planar 32-bit float audio.
public final class AVAudioPCMBuffer: @unchecked Sendable {
    public let format: AVAudioFormat
    public let frameCapacity: AVAudioFrameCount
    public var frameLength: AVAudioFrameCount = 0
    private let channels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>

    public init?(pcmFormat format: AVAudioFormat, frameCapacity: AVAudioFrameCount) {
        self.format = format
        self.frameCapacity = frameCapacity
        let channelCount = Int(format.channelCount)
        channels = .allocate(capacity: channelCount)
        for channel in 0..<channelCount {
            let samples = UnsafeMutablePointer<Float>.allocate(capacity: max(Int(frameCapacity), 1))
            samples.initialize(repeating: 0, count: max(Int(frameCapacity), 1))
            (channels + channel).initialize(to: samples)
        }
    }

    deinit {
        for channel in 0..<Int(format.channelCount) {
            channels[channel].deallocate()
        }
        channels.deallocate()
    }

    public var floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>? {
        UnsafePointer(channels)
    }
}

public final class AVAudioTime: @unchecked Sendable {
    public let sampleTime: AVAudioFramePosition
    public let sampleRate: Double
    public let hostTime: UInt64
    public let isSampleTimeValid: Bool
    public let isHostTimeValid: Bool

    public init(sampleTime: AVAudioFramePosition, atRate sampleRate: Double) {
        self.sampleTime = sampleTime
        self.sampleRate = sampleRate
        hostTime = 0
        isSampleTimeValid = true
        isHostTimeValid = false
    }

    public init(hostTime: UInt64) {
        self.hostTime = hostTime
        sampleTime = 0
        sampleRate = 0
        isSampleTimeValid = false
        isHostTimeValid = true
    }

    public static func seconds(forHostTime hostTime: UInt64) -> TimeInterval {
        TimeInterval(hostTime) / 1e9
    }

    public static func hostTime(forSeconds seconds: TimeInterval) -> UInt64 {
        UInt64(max(seconds, 0) * 1e9)
    }
}

// MARK: - Nodes

open class AVAudioNode: @unchecked Sendable {
    weak var engine: AVAudioEngine?

    public init() {}
}

public final class AVAudioMixerNode: AVAudioNode, @unchecked Sendable {
    public var outputVolume: Float = 1 {
        didSet { engine?.applyMaster() }
    }

    public var pan: Float = 0 {
        didSet { engine?.applyMaster() }
    }

    public typealias TapBlock = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

    /// Calls `block` about every `bufferSize` frames with a short buffer holding the
    /// output's peak, which is what the shared code reads from tap buffers.
    public func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat?,
                           block: @escaping TapBlock) {
        engine?.installTap(bufferSize: bufferSize, block: block)
    }

    public func removeTap(onBus bus: AVAudioNodeBus) {
        engine?.removeTap()
    }
}

public final class AVAudioOutputNode: AVAudioNode, @unchecked Sendable {
    public var presentationLatency: TimeInterval {
        engine?.output.map { max($0.latencySeconds - $0.bufferSeconds, 0) } ?? 0
    }

    public func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        let sampleRate = engine?.output?.sampleRate ?? engine?.connectedSampleRate ?? 48_000
        return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
    }
}

public struct AVAudioPlayerNodeBufferOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let loops = AVAudioPlayerNodeBufferOptions(rawValue: 1 << 0)
    public static let interrupts = AVAudioPlayerNodeBufferOptions(rawValue: 1 << 1)
}

public enum AVAudioPlayerNodeCompletionCallbackType: Int, Sendable {
    case dataConsumed = 0
    case dataRendered = 1
    case dataPlayedBack = 2
}

public final class AVAudioPlayerNode: AVAudioNode, @unchecked Sendable {
    public typealias CompletionHandler = @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void

    /// The node's player in the engine's output.
    var playerIndex = 0
    private let lock = NSLock()
    private var completions: [Int64: @Sendable () -> Void] = [:]
    private var nextBufferID: Int64 = 1
    private var completionTimer: DispatchSourceTimer?

    public var volume: Float = 1 {
        didSet { engine?.output?.setVolume(player: playerIndex, volume: volume) }
    }

    /// Balance; the shared code keeps it centred and pans in its own mix.
    public var pan: Float = 0

    public var isPlaying: Bool {
        engine?.output?.isPlaying(player: playerIndex) ?? false
    }

    public func scheduleBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime?,
                               options: AVAudioPlayerNodeBufferOptions = []) {
        schedule(buffer, at: when, completion: nil)
    }

    public func scheduleBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime?,
                               options: AVAudioPlayerNodeBufferOptions = [],
                               completionCallbackType callbackType: AVAudioPlayerNodeCompletionCallbackType,
                               completionHandler: CompletionHandler? = nil) {
        var completion: (@Sendable () -> Void)?
        if let completionHandler {
            completion = { completionHandler(callbackType) }
        }
        schedule(buffer, at: when, completion: completion)
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime?, completion: (@Sendable () -> Void)?) {
        guard let output = engine?.output, let channels = buffer.floatChannelData else {
            return
        }
        lock.lock()
        let id = nextBufferID
        nextBufferID += 1
        if let completion {
            completions[id] = completion
        }
        lock.unlock()
        let right = buffer.format.channelCount > 1 ? channels[1] : channels[0]
        let sampleTime = when.flatMap { $0.isSampleTimeValid ? $0.sampleTime : nil }
        output.schedule(player: playerIndex, sampleTime: sampleTime, left: channels[0], right: right,
                        frameCount: Int(buffer.frameLength), id: id)
        startCompletionTimerIfNeeded()
    }

    public func play() {
        engine?.output?.play(player: playerIndex, hostTimeNanos: 0)
    }

    public func play(at when: AVAudioTime?) {
        let hostTime = when.flatMap { $0.isHostTimeValid ? $0.hostTime : nil } ?? 0
        engine?.output?.play(player: playerIndex, hostTimeNanos: hostTime)
    }

    public func pause() {
        engine?.output?.pause(player: playerIndex)
    }

    /// Clears the queue; like AVAudioPlayerNode, pending completion handlers still run.
    public func stop() {
        engine?.output?.stop(player: playerIndex)
        deliverCompletions()
    }

    public func prepare(withFrameCount frameCount: AVAudioFrameCount) {}

    public var lastRenderTime: AVAudioTime? {
        guard let output = engine?.output, output.isPlaying(player: playerIndex) else {
            return nil
        }
        return AVAudioTime(sampleTime: output.sampleTime(player: playerIndex), atRate: output.sampleRate)
    }

    public func playerTime(forNodeTime nodeTime: AVAudioTime) -> AVAudioTime? {
        nodeTime
    }

    private func startCompletionTimerIfNeeded() {
        lock.withLock {
            guard completionTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
            timer.schedule(deadline: .now(), repeating: .milliseconds(10))
            timer.setEventHandler { [weak self] in
                self?.deliverCompletions()
            }
            completionTimer = timer
            timer.resume()
        }
    }

    private func deliverCompletions() {
        guard let output = engine?.output else { return }
        let finished = output.takeFinished(player: playerIndex)
        guard !finished.isEmpty else { return }
        let handlers = lock.withLock { finished.compactMap { completions.removeValue(forKey: $0) } }
        for handler in handlers {
            handler()
        }
    }

    func detach() {
        lock.withLock {
            completionTimer?.cancel()
            completionTimer = nil
            completions.removeAll()
        }
    }
}

/// A SoundFont instrument played live (NativeNotePreviewController), with the engine's
/// FluidSynth.
public final class AVAudioUnitSampler: AVAudioNode, @unchecked Sendable {
    private var soundBank: (path: String, program: Int)?

    public func loadSoundBankInstrument(at bankURL: URL, program: UInt8, bankMSB: UInt8, bankLSB: UInt8) throws {
        // Apple's melodic bank (MSB 121) is the SoundFont's bank 0.
        soundBank = (bankURL.path, Int(program))
        try loadIfRunning()
    }

    func loadIfRunning() throws {
        guard let output = engine?.output, let soundBank else { return }
        try output.loadSampler(soundFontPath: soundBank.path, bank: 0, program: soundBank.program)
    }

    public func startNote(_ note: UInt8, withVelocity velocity: UInt8, onChannel channel: UInt8) {
        engine?.output?.samplerNoteOn(Int(note), velocity: Int(velocity))
    }

    public func stopNote(_ note: UInt8, onChannel channel: UInt8) {
        engine?.output?.samplerNoteOff(Int(note))
    }
}

// MARK: - Engine

public enum AVAudioEngineError: LocalizedError {
    case noPlayers

    public var errorDescription: String? {
        "The audio engine has no player or instrument connected."
    }
}

public final class AVAudioEngine: @unchecked Sendable {
    public let mainMixerNode = AVAudioMixerNode()
    public let outputNode = AVAudioOutputNode()
    private var players: [AVAudioPlayerNode] = []
    private var samplers: [AVAudioUnitSampler] = []
    private(set) var output: AriaAudioOutput?
    private(set) var connectedSampleRate: Double?
    private var tapTimer: DispatchSourceTimer?

    public init() {
        mainMixerNode.engine = self
        outputNode.engine = self
    }

    deinit {
        stop()
        tapTimer?.cancel()
        players.forEach { $0.detach() }
    }

    public func attach(_ node: AVAudioNode) {
        node.engine = self
        if let player = node as? AVAudioPlayerNode, !players.contains(where: { $0 === player }) {
            player.playerIndex = players.count
            players.append(player)
        }
        if let sampler = node as? AVAudioUnitSampler, !samplers.contains(where: { $0 === sampler }) {
            samplers.append(sampler)
        }
    }

    public func connect(_ node: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat?) {
        if let format {
            connectedSampleRate = format.sampleRate
        }
    }

    public func prepare() {}

    /// Load the preview instrument without publishing this output as the score's
    /// playback clock. The native constructor starts its stream; stop it before
    /// loading any samples. A later start() resumes the prepared stream.
    public func prewarmSamplers() throws {
        guard players.isEmpty, !samplers.isEmpty else { throw AVAudioEngineError.noPlayers }
        guard output == nil else { return }
        let prepared = try AriaAudioOutput(sampleRate: connectedSampleRate, playerCount: 0)
        prepared.stop()
        output = prepared
        applyMaster()
        do {
            for sampler in samplers { try sampler.loadIfRunning() }
        } catch {
            output = nil
            throw error
        }
    }

    public var isRunning: Bool {
        output?.isRunning ?? false
    }

    public func start() throws {
        if let output {
            try output.start()
        } else {
            guard !players.isEmpty || !samplers.isEmpty else { throw AVAudioEngineError.noPlayers }
            let output = try AriaAudioOutput(sampleRate: connectedSampleRate, playerCount: players.count)
            self.output = output
            applyMaster()
            for player in players {
                output.setVolume(player: player.playerIndex, volume: player.volume)
            }
            for sampler in samplers {
                try sampler.loadIfRunning()
            }
        }
        AVAudioSession.activeOutput = output
    }

    public func stop() {
        output?.stop()
    }

    func applyMaster() {
        output?.setMaster(volume: mainMixerNode.outputVolume, pan: mainMixerNode.pan)
    }

    func installTap(bufferSize: AVAudioFrameCount, block: @escaping AVAudioMixerNode.TapBlock) {
        removeTap()
        let sampleRate = output?.sampleRate ?? connectedSampleRate ?? 48_000
        let interval = max(Double(bufferSize) / sampleRate, 0.005)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let output = self?.output,
                  let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1),
                  let channels = buffer.floatChannelData
            else { return }
            let peak = output.takePeak()
            channels[0][0] = peak
            channels[1][0] = peak
            buffer.frameLength = 1
            block(buffer, AVAudioTime(hostTime: mach_absolute_time()))
        }
        tapTimer = timer
        timer.resume()
    }

    func removeTap() {
        tapTimer?.cancel()
        tapTimer = nil
    }
}
