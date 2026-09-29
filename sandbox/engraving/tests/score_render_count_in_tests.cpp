// Checks the count-in Aria plays before playback: click count, beat numbers,
// length and audible clicks, on the score MuseScore's own count-in tests use
// (1/4 pickup in 4/4, then 4/4, then 3/8, at 120 BPM).
//
//   score_render_count_in_tests <count_in.mscx> <soundfont.sf2>

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "score_render_core.h"

namespace {

[[noreturn]] void fail(const std::string& message)
{
    throw std::runtime_error(message);
}

void expect(const bool condition, const std::string& message)
{
    if (!condition) {
        fail(message);
    }
}

bool nearlyEqual(const double lhs, const double rhs)
{
    return std::abs(lhs - rhs) < 0.002;
}

msr::render::PlaybackCountIn countIn(const msr::render::ScoreRenderSession& session,
                                     const std::string& soundFontPath,
                                     const double startTimeSeconds)
{
    msr::render::PlaybackCountIn output;
    std::string error;
    if (!session.playbackCountIn(soundFontPath, startTimeSeconds, output, error)) {
        fail("playbackCountIn failed: " + error);
    }
    return output;
}

void expectCountIn(const msr::render::PlaybackCountIn& output,
                   const std::vector<int>& beatNumbers,
                   const double beatSeconds,
                   const std::string& label)
{
    expect(output.clicks.size() == beatNumbers.size(),
           label + ": expected " + std::to_string(beatNumbers.size()) + " clicks, got " + std::to_string(output.clicks.size()));
    for (size_t index = 0; index < beatNumbers.size(); ++index) {
        const msr::render::PlaybackCountInClick& click = output.clicks[index];
        expect(click.beatNumber == beatNumbers[index],
               label + ": click " + std::to_string(index) + " is beat " + std::to_string(click.beatNumber)
               + ", expected " + std::to_string(beatNumbers[index]));
        expect(click.isDownbeat == (beatNumbers[index] == 1), label + ": downbeat flag mismatch");
        expect(nearlyEqual(click.timeSeconds, beatSeconds * static_cast<double>(index)),
               label + ": click " + std::to_string(index) + " at " + std::to_string(click.timeSeconds) + "s");
    }
    expect(nearlyEqual(output.durationSeconds, beatSeconds * static_cast<double>(beatNumbers.size())),
           label + ": duration " + std::to_string(output.durationSeconds) + "s");

    // Every click must sound, and the buffer must cover the whole count-in.
    const msr::render::PlaybackAudioData& audio = output.audio;
    expect(audio.channelCount == 2 && audio.sampleRate > 0, label + ": bad audio format");
    const size_t frameCount = audio.interleavedSamples.size() / 2;
    expect(static_cast<double>(frameCount) / audio.sampleRate >= output.durationSeconds, label + ": audio shorter than count-in");
    for (const msr::render::PlaybackCountInClick& click : output.clicks) {
        const size_t start = static_cast<size_t>(click.timeSeconds * audio.sampleRate);
        const size_t end = std::min(frameCount, start + static_cast<size_t>(0.05 * audio.sampleRate));
        float peak = 0.0f;
        for (size_t frame = start; frame < end; ++frame) {
            peak = std::max(peak, std::abs(audio.interleavedSamples[frame * 2]));
        }
        expect(peak > 0.01f, label + ": click at " + std::to_string(click.timeSeconds) + "s is silent");
    }
}

} // namespace

int main(int argc, char* argv[])
{
    if (argc != 3) {
        std::cerr << "usage: score_render_count_in_tests <count_in.mscx> <soundfont.sf2>" << std::endl;
        return 2;
    }

    try {
        std::string error;
        auto session = msr::render::ScoreRenderSession::open(argv[1], error);
        if (!session) {
            fail("open failed: " + error);
        }
        const std::string soundFontPath = argv[2];

        std::vector<msr::render::PlaybackMeasureRegion> regions;
        if (!session->playbackMeasureRegions(regions, error) || regions.size() < 3) {
            fail("measure regions unavailable: " + error);
        }
        for (const auto& region : regions) {
            expect(!region.measureEid.empty(), "measure region is missing its persistent EID");
        }
        const double quarter = 0.5;

        // A 1/4 pickup counts a full 4/4 bar, then leads into beat 4.
        expectCountIn(countIn(*session, soundFontPath, regions[0].startTimeSeconds), { 1, 2, 3, 4, 1, 2, 3 }, quarter, "pickup");
        // A full 4/4 bar counts one bar.
        expectCountIn(countIn(*session, soundFontPath, regions[1].startTimeSeconds), { 1, 2, 3, 4 }, quarter, "4/4 bar");
        // Resuming on beat 3 counts a bar, then beats 1 and 2.
        expectCountIn(countIn(*session, soundFontPath, regions[1].startTimeSeconds + 2 * quarter),
                      { 1, 2, 3, 4, 1, 2 }, quarter, "4/4 beat 3");
        // 3/8 at this tempo is counted in eighths.
        expectCountIn(countIn(*session, soundFontPath, regions[2].startTimeSeconds), { 1, 2, 3 }, quarter / 2, "3/8 bar");
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << std::endl;
        return 1;
    }

    std::cout << "score_render_count_in_tests: all passed" << std::endl;
    return 0;
}
