package aria.skip

import android.content.Context
import android.content.pm.PackageManager
import android.media.midi.MidiDevice
import android.media.midi.MidiDeviceInfo
import android.media.midi.MidiManager
import android.media.midi.MidiOutputPort
import android.media.midi.MidiReceiver
import android.os.Handler
import android.os.Looper
import skip.ui.UIApplication

/// MIDI keyboards for note input (Android's CoreMIDI counterpart). Connects to every
/// device's output ports, as iOS connects to every source, and queues note events for
/// Swift (MIDIInputController), which collects them with takeNotes().
object AriaMidiImpl {
    private val lock = Any()
    private val notes = StringBuilder()
    private val openDevices = mutableMapOf<Int, MidiDevice>()
    private val openPorts = mutableListOf<MidiOutputPort>()
    private var manager: MidiManager? = null
    private var callback: MidiManager.DeviceCallback? = null

    fun start(): Boolean {
        val context = UIApplication.shared.androidActivity ?: return false
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_MIDI)) return false
        val midiManager = manager ?: (context.getSystemService(Context.MIDI_SERVICE) as? MidiManager) ?: return false
        if (manager == null) {
            manager = midiManager
            val deviceCallback = object : MidiManager.DeviceCallback() {
                override fun onDeviceAdded(device: MidiDeviceInfo) = open(midiManager, device)
                override fun onDeviceRemoved(device: MidiDeviceInfo) {
                    synchronized(lock) { openDevices.remove(device.id)?.close() }
                }
            }
            callback = deviceCallback
            midiManager.registerDeviceCallback(deviceCallback, Handler(Looper.getMainLooper()))
        }
        @Suppress("DEPRECATION")
        midiManager.devices.forEach { open(midiManager, it) }
        return true
    }

    fun stop() {
        synchronized(lock) {
            callback?.let { manager?.unregisterDeviceCallback(it) }
            callback = null
            manager = null
            openPorts.forEach { it.close() }
            openPorts.clear()
            openDevices.values.forEach { it.close() }
            openDevices.clear()
            notes.setLength(0)
        }
    }

    /// Note events since the last call: "60+" note on, "60-" note off, comma separated.
    fun takeNotes(): String = synchronized(lock) {
        val events = notes.toString()
        notes.setLength(0)
        events
    }

    private fun open(midiManager: MidiManager, info: MidiDeviceInfo) {
        if (info.outputPortCount == 0 || synchronized(lock) { openDevices.containsKey(info.id) }) return
        midiManager.openDevice(info, { device ->
            if (device == null) return@openDevice
            synchronized(lock) {
                if (manager == null) {
                    device.close()
                    return@openDevice
                }
                openDevices[info.id] = device
                for (portIndex in 0 until info.outputPortCount) {
                    device.openOutputPort(portIndex)?.let { port ->
                        port.connect(NoteReceiver())
                        openPorts.add(port)
                    }
                }
            }
        }, Handler(Looper.getMainLooper()))
    }

    private class NoteReceiver : MidiReceiver() {
        private var runningStatus = 0

        override fun onSend(data: ByteArray, offset: Int, count: Int, timestamp: Long) {
            var index = offset
            val end = offset + count
            while (index < end) {
                val first = data[index].toInt() and 0xFF
                val status: Int
                if (first and 0x80 != 0) {
                    status = first
                    runningStatus = status
                    index += 1
                } else if (runningStatus != 0) {
                    status = runningStatus
                } else {
                    index += 1
                    continue
                }
                when (status and 0xF0) {
                    0x80, 0x90 -> {
                        if (index + 1 >= end) return
                        val note = data[index].toInt() and 0x7F
                        val velocity = data[index + 1].toInt() and 0x7F
                        index += 2
                        val on = (status and 0xF0) == 0x90 && velocity > 0
                        synchronized(lock) {
                            if (notes.isNotEmpty()) notes.append(',')
                            notes.append(note).append(if (on) '+' else '-')
                        }
                    }
                    0xA0, 0xB0, 0xE0 -> index += minOf(2, end - index)
                    0xC0, 0xD0 -> index += minOf(1, end - index)
                    0xF0 -> {
                        runningStatus = 0
                        index = end
                    }
                    else -> index += 1
                }
            }
        }
    }
}

/// What Swift calls (AnyDynamicObject reflects on class instances, not on objects).
class AriaMidi {
    fun start(): Boolean = AriaMidiImpl.start()
    fun stop(): Unit = AriaMidiImpl.stop()
    fun takeNotes(): String = AriaMidiImpl.takeNotes()
}
