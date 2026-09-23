// Host-only tool for the MuseScore 4.7.5 round-trip check (see compat/README.md).
//
// Opens each score through the same ScoreRenderSession::open/saveToPath path the
// Aria app uses and writes the result to a new file, so the check exercises the
// exact serializer Aria ships.
//
//   score_render_resave <input> <output>
//   score_render_resave --manifest <file.tsv>   (one "input<TAB>output" per line)
//   score_render_resave --scan <input>...        (list the older-score repairs Aria
//                                                 would offer; changes nothing)
//   score_render_resave --repair <input> <output> (apply every offered repair, save)
//
// For every job it prints one line to stdout: "OK\t<input>" or
// "FAIL\t<input>\t<error>", flushed immediately so a driver can resume after a crash.

#include <fstream>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

#include "score_render_core.h"

namespace {

bool resave(const std::string& inputPath, const std::string& outputPath, std::string& errorMessage)
{
    std::unique_ptr<msr::render::ScoreRenderSession> session = msr::render::ScoreRenderSession::open(inputPath, errorMessage);
    if (!session) {
        if (errorMessage.empty()) {
            errorMessage = "open failed";
        }
        return false;
    }

    return session->saveToPath(outputPath, errorMessage);
}

std::string singleLine(std::string text)
{
    for (char& c : text) {
        if (c == '\n' || c == '\r' || c == '\t') {
            c = ' ';
        }
    }
    return text;
}

} // namespace

int scan(int argc, char* argv[])
{
    int failures = 0;
    for (int i = 2; i < argc; ++i) {
        std::string errorMessage;
        std::unique_ptr<msr::render::ScoreRenderSession> session = msr::render::ScoreRenderSession::open(argv[i], errorMessage);
        std::vector<msr::render::ScoreLegacyRepairIssue> issues;
        if (!session || !session->legacyRepairIssues(issues, errorMessage)) {
            ++failures;
            std::cout << "FAIL\t" << argv[i] << "\t" << singleLine(errorMessage) << std::endl;
            continue;
        }
        std::cout << "SCAN\t" << argv[i] << "\t" << issues.size() << " repair(s)" << std::endl;
        for (const auto& issue : issues) {
            std::cout << "  " << issue.kind << " | " << issue.location << " | measure " << issue.measureNumber
                      << " | " << issue.message << std::endl;
        }
    }
    return failures == 0 ? 0 : 1;
}

int repair(const std::string& inputPath, const std::string& outputPath)
{
    std::string errorMessage;
    std::unique_ptr<msr::render::ScoreRenderSession> session = msr::render::ScoreRenderSession::open(inputPath, errorMessage);
    std::vector<msr::render::ScoreLegacyRepairIssue> issues;
    if (!session || !session->legacyRepairIssues(issues, errorMessage)) {
        std::cout << "FAIL\t" << inputPath << "\t" << singleLine(errorMessage) << std::endl;
        return 1;
    }
    std::vector<int> indexes;
    for (const auto& issue : issues) {
        indexes.push_back(issue.index);
    }
    msr::render::ScoreEditState state;
    if (!indexes.empty() && !session->applyLegacyRepairs(indexes, state, errorMessage)) {
        std::cout << "FAIL\t" << inputPath << "\t" << singleLine(errorMessage) << std::endl;
        return 1;
    }
    if (!session->saveToPath(outputPath, errorMessage)) {
        std::cout << "FAIL\t" << inputPath << "\t" << singleLine(errorMessage) << std::endl;
        return 1;
    }
    std::cout << "REPAIRED\t" << inputPath << "\t" << indexes.size() << " repair(s)" << std::endl;
    return 0;
}

int main(int argc, char* argv[])
{
    if (argc >= 3 && std::string(argv[1]) == "--scan") {
        return scan(argc, argv);
    }
    if (argc == 4 && std::string(argv[1]) == "--repair") {
        return repair(argv[2], argv[3]);
    }

    std::vector<std::pair<std::string, std::string> > jobs;

    if (argc == 3 && std::string(argv[1]) == "--manifest") {
        std::ifstream manifest(argv[2]);
        if (!manifest) {
            std::cerr << "Cannot read manifest: " << argv[2] << std::endl;
            return 2;
        }
        std::string line;
        while (std::getline(manifest, line)) {
            const size_t tab = line.find('\t');
            if (tab == std::string::npos) {
                continue;
            }
            jobs.emplace_back(line.substr(0, tab), line.substr(tab + 1));
        }
    } else if (argc == 3) {
        jobs.emplace_back(argv[1], argv[2]);
    } else {
        std::cerr << "usage: score_render_resave <input> <output>\n"
                  << "       score_render_resave --manifest <file.tsv>" << std::endl;
        return 2;
    }

    int failures = 0;
    for (const auto& [inputPath, outputPath] : jobs) {
        std::string errorMessage;
        if (resave(inputPath, outputPath, errorMessage)) {
            std::cout << "OK\t" << inputPath << std::endl;
        } else {
            ++failures;
            std::cout << "FAIL\t" << inputPath << "\t" << singleLine(errorMessage) << std::endl;
        }
    }

    return failures == 0 ? 0 : 1;
}
