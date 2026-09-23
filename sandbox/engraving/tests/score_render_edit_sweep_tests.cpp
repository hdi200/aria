#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

#include "score_render_core.h"

namespace {

struct LocatedItem {
    int pageIndex = 0;
    double x = 0.0;
    double y = 0.0;
    int midiPitch = -1;
    bool isNote = false;
    bool isRest = false;
};

struct TestDirectory {
    TestDirectory()
    {
        if (const char* requested = std::getenv("ARIA_EDIT_SWEEP_OUTPUT_DIR"); requested && *requested) {
            path = std::filesystem::absolute(requested);
            preserve = true;
            std::error_code error;
            std::filesystem::remove_all(path, error);
        } else {
            const auto nonce = std::chrono::steady_clock::now().time_since_epoch().count();
            path = std::filesystem::temp_directory_path() / ("score-render-edit-sweep-tests-" + std::to_string(nonce));
        }
        std::filesystem::create_directories(path / "roundtrip-artifacts");
    }

    ~TestDirectory()
    {
        if (!preserve) {
            std::error_code error;
            std::filesystem::remove_all(path, error);
        }
    }

    std::filesystem::path path;
    bool preserve = false;
};

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

std::string readFile(const std::filesystem::path& path)
{
    std::ifstream stream(path, std::ios::binary);
    expect(stream.good(), "Could not read " + path.string());
    return std::string(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
}

void writeFile(const std::filesystem::path& path, const std::string& contents)
{
    std::ofstream stream(path, std::ios::binary);
    expect(stream.good(), "Could not write " + path.string());
    stream << contents;
    expect(stream.good(), "Could not finish writing " + path.string());
}

size_t countOccurrences(const std::string& haystack, const std::string& needle)
{
    size_t count = 0;
    size_t offset = 0;
    while ((offset = haystack.find(needle, offset)) != std::string::npos) {
        ++count;
        offset += needle.size();
    }
    return count;
}

std::string twoInstrumentScoreXml()
{
    return R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <trackName>Violin</trackName>
      <Instrument id="violin">
        <longName>Violin</longName>
        <trackName>Violin</trackName>
        <instrumentId>strings.violin</instrumentId>
        <Channel><program value="40"/></Channel>
      </Instrument>
    </Part>
    <Part>
      <Staff id="2"/>
      <trackName>Violoncello</trackName>
      <Instrument id="cello">
        <longName>Violoncello</longName>
        <trackName>Violoncello</trackName>
        <instrumentId>strings.cello</instrumentId>
        <Channel><program value="42"/></Channel>
      </Instrument>
    </Part>
    <Staff id="1">
      <Measure>
        <voice>
          <KeySig><concertKey>0</concertKey></KeySig>
          <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
          <Clef><concertClefType>G</concertClefType></Clef>
          <Chord><durationType>quarter</durationType><Note><pitch>60</pitch><tpc>14</tpc></Note></Chord>
          <Chord><durationType>quarter</durationType><Note><pitch>62</pitch><tpc>16</tpc></Note></Chord>
          <Chord><durationType>quarter</durationType><Note><pitch>64</pitch><tpc>18</tpc></Note></Chord>
          <Chord><durationType>quarter</durationType><Note><pitch>65</pitch><tpc>13</tpc></Note></Chord>
        </voice>
      </Measure>
      <Measure>
        <voice>
          <Chord><durationType>quarter</durationType><Note><pitch>67</pitch><tpc>15</tpc></Note></Chord>
          <Rest><durationType>quarter</durationType></Rest>
          <Rest><durationType>half</durationType></Rest>
        </voice>
      </Measure>
      <Measure>
        <voice><Rest><durationType>measure</durationType><duration>4/4</duration></Rest></voice>
      </Measure>
    </Staff>
    <Staff id="2">
      <Measure>
        <voice>
          <KeySig><concertKey>0</concertKey></KeySig>
          <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
          <Clef><concertClefType>F</concertClefType></Clef>
          <Chord><durationType>whole</durationType><Note><pitch>48</pitch><tpc>14</tpc></Note></Chord>
        </voice>
      </Measure>
      <Measure>
        <voice><Rest><durationType>measure</durationType><duration>4/4</duration></Rest></voice>
      </Measure>
      <Measure>
        <voice><Rest><durationType>measure</durationType><duration>4/4</duration></Rest></voice>
      </Measure>
    </Staff>
  </Score>
</museScore>
)MSCX";
}

std::unique_ptr<msr::render::ScoreRenderSession> openSession(const std::filesystem::path& root,
                                                             const std::string& name)
{
    std::filesystem::create_directories(root);
    const std::filesystem::path path = root / (name + ".mscx");
    writeFile(path, twoInstrumentScoreXml());
    std::string error;
    auto session = msr::render::ScoreRenderSession::open(path.string(), error);
    expect(session != nullptr, "Could not open " + name + ": " + error);
    expect(session->supportsEditing(), name + " did not open as editable");
    return session;
}

void createLinkedParts(msr::render::ScoreRenderSession& session)
{
    int pageCount = 0;
    std::string error;
    expect(session.setActivePartIndex(0, pageCount, error), "Could not create violin part: " + error);
    expect(session.setActivePartIndex(1, pageCount, error), "Could not create cello part: " + error);
    expect(session.setActivePartIndex(std::nullopt, pageCount, error), "Could not return to full score: " + error);
}

std::vector<LocatedItem> scanScore(msr::render::ScoreRenderSession& session,
                                   const std::vector<int>& pitches,
                                   const size_t restCountWanted)
{
    std::vector<LocatedItem> found;
    std::string error;
    msr::render::ScoreEditState state;
    for (double y = 0.035; y <= 0.965; y += 0.0125) {
        for (double x = 0.035; x <= 0.965; x += 0.0125) {
            error.clear();
            expect(session.selectElement(0, x, y, 1.5, state, error), "Hit testing failed: " + error);
            const auto& selection = state.selection;
            const bool wantedNote = selection.isNote
                && std::find(pitches.begin(), pitches.end(), selection.midiPitch) != pitches.end();
            if (!wantedNote && !selection.isRest) {
                continue;
            }
            const LocatedItem item {
                selection.pageIndex,
                selection.normalizedX + selection.normalizedWidth * 0.5,
                selection.normalizedY + selection.normalizedHeight * 0.5,
                selection.midiPitch,
                selection.isNote,
                selection.isRest
            };
            const bool duplicate = std::any_of(found.begin(), found.end(), [&](const LocatedItem& prior) {
                return prior.pageIndex == item.pageIndex
                    && std::abs(prior.x - item.x) < 0.004
                    && std::abs(prior.y - item.y) < 0.004;
            });
            if (!duplicate) {
                found.push_back(item);
            }
            const bool havePitches = std::all_of(pitches.begin(), pitches.end(), [&](const int pitch) {
                return std::any_of(found.begin(), found.end(), [&](const LocatedItem& candidate) {
                    return candidate.isNote && candidate.midiPitch == pitch;
                });
            });
            const size_t rests = static_cast<size_t>(std::count_if(found.begin(), found.end(), [](const LocatedItem& candidate) {
                return candidate.isRest;
            }));
            if (havePitches && rests >= restCountWanted) {
                return found;
            }
        }
    }
    fail("Could not find requested notes/rests");
}

LocatedItem noteWithPitch(const std::vector<LocatedItem>& items, const int pitch)
{
    const auto found = std::find_if(items.begin(), items.end(), [&](const LocatedItem& item) {
        return item.isNote && item.midiPitch == pitch;
    });
    expect(found != items.end(), "Could not find MIDI pitch " + std::to_string(pitch));
    return *found;
}

LocatedItem firstRest(const std::vector<LocatedItem>& items)
{
    const auto found = std::find_if(items.begin(), items.end(), [](const LocatedItem& item) {
        return item.isRest;
    });
    expect(found != items.end(), "Could not find a rest");
    return *found;
}

void selectAt(msr::render::ScoreRenderSession& session, const LocatedItem& item)
{
    std::string error;
    msr::render::ScoreEditState state;
    expect(session.selectElement(item.pageIndex, item.x, item.y, 1.5, state, error), "Could not select item: " + error);
}

struct SavedState {
    std::string master;
    std::string masterStyle;
    std::vector<std::string> excerpts;
    std::vector<std::string> excerptStyles;
    std::filesystem::path artifactPath;
};

SavedState saveState(msr::render::ScoreRenderSession& session,
                     const std::filesystem::path& testRoot,
                     const std::filesystem::path& artifactRoot,
                     const std::string& name)
{
    std::string error;
    const std::filesystem::path folderPath = testRoot / (name + ".mscx");
    expect(session.saveToPath(folderPath.string(), error), "Could not save " + name + ": " + error);

    SavedState state;
    state.master = readFile(folderPath);
    const std::filesystem::path masterStylePath = testRoot / "score_style.mss";
    if (std::filesystem::exists(masterStylePath)) {
        state.masterStyle = readFile(masterStylePath);
    }
    const std::filesystem::path excerptsPath = testRoot / "Excerpts";
    if (std::filesystem::exists(excerptsPath)) {
        for (const auto& entry : std::filesystem::recursive_directory_iterator(excerptsPath)) {
            if (entry.path().extension() == ".mscx") {
                state.excerpts.push_back(readFile(entry.path()));
            } else if (entry.path().extension() == ".mss") {
                state.excerptStyles.push_back(readFile(entry.path()));
            }
        }
    }
    std::sort(state.excerpts.begin(), state.excerpts.end());
    std::sort(state.excerptStyles.begin(), state.excerptStyles.end());

    std::filesystem::create_directories(artifactRoot);
    const std::filesystem::path artifactPath = artifactRoot / (name + ".mscz");
    error.clear();
    expect(session.saveToPath(artifactPath.string(), error), "Could not save round-trip artifact " + name + ": " + error);
    state.artifactPath = artifactPath;
    return state;
}

std::string shellQuote(const std::string& value)
{
    std::string quoted = "'";
    for (const char ch : value) {
        if (ch == '\'') {
            quoted += "'\\''";
        } else {
            quoted += ch;
        }
    }
    quoted += "'";
    return quoted;
}

void expectPartcheckClean(const SavedState& baseline, const SavedState& target, const std::string& context)
{
    const std::filesystem::path script
        = std::filesystem::path(__FILE__).parent_path().parent_path() / "compat" / "partcheck.py";
    const std::string command = "python3 " + shellQuote(script.string())
        + " --fail-on-new " + shellQuote(baseline.artifactPath.string())
        + " " + shellQuote(target.artifactPath.string());
    expect(std::system(command.c_str()) == 0, context + ": partcheck.py found a new full-score/part mismatch");
}

std::string normalizedUndoXml(const std::string& xml)
{
    std::istringstream input(xml);
    std::ostringstream output;
    std::string line;
    while (std::getline(input, line)) {
        if (line.find("<eid>") != std::string::npos
            || line.find("<linkedTo>") != std::string::npos
            || line.find("<linkedMain>") != std::string::npos
            || line.find("<linked>") != std::string::npos) {
            continue;
        }
        output << line << '\n';
    }
    return output.str();
}

std::string normalizedExcerptUndoXml(const std::string& xml)
{
    // Inserting a pickup at tick zero makes MuseScore move the initial clef
    // into the inserted measure. Undo restores the staff's effective clef, but
    // an excerpt may omit the now-redundant explicit Clef element. MuseScore
    // 4.7.5 round-trips both forms identically, so compare the semantic excerpt
    // content while the master-score comparison above remains exact.
    std::istringstream input(normalizedUndoXml(xml));
    std::ostringstream output;
    std::string line;
    bool insideClef = false;
    while (std::getline(input, line)) {
        if (line.find("<Clef>") != std::string::npos) {
            insideClef = true;
        }
        if (!insideClef) {
            output << line << '\n';
        }
        if (insideClef && line.find("</Clef>") != std::string::npos) {
            insideClef = false;
        }
    }
    return output.str();
}

void expectUndoMatches(const SavedState& baseline, const SavedState& undone, const std::string& context)
{
    expect(normalizedUndoXml(undone.master) == normalizedUndoXml(baseline.master),
           context + ": undo did not restore the full score");
    expect(undone.masterStyle == baseline.masterStyle, context + ": undo did not restore the full-score style");
    expect(undone.excerpts.size() == baseline.excerpts.size(), context + ": undo changed the linked-part count");
    for (size_t index = 0; index < undone.excerpts.size(); ++index) {
        expect(normalizedExcerptUndoXml(undone.excerpts[index]) == normalizedExcerptUndoXml(baseline.excerpts[index]),
               context + ": undo did not restore linked part " + std::to_string(index));
    }
    expect(undone.excerptStyles == baseline.excerptStyles, context + ": undo did not restore linked-part styles");
}

void expectAllScoresContain(const SavedState& state, const std::string& needle, const std::string& context)
{
    expect(state.excerpts.size() == 2, context + ": expected two linked parts");
    expect(state.master.find(needle) != std::string::npos, context + ": full score is missing " + needle);
    for (size_t index = 0; index < state.excerpts.size(); ++index) {
        expect(state.excerpts[index].find(needle) != std::string::npos,
               context + ": linked part " + std::to_string(index) + " is missing " + needle);
    }
}

void expectNoScoreContains(const SavedState& state, const std::string& needle, const std::string& context)
{
    expect(state.master.find(needle) == std::string::npos, context + ": full score still contains " + needle);
    for (size_t index = 0; index < state.excerpts.size(); ++index) {
        expect(state.excerpts[index].find(needle) == std::string::npos,
               context + ": linked part " + std::to_string(index) + " still contains " + needle);
    }
}

using Mutation = std::function<bool(msr::render::ScoreRenderSession&,
                                    msr::render::ScoreEditState&,
                                    std::string&)>;

using Preparation = Mutation;

void runLinkedMutationCase(const std::filesystem::path& root,
                           const std::string& name,
                           const bool fromPart,
                           const Mutation& mutation,
                           const bool expectLinkedChange = true)
{
    const std::string view = fromPart ? "part" : "full";
    const std::string caseName = name + "-" + view;
    const std::filesystem::path testRoot = root / ("linked-sweep-" + caseName);
    auto session = openSession(testRoot, caseName + "-source");
    createLinkedParts(*session);
    const SavedState baseline = saveState(*session, testRoot, root / "roundtrip-artifacts", caseName + "-baseline");

    int pageCount = 0;
    std::string error;
    if (fromPart) {
        expect(session->setActivePartIndex(0, pageCount, error), caseName + ": could not activate violin part: " + error);
    }
    selectAt(*session, noteWithPitch(scanScore(*session, { 60 }, 0), 60));

    msr::render::ScoreEditState state;
    error.clear();
    expect(mutation(*session, state, error), caseName + ": command failed: " + error);
    if (fromPart) {
        expect(session->setActivePartIndex(std::nullopt, pageCount, error), caseName + ": could not return to full score: " + error);
    }

    const SavedState changed = saveState(*session, testRoot, root / "roundtrip-artifacts", caseName + "-changed");
    expect(normalizedUndoXml(changed.master) != normalizedUndoXml(baseline.master)
               || changed.masterStyle != baseline.masterStyle
               || changed.excerpts != baseline.excerpts
               || changed.excerptStyles != baseline.excerptStyles,
           caseName + ": command made no saved change");
    if (expectLinkedChange) {
        expectPartcheckClean(baseline, changed, caseName);
    }

    error.clear();
    expect(session->undo(state, error), caseName + ": undo failed: " + error);
    const SavedState undone = saveState(*session, testRoot, root / "roundtrip-artifacts", caseName + "-undone");
    expectUndoMatches(baseline, undone, caseName);
    expectPartcheckClean(baseline, undone, caseName + " undo");
}

void runPreparedMutationCase(const std::filesystem::path& root,
                             const std::string& name,
                             const bool fromPart,
                             const Preparation& prepare,
                             const Mutation& mutation,
                             const bool expectLinkedChange = true)
{
    const std::string view = fromPart ? "part" : "full";
    const std::string caseName = name + "-" + view;
    const std::filesystem::path testRoot = root / ("prepared-sweep-" + caseName);
    auto session = openSession(testRoot, caseName + "-source");
    createLinkedParts(*session);

    int pageCount = 0;
    std::string error;
    if (fromPart) {
        expect(session->setActivePartIndex(0, pageCount, error), caseName + ": could not activate violin part: " + error);
    }
    selectAt(*session, noteWithPitch(scanScore(*session, { 60 }, 0), 60));

    msr::render::ScoreEditState state;
    expect(prepare(*session, state, error), caseName + ": preparation failed: " + error);
    const SavedState baseline = saveState(*session, testRoot, root / "roundtrip-artifacts", caseName + "-baseline");

    error.clear();
    expect(mutation(*session, state, error), caseName + ": command failed: " + error);
    if (fromPart) {
        expect(session->setActivePartIndex(std::nullopt, pageCount, error), caseName + ": could not return to full score: " + error);
    }

    const SavedState changed = saveState(*session, testRoot, root / "roundtrip-artifacts", caseName + "-changed");
    expect(normalizedUndoXml(changed.master) != normalizedUndoXml(baseline.master)
               || changed.masterStyle != baseline.masterStyle
               || changed.excerpts != baseline.excerpts
               || changed.excerptStyles != baseline.excerptStyles,
           caseName + ": command made no saved change");
    if (expectLinkedChange) {
        expectPartcheckClean(baseline, changed, caseName);
    }

    error.clear();
    expect(session->undo(state, error), caseName + ": undo failed: " + error);
    const SavedState undone = saveState(*session, testRoot, root / "roundtrip-artifacts", caseName + "-undone");
    expectUndoMatches(baseline, undone, caseName);
    expectPartcheckClean(baseline, undone, caseName + " undo");
}

void testCoreNotationMutationSweep(const std::filesystem::path& root)
{
    const std::vector<std::pair<std::string, Mutation>> cases = {
        { "duration", [](auto& session, auto& state, auto& error) { return session.applyDuration(8, state, error); } },
        { "voice", [](auto& session, auto& state, auto& error) { return session.setCurrentVoice(1, state, error); } },
        { "dot", [](auto& session, auto& state, auto& error) { return session.toggleDot(state, error); } },
        { "rest", [](auto& session, auto& state, auto& error) { return session.toggleRest(state, error); } },
        { "tie", [](auto& session, auto& state, auto& error) { return session.toggleTie(state, error); } },
        { "tuplet", [](auto& session, auto& state, auto& error) { return session.addTuplet(3, state, error); } },
        { "staff-text", [](auto& session, auto& state, auto& error) { return session.addText("staff", state, error); } },
        { "system-text", [](auto& session, auto& state, auto& error) { return session.addText("system", state, error); } },
        { "rehearsal-mark", [](auto& session, auto& state, auto& error) { return session.addText("rehearsal", state, error); } },
        { "chord-symbol", [](auto& session, auto& state, auto& error) { return session.addText("chord", state, error); } },
        { "lyrics", [](auto& session, auto& state, auto& error) { return session.addLyricsText("la", false, state, error); } },
        { "lyrics-advance", [](auto& session, auto& state, auto& error) { return session.addLyricsText("la", true, state, error); } },
        { "dynamic", [](auto& session, auto& state, auto& error) { return session.addExpression("mf", state, error); } },
        { "articulation", [](auto& session, auto& state, auto& error) { return session.addExpression("accent", state, error); } },
        { "marcato", [](auto& session, auto& state, auto& error) { return session.addExpression("marcato", state, error); } },
        { "tenuto", [](auto& session, auto& state, auto& error) { return session.addExpression("tenuto", state, error); } },
        { "staccato", [](auto& session, auto& state, auto& error) { return session.addExpression("staccato", state, error); } },
        { "up-bow", [](auto& session, auto& state, auto& error) { return session.addExpression("upbow", state, error); } },
        { "down-bow", [](auto& session, auto& state, auto& error) { return session.addExpression("downbow", state, error); } },
        { "crescendo", [](auto& session, auto& state, auto& error) { return session.addExpression("crescendo", state, error); } },
        { "decrescendo", [](auto& session, auto& state, auto& error) { return session.addExpression("decrescendo", state, error); } },
        { "pedal", [](auto& session, auto& state, auto& error) { return session.addExpression("pedal", state, error); } },
        { "laissez-vibrer", [](auto& session, auto& state, auto& error) { return session.addExpression("lv", state, error); } },
        { "ottava-up", [](auto& session, auto& state, auto& error) { return session.addExpression("8va", state, error); } },
        { "ottava-down", [](auto& session, auto& state, auto& error) { return session.addExpression("8vb", state, error); } },
        { "slur", [](auto& session, auto& state, auto& error) { return session.addExpression("slur", state, error); } },
        { "start-repeat", [](auto& session, auto& state, auto& error) { return session.addRepeatJump("startrepeat", state, error); } },
        { "end-repeat", [](auto& session, auto& state, auto& error) { return session.addRepeatJump("endrepeat", state, error); } },
        { "coda", [](auto& session, auto& state, auto& error) { return session.addRepeatJump("coda", state, error); } },
        { "segno", [](auto& session, auto& state, auto& error) { return session.addRepeatJump("segno", state, error); } },
        { "to-coda", [](auto& session, auto& state, auto& error) { return session.addRepeatJump("tocoda", state, error); } },
        { "jump", [](auto& session, auto& state, auto& error) { return session.addRepeatJump("dsalcoda", state, error); } },
        { "jump-fine", [](auto& session, auto& state, auto& error) { return session.addRepeatJump("dsalfine", state, error); } },
        { "volta", [](auto& session, auto& state, auto& error) { return session.addRepeatJump("firstending", state, error); } },
        { "second-volta", [](auto& session, auto& state, auto& error) { return session.addRepeatJump("secondending", state, error); } },
        { "system-break", [](auto& session, auto& state, auto& error) { return session.addLayoutBreak("system", state, error); } },
        { "page-break", [](auto& session, auto& state, auto& error) { return session.addLayoutBreak("page", state, error); } },
        { "no-break", [](auto& session, auto& state, auto& error) { return session.addLayoutBreak("nobreak", state, error); } },
        { "auto-system-breaks", [](auto& session, auto& state, auto& error) {
             return session.applyAutoSystemBreaks(2, false, false, state, error);
         } },
        { "staff-spacing", [](auto& session, auto& state, auto& error) {
             return session.updateStaffSpacing(8.0, state, error);
         } },
        { "page-layout", [](auto& session, auto& state, auto& error) {
             return session.updatePageLayout(210.0, 297.0, 12.0, 1.8, 8.0, 10.0, state, error);
         } },
        { "layout-options", [](auto& session, auto& state, auto& error) {
             return session.updateLayoutOptions(true, true, state, error);
         } },
        { "time-signature", [](auto& session, auto& state, auto& error) {
             return session.updateTimeSignature(3, 4, false, false, false, state, error);
         } },
        { "key-signature", [](auto& session, auto& state, auto& error) {
             return session.updateKeySignature(2, false, state, error);
         } },
        { "accidental", [](auto& session, auto& state, auto& error) {
             return session.changeSelectionAccidental(1, state, error);
         } },
        { "semitone", [](auto& session, auto& state, auto& error) {
             return session.shiftSelectionPitchBySemitones(1, state, error);
         } },
        { "octave", [](auto& session, auto& state, auto& error) {
             return session.shiftSelectionPitchByOctaves(1, state, error);
         } },
        { "enharmonic", [](auto& session, auto& state, auto& error) {
             return session.changeSelectionEnharmonicSpelling(state, error);
         } },
        { "pitch-class", [](auto& session, auto& state, auto& error) {
             return session.setSelectionPitchClass(1, false, state, error);
         } },
        { "midi-pitch", [](auto& session, auto& state, auto& error) {
             return session.setSelectionMIDIPitch(61, false, state, error);
         } },
        { "move-pitch", [](auto& session, auto& state, auto& error) {
             return session.moveSelectionPitch(true, state, error);
         } },
        { "page-position-pitch", [](auto& session, auto& state, auto& error) {
             msr::render::ScoreEditState current;
             if (!session.currentEditState(current, error)) {
                 return false;
             }
             return session.setSelectionPitchAtPagePosition(
                 current.selection.pageIndex,
                 current.selection.actionNormalizedX,
                 std::max(0.01, current.selection.actionNormalizedY - 0.025),
                 state,
                 error
             );
         } },
        { "stem", [](auto& session, auto& state, auto& error) {
             return session.flipSelectionStemDirection(state, error);
         } },
        { "clef", [](auto& session, auto& state, auto& error) {
             return session.changeClef("bass", state, error);
         } },
        { "add-measure", [](auto& session, auto& state, auto& error) {
             return session.addMeasures(1, state, error);
         } },
        { "reset-template-measures", [](auto& session, auto& state, auto& error) {
             return session.resetTemplateMeasures(2, state, error);
         } },
        { "regular-measure-count", [](auto& session, auto& state, auto& error) {
             return session.setRegularMeasureCount(4, state, error);
         } },
        { "set-pickup", [](auto& session, auto& state, auto& error) {
             return session.setFirstMeasurePickup(1, 4, state, error);
         } },
        { "create-pickup", [](auto& session, auto& state, auto& error) {
             return session.createFirstPickupMeasure(1, 4, state, error);
         } },
        { "transpose-score", [](auto& session, auto& state, auto& error) {
             return session.transposeScore(1, 0, 1, 0, state, error);
         } },
        { "replace-part-instrument", [](auto& session, auto& state, auto& error) {
             const auto parts = session.partInfoList();
             return !parts.empty() && session.replacePartInstrument(parts.front().partId, "flute", state, error);
         } },
        { "add-instrument", [](auto& session, auto& state, auto& error) {
             return session.addInstrument("flute", state, error);
         } },
        { "remove-instrument-index", [](auto& session, auto& state, auto& error) {
             return session.removeInstrumentAtIndex(1, state, error);
         } },
        { "remove-selected-instrument", [](auto& session, auto& state, auto& error) {
             return session.removeSelectedInstrument(state, error);
         } },
        { "move-instrument", [](auto& session, auto& state, auto& error) {
             return session.moveInstrument(0, 2, state, error);
         } },
        { "hide-instrument", [](auto& session, auto& state, auto& error) {
             return session.setInstrumentVisible(1, false, state, error);
         } },
        { "metadata", [](auto& session, auto& state, auto& error) {
             msr::render::ScoreMetadata metadata;
             metadata.title = "Aria sweep";
             metadata.subtitle = "Linked parts";
             metadata.composer = "Test Composer";
             metadata.lyricist = "Test Lyricist";
             metadata.arranger = "Test Arranger";
             return session.updateMetadata(metadata, error) && session.currentEditState(state, error);
         } },
        { "initial-key", [](auto& session, auto& state, auto& error) {
             return session.updateInitialKeySignature(-2, error) && session.currentEditState(state, error);
         } },
        { "concert-pitch", [](auto& session, auto& state, auto& error) {
             int pageCount = 0;
             return session.setConcertPitchEnabled(!session.concertPitchEnabled(), pageCount, error)
                 && session.currentEditState(state, error);
         } },
        { "delete", [](auto& session, auto& state, auto& error) {
             return session.deleteSelection(state, error);
         } },
    };

    for (const auto& [name, mutation] : cases) {
        const bool layoutStructureIsViewLocal = name == "layout-options";
        runLinkedMutationCase(root, name, false, mutation, !layoutStructureIsViewLocal);
        // Stem direction is an appearance property in MuseScore: changing it
        // from a part intentionally unlinks that part's appearance while the
        // full-score command continues to update linked views.
        const bool viewLocalChange = name == "stem" || name == "layout-options";
        runLinkedMutationCase(root, name, true, mutation, !viewLocalChange);
    }
}

void testPreparedTextLyricsAndLayoutEdits(const std::filesystem::path& root)
{
    const Preparation addStaffText = [](auto& session, auto& state, auto& error) {
        return session.addText("staff", state, error);
    };
    const Preparation addAndReselectChordText = [](auto& session, auto& state, auto& error) {
        if (!session.addText("chord", state, error)) {
            return false;
        }
        selectAt(session, noteWithPitch(scanScore(session, { 60 }, 0), 60));
        return session.selectAttachedChordText(state, error);
    };
    const Preparation addAndReselectLyrics = [](auto& session, auto& state, auto& error) {
        if (!session.addLyricsText("la", false, state, error)) {
            return false;
        }
        selectAt(session, noteWithPitch(scanScore(session, { 60 }, 0), 60));
        return session.selectAttachedLyrics(state, error);
    };
    const Preparation addLyrics = [](auto& session, auto& state, auto& error) {
        return session.addLyricsText("la", false, state, error);
    };
    const Preparation addSystemBreak = [](auto& session, auto& state, auto& error) {
        return session.addLayoutBreak("system", state, error);
    };

    for (const bool fromPart : { false, true }) {
        runPreparedMutationCase(root, "edit-staff-text", fromPart, addStaffText,
                                [](auto& session, auto& state, auto& error) {
                                    return session.setSelectedText("Edited Staff Text", state, error);
                                });
        runPreparedMutationCase(root, "edit-chord-text", fromPart, addAndReselectChordText,
                                [](auto& session, auto& state, auto& error) {
                                    return session.setSelectedText("Dm7", state, error);
                                });
        runPreparedMutationCase(root, "edit-lyrics", fromPart, addAndReselectLyrics,
                                [](auto& session, auto& state, auto& error) {
                                    return session.setSelectedText("do", state, error);
                                });
        runPreparedMutationCase(root, "lyrics-melisma", fromPart, addLyrics,
                                [](auto& session, auto& state, auto& error) {
                                    return session.addLyricsMelisma("la", state, error);
                                });
        // Layout breaks are intentionally local to the active score/part view.
        runPreparedMutationCase(root, "remove-layout-break", fromPart, addSystemBreak,
                                [](auto& session, auto& state, auto& error) {
                                    return session.removeLayoutBreak(state, error);
                                }, false);
    }
}

bool selectFirstTwoMeasureRange(msr::render::ScoreRenderSession& session,
                                msr::render::ScoreEditState& state,
                                std::string& error)
{
    const auto items = scanScore(session, { 60, 67 }, 0);
    const LocatedItem start = noteWithPitch(items, 60);
    const LocatedItem end = noteWithPitch(items, 67);
    if (!session.previewMeasureRange(start.pageIndex, start.x, start.y, end.x, end.y, state, error)) {
        return false;
    }
    return session.selectMeasureRange(start.pageIndex, start.x, start.y, end.x, end.y, state, error);
}

void testRangeMeasureAndClipboardEdits(const std::filesystem::path& root)
{
    const Preparation selectRange = [](auto& session, auto& state, auto& error) {
        return selectFirstTwoMeasureRange(session, state, error);
    };
    const std::vector<std::pair<std::string, Mutation>> cases = {
        { "slash-fill", [](auto& session, auto& state, auto& error) {
             return session.fillSelectionWithSlashes(state, error);
         } },
        { "rhythmic-slashes", [](auto& session, auto& state, auto& error) {
             return session.replaceSelectionWithRhythmicSlashes(state, error);
         } },
        { "clear-measures", [](auto& session, auto& state, auto& error) {
             return session.clearSelectedMeasure(state, error);
         } },
        { "remove-measures", [](auto& session, auto& state, auto& error) {
             return session.removeSelectedMeasure(state, error);
         } },
        { "cut-measures", [](auto& session, auto& state, auto& error) {
             return session.cutSelectedMeasureRange(state, error);
         } },
        { "transpose-measures", [](auto& session, auto& state, auto& error) {
             return session.transposeSelectedMeasureRange(1, 0, 1, 0, state, error);
         } },
    };

    for (const auto& [name, mutation] : cases) {
        for (const bool fromPart : { false, true }) {
            const bool rhythmicAppearanceIsViewLocal = fromPart && name == "rhythmic-slashes";
            runPreparedMutationCase(root, name, fromPart, selectRange, mutation, !rhythmicAppearanceIsViewLocal);
        }
    }

    const Preparation copyThenSelectDestination = [](auto& session, auto& state, auto& error) {
        const auto items = scanScore(session, { 60, 65, 67 }, 0);
        const LocatedItem start = noteWithPitch(items, 60);
        const LocatedItem end = noteWithPitch(items, 65);
        if (!session.selectMeasureRange(start.pageIndex, start.x, start.y, end.x, end.y, state, error)
            || !session.copySelectedMeasureRange(state, error)) {
            return false;
        }
        selectAt(session, noteWithPitch(items, 67));
        return true;
    };
    for (const bool fromPart : { false, true }) {
        runPreparedMutationCase(root, "paste-measures", fromPart, copyThenSelectDestination,
                                [](auto& session, auto& state, auto& error) {
                                    return session.pasteMeasureRange(state, error);
                                });
    }
}

void testPointAndCursorEntryEdits(const std::filesystem::path& root)
{
    for (const bool fromPart : { false, true }) {
        for (const std::string command : { "point-note", "point-accidental", "point-pitch-class" }) {
            LocatedItem target;
            LocatedItem pitchReference;
            const Preparation preparePointEntry = [&](auto& session, auto& state, auto& error) {
                const auto items = scanScore(session, { 65 }, 1);
                target = firstRest(items);
                pitchReference = noteWithPitch(items, 65);
                selectAt(session, target);
                if (!session.setNoteInputEnabled(true, state, error)
                    || !session.applyDuration(4, state, error)) {
                    return false;
                }
                msr::render::NoteEntryPreviewState preview;
                return session.noteEntryPreview(
                    target.pageIndex,
                    target.x,
                    pitchReference.y,
                    4,
                    false,
                    command == "point-accidental" ? 1 : 0,
                    preview,
                    error
                ) && preview.hasPreview;
            };
            const Mutation insertPoint = [&](auto& session, auto& state, auto& error) {
                if (command == "point-accidental") {
                    return session.insertNoteWithAccidental(target.pageIndex, target.x, pitchReference.y, 1, state, error);
                }
                if (command == "point-pitch-class") {
                    return session.insertNoteWithPitch(target.pageIndex, target.x, pitchReference.y, 11, false, state, error);
                }
                return session.insertNote(target.pageIndex, target.x, pitchReference.y, state, error);
            };
            runPreparedMutationCase(root, command, fromPart, preparePointEntry, insertPoint);
        }

        const Preparation prepareCursor = [](auto& session, auto& state, auto& error) {
            return session.setNoteInputEnabled(true, state, error)
                && session.applyDuration(4, state, error)
                && session.setCurrentVoice(0, state, error);
        };
        runPreparedMutationCase(root, "cursor-rest", fromPart, prepareCursor,
                                [](auto& session, auto& state, auto& error) {
                                    return session.enterRestAtCursor(state, error);
                                });
        runPreparedMutationCase(root, "cursor-pitch-class", fromPart, prepareCursor,
                                [](auto& session, auto& state, auto& error) {
                                    return session.insertPitchAtCursor(11, false, false, state, error);
                                });
        runPreparedMutationCase(root, "cursor-midi-pitch", fromPart, prepareCursor,
                                [](auto& session, auto& state, auto& error) {
                                    return session.insertMIDIPitchAtCursor(73, false, false, state, error);
                                });

        const Preparation prepareMIDIChord = [](auto& session, auto& state, auto& error) {
            return session.setNoteInputEnabled(true, state, error)
                && session.applyDuration(4, state, error)
                && session.insertMIDIChordAtCursor({ 72, 76 }, false, state, error);
        };
        runPreparedMutationCase(root, "remove-midi-chord-pitch", fromPart, prepareMIDIChord,
                                [](auto& session, auto& state, auto& error) {
                                    return session.removeMIDIPitchFromCurrentChord(76, state, error);
                                });
    }
}

void testPickupClearAndKeySignatureRedo(const std::filesystem::path& root)
{
    for (const bool fromPart : { false, true }) {
        const Preparation preparePickup = [](auto& session, auto& state, auto& error) {
            if (!session.setFirstMeasurePickup(1, 4, state, error)) {
                return false;
            }
            msr::render::PickupMeasureState pickup;
            return session.firstMeasurePickupState(pickup, error) && pickup.isPickup
                && pickup.actualNumerator == 1 && pickup.actualDenominator == 4;
        };
        runPreparedMutationCase(root, "clear-pickup", fromPart, preparePickup,
                                [](auto& session, auto& state, auto& error) {
                                    return session.clearFirstMeasurePickup(state, error);
                                });

        const std::string view = fromPart ? "part" : "full";
        const std::string caseName = "key-redo-" + view;
        const std::filesystem::path testRoot = root / caseName;
        auto session = openSession(testRoot, caseName + "-source");
        createLinkedParts(*session);
        int pageCount = 0;
        std::string error;
        if (fromPart) {
            expect(session->setActivePartIndex(0, pageCount, error), caseName + ": could not activate part: " + error);
        }
        selectAt(*session, noteWithPitch(scanScore(*session, { 60 }, 0), 60));
        const SavedState baseline = saveState(*session, testRoot, root / "roundtrip-artifacts", caseName + "-baseline");
        msr::render::ScoreEditState state;
        expect(session->updateKeySignature(2, false, state, error), caseName + ": could not change key: " + error);
        if (fromPart) {
            expect(session->setActivePartIndex(std::nullopt, pageCount, error), caseName + ": could not return to score: " + error);
        }
        const SavedState changed = saveState(*session, testRoot, root / "roundtrip-artifacts", caseName + "-changed");
        expect(session->undo(state, error), caseName + ": undo failed: " + error);
        const SavedState undone = saveState(*session, testRoot, root / "roundtrip-artifacts", caseName + "-undone");
        expectUndoMatches(baseline, undone, caseName + " undo");
        expect(session->redo(state, error), caseName + ": redo failed: " + error);
        const SavedState redone = saveState(*session, testRoot, root / "roundtrip-artifacts", caseName + "-redone");
        expectUndoMatches(changed, redone, caseName + " redo");
        expectPartcheckClean(baseline, redone, caseName + " redo");
    }
}

void testDragAndEndpointEdits(const std::filesystem::path& root)
{
    for (const bool fromPart : { false, true }) {
        runPreparedMutationCase(root, "drag-staff-text", fromPart,
                                [](auto& session, auto& state, auto& error) {
                                    return session.addText("staff", state, error);
                                },
                                [](auto& session, auto& state, auto& error) {
                                    msr::render::ScoreEditState current;
                                    if (!session.currentEditState(current, error)) {
                                        return false;
                                    }
                                    return session.dragSelectedMovableElement(
                                        current.selection.pageIndex,
                                        std::min(0.98, current.selection.actionNormalizedX + 0.025),
                                        std::min(0.98, current.selection.actionNormalizedY + 0.025),
                                        state,
                                        error
                                    );
                                }, false);

        LocatedItem chordTextTarget;
        const Preparation prepareChordText = [&](auto& session, auto& state, auto& error) {
            const auto items = scanScore(session, { 60, 62 }, 0);
            chordTextTarget = noteWithPitch(items, 62);
            selectAt(session, noteWithPitch(items, 60));
            return session.addText("chord", state, error);
        };
        runPreparedMutationCase(root, "drag-chord-text", fromPart, prepareChordText,
                                [&](auto& session, auto& state, auto& error) {
                                    return session.dragSelectedChordText(
                                        chordTextTarget.pageIndex,
                                        chordTextTarget.x,
                                        chordTextTarget.y,
                                        state,
                                        error
                                    );
                                });

        for (const std::string expression : { "crescendo", "slur" }) {
            LocatedItem endpointTarget;
            const Preparation prepareExpression = [&](auto& session, auto& state, auto& error) {
                const auto items = scanScore(session, { 60, 65, 67 }, 0);
                const LocatedItem start = noteWithPitch(items, 60);
                const LocatedItem end = noteWithPitch(items, 65);
                endpointTarget = noteWithPitch(items, 67);
                if (!session.selectMeasureRange(start.pageIndex, start.x, start.y, end.x, end.y, state, error)) {
                    return false;
                }
                return session.addExpression(expression, state, error);
            };
            runPreparedMutationCase(root, "retarget-" + expression, fromPart, prepareExpression,
                                    [&](auto& session, auto& state, auto& error) {
                                        return session.retargetSelectedExpressionEndpoint(
                                            false,
                                            endpointTarget.pageIndex,
                                            endpointTarget.x,
                                            endpointTarget.y,
                                            state,
                                            error
                                        );
                                    });
        }
    }
}

void testNonPersistedEditingStateCommands(const std::filesystem::path& root)
{
    const std::filesystem::path testRoot = root / "non-persisted-state";
    auto session = openSession(testRoot, "non-persisted-source");
    createLinkedParts(*session);
    selectAt(*session, noteWithPitch(scanScore(*session, { 60 }, 0), 60));

    msr::render::ScoreEditState state;
    std::string error;
    expect(session->currentEditState(state, error), "Could not read edit state: " + error);
    expect(session->selectAdjacentElement(true, state, error), "Could not select next element: " + error);
    expect(session->selectAdjacentElement(false, state, error), "Could not select previous element: " + error);
    expect(session->selectAll(state, error), "Could not select all: " + error);
    expect(session->clearSelection(state, error), "Could not clear selection: " + error);

    msr::render::ScoreCorruptionReport report;
    expect(session->scoreCorruptionReport(report, error), "Could not scan score corruption: " + error);
    expect(!report.corrupted, "Clean sweep fixture was reported as corrupt");

    const SavedState baseline = saveState(*session, testRoot, root / "roundtrip-artifacts", "view-transpose-baseline");
    int pageCount = 0;
    expect(session->setViewTransposeKey(2, pageCount, error), "Could not enable view transpose: " + error);
    const SavedState transposedView = saveState(*session, testRoot, root / "roundtrip-artifacts", "view-transpose-active");
    expectUndoMatches(baseline, transposedView, "temporary view transpose must not alter the saved score");
    expect(session->clearViewTranspose(pageCount, error), "Could not clear view transpose: " + error);
    expect(session->save(error), "Could not save back to the source path: " + error);
}

void testTempoPropertiesReachLinkedParts(const std::filesystem::path& root)
{
    const std::filesystem::path testRoot = root / "tempo-linked-parts";
    auto session = openSession(testRoot, "tempo-source");
    createLinkedParts(*session);
    selectAt(*session, noteWithPitch(scanScore(*session, { 60 }, 0), 60));

    msr::render::ScoreEditState state;
    std::string error;
    expect(session->addTempo("quarter", 96, state, error), "Could not add tempo: " + error);
    const SavedState added = saveState(*session, testRoot, root / "roundtrip-artifacts", "tempo-full-added");
    expectAllScoresContain(added, "<Tempo>", "new tempo");
    expectAllScoresContain(added, "<tempo>1.6</tempo>", "new tempo playback value");
    expectAllScoresContain(added, "<followText>1</followText>", "new tempo follow-text flag");

    expect(session->undo(state, error), "Could not undo tempo: " + error);
    const SavedState undone = saveState(*session, testRoot, root / "roundtrip-artifacts", "tempo-full-undone");
    expectNoScoreContains(undone, "<Tempo>", "undone tempo");
}

void testTempoAddedFromPartReachesFullScore(const std::filesystem::path& root)
{
    const std::filesystem::path testRoot = root / "tempo-from-part";
    auto session = openSession(testRoot, "tempo-part-source");
    createLinkedParts(*session);

    int pageCount = 0;
    std::string error;
    expect(session->setActivePartIndex(0, pageCount, error), "Could not activate violin part: " + error);
    selectAt(*session, noteWithPitch(scanScore(*session, { 60 }, 0), 60));
    msr::render::ScoreEditState state;
    expect(session->addTempo("quarter", 108, state, error), "Could not add tempo from part: " + error);
    expect(session->setActivePartIndex(std::nullopt, pageCount, error), "Could not return to full score: " + error);

    const SavedState added = saveState(*session, testRoot, root / "roundtrip-artifacts", "tempo-part-added");
    expectAllScoresContain(added, "<Tempo>", "tempo added from part");
    expectAllScoresContain(added, "<tempo>1.8</tempo>", "tempo added from part playback value");

    expect(session->undo(state, error), "Could not undo part tempo: " + error);
    const SavedState undone = saveState(*session, testRoot, root / "roundtrip-artifacts", "tempo-part-undone");
    expectNoScoreContains(undone, "<Tempo>", "undone part tempo");
}

void testInstrumentChangeInitReachesLinkedPart(const std::filesystem::path& root)
{
    const std::filesystem::path testRoot = root / "instrument-change-linked-part";
    auto session = openSession(testRoot, "instrument-change-source");
    createLinkedParts(*session);
    const auto parts = session->partInfoList();
    expect(parts.size() == 2, "Expected two parts before instrument change");

    msr::render::ScoreEditState state;
    std::string error;
    expect(session->setInstrumentFromTick(parts.front().partId, 1920, "flute", state, error),
           "Could not add instrument change: " + error);
    const SavedState added = saveState(*session, testRoot, root / "roundtrip-artifacts", "instrument-change-added");
    expect(countOccurrences(added.master, "<InstrumentChange>") == 1, "Full score is missing the instrument change");
    expect(added.master.find("<init>1</init>") != std::string::npos, "Full-score instrument change is not initialized");

    size_t excerptChanges = 0;
    for (const std::string& excerpt : added.excerpts) {
        if (excerpt.find("<InstrumentChange>") == std::string::npos) {
            continue;
        }
        ++excerptChanges;
        expect(excerpt.find("<init>1</init>") != std::string::npos,
               "Linked instrument change did not receive the init flag");
    }
    expect(excerptChanges == 1, "Expected the instrument change in exactly one linked part");

    expect(session->undo(state, error), "Could not undo instrument change: " + error);
    const SavedState undone = saveState(*session, testRoot, root / "roundtrip-artifacts", "instrument-change-undone");
    expectNoScoreContains(undone, "<InstrumentChange>", "undone instrument change");
}

void testMIDIChordIsOneUndo(const std::filesystem::path& root)
{
    const std::filesystem::path testRoot = root / "midi-chord-one-undo";
    auto session = openSession(testRoot, "midi-chord-source");
    createLinkedParts(*session);
    selectAt(*session, noteWithPitch(scanScore(*session, { 60 }, 0), 60));

    const SavedState baseline = saveState(*session, testRoot, root / "roundtrip-artifacts", "midi-chord-baseline");
    const size_t baselineNotes = countOccurrences(baseline.master, "<Note>");
    msr::render::ScoreEditState state;
    std::string error;
    expect(session->setNoteInputEnabled(true, state, error), "Could not enable note input: " + error);
    expect(session->insertMIDIChordAtCursor({ 72, 76, 79 }, false, state, error), "Could not enter MIDI chord: " + error);
    const SavedState added = saveState(*session, testRoot, root / "roundtrip-artifacts", "midi-chord-added");
    // Note input replaces the next quarter note with the three-note chord, so
    // the score gains two Note elements overall.
    expect(countOccurrences(added.master, "<Note>") == baselineNotes + 2, "MIDI chord did not enter all three pitches");

    expect(session->undo(state, error), "Could not undo MIDI chord: " + error);
    const SavedState undone = saveState(*session, testRoot, root / "roundtrip-artifacts", "midi-chord-undone");
    expect(countOccurrences(undone.master, "<Note>") == baselineNotes,
           "One undo did not remove the complete MIDI chord");
    expect(undone.excerpts.size() == baseline.excerpts.size(), "Undo changed the linked-part count");
    for (size_t index = 0; index < undone.excerpts.size(); ++index) {
        expect(countOccurrences(undone.excerpts[index], "<Note>") == countOccurrences(baseline.excerpts[index], "<Note>"),
               "One undo left MIDI-chord notes in linked part " + std::to_string(index));
    }
}

void testReplaceInstrumentsFromPartUpdatesFullScore(const std::filesystem::path& root)
{
    const std::filesystem::path testRoot = root / "replace-instruments-from-part";
    auto session = openSession(testRoot, "replace-instruments-source");
    createLinkedParts(*session);
    const SavedState baseline = saveState(*session, testRoot, root / "roundtrip-artifacts", "replace-instruments-baseline");

    int pageCount = 0;
    std::string error;
    expect(session->setActivePartIndex(0, pageCount, error), "Could not activate violin part: " + error);
    msr::render::ScoreEditState state;
    expect(session->replaceInstruments({ "flute", "piano" }, state, error),
           "Could not replace instruments while viewing a part: " + error);
    expect(session->setActivePartIndex(std::nullopt, pageCount, error), "Could not return to full score: " + error);

    const SavedState replaced = saveState(*session, testRoot, root / "roundtrip-artifacts", "replace-instruments-replaced");
    expect(replaced.master.find("<Instrument id=\"flute\">") != std::string::npos,
           "Part-view replacement did not add Flute to the full score");
    expect(replaced.master.find("<Instrument id=\"piano\">") != std::string::npos,
           "Part-view replacement did not add Piano to the full score");
    expect(replaced.master.find("<Instrument id=\"violin\">") == std::string::npos,
           "Part-view replacement left Violin in the full score");

    expect(session->undo(state, error), "Could not undo instrument-list replacement: " + error);
    const SavedState undone = saveState(*session, testRoot, root / "roundtrip-artifacts", "replace-instruments-undone");
    expect(undone.master.find("<Instrument id=\"violin\">") != std::string::npos,
           "Undo did not restore Violin");
    expect(undone.master.find("<Instrument id=\"cello\">") != std::string::npos,
           "Undo did not restore Violoncello");
    expect(countOccurrences(undone.master, "<Part>") == countOccurrences(baseline.master, "<Part>"),
           "Undo did not restore the original number of parts");
}

template<typename Function>
bool runTest(const std::string& name, Function&& function)
{
    try {
        function();
        std::cout << "PASS " << name << '\n';
        return true;
    } catch (const std::exception& error) {
        std::cerr << "FAIL " << name << ": " << error.what() << '\n';
        return false;
    }
}

} // namespace

int main()
{
    TestDirectory directory;
    bool passed = true;
    passed &= runTest("tempo properties reach linked parts", [&] { testTempoPropertiesReachLinkedParts(directory.path); });
    passed &= runTest("tempo added from a part reaches the full score", [&] { testTempoAddedFromPartReachesFullScore(directory.path); });
    passed &= runTest("instrument-change init reaches linked part", [&] { testInstrumentChangeInitReachesLinkedPart(directory.path); });
    passed &= runTest("MIDI chord is one undo", [&] { testMIDIChordIsOneUndo(directory.path); });
    passed &= runTest("replace instruments from a part updates full score",
                      [&] { testReplaceInstrumentsFromPartUpdatesFullScore(directory.path); });
    passed &= runTest("core notation mutations stay linked and undo from full score and part",
                      [&] { testCoreNotationMutationSweep(directory.path); });
    passed &= runTest("prepared text, lyrics, melisma, and layout edits undo cleanly",
                      [&] { testPreparedTextLyricsAndLayoutEdits(directory.path); });
    passed &= runTest("range, measure, slash, clipboard, and transpose edits stay linked",
                      [&] { testRangeMeasureAndClipboardEdits(directory.path); });
    passed &= runTest("point and cursor note-entry edits stay linked and undo cleanly",
                      [&] { testPointAndCursorEntryEdits(directory.path); });
    passed &= runTest("pickup clear and key-signature redo restore linked scores",
                      [&] { testPickupClearAndKeySignatureRedo(directory.path); });
    passed &= runTest("drag and expression-endpoint edits undo cleanly",
                      [&] { testDragAndEndpointEdits(directory.path); });
    passed &= runTest("selection, view transpose, and corruption state commands are non-persisting",
                      [&] { testNonPersistedEditingStateCommands(directory.path); });
    if (directory.preserve) {
        std::cout << "EDIT_SWEEP_OUTPUT " << directory.path << '\n';
    }
    return passed ? 0 : 1;
}
