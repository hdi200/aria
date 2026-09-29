// Mixed-only video audio must be sample-identical to normal stem playback.
#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <string>

#include "score_render_core.h"

namespace {
void expect(bool condition, const std::string& message)
{
    if (!condition) { throw std::runtime_error(message); }
}

void check(const std::string& scorePath, const std::string& soundFontPath, bool metronome, bool part)
{
    std::string error;
    auto withStems = msr::render::ScoreRenderSession::open(scorePath, error);
    expect(withStems != nullptr, "open stem session: " + error);
    auto mixedOnly = msr::render::ScoreRenderSession::open(scorePath, error);
    expect(mixedOnly != nullptr, "open mix session: " + error);
    if (part) {
        int pages = 0;
        expect(withStems->setActivePartIndex(0, pages, error), "select stem part: " + error);
        expect(mixedOnly->setActivePartIndex(0, pages, error), "select mix part: " + error);
    }

    double start = 0.0;
    bool audible = false;
    for (int chunk = 0; chunk < 3; ++chunk) {
        msr::render::PlaybackAudioData stems;
        msr::render::PlaybackAudioData mix;
        // Omitting the optional flag must preserve the playback/mixer contract.
        expect(withStems->playbackEventAudioData(soundFontPath, start, 1.0, metronome, stems, error), "stem render: " + error);
        // Reusing an output must clear old stems as well as avoid new allocations.
        mix.partSamples["stale"] = { 1.0f };
        expect(mixedOnly->playbackEventAudioData(soundFontPath, start, 1.0, metronome, mix, error, false), "mix render: " + error);
        expect(!stems.partSamples.empty(), "default playback omitted stems");
        expect(mix.partSamples.empty(), "mixed-only output contains stems");
        expect(mix.sampleRate == stems.sampleRate && mix.channelCount == stems.channelCount
               && mix.durationSeconds == stems.durationSeconds, "audio format differs");
        expect(mix.interleavedSamples == stems.interleavedSamples, "mixed PCM differs");
        audible = audible || std::any_of(mix.interleavedSamples.begin(), mix.interleavedSamples.end(), [](float s) { return s != 0.0f; });
        start += stems.durationSeconds;
    }
    expect(audible, "fixture rendered only silence");

    // Switching stem output on again must reuse the unchanged sequential stream.
    msr::render::PlaybackAudioData stems;
    msr::render::PlaybackAudioData switched;
    expect(withStems->playbackEventAudioData(soundFontPath, start, 0.4, metronome, stems, error), "stem continuation: " + error);
    expect(mixedOnly->playbackEventAudioData(soundFontPath, start, 0.4, metronome, switched, error), "switched continuation: " + error);
    expect(!switched.partSamples.empty() && switched.partSamples == stems.partSamples, "restored stems differ");
    expect(switched.interleavedSamples == stems.interleavedSamples, "mode switch changed mixed PCM");

    // Silent tails must not leak stems from an earlier render in a reused output.
    switched.partSamples["stale"] = { 1.0f };
    expect(mixedOnly->playbackEventAudioData(soundFontPath, 3600.0, 0.1, metronome, switched, error, false), "silent tail: " + error);
    expect(switched.partSamples.empty(), "silent tail retained stems");
}
}

int main(int argc, char* argv[])
{
    if (argc != 3) {
        std::cerr << "usage: score_render_audio_mix_tests <score.mscx> <soundfont.sf2>\n";
        return 2;
    }
    try {
        check(argv[1], argv[2], false, false);
        check(argv[1], argv[2], true, false);
        check(argv[1], argv[2], false, true);
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
    std::cout << "score_render_audio_mix_tests: all passed\n";
}
