// Mixed-only video audio must be sample-identical to normal stem playback.
#include <algorithm>
#include <cmath>
#include <set>
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

void checkUserMix(const std::string& scorePath, const std::string& soundFontPath, int scenario, bool part)
{
    std::string error;
    auto reference = msr::render::ScoreRenderSession::open(scorePath, error);
    auto exported = msr::render::ScoreRenderSession::open(scorePath, error);
    expect(reference && exported, "open user mix sessions: " + error);
    if (part) {
        int pages = 0;
        expect(reference->setActivePartIndex(0, pages, error), "reference part: " + error);
        expect(exported->setActivePartIndex(0, pages, error), "export part: " + error);
    }
    msr::render::PlaybackMix settings;
    double start = 0;
    bool audible = false;
    for (int chunk = 0; chunk < 3; ++chunk) {
        msr::render::PlaybackAudioData stems, actual;
        expect(reference->playbackEventAudioData(soundFontPath, start, 1, false, stems, error), "reference audio: " + error);
        if (chunk == 0) {
            int index = 0;
            for (const auto& stem : stems.partSamples) {
                auto& setting = settings[stem.first];
                setting.volume = scenario == 0 ? 1.0f : 0.35f + 0.15f * (index % 3);
                setting.pan = scenario == 0 ? 0.0f : (index % 2 == 0 ? 0.6f : -0.4f);
                setting.muted = (scenario == 2 || scenario == 4) && index == 0;
                setting.solo = (scenario == 3 || scenario == 4) && index == 0;
                ++index;
            }
            // An instrument outside this target must not silence the target.
            settings["absent-part"].solo = true;
        }
        expect(exported->playbackMixedAudioData(soundFontPath, start, 1, false, actual, error, settings),
               "user mix audio: " + error);
        expect(actual.partSamples.empty(), "user mix allocated stems");
        expect(actual.interleavedSamples.size() == stems.interleavedSamples.size(), "user mix length changed");
        bool hasSolo = false;
        for (const auto& stem : stems.partSamples) { hasSolo = hasSolo || settings.at(stem.first).solo; }
        std::vector<float> expected(actual.interleavedSamples.size(), 0.0f);
        for (const auto& stem : stems.partSamples) {
            const auto& setting = settings.at(stem.first);
            const float volume = setting.muted || (hasSolo && !setting.solo) ? 0.0f : setting.volume;
            const float leftGain = volume * (setting.pan > 0 ? 1 - setting.pan : 1);
            const float rightGain = volume * (setting.pan < 0 ? 1 + setting.pan : 1);
            for (size_t sample = 0; sample < expected.size(); sample += 2) {
                expected[sample] += stem.second[sample] * leftGain;
                expected[sample + 1] += stem.second[sample + 1] * rightGain;
            }
        }
        for (size_t sample = 0; sample < expected.size(); ++sample) {
            expect(std::abs(expected[sample] - actual.interleavedSamples[sample]) < 0.000002f,
                   "user mix differs from stem playback, scenario " + std::to_string(scenario));
            audible = audible || std::abs(actual.interleavedSamples[sample]) > 0.00001f;
        }
        start += stems.durationSeconds;
    }
    if (scenario == 0 || scenario == 1 || scenario == 3) { expect(audible, "user mix expected audible output"); }
    // Returning to playback on the same stream must discard all export gains.
    msr::render::PlaybackAudioData normalReference, normalAfterExport;
    expect(reference->playbackEventAudioData(soundFontPath, start, 0.4, false, normalReference, error), "normal reference: " + error);
    expect(exported->playbackEventAudioData(soundFontPath, start, 0.4, false, normalAfterExport, error), "normal after export: " + error);
    expect(normalAfterExport.interleavedSamples == normalReference.interleavedSamples,
           "export settings leaked into normal mixed PCM");
    expect(normalAfterExport.partSamples == normalReference.partSamples,
           "export settings leaked into playback stems");
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
        for (int scenario = 0; scenario < 5; ++scenario) {
            checkUserMix(argv[1], argv[2], scenario, false);
            checkUserMix(argv[1], argv[2], scenario, true);
        }
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
    std::cout << "score_render_audio_mix_tests: all passed\n";
}
