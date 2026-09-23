// Host adapter for Aria's actual ScoreRenderSession MusicXML export path.
//
//   score_render_musicxml_export <input.mscz> <output.musicxml>
//   score_render_musicxml_export --manifest <file.tsv>
//
// The manifest contains one input<TAB>output pair per line. Every job emits
// OK<TAB>input or FAIL<TAB>input<TAB>message so a driver can resume after a
// single bad score without losing all completed exports.

#include <fstream>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

#include "score_render_core.h"

namespace {

bool exportMusicXml(const std::string& inputPath, const std::string& outputPath, std::string& errorMessage)
{
    std::unique_ptr<msr::render::ScoreRenderSession> session =
        msr::render::ScoreRenderSession::open(inputPath, errorMessage);
    if (!session) {
        if (errorMessage.empty()) {
            errorMessage = "open failed";
        }
        return false;
    }

    std::vector<std::uint8_t> data;
    if (!session->musicXMLData(data, errorMessage)) {
        return false;
    }
    if (data.empty()) {
        errorMessage = "MusicXML export was empty";
        return false;
    }

    std::ofstream output(outputPath, std::ios::binary | std::ios::trunc);
    if (!output) {
        errorMessage = "cannot create output";
        return false;
    }
    output.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
    if (!output) {
        errorMessage = "cannot write output";
        return false;
    }
    return true;
}

std::string singleLine(std::string message)
{
    for (char& c : message) {
        if (c == '\n' || c == '\r' || c == '\t') {
            c = ' ';
        }
    }
    return message;
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
            const std::size_t tab = line.find('\t');
            if (tab != std::string::npos) {
                jobs.emplace_back(line.substr(0, tab), line.substr(tab + 1));
            }
        }
    } else if (argc == 3) {
        jobs.emplace_back(argv[1], argv[2]);
    } else {
        std::cerr << "usage: score_render_musicxml_export <input> <output.musicxml>\n"
                  << "       score_render_musicxml_export --manifest <file.tsv>" << std::endl;
        return 2;
    }

    int failures = 0;
    for (const auto& [inputPath, outputPath] : jobs) {
        std::string errorMessage;
        if (exportMusicXml(inputPath, outputPath, errorMessage)) {
            std::cout << "OK\t" << inputPath << std::endl;
        } else {
            ++failures;
            std::cout << "FAIL\t" << inputPath << "\t" << singleLine(errorMessage) << std::endl;
        }
    }
    return failures == 0 ? 0 : 1;
}
