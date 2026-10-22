// Android stand-in for the Core Media the video export uses: times, and audio sample
// buffers of float PCM for AVAssetWriterInput (the AVFoundation shim's writer).
#if os(Android)
@_exported import Foundation
import UIKit

public typealias OSStatus = Int32
public let noErr: OSStatus = 0
public typealias CMTimeValue = Int64
public typealias CMTimeScale = Int32
public typealias CMItemCount = Int
public typealias CMBlockBufferFlags = UInt32
public let kCMBlockBufferAssureMemoryNowFlag: CMBlockBufferFlags = 1 << 0

public struct CMTime: Equatable, Sendable {
    public var value: CMTimeValue
    public var timescale: CMTimeScale

    public init(value: CMTimeValue, timescale: CMTimeScale) {
        self.value = value
        self.timescale = timescale
    }

    public static let zero = CMTime(value: 0, timescale: 1)

    public var seconds: Double {
        timescale == 0 ? 0 : Double(value) / Double(timescale)
    }

    public var isNumeric: Bool { timescale != 0 }
}

// Core Audio's stream description, as AVFoundation re-exports it on iOS.
public typealias AudioFormatID = UInt32
public typealias AudioFormatFlags = UInt32
public let kAudioFormatFlagIsFloat: AudioFormatFlags = 1 << 0
public let kAudioFormatFlagIsBigEndian: AudioFormatFlags = 1 << 1
public let kAudioFormatFlagIsSignedInteger: AudioFormatFlags = 1 << 2
public let kAudioFormatFlagIsPacked: AudioFormatFlags = 1 << 3

public struct AudioStreamBasicDescription: Sendable {
    public var mSampleRate: Double
    public var mFormatID: AudioFormatID
    public var mFormatFlags: AudioFormatFlags
    public var mBytesPerPacket: UInt32
    public var mFramesPerPacket: UInt32
    public var mBytesPerFrame: UInt32
    public var mChannelsPerFrame: UInt32
    public var mBitsPerChannel: UInt32
    public var mReserved: UInt32

    public init(mSampleRate: Double, mFormatID: AudioFormatID, mFormatFlags: AudioFormatFlags,
                mBytesPerPacket: UInt32, mFramesPerPacket: UInt32, mBytesPerFrame: UInt32,
                mChannelsPerFrame: UInt32, mBitsPerChannel: UInt32, mReserved: UInt32) {
        self.mSampleRate = mSampleRate
        self.mFormatID = mFormatID
        self.mFormatFlags = mFormatFlags
        self.mBytesPerPacket = mBytesPerPacket
        self.mFramesPerPacket = mFramesPerPacket
        self.mBytesPerFrame = mBytesPerFrame
        self.mChannelsPerFrame = mChannelsPerFrame
        self.mBitsPerChannel = mBitsPerChannel
        self.mReserved = mReserved
    }
}

public final class CMAudioFormatDescription: @unchecked Sendable {
    public let streamDescription: AudioStreamBasicDescription

    init(_ description: AudioStreamBasicDescription) {
        streamDescription = description
    }
}

public final class CMBlockBuffer: @unchecked Sendable {
    var bytes: Data

    init(length: Int) {
        bytes = Data(count: length)
    }
}

/// Interleaved 32-bit float samples (all the export writes) and when they start.
public final class CMSampleBuffer: @unchecked Sendable {
    public let samples: Data
    public let sampleCount: Int
    public let presentationTimeStamp: CMTime
    public let format: AudioStreamBasicDescription

    init(samples: Data, sampleCount: Int, presentationTimeStamp: CMTime, format: AudioStreamBasicDescription) {
        self.samples = samples
        self.sampleCount = sampleCount
        self.presentationTimeStamp = presentationTimeStamp
        self.format = format
    }
}

public func CMAudioFormatDescriptionCreate(allocator: CFAllocator?, asbd: UnsafePointer<AudioStreamBasicDescription>,
                                           layoutSize: Int, layout: UnsafeRawPointer?, magicCookieSize: Int,
                                           magicCookie: UnsafeRawPointer?, extensions: CFDictionary?,
                                           formatDescriptionOut: UnsafeMutablePointer<CMAudioFormatDescription?>) -> OSStatus {
    formatDescriptionOut.pointee = CMAudioFormatDescription(asbd.pointee)
    return noErr
}

public func CMBlockBufferCreateWithMemoryBlock(allocator: CFAllocator?, memoryBlock: UnsafeMutableRawPointer?,
                                               blockLength: Int, blockAllocator: CFAllocator?,
                                               customBlockSource: UnsafeRawPointer?, offsetToData: Int,
                                               dataLength: Int, flags: CMBlockBufferFlags,
                                               blockBufferOut: UnsafeMutablePointer<CMBlockBuffer?>) -> OSStatus {
    let block = CMBlockBuffer(length: dataLength)
    if let memoryBlock {
        block.bytes = Data(bytes: memoryBlock + offsetToData, count: dataLength)
    }
    blockBufferOut.pointee = block
    return noErr
}

public func CMBlockBufferReplaceDataBytes(with sourceBytes: UnsafeRawPointer, blockBuffer destinationBuffer: CMBlockBuffer,
                                          offsetIntoDestination: Int, dataLength: Int) -> OSStatus {
    guard offsetIntoDestination + dataLength <= destinationBuffer.bytes.count else { return -12700 }
    destinationBuffer.bytes.replaceSubrange(offsetIntoDestination..<(offsetIntoDestination + dataLength),
                                            with: Data(bytes: sourceBytes, count: dataLength))
    return noErr
}

public func CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: CFAllocator?, dataBuffer: CMBlockBuffer,
                                                                 formatDescription: CMAudioFormatDescription,
                                                                 sampleCount: CMItemCount, presentationTimeStamp: CMTime,
                                                                 packetDescriptions: UnsafeRawPointer?,
                                                                 sampleBufferOut: UnsafeMutablePointer<CMSampleBuffer?>) -> OSStatus {
    let format = formatDescription.streamDescription
    guard format.mFormatID == 0x6C70636D, format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
        return -12710
    }
    sampleBufferOut.pointee = CMSampleBuffer(samples: dataBuffer.bytes, sampleCount: sampleCount,
                                             presentationTimeStamp: presentationTimeStamp, format: format)
    return noErr
}
#endif
