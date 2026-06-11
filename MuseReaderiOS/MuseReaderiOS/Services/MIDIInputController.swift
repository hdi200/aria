//
//  MIDIInputController.swift
//  MuseReaderiOS
//

import CoreMIDI
import Foundation

final class MIDIInputController {
    var noteOnHandler: ((Int) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSourceIDs = Set<MIDIUniqueID>()
    private var isRunning = false

    func start() {
        guard !isRunning else {
            connectAvailableSources()
            return
        }

        let clientStatus = MIDIClientCreateWithBlock("Aria MIDI Client" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async {
                self?.connectAvailableSources()
            }
        }
        guard clientStatus == noErr else {
            return
        }

        let portStatus = MIDIInputPortCreateWithBlock(client, "Aria MIDI Input" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.handle(packetList: packetList)
        }
        guard portStatus == noErr else {
            MIDIClientDispose(client)
            client = MIDIClientRef()
            return
        }

        isRunning = true
        connectAvailableSources()
    }

    func stop() {
        guard isRunning else {
            return
        }

        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = MIDIPortRef()
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = MIDIClientRef()
        }
        connectedSourceIDs.removeAll()
        isRunning = false
    }

    deinit {
        stop()
    }

    private func connectAvailableSources() {
        guard isRunning, inputPort != 0 else {
            return
        }

        let sourceCount = MIDIGetNumberOfSources()
        for sourceIndex in 0..<sourceCount {
            let source = MIDIGetSource(sourceIndex)
            guard source != 0 else {
                continue
            }

            var sourceID = MIDIUniqueID()
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &sourceID)
            guard !connectedSourceIDs.contains(sourceID) else {
                continue
            }

            if MIDIPortConnectSource(inputPort, source, nil) == noErr {
                connectedSourceIDs.insert(sourceID)
            }
        }
    }

    private func handle(packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            handle(packet: packet)
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func handle(packet: MIDIPacket) {
        let byteCount = Int(packet.length)
        guard byteCount > 0 else {
            return
        }

        withUnsafePointer(to: packet.data) { dataPointer in
            dataPointer.withMemoryRebound(to: UInt8.self, capacity: byteCount) { bytes in
                parseMIDIBytes(bytes, count: byteCount)
            }
        }
    }

    private func parseMIDIBytes(_ bytes: UnsafePointer<UInt8>, count: Int) {
        var index = 0
        var runningStatus: UInt8?

        while index < count {
            let firstByte = bytes[index]
            let status: UInt8
            if firstByte & 0x80 != 0 {
                status = firstByte
                runningStatus = status
                index += 1
            } else if let currentStatus = runningStatus {
                status = currentStatus
            } else {
                index += 1
                continue
            }

            let messageType = status & 0xF0
            switch messageType {
            case 0x80, 0x90:
                guard index + 1 < count else {
                    return
                }
                let note = bytes[index]
                let velocity = bytes[index + 1]
                index += 2
                if messageType == 0x90, velocity > 0 {
                    emitNoteOn(Int(note))
                }
            case 0xA0, 0xB0, 0xE0:
                index += min(2, count - index)
            case 0xC0, 0xD0:
                index += min(1, count - index)
            case 0xF0:
                runningStatus = nil
                index = count
            default:
                index += 1
            }
        }
    }

    private func emitNoteOn(_ midiPitch: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.noteOnHandler?(midiPitch)
        }
    }
}
