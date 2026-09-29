#include "score_render_core.h"

#include <algorithm>
#include <vector>

#include "audio/common/audioutils.h"
#include "audio/engine/internal/fx/reverb/reverbprocessor.h"

namespace msr::render {
namespace {
// The reverb reconfigures its filters whenever the block size changes, so it
// always processes fixed blocks. Buffering one block lets callers pass any frame
// count, for 128 frames (2.7 ms at 48 kHz) of extra wet delay.
constexpr int kReverbBlockFrames = 128;
constexpr int kReverbChannels = 2;
}

struct PlaybackReverb::Impl {
    double sampleRate = 48000.0;
    std::unique_ptr<muse::audio::fx::ReverbProcessor> processor;
    std::vector<float> pendingInput;
    std::vector<float> processedOutput;

    void create()
    {
        // The same parameters desktop uses for its default reverb aux channel.
        muse::audio::AudioFxParams params;
        params.resourceMeta = muse::audio::makeReverbMeta();
        params.categories.insert(muse::audio::AudioFxCategory::FxReverb);
        params.chainOrder = 0;
        params.active = true;
        processor = std::make_unique<muse::audio::fx::ReverbProcessor>(params);

        muse::audio::OutputSpec spec;
        spec.sampleRate = static_cast<muse::audio::sample_rate_t>(sampleRate);
        spec.samplesPerChannel = kReverbBlockFrames;
        spec.audioChannelCount = kReverbChannels;
        processor->init(spec);

        pendingInput.clear();
        processedOutput.assign(kReverbBlockFrames * kReverbChannels, 0.0f);
    }
};

PlaybackReverb::PlaybackReverb(const double sampleRate)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->sampleRate = sampleRate;
    m_impl->create();
}

PlaybackReverb::~PlaybackReverb() = default;

void PlaybackReverb::process(float* interleavedStereo, const int frameCount)
{
    if (!interleavedStereo || frameCount <= 0) {
        return;
    }

    constexpr size_t blockSamples = kReverbBlockFrames * kReverbChannels;
    const size_t sampleCount = static_cast<size_t>(frameCount) * kReverbChannels;
    std::vector<float>& input = m_impl->pendingInput;
    std::vector<float>& output = m_impl->processedOutput;

    input.insert(input.end(), interleavedStereo, interleavedStereo + sampleCount);
    size_t processedSamples = 0;
    while (input.size() - processedSamples >= blockSamples) {
        float* block = input.data() + processedSamples;
        m_impl->processor->process(block, kReverbBlockFrames);
        output.insert(output.end(), block, block + blockSamples);
        processedSamples += blockSamples;
    }
    input.erase(input.begin(), input.begin() + static_cast<std::ptrdiff_t>(processedSamples));

    // The output always holds one block more than the pending input lacks, so
    // every requested frame is available.
    std::copy_n(output.begin(), sampleCount, interleavedStereo);
    output.erase(output.begin(), output.begin() + static_cast<std::ptrdiff_t>(sampleCount));
}

void PlaybackReverb::reset()
{
    m_impl->create();
}
} // namespace msr::render
