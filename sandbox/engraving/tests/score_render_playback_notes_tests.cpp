// Playback notes must follow the audio's timing, not MuseScore's MIDI export,
// which misplaces section-break pauses and tempos on repeats (goldberg).
#include <algorithm>
#include <cmath>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string>

#include "score_render_core.h"

namespace {
void expect(bool condition, const std::string& message)
{
    if (!condition) { throw std::runtime_error(message); }
}

void check(const std::string& scorePath, const int expectedStaves)
{
    std::string error;
    auto session = msr::render::ScoreRenderSession::open(scorePath, error);
    expect(session != nullptr, "open: " + error);
    std::vector<msr::render::PlaybackNote> notes;
    expect(session->playbackNotes(notes, error), "notes: " + error);
    std::vector<msr::render::PlaybackMeasureRegion> regions;
    expect(session->playbackMeasureRegions(regions, error), "regions: " + error);
    expect(!notes.empty() && !regions.empty(), "no notes or regions");

    std::set<int> staves;
    for (size_t i = 0; i < notes.size(); ++i) {
        const auto& note = notes[i];
        expect(note.endTimeSeconds > note.startTimeSeconds, "note ends before it starts");
        expect(note.pitch >= 0 && note.pitch <= 127, "pitch out of range");
        expect(i == 0 || notes[i - 1].startTimeSeconds <= note.startTimeSeconds, "notes not in start order");
        staves.insert(note.staffIndex);
    }
    expect(static_cast<int>(staves.size()) == expectedStaves
           && *staves.begin() == 0 && *staves.rbegin() == expectedStaves - 1, "staff numbering");

    // Measures start on notes, at the audio's times.
    size_t onNote = 0;
    for (const auto& region : regions) {
        const auto first = std::lower_bound(notes.begin(), notes.end(), region.startTimeSeconds - 0.001,
                                            [](const msr::render::PlaybackNote& note, double time) { return note.startTimeSeconds < time; });
        onNote += first != notes.end() && std::abs(first->startTimeSeconds - region.startTimeSeconds) < 0.001;
    }
    expect(onNote * 100 >= regions.size() * 90, "measures do not start on notes: "
           + std::to_string(onNote) + "/" + std::to_string(regions.size()));
    double lastEnd = 0.0;
    for (const auto& note : notes) { lastEnd = std::max(lastEnd, note.endTimeSeconds); }
    expect(std::abs(lastEnd - regions.back().endTimeSeconds) < 2.0, "notes end at "
           + std::to_string(lastEnd) + "s, playback at " + std::to_string(regions.back().endTimeSeconds) + "s");
    std::cout << scorePath << ": " << notes.size() << " notes, " << onNote << "/" << regions.size()
              << " measures start on a note\n";
}
}

int main(int argc, char* argv[])
{
    if (argc != 3) {
        std::cerr << "usage: score_render_playback_notes_tests <goldberg.mscz> <Amazing_grace.mscz>\n";
        return 2;
    }
    try {
        check(argv[1], 2);
        check(argv[2], 4);
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
    return 0;
}
