// Android entry points to the shared render core (sandbox/engraving/score_render_core.h),
// called from Swift through C++ interop. AriaEngine (Aria/Sources/AriaEngine) is the
// Swift bridge on top: Android's counterpart to the iOS app's MuseScoreRenderCoreBridge.

#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "MSRZipArchive.hpp"
#include "score_render_core.h"

namespace aria {

// Names for template types Swift needs to create or read (Swift can only refer to C++
// template specializations through typedefs).
using Bytes = std::vector<std::uint8_t>;
using Floats = std::vector<float>;
using Ints = std::vector<int>;
using Strings = std::vector<std::string>;
using OptionalInt = std::optional<int>;
using PlaybackNotes = std::vector<msr::render::PlaybackNote>;
using PlaybackMeasureRegions = std::vector<msr::render::PlaybackMeasureRegion>;
using PlaybackBeatPoints = std::vector<msr::render::PlaybackBeatPoint>;
using LegacyRepairIssues = std::vector<msr::render::ScoreLegacyRepairIssue>;
using ScorePartInfos = std::vector<msr::render::ScorePartInfo>;
using Int64s = std::vector<std::int64_t>;

//! Starts the engine like iOS does: Qt's application lives on its own thread, which then
//! runs Qt's event loop (on iOS that is the main thread and its run loop). Engine calls can
//! then come from any one thread at a time. Blocks until the engine is ready; safe to call
//! repeatedly.
void startEngine();

//! Opens a score, or returns null and sets errorMessage. Close it with closeSession.
msr::render::ScoreRenderSession* openSession(const std::string& scorePath, std::string& errorMessage);
void closeSession(msr::render::ScoreRenderSession* session);

// msr::render::PlaybackReverb can be neither copied nor moved, so Swift cannot import it;
// it is handled through these functions instead.
void* makeReverb(double sampleRate);
void processReverb(void* reverb, float* interleavedStereo, int frameCount);
void resetReverb(void* reverb);
void destroyReverb(void* reverb);

inline OptionalInt someInt(int value) { return value; }
inline OptionalInt noInt() { return std::nullopt; }

inline void setPartMix(msr::render::PlaybackMix& mix, const std::string& partId, float volume, float pan, bool muted, bool solo)
{
    mix[partId] = { volume, pan, muted, solo };
}

//! Part stems of rendered audio, in key order.
inline Strings partSampleIds(const msr::render::PlaybackAudioData& audio)
{
    Strings ids;
    for (const auto& pair : audio.partSamples) {
        ids.push_back(pair.first);
    }
    return ids;
}

inline const float* partSampleData(const msr::render::PlaybackAudioData& audio, const std::string& partId, std::size_t& count)
{
    const auto it = audio.partSamples.find(partId);
    count = it == audio.partSamples.end() ? 0 : it->second.size();
    return count == 0 ? nullptr : it->second.data();
}

// Zip packages (MSCZ/MXL), read with the iOS app's MSRZipArchive (shared source).
inline bool zipOpen(msr::ZipArchive& archive, const std::uint8_t* bytes, std::size_t length, std::string& errorMessage)
{
    return archive.open(Bytes(bytes, bytes + length), errorMessage);
}

inline bool zipExtract(const msr::ZipArchive& archive, const std::string& path, Bytes& output, std::string& errorMessage)
{
    return archive.extract(path, output, errorMessage);
}

// Audio output (aria_audio_output.cpp): an AAudio stereo float stream with players that
// play scheduled buffers on their own sample timelines, which is what AVAudioEngine and
// AVAudioPlayerNode do for the iOS app. The AVFoundation stand-in in AndroidShims is
// built on these. Handles are opaque (the output holds a mutex, so Swift can't import it).

//! Monotonic clock in nanoseconds: the host time of play times.
std::int64_t hostTimeNanos();

//! Opens and starts the output, or returns null and sets errorMessage. sampleRate 0: the
//! device's rate.
void* audioOutputCreate(double sampleRate, int playerCount, std::string& errorMessage);
double audioOutputSampleRate(void* output);
void audioOutputDestroy(void* output);
bool audioOutputStart(void* output, std::string& errorMessage);
void audioOutputStop(void* output);
bool audioOutputIsRunning(void* output);
//! Main mix volume and balance (-1 left ... 1 right).
void audioOutputSetMaster(void* output, float volume, float pan);
//! Time from writing a frame to hearing it.
double audioOutputLatencySeconds(void* output);
double audioOutputBufferSeconds(void* output);
//! The largest output sample since the previous call.
float audioOutputTakePeak(void* output);

//! Queues planar stereo audio on a player's timeline at sampleTime, or after the
//! previous buffer when sampleTime is negative. id is reported by audioPlayerTakeFinished
//! once the buffer has been rendered, or dropped by audioPlayerStop.
void audioPlayerSchedule(void* output, int player, std::int64_t sampleTime, const float* left, const float* right,
                         int frameCount, std::int64_t id);
//! Starts or resumes the player's timeline at a host time (0: now).
void audioPlayerPlayAt(void* output, int player, std::int64_t hostTimeNanos);
//! Holds the timeline and the queue.
void audioPlayerPause(void* output, int player);
//! Clears the queue and puts the timeline back to 0.
void audioPlayerStop(void* output, int player);
bool audioPlayerIsPlaying(void* output, int player);
//! The timeline position as of the last render (negative before a delayed start).
std::int64_t audioPlayerSampleTime(void* output, int player);
void audioPlayerSetVolume(void* output, int player, float volume);
Int64s audioPlayerTakeFinished(void* output, int player);

//! A FluidSynth instrument played live into the output, like AVAudioUnitSampler (note
//! preview). Loading again with the same SoundFont only changes the program.
bool audioSamplerLoad(void* output, const std::string& soundFontPath, int bank, int program, std::string& errorMessage);
void audioSamplerNoteOn(void* output, int key, int velocity);
void audioSamplerNoteOff(void* output, int key);

//! Writes a line to the Android log (tag "AriaEngine").
void log(const char* message);

} // namespace aria
