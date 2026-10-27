// The audio output declared in aria_engine.h: AAudio with AVAudioPlayerNode-like players.

#include "aria_engine.h"
#include "score_render_core.h"

#include <aaudio/AAudio.h>
#include <android/log.h>
#include <fluidsynth.h>
#include <time.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <deque>
#include <mutex>
#include <utility>

namespace {

struct ScheduledBuffer {
    std::int64_t start = 0;
    std::vector<float> left;
    std::vector<float> right;
    std::int64_t id = 0;

    std::int64_t end() const { return start + static_cast<std::int64_t>(left.size()); }
};

struct Player {
    enum class State { stopped, playing, paused };

    State state = State::stopped;
    //! Playing and past its start host time.
    bool started = false;
    std::int64_t startHostNanos = 0;
    std::int64_t sampleTime = 0;
    float volume = 1;
    std::deque<ScheduledBuffer> buffers;
    aria::Int64s finished;

    void finishAll()
    {
        for (const ScheduledBuffer& buffer : buffers) {
            finished.push_back(buffer.id);
        }
        buffers.clear();
    }

    void finishRendered()
    {
        while (!buffers.empty() && buffers.front().end() <= sampleTime) {
            finished.push_back(buffers.front().id);
            buffers.pop_front();
        }
    }
};

struct AudioOutput {
    AAudioStream* stream = nullptr;
    double sampleRate = 48000;
    std::mutex mutex;
    std::vector<Player> players;
    float masterVolume = 1;
    float masterPan = 0;
    float peak = 0;
    std::int64_t lastCallbackNanos = 0;
    std::int64_t framesWritten = 0;
    std::atomic<bool> running { false };

    // The live instrument (audioSamplerLoad). FluidSynth's own locking is compiled out
    // (see msr::render::fluidSynthLock), so note calls take `mutex` against the audio
    // callback, and sample loading also takes the process-wide FluidSynth lock.
    fluid_settings_t* synthSettings = nullptr;
    fluid_synth_t* synth = nullptr;
    std::string soundFontPath;
    std::vector<float> synthBlock;

    ~AudioOutput()
    {
        std::lock_guard<std::recursive_mutex> fluidLock(msr::render::fluidSynthLock());
        if (synth) {
            delete_fluid_synth(synth);
        }
        if (synthSettings) {
            delete_fluid_settings(synthSettings);
        }
    }
};

AudioOutput* outputFrom(void* handle)
{
    return static_cast<AudioOutput*>(handle);
}

Player* playerFrom(AudioOutput* output, int index)
{
    if (!output || index < 0 || index >= static_cast<int>(output->players.size())) {
        return nullptr;
    }
    return &output->players[index];
}

aaudio_data_callback_result_t renderAudio(AAudioStream*, void* userData, void* audioData, int32_t frameCount)
{
    auto* output = static_cast<AudioOutput*>(userData);
    auto* samples = static_cast<float*>(audioData);
    std::fill(samples, samples + frameCount * 2, 0.0f);
    const std::int64_t now = aria::hostTimeNanos();

    std::lock_guard<std::mutex> lock(output->mutex);
    for (Player& player : output->players) {
        if (player.state != Player::State::playing) {
            continue;
        }
        int32_t firstFrame = 0;
        if (!player.started) {
            const std::int64_t waitNanos = player.startHostNanos - now;
            const std::int64_t waitFrames = waitNanos <= 0 ? 0 : std::llround(waitNanos * output->sampleRate / 1e9);
            if (waitFrames >= frameCount) {
                continue;
            }
            firstFrame = static_cast<int32_t>(waitFrames);
            player.started = true;
        }
        for (int32_t frame = firstFrame; frame < frameCount; ++frame) {
            const std::int64_t time = player.sampleTime++;
            for (const ScheduledBuffer& buffer : player.buffers) {
                if (buffer.start > time) {
                    break;
                }
                const std::int64_t offset = time - buffer.start;
                if (offset < static_cast<std::int64_t>(buffer.left.size())) {
                    samples[frame * 2] += buffer.left[offset] * player.volume;
                    samples[frame * 2 + 1] += buffer.right[offset] * player.volume;
                }
            }
        }
        player.finishRendered();
    }

    // Never wait here: when a SoundFont load or a playback render block holds the
    // FluidSynth lock, the live synth skips this buffer and resumes on the next.
    std::unique_lock<std::recursive_mutex> fluidLock(msr::render::fluidSynthLock(), std::try_to_lock);
    if (output->synth && fluidLock.owns_lock()) {
        output->synthBlock.assign(static_cast<std::size_t>(frameCount) * 2, 0.0f);
        float* block = output->synthBlock.data();
        if (fluid_synth_write_float(output->synth, frameCount, block, 0, 2, block, 1, 2) == FLUID_OK) {
            for (int32_t index = 0; index < frameCount * 2; ++index) {
                samples[index] += block[index];
            }
        }
    }

    // Balance like AVAudioMixing: the centre keeps both channels, either side
    // attenuates the other one.
    const float pan = std::clamp(output->masterPan, -1.0f, 1.0f);
    const float leftGain = output->masterVolume * (pan > 0 ? 1 - pan : 1);
    const float rightGain = output->masterVolume * (pan < 0 ? 1 + pan : 1);
    float peak = output->peak;
    for (int32_t frame = 0; frame < frameCount; ++frame) {
        samples[frame * 2] *= leftGain;
        samples[frame * 2 + 1] *= rightGain;
        peak = std::max({ peak, std::fabs(samples[frame * 2]), std::fabs(samples[frame * 2 + 1]) });
    }
    output->peak = peak;
    output->lastCallbackNanos = now;
    output->framesWritten += frameCount;
    return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

void streamError(AAudioStream*, void*, aaudio_result_t error)
{
    __android_log_print(ANDROID_LOG_WARN, "AriaEngine", "audio output error: %s", AAudio_convertResultToText(error));
}

} // namespace

std::int64_t aria::hostTimeNanos()
{
    timespec time {};
    clock_gettime(CLOCK_MONOTONIC, &time);
    return static_cast<std::int64_t>(time.tv_sec) * 1000000000LL + time.tv_nsec;
}

void* aria::audioOutputCreate(double sampleRate, int playerCount, std::string& errorMessage)
{
    AAudioStreamBuilder* builder = nullptr;
    aaudio_result_t result = AAudio_createStreamBuilder(&builder);
    if (result != AAUDIO_OK) {
        errorMessage = AAudio_convertResultToText(result);
        return nullptr;
    }

    auto* output = new AudioOutput();
    output->players.resize(std::max(playerCount, 0));
    AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_FLOAT);
    AAudioStreamBuilder_setChannelCount(builder, 2);
    if (sampleRate > 0) {
        AAudioStreamBuilder_setSampleRate(builder, static_cast<int32_t>(std::lround(sampleRate)));
    }
    AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setUsage(builder, AAUDIO_USAGE_MEDIA);
    AAudioStreamBuilder_setContentType(builder, AAUDIO_CONTENT_TYPE_MUSIC);
    AAudioStreamBuilder_setDataCallback(builder, renderAudio, output);
    AAudioStreamBuilder_setErrorCallback(builder, streamError, output);
    result = AAudioStreamBuilder_openStream(builder, &output->stream);
    AAudioStreamBuilder_delete(builder);
    if (result != AAUDIO_OK) {
        errorMessage = AAudio_convertResultToText(result);
        delete output;
        return nullptr;
    }

    // The players' timelines run at the stream's rate; the renderer must match it.
    output->sampleRate = AAudioStream_getSampleRate(output->stream);
    if (sampleRate > 0 && std::lround(output->sampleRate) != std::lround(sampleRate)) {
        errorMessage = "The audio output runs at " + std::to_string(std::lround(output->sampleRate))
                       + " Hz instead of " + std::to_string(std::lround(sampleRate)) + " Hz.";
        AAudioStream_close(output->stream);
        delete output;
        return nullptr;
    }
    // Double buffering: low latency without glitches when the device is busy.
    AAudioStream_setBufferSizeInFrames(output->stream, AAudioStream_getFramesPerBurst(output->stream) * 2);
    if (!audioOutputStart(output, errorMessage)) {
        AAudioStream_close(output->stream);
        delete output;
        return nullptr;
    }
    return output;
}

double aria::audioOutputSampleRate(void* handle)
{
    return outputFrom(handle)->sampleRate;
}

void aria::audioOutputDestroy(void* handle)
{
    AudioOutput* output = outputFrom(handle);
    if (!output) {
        return;
    }
    AAudioStream_requestStop(output->stream);
    AAudioStream_close(output->stream);
    delete output;
}

bool aria::audioOutputStart(void* handle, std::string& errorMessage)
{
    AudioOutput* output = outputFrom(handle);
    if (output->running) {
        return true;
    }
    const aaudio_result_t result = AAudioStream_requestStart(output->stream);
    if (result != AAUDIO_OK) {
        errorMessage = AAudio_convertResultToText(result);
        return false;
    }
    output->running = true;
    return true;
}

void aria::audioOutputStop(void* handle)
{
    AudioOutput* output = outputFrom(handle);
    AAudioStream_requestStop(output->stream);
    output->running = false;
}

bool aria::audioOutputIsRunning(void* handle)
{
    return outputFrom(handle)->running;
}

void aria::audioOutputSetMaster(void* handle, float volume, float pan)
{
    AudioOutput* output = outputFrom(handle);
    std::lock_guard<std::mutex> lock(output->mutex);
    output->masterVolume = volume;
    output->masterPan = pan;
}

double aria::audioOutputLatencySeconds(void* handle)
{
    AudioOutput* output = outputFrom(handle);
    int64_t presentedFrame = 0;
    int64_t presentedNanos = 0;
    if (AAudioStream_getTimestamp(output->stream, CLOCK_MONOTONIC, &presentedFrame, &presentedNanos) == AAUDIO_OK) {
        const int64_t writtenFrames = AAudioStream_getFramesWritten(output->stream);
        const double latency = (writtenFrames - presentedFrame) / output->sampleRate
                               - (hostTimeNanos() - presentedNanos) / 1e9;
        if (latency > 0) {
            return latency;
        }
    }
    return audioOutputBufferSeconds(handle);
}

double aria::audioOutputBufferSeconds(void* handle)
{
    AudioOutput* output = outputFrom(handle);
    return AAudioStream_getBufferSizeInFrames(output->stream) / output->sampleRate;
}

float aria::audioOutputTakePeak(void* handle)
{
    AudioOutput* output = outputFrom(handle);
    std::lock_guard<std::mutex> lock(output->mutex);
    return std::exchange(output->peak, 0.0f);
}

void aria::audioPlayerSchedule(void* handle, int index, std::int64_t sampleTime, const float* left, const float* right,
                               int frameCount, std::int64_t id)
{
    AudioOutput* output = outputFrom(handle);
    ScheduledBuffer buffer;
    buffer.left.assign(left, left + std::max(frameCount, 0));
    buffer.right.assign(right, right + std::max(frameCount, 0));
    buffer.id = id;

    std::lock_guard<std::mutex> lock(output->mutex);
    Player* player = playerFrom(output, index);
    if (!player) {
        return;
    }
    if (sampleTime < 0) {
        sampleTime = player->buffers.empty() ? player->sampleTime : player->buffers.back().end();
    }
    buffer.start = sampleTime;
    const auto position = std::upper_bound(player->buffers.begin(), player->buffers.end(), sampleTime,
                                           [](std::int64_t time, const ScheduledBuffer& other) { return time < other.start; });
    player->buffers.insert(position, std::move(buffer));
}

void aria::audioPlayerPlayAt(void* handle, int index, std::int64_t hostTime)
{
    AudioOutput* output = outputFrom(handle);
    std::lock_guard<std::mutex> lock(output->mutex);
    if (Player* player = playerFrom(output, index); player && player->state != Player::State::playing) {
        player->state = Player::State::playing;
        player->started = false;
        player->startHostNanos = hostTime > 0 ? hostTime : hostTimeNanos();
    }
}

void aria::audioPlayerPause(void* handle, int index)
{
    AudioOutput* output = outputFrom(handle);
    std::lock_guard<std::mutex> lock(output->mutex);
    if (Player* player = playerFrom(output, index); player && player->state == Player::State::playing) {
        player->state = Player::State::paused;
        player->started = false;
    }
}

void aria::audioPlayerStop(void* handle, int index)
{
    AudioOutput* output = outputFrom(handle);
    std::lock_guard<std::mutex> lock(output->mutex);
    if (Player* player = playerFrom(output, index)) {
        player->state = Player::State::stopped;
        player->started = false;
        player->sampleTime = 0;
        player->finishAll();
    }
}

bool aria::audioPlayerIsPlaying(void* handle, int index)
{
    AudioOutput* output = outputFrom(handle);
    std::lock_guard<std::mutex> lock(output->mutex);
    const Player* player = playerFrom(output, index);
    return player && player->state == Player::State::playing;
}

std::int64_t aria::audioPlayerSampleTime(void* handle, int index)
{
    AudioOutput* output = outputFrom(handle);
    std::lock_guard<std::mutex> lock(output->mutex);
    const Player* player = playerFrom(output, index);
    if (!player) {
        return 0;
    }
    if (player->state == Player::State::playing && !player->started) {
        const std::int64_t waitNanos = std::max<std::int64_t>(player->startHostNanos - output->lastCallbackNanos, 0);
        return player->sampleTime - std::llround(waitNanos * output->sampleRate / 1e9);
    }
    return player->sampleTime;
}

void aria::audioPlayerSetVolume(void* handle, int index, float volume)
{
    AudioOutput* output = outputFrom(handle);
    std::lock_guard<std::mutex> lock(output->mutex);
    if (Player* player = playerFrom(output, index)) {
        player->volume = volume;
    }
}

aria::Int64s aria::audioPlayerTakeFinished(void* handle, int index)
{
    AudioOutput* output = outputFrom(handle);
    std::lock_guard<std::mutex> lock(output->mutex);
    Player* player = playerFrom(output, index);
    return player ? std::exchange(player->finished, {}) : Int64s {};
}

bool aria::audioSamplerLoad(void* handle, const std::string& soundFontPath, int bank, int program, std::string& errorMessage)
{
    AudioOutput* output = outputFrom(handle);
    std::lock_guard<std::recursive_mutex> fluidLock(msr::render::fluidSynthLock());
    if (!output->synth || output->soundFontPath != soundFontPath) {
        fluid_settings_t* settings = new_fluid_settings();
        if (!settings) {
            errorMessage = "FluidSynth could not allocate settings.";
            return false;
        }
        // As the render core sets up its synth (score_render_runtime.cpp), but live.
        fluid_settings_setnum(settings, "synth.sample-rate", output->sampleRate);
        fluid_settings_setnum(settings, "synth.gain", 1.0);
        fluid_settings_setint(settings, "synth.dynamic-sample-loading", 1);
        fluid_settings_setint(settings, "synth.threadsafe-api", 1);
        fluid_settings_setint(settings, "synth.lock-memory", 0);
        fluid_settings_setint(settings, "synth.reverb.active", 0);
        fluid_settings_setint(settings, "synth.chorus.active", 0);
        fluid_synth_t* synth = new_fluid_synth(settings);
        if (!synth || fluid_synth_sfload(synth, soundFontPath.c_str(), 1) == FLUID_FAILED) {
            errorMessage = synth ? "FluidSynth could not load the SoundFont." : "FluidSynth could not allocate the synthesizer.";
            if (synth) {
                delete_fluid_synth(synth);
            }
            delete_fluid_settings(settings);
            return false;
        }

        fluid_synth_t* oldSynth = nullptr;
        fluid_settings_t* oldSettings = nullptr;
        {
            std::lock_guard<std::mutex> lock(output->mutex);
            oldSynth = std::exchange(output->synth, synth);
            oldSettings = std::exchange(output->synthSettings, settings);
            output->soundFontPath = soundFontPath;
        }
        if (oldSynth) {
            delete_fluid_synth(oldSynth);
        }
        if (oldSettings) {
            delete_fluid_settings(oldSettings);
        }
    }
    std::lock_guard<std::mutex> lock(output->mutex);
    fluid_synth_bank_select(output->synth, 0, bank);
    fluid_synth_program_change(output->synth, 0, program);
    return true;
}

void aria::audioSamplerNoteOn(void* handle, int key, int velocity)
{
    AudioOutput* output = outputFrom(handle);
    std::lock_guard<std::mutex> lock(output->mutex);
    if (output->synth) {
        fluid_synth_noteon(output->synth, 0, key, velocity);
    }
}

void aria::audioSamplerNoteOff(void* handle, int key)
{
    AudioOutput* output = outputFrom(handle);
    std::lock_guard<std::mutex> lock(output->mutex);
    if (output->synth) {
        fluid_synth_noteoff(output->synth, 0, key);
    }
}
