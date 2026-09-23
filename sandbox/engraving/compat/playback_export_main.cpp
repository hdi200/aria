// Host tool for comparing Aria playback MIDI with MuseScore Studio 4.7.5.
//
//   score_render_playback_export <input> <output.mid>
//   score_render_playback_export --manifest <file.tsv>
//
// A manifest has one input<TAB>output pair per line. Each completed job emits
// OK<TAB>input or FAIL<TAB>input<TAB>message so a driver can recover after a
// crash or timeout. This calls Aria's playback MIDI export API; in-app audio
// playback uses a separate rendering path.

#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

#include "score_render_core.h"

namespace {

std::string oneLine(std::string message)
{
    for (char& c : message) {
        if (c == '\n' || c == '\r' || c == '\t') {
            c = ' ';
        }
    }
    return message;
}

bool exportPlayback(const std::string& inputPath, const std::string& outputPath, std::string& error)
{
    auto session = msr::render::ScoreRenderSession::open(inputPath, error);
    if (!session) {
        if (error.empty()) {
            error = "open failed";
        }
        return false;
    }

    std::vector<std::uint8_t> midi;
    if (!session->playbackMIDIData(midi, error)) {
        return false;
    }
    if (midi.empty()) {
        error = "playback MIDI was empty";
        return false;
    }

    std::ofstream output(outputPath, std::ios::binary | std::ios::trunc);
    if (!output) {
        error = "cannot open MIDI output";
        return false;
    }
    output.write(reinterpret_cast<const char*>(midi.data()), static_cast<std::streamsize>(midi.size()));
    if (!output) {
        error = "cannot write MIDI output";
        return false;
    }
    return true;
}

} // namespace

int main(int argc, char* argv[])
{
    std::vector<std::pair<std::string, std::string>> jobs;
    if (argc == 3 && std::string(argv[1]) == "--manifest") {
        std::ifstream manifest(argv[2]);
        if (!manifest) {
            std::cerr << "Cannot read manifest: " << argv[2] << std::endl;
            return 2;
        }
        std::string line;
        while (std::getline(manifest, line)) {
            const size_t tab = line.find('\t');
            if (tab != std::string::npos) {
                jobs.emplace_back(line.substr(0, tab), line.substr(tab + 1));
            }
        }
    } else if (argc == 3) {
        jobs.emplace_back(argv[1], argv[2]);
    } else {
        std::cerr << "usage: score_render_playback_export <input> <output.mid>\n"
                  << "       score_render_playback_export --manifest <file.tsv>" << std::endl;
        return 2;
    }

    int failures = 0;
    for (const auto& [input, output] : jobs) {
        std::string error;
        if (exportPlayback(input, output, error)) {
            std::cout << "OK\t" << input << std::endl;
        } else {
            ++failures;
            std::cout << "FAIL\t" << input << "\t" << oneLine(error) << std::endl;
        }
    }
    return failures ? 1 : 0;
}
