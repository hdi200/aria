package aria.skip

import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/// Writes an H.264 + AAC MP4 from frames (bitmaps held by AriaGraphics) and float PCM:
/// what AVAssetWriter does for the video export (the AVFoundation shim's AVAssetWriter).
/// Encoding is synchronous: each append feeds the encoder and drains what it has ready.
class AriaVideoWriter {
    private var muxer: MediaMuxer? = null
    private var video: MediaCodec? = null
    private var audio: MediaCodec? = null
    private var videoTrack = -1
    private var audioTrack = -1
    private var muxerStarted = false
    private var videoDone = false
    private var audioDone = false
    private var width = 0
    private var height = 0
    private var channels = 2
    private var sampleRate = 44100
    private val pending = ArrayList<Triple<Boolean, ByteArray, MediaCodec.BufferInfo>>()
    private var argb = IntArray(0)
    // Serial writer-owned scratch storage; no per-block or per-frame plane arrays.
    private var chromaU = IntArray(0)
    private var chromaV = IntArray(0)
    private val planeBytes = Array(3) { ByteArray(0) }
    private var auditStartedNs = 0L
    private var auditFrames = 0
    var error: String = ""
        private set

    /// Opens the file. Sizes are rounded down to even, as H.264 needs.
    fun open(path: String, width: Int, height: Int, frameRate: Int, bitRate: Int, keyFrameSeconds: Int,
             sampleRate: Int, channels: Int, audioBitRate: Int): Boolean {
        try {
            if (BuildConfig.ARIA_VIDEO_AUDIT) {
                auditStartedNs = android.os.SystemClock.elapsedRealtimeNanos()
                auditFrames = 0
                AriaVideoAudit.reset()
                AriaVideoAudit.thread("writer.open")
            }
            File(path).delete()
            this.width = width and 1.inv()
            this.height = height and 1.inv()
            this.sampleRate = sampleRate
            this.channels = channels
            val videoFormat = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, this.width, this.height)
            videoFormat.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            videoFormat.setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            videoFormat.setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            videoFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, keyFrameSeconds)
            video = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).also {
                it.configure(videoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                it.start()
            }
            val audioFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channels)
            audioFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            audioFormat.setInteger(MediaFormat.KEY_BIT_RATE, audioBitRate)
            audioFormat.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
            audio = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).also {
                it.configure(audioFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                it.start()
            }
            muxer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            return true
        } catch (exception: Exception) {
            fail("The encoder did not start", exception)
            release()
            return false
        }
    }

    /// Encodes the bitmap (AriaGraphics) as the frame at `timeUs`.
    fun appendFrame(bitmapId: Int, timeUs: Long): Boolean {
        val codec = video ?: return false
        val bitmap = AriaGraphicsImpl.bitmap(bitmapId) ?: return false
        return try {
            val index = dequeueInput(codec)
            val image = codec.getInputImage(index) ?: throw IllegalStateException("No input image")
            writeYuv(bitmap, image)
            if (BuildConfig.ARIA_VIDEO_AUDIT) {
                if (auditFrames in intArrayOf(0, 15, 150, 450, 899)) {
                    AriaVideoAudit.frame(auditFrames, timeUs, width, height, argb, image)
                }
                auditFrames += 1
            }
            codec.queueInputBuffer(index, 0, width * height * 3 / 2, timeUs, 0)
            drain(codec, false)
            true
        } catch (exception: Exception) {
            fail("A frame was not encoded", exception)
            false
        }
    }

    /// Encodes interleaved 32-bit float samples (little-endian bytes) starting at `timeUs`.
    fun appendAudio(samples: ByteArray, timeUs: Long): Boolean {
        val codec = audio ?: return false
        return try {
            val floats = ByteBuffer.wrap(samples).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
            val pcm = ShortArray(floats.remaining())
            for (index in pcm.indices) {
                pcm[index] = (floats.get(index).coerceIn(-1f, 1f) * 32767f).toInt().toShort()
            }
            val frameBytes = 2 * channels
            var offset = 0
            while (offset < pcm.size) {
                val index = dequeueInput(codec)
                val buffer = codec.getInputBuffer(index) ?: throw IllegalStateException("No audio buffer")
                buffer.clear()
                val frames = minOf((pcm.size - offset) / channels, buffer.capacity() / frameBytes)
                buffer.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().put(pcm, offset, frames * channels)
                val time = timeUs + (offset / channels).toLong() * 1_000_000L / sampleRate
                codec.queueInputBuffer(index, 0, frames * frameBytes, time, 0)
                offset += frames * channels
                drain(codec, false)
            }
            true
        } catch (exception: Exception) {
            fail("Audio was not encoded", exception)
            false
        }
    }

    /// Ends both streams and finishes the file.
    fun finish(): Boolean {
        return try {
            for (codec in listOfNotNull(video, audio)) {
                val index = dequeueInput(codec)
                codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            }
            var waited = 0
            while ((!videoDone || !audioDone) && waited < 2000) {
                video?.let { drain(it, true) }
                audio?.let { drain(it, true) }
                waited += 1
            }
            if (!muxerStarted) throw IllegalStateException("No media was written")
            muxer?.stop()
            if (BuildConfig.ARIA_VIDEO_AUDIT) {
                android.util.Log.i("AriaVideoAudit", "FINISH frames=$auditFrames seconds=${(android.os.SystemClock.elapsedRealtimeNanos() - auditStartedNs) / 1e9}")
            }
            release()
            videoDone && audioDone
        } catch (exception: Exception) {
            fail("The video did not finish", exception)
            release()
            false
        }
    }

    fun cancel() {
        release()
    }

    private fun release() {
        for (codec in listOfNotNull(video, audio)) {
            try { codec.stop() } catch (_: Exception) {}
            codec.release()
        }
        video = null
        audio = null
        try { muxer?.release() } catch (_: Exception) {}
        muxer = null
    }

    private fun fail(message: String, exception: Exception) {
        android.util.Log.e("Aria", message, exception)
        error = "$message: ${exception.message ?: exception.javaClass.simpleName}"
    }

    /// Waits for an input buffer, draining output meanwhile so the encoder never stalls.
    private fun dequeueInput(codec: MediaCodec): Int {
        repeat(1000) {
            val index = codec.dequeueInputBuffer(5_000)
            if (index >= 0) return index
            drain(codec, false)
        }
        throw IllegalStateException("The encoder stopped taking input")
    }

    private fun drain(codec: MediaCodec, waiting: Boolean) {
        val isVideo = codec === video
        val info = MediaCodec.BufferInfo()
        while (true) {
            val index = codec.dequeueOutputBuffer(info, if (waiting) 10_000 else 0)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> return
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val track = muxer!!.addTrack(codec.outputFormat)
                    if (isVideo) videoTrack = track else audioTrack = track
                    startMuxerIfReady()
                }
                index >= 0 -> {
                    val buffer = codec.getOutputBuffer(index)
                    val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (buffer != null && info.size > 0 && !isConfig) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        if (muxerStarted) {
                            muxer!!.writeSampleData(if (isVideo) videoTrack else audioTrack, buffer, info)
                        } else {
                            // The muxer starts once both tracks have formats.
                            val bytes = ByteArray(info.size)
                            buffer.get(bytes)
                            val copy = MediaCodec.BufferInfo()
                            copy.set(0, info.size, info.presentationTimeUs, info.flags)
                            pending.add(Triple(isVideo, bytes, copy))
                        }
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        if (isVideo) videoDone = true else audioDone = true
                        return
                    }
                }
            }
        }
    }

    private fun startMuxerIfReady() {
        val muxer = muxer ?: return
        if (muxerStarted || videoTrack < 0 || audioTrack < 0) return
        muxer.start()
        muxerStarted = true
        for ((isVideo, bytes, info) in pending) {
            muxer.writeSampleData(if (isVideo) videoTrack else audioTrack, ByteBuffer.wrap(bytes), info)
        }
        pending.clear()
    }

    /// The frame as YUV 4:2:0 (BT.601, limited range) in the encoder's image planes. Each
    /// plane is built in an array and copied in one go: per-byte puts cost ~100 ms a frame.
    private fun writeYuv(bitmap: Bitmap, image: android.media.Image) {
        val w = width
        val h = height
        if (argb.size != w * h) argb = IntArray(w * h)
        bitmap.getPixels(argb, 0, w, 0, 0, minOf(w, bitmap.width), minOf(h, bitmap.height))
        val planes = image.planes
        writePlane(0, planes[0].buffer, planes[0].rowStride, planes[0].pixelStride, w, h) { x, y ->
            val pixel = argb[y * w + x]
            val r = (pixel shr 16) and 0xFF
            val g = (pixel shr 8) and 0xFF
            val b = pixel and 0xFF
            ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
        }
        // Chroma from the average of each 2×2 block.
        val cw = w / 2
        val ch = h / 2
        if (chromaU.size != cw * ch) {
            chromaU = IntArray(cw * ch)
            chromaV = IntArray(cw * ch)
        }
        val u = chromaU
        val v = chromaV
        for (y in 0 until ch) {
            for (x in 0 until cw) {
                val top = (y * 2) * w + x * 2
                val a = argb[top]
                val b = argb[top + 1]
                val c = argb[top + w]
                val d = argb[top + w + 1]
                // Keep the original average-then-convert rounding exactly.
                val r = (((a shr 16) and 255) + ((b shr 16) and 255) +
                    ((c shr 16) and 255) + ((d shr 16) and 255)) shr 2
                val g = (((a shr 8) and 255) + ((b shr 8) and 255) +
                    ((c shr 8) and 255) + ((d shr 8) and 255)) shr 2
                val blue = ((a and 255) + (b and 255) + (c and 255) + (d and 255)) shr 2
                u[y * cw + x] = ((-38 * r - 74 * g + 112 * blue + 128) shr 8) + 128
                v[y * cw + x] = ((112 * r - 94 * g - 18 * blue + 128) shr 8) + 128
            }
        }
        val uPlane = planes[1]
        val vPlane = planes[2]
        if (uPlane.pixelStride == 2 && vPlane.pixelStride == 2 && uPlane.rowStride == vPlane.rowStride) {
            // Semi-planar: U and V interleaved in one buffer, NV12 (U first) or NV21.
            val uBuffer = uPlane.buffer
            val vBuffer = vPlane.buffer
            uBuffer.put(0, 1.toByte())
            vBuffer.put(0, 2.toByte())
            val uFirst = uBuffer.capacity() > 1 && uBuffer.get(1) == 2.toByte()
            val vFirst = vBuffer.capacity() > 1 && vBuffer.get(1) == 1.toByte()
            if (uFirst || vFirst) {
                val target = if (uFirst) uBuffer else vBuffer
                val first = if (uFirst) u else v
                val second = if (uFirst) v else u
                val row = uPlane.rowStride
                val bytes = scratchPlane(1, minOf(target.capacity(), row * (ch - 1) + cw * 2))
                for (y in 0 until ch) {
                    var out = y * row
                    for (x in 0 until cw) {
                        if (out < bytes.size) bytes[out] = first[y * cw + x].toByte()
                        if (out + 1 < bytes.size) bytes[out + 1] = second[y * cw + x].toByte()
                        out += 2
                    }
                }
                target.position(0)
                target.put(bytes)
                return
            }
        }
        writePlane(1, uPlane.buffer, uPlane.rowStride, uPlane.pixelStride, cw, ch) { x, y -> u[y * cw + x] }
        writePlane(2, vPlane.buffer, vPlane.rowStride, vPlane.pixelStride, cw, ch) { x, y -> v[y * cw + x] }
    }

    private fun scratchPlane(slot: Int, size: Int): ByteArray {
        if (planeBytes[slot].size != size) planeBytes[slot] = ByteArray(size)
        // Fresh arrays zeroed row padding too. Preserve that when reusing storage
        // across frames or codec layouts with the same capacity.
        return planeBytes[slot].also { it.fill(0) }
    }

    private inline fun writePlane(slot: Int, buffer: ByteBuffer, rowStride: Int, pixelStride: Int, w: Int, h: Int,
                                  value: (Int, Int) -> Int) {
        if (pixelStride == 1) {
            val bytes = scratchPlane(slot, minOf(buffer.capacity(), rowStride * (h - 1) + w))
            for (y in 0 until h) {
                val row = y * rowStride
                for (x in 0 until w) bytes[row + x] = value(x, y).toByte()
            }
            buffer.position(0)
            buffer.put(bytes)
        } else {
            for (y in 0 until h) for (x in 0 until w) {
                buffer.put(y * rowStride + x * pixelStride, value(x, y).toByte())
            }
        }
    }
}
