// Swing markings must swing playback, as desktop MuseScore does on open, in the
// full score, a part, and a transposed view. Bar 1 is marked Swing (8ths, 60%),
// bar 2 Straight, at quarter = 120.
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "score_render_core.h"

namespace {
void expect(bool condition, const std::string& message)
{
    if (!condition) { throw std::runtime_error(message); }
}

std::vector<double> startTimes(const msr::render::ScoreRenderSession& session, const int pitch)
{
    std::string error;
    std::vector<msr::render::PlaybackNote> notes;
    expect(session.playbackNotes(notes, error), "notes: " + error);
    std::vector<double> times;
    for (const auto& note : notes) {
        if (note.pitch == pitch) { times.push_back(note.startTimeSeconds); }
    }
    expect(times.size() == 8, "expected 8 notes at pitch " + std::to_string(pitch) + ", got " + std::to_string(times.size()));
    return times;
}

void expectEighths(const std::vector<double>& times, const double barStart, const double offbeat, const std::string& label)
{
    for (size_t i = 0; i < times.size(); ++i) {
        const double expected = barStart + static_cast<double>(i / 2) * 0.5 + (i % 2 ? offbeat : 0.0);
        expect(std::abs(times[i] - expected) < 0.005, label + ": eighth " + std::to_string(i) + " starts at "
               + std::to_string(times[i]) + "s, expected " + std::to_string(expected) + "s");
    }
}

void check(const msr::render::ScoreRenderSession& session, const std::string& label)
{
    expectEighths(startTimes(session, 72), 0.0, 0.30, label + " swing bar");
    expectEighths(startTimes(session, 74), 2.0, 0.25, label + " straight bar");
    std::cout << label << ": swung, then straight\n";
}
}

int main(int argc, char* argv[])
{
    if (argc != 2) {
        std::cerr << "usage: score_render_swing_tests <swing.mscx>\n";
        return 2;
    }
    try {
        std::string error;
        auto session = msr::render::ScoreRenderSession::open(argv[1], error);
        expect(session != nullptr, "open: " + error);
        check(*session, "full score");

        int pages = 0;
        expect(session->setActivePartIndex(0, pages, error), "part: " + error);
        check(*session, "part");

        // Transposing the view to D shifts the pitches up a whole step.
        expect(session->setActivePartIndex(std::nullopt, pages, error), "full score: " + error);
        expect(session->setViewTransposeKey(2, pages, error), "transpose: " + error);
        expectEighths(startTimes(*session, 74), 0.0, 0.30, "transposed swing bar");
        expectEighths(startTimes(*session, 76), 2.0, 0.25, "transposed straight bar");
        std::cout << "transposed view: swung, then straight\n";
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
    return 0;
}
