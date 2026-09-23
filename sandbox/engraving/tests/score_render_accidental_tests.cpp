#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <optional>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

#include "score_render_core.h"

namespace {

constexpr int NATURAL = 0;
constexpr int SHARP = 1;
constexpr int FLAT = 2;

struct NoteSpec {
    int pitch = 60;
    int tpc = 14;
};

struct TestDirectory {
    TestDirectory()
    {
        const auto nonce = std::chrono::steady_clock::now().time_since_epoch().count();
        path = std::filesystem::temp_directory_path() / ("score-render-accidental-tests-" + std::to_string(nonce));
        std::filesystem::create_directories(path);
    }

    ~TestDirectory()
    {
        std::error_code error;
        std::filesystem::remove_all(path, error);
    }

    std::filesystem::path path;
};

struct LocatedItem {
    int pageIndex = 0;
    double x = 0.0;
    double y = 0.0;
    int midiPitch = -1;
    bool isNote = false;
    bool isRest = false;
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

std::string scoreXml(const int key, const std::vector<NoteSpec>& referenceNotes, const int targetMeasureCount)
{
    std::ostringstream xml;
    xml << R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <Instrument id="violin">
        <trackName>Violin</trackName>
        <instrumentId>strings.violin</instrumentId>
        <Channel><program value="40"/></Channel>
      </Instrument>
    </Part>
    <Staff id="1">
      <Measure>
        <voice>
          <KeySig><concertKey>)MSCX" << key << R"MSCX(</concertKey></KeySig>
          <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
          <Clef><concertClefType>G</concertClefType></Clef>
)MSCX";

    if (referenceNotes.size() == 1) {
        const NoteSpec& note = referenceNotes.front();
        xml << "          <Chord><durationType>whole</durationType><Note><pitch>" << note.pitch
            << "</pitch><tpc>" << note.tpc << "</tpc></Note></Chord>\n";
    } else {
        for (const NoteSpec& note : referenceNotes) {
            xml << "          <Chord><durationType>quarter</durationType><Note><pitch>" << note.pitch
                << "</pitch><tpc>" << note.tpc << "</tpc></Note></Chord>\n";
        }
        const int remainingQuarters = 4 - static_cast<int>(referenceNotes.size());
        if (remainingQuarters == 1) {
            xml << "          <Rest><durationType>quarter</durationType></Rest>\n";
        } else if (remainingQuarters == 2) {
            xml << "          <Rest><durationType>half</durationType></Rest>\n";
        }
    }

    xml << R"MSCX(        </voice>
      </Measure>
)MSCX";
    for (int index = 0; index < targetMeasureCount; ++index) {
        xml << R"MSCX(      <Measure>
        <voice>
          <Rest><durationType>measure</durationType><duration>4/4</duration></Rest>
        </voice>
      </Measure>
)MSCX";
    }
    xml << R"MSCX(    </Staff>
  </Score>
</museScore>
)MSCX";
    return xml.str();
}

std::string horizontalFrameScoreXml()
{
    return R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <Instrument id="violin">
        <trackName>Violin</trackName>
        <instrumentId>strings.violin</instrumentId>
        <Channel><program value="40"/></Channel>
      </Instrument>
    </Part>
    <Staff id="1">
      <Measure>
        <voice>
          <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
          <Clef><concertClefType>G</concertClefType></Clef>
          <Rest><durationType>measure</durationType><duration>4/4</duration></Rest>
        </voice>
      </Measure>
      <HBox><width>5</width></HBox>
      <Measure>
        <voice>
          <Rest><durationType>measure</durationType><duration>4/4</duration></Rest>
        </voice>
      </Measure>
    </Staff>
  </Score>
</museScore>
)MSCX";
}

std::string customPartNameScoreXml()
{
    return R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <trackName>Keys &amp; Synth</trackName>
      <Instrument id="piano">
        <longName>Piano</longName>
        <trackName>Piano</trackName>
        <instrumentId>keyboard.piano</instrumentId>
        <Channel><program value="0"/></Channel>
      </Instrument>
    </Part>
    <Staff id="1">
      <Measure>
        <voice>
          <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
          <Rest><durationType>measure</durationType><duration>4/4</duration></Rest>
        </voice>
      </Measure>
    </Staff>
  </Score>
</museScore>
)MSCX";
}

std::unique_ptr<msr::render::ScoreRenderSession> openSession(const std::filesystem::path& root,
                                                             const std::string& name,
                                                             const std::string& xml)
{
    const std::filesystem::path scorePath = root / (name + ".mscx");
    writeFile(scorePath, xml);

    std::string error;
    std::unique_ptr<msr::render::ScoreRenderSession> session
        = msr::render::ScoreRenderSession::open(scorePath.string(), error);
    expect(session != nullptr, "Could not open " + name + ": " + error);
    expect(session->supportsEditing(), name + " did not open as an editable score");
    return session;
}

LocatedItem locatedItem(const msr::render::ScoreSelectionState& selection)
{
    return {
        selection.pageIndex,
        selection.normalizedX + selection.normalizedWidth * 0.5,
        selection.normalizedY + selection.normalizedHeight * 0.5,
        selection.midiPitch,
        selection.isNote,
        selection.isRest
    };
}

bool sameLocation(const LocatedItem& lhs, const LocatedItem& rhs)
{
    return lhs.pageIndex == rhs.pageIndex
        && std::abs(lhs.x - rhs.x) < 0.004
        && std::abs(lhs.y - rhs.y) < 0.004;
}

std::vector<LocatedItem> scanScore(msr::render::ScoreRenderSession& session,
                                   const std::vector<int>& expectedPitches,
                                   const size_t expectedRestCount)
{
    std::vector<LocatedItem> found;
    std::string error;
    msr::render::ScoreEditState state;

    for (double y = 0.035; y <= 0.965; y += 0.0125) {
        for (double x = 0.035; x <= 0.965; x += 0.0125) {
            error.clear();
            if (!session.selectElement(0, x, y, 1.5, state, error)) {
                fail("Native hit testing failed: " + error);
            }

            const auto& selection = state.selection;
            const bool wantedNote = selection.isNote
                && std::find(expectedPitches.begin(), expectedPitches.end(), selection.midiPitch) != expectedPitches.end();
            const bool wantedRest = selection.isRest;
            if (!wantedNote && !wantedRest) {
                continue;
            }

            const LocatedItem item = locatedItem(selection);
            if (std::none_of(found.begin(), found.end(), [&](const LocatedItem& prior) { return sameLocation(prior, item); })) {
                found.push_back(item);
            }

            const bool hasEveryPitch = std::all_of(expectedPitches.begin(), expectedPitches.end(), [&](const int pitch) {
                return std::any_of(found.begin(), found.end(), [&](const LocatedItem& candidate) {
                    return candidate.isNote && candidate.midiPitch == pitch;
                });
            });
            const size_t restCount = static_cast<size_t>(std::count_if(found.begin(), found.end(), [](const LocatedItem& item) {
                return item.isRest;
            }));
            if (hasEveryPitch && restCount >= expectedRestCount) {
                return found;
            }
        }
    }

    fail("Could not locate the expected notes and rests through render-core hit testing");
}

LocatedItem noteWithPitch(const std::vector<LocatedItem>& items, const int pitch)
{
    const auto found = std::find_if(items.begin(), items.end(), [&](const LocatedItem& item) {
        return item.isNote && item.midiPitch == pitch;
    });
    expect(found != items.end(), "Could not locate MIDI pitch " + std::to_string(pitch));
    return *found;
}

std::vector<LocatedItem> restsByX(const std::vector<LocatedItem>& items)
{
    std::vector<LocatedItem> rests;
    std::copy_if(items.begin(), items.end(), std::back_inserter(rests), [](const LocatedItem& item) { return item.isRest; });
    std::sort(rests.begin(), rests.end(), [](const LocatedItem& lhs, const LocatedItem& rhs) { return lhs.x < rhs.x; });
    return rests;
}

msr::render::ScoreEditState selectAt(msr::render::ScoreRenderSession& session, const LocatedItem& item)
{
    msr::render::ScoreEditState state;
    std::string error;
    expect(session.selectElement(item.pageIndex, item.x, item.y, 1.5, state, error), "Could not select test item: " + error);
    return state;
}

msr::render::ScoreEditState changeAccidental(msr::render::ScoreRenderSession& session, const int accidentalKind)
{
    msr::render::ScoreEditState state;
    std::string error;
    expect(session.changeSelectionAccidental(accidentalKind, state, error), "Could not change selected accidental: " + error);
    expect(state.selection.isNote, "Accidental command lost the selected note");
    return state;
}

std::string saveSnapshot(msr::render::ScoreRenderSession& session,
                         const std::filesystem::path& root,
                         const std::string& name)
{
    const std::filesystem::path path = root / (name + ".mscx");
    std::string error;
    expect(session.saveToPath(path.string(), error), "Could not save " + name + ": " + error);
    return readFile(path);
}

void expectSelection(const msr::render::ScoreEditState& state,
                     const int pitch,
                     const int accidentalKind,
                     const int key,
                     const std::string& context)
{
    expect(state.selection.isNote, context + ": expected a selected note");
    expect(state.selection.midiPitch == pitch,
           context + ": expected MIDI " + std::to_string(pitch) + ", got " + std::to_string(state.selection.midiPitch));
    expect(state.selection.accidentalKind == accidentalKind,
           context + ": unexpected effective accidental kind " + std::to_string(state.selection.accidentalKind));
    expect(state.selection.currentKey == key,
           context + ": expected key " + std::to_string(key) + ", got " + std::to_string(state.selection.currentKey));
}

void expectExplicitAccidental(const std::string& xml,
                              const std::optional<std::string>& subtype,
                              const std::string& context)
{
    const size_t accidentalCount = countOccurrences(xml, "<Accidental>");
    if (!subtype.has_value()) {
        expect(accidentalCount == 0, context + ": expected no explicit accidental");
        return;
    }

    expect(accidentalCount == 1,
           context + ": expected exactly one explicit accidental, got " + std::to_string(accidentalCount));
    expect(xml.find("<subtype>" + *subtype + "</subtype>") != std::string::npos,
           context + ": expected explicit " + *subtype);
}

void testSelectedAccidentals(const std::filesystem::path& root)
{
    {
        auto session = openSession(root, "selection-c", scoreXml(0, { { 65, 13 } }, 0));
        auto items = scanScore(*session, { 65 }, 0);
        auto state = selectAt(*session, noteWithPitch(items, 65));
        expectSelection(state, 65, NATURAL, 0, "C initial F natural");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-c-initial"), std::nullopt, "C initial F natural");

        state = changeAccidental(*session, SHARP);
        expectSelection(state, 66, SHARP, 0, "C explicit F sharp");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-c-sharp"), "accidentalSharp", "C explicit F sharp");

        state = changeAccidental(*session, SHARP);
        expectSelection(state, 65, NATURAL, 0, "C toggled F sharp off");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-c-sharp-off"), std::nullopt, "C toggled F sharp off");

        state = changeAccidental(*session, FLAT);
        expectSelection(state, 64, FLAT, 0, "C explicit F flat");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-c-flat"), "accidentalFlat", "C explicit F flat");

        state = changeAccidental(*session, FLAT);
        expectSelection(state, 65, NATURAL, 0, "C toggled F flat off");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-c-flat-off"), std::nullopt, "C toggled F flat off");
    }

    {
        auto session = openSession(root, "selection-g", scoreXml(1, { { 66, 20 } }, 0));
        auto items = scanScore(*session, { 66 }, 0);
        auto state = selectAt(*session, noteWithPitch(items, 66));
        expectSelection(state, 66, SHARP, 1, "G implied F sharp");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-g-initial"), std::nullopt, "G implied F sharp");

        state = changeAccidental(*session, SHARP);
        expectSelection(state, 66, SHARP, 1, "G courtesy F sharp");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-g-courtesy-sharp"), "accidentalSharp", "G courtesy F sharp");

        state = changeAccidental(*session, SHARP);
        expectSelection(state, 66, SHARP, 1, "G courtesy F sharp removed");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-g-courtesy-off"), std::nullopt, "G courtesy F sharp removed");

        state = changeAccidental(*session, NATURAL);
        expectSelection(state, 65, NATURAL, 1, "G explicit F natural");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-g-natural"), "accidentalNatural", "G explicit F natural");
    }

    {
        auto session = openSession(root, "selection-f", scoreXml(-1, { { 70, 12 } }, 0));
        auto items = scanScore(*session, { 70 }, 0);
        auto state = selectAt(*session, noteWithPitch(items, 70));
        expectSelection(state, 70, FLAT, -1, "F implied B flat");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-f-initial"), std::nullopt, "F implied B flat");

        state = changeAccidental(*session, FLAT);
        expectSelection(state, 70, FLAT, -1, "F courtesy B flat");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-f-courtesy-flat"), "accidentalFlat", "F courtesy B flat");

        state = changeAccidental(*session, FLAT);
        expectSelection(state, 70, FLAT, -1, "F courtesy B flat removed");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-f-courtesy-off"), std::nullopt, "F courtesy B flat removed");

        state = changeAccidental(*session, NATURAL);
        expectSelection(state, 71, NATURAL, -1, "F explicit B natural");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-f-natural"), "accidentalNatural", "F explicit B natural");
    }

    {
        auto session = openSession(root, "selection-eb", scoreXml(-3, { { 68, 10 } }, 0));
        auto items = scanScore(*session, { 68 }, 0);
        auto state = selectAt(*session, noteWithPitch(items, 68));
        expectSelection(state, 68, FLAT, -3, "E-flat implied A flat");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-eb-initial"), std::nullopt, "E-flat implied A flat");

        state = changeAccidental(*session, NATURAL);
        expectSelection(state, 69, NATURAL, -3, "E-flat explicit A natural");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-eb-natural"), "accidentalNatural", "E-flat explicit A natural");

        state = changeAccidental(*session, FLAT);
        expectSelection(state, 68, FLAT, -3, "E-flat explicit A flat");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-eb-flat"), "accidentalFlat", "E-flat explicit A flat");

        state = changeAccidental(*session, FLAT);
        expectSelection(state, 68, FLAT, -3, "E-flat explicit A flat removed");
        expectExplicitAccidental(saveSnapshot(*session, root, "selection-eb-flat-off"), std::nullopt, "E-flat explicit A flat removed");
    }
}

msr::render::ScoreEditState enableQuarterNoteEntry(msr::render::ScoreRenderSession& session, const LocatedItem& rest)
{
    msr::render::ScoreEditState state = selectAt(session, rest);
    expect(state.selection.isRest, "Expected a rest before enabling note input");

    std::string error;
    expect(session.setNoteInputEnabled(true, state, error), "Could not enable note input: " + error);
    error.clear();
    expect(session.applyDuration(4, state, error), "Could not choose quarter-note duration: " + error);
    return state;
}

msr::render::ScoreEditState insertPointNote(msr::render::ScoreRenderSession& session,
                                            const LocatedItem& rest,
                                            const LocatedItem& pitchReference,
                                            const std::optional<int> accidentalKind)
{
    msr::render::ScoreEditState state;
    std::string error;
    const bool inserted = accidentalKind.has_value()
        ? session.insertNoteWithAccidental(rest.pageIndex, rest.x, pitchReference.y, *accidentalKind, state, error)
        : session.insertNote(rest.pageIndex, rest.x, pitchReference.y, state, error);
    expect(inserted, "Could not insert point-entry note: " + error);
    expect(state.selection.isNote, "Point entry did not select the inserted note");
    return state;
}

void testPointEntryAccidentalsAreOneShot(const std::filesystem::path& root)
{
    {
        auto session = openSession(root, "point-c-sharp", scoreXml(0, { { 65, 13 }, { 67, 15 } }, 2));
        const auto items = scanScore(*session, { 65, 67 }, 3);
        const auto rests = restsByX(items);
        expect(rests.size() >= 3, "C sharp one-shot fixture did not expose its rests");
        const LocatedItem firstTarget = rests[rests.size() - 2];
        const LocatedItem secondTarget = rests.back();
        enableQuarterNoteEntry(*session, firstTarget);

        auto state = insertPointNote(*session, firstTarget, noteWithPitch(items, 65), SHARP);
        expectSelection(state, 66, SHARP, 0, "Point-entry explicit F sharp");
        expectExplicitAccidental(saveSnapshot(*session, root, "point-c-after-sharp"), "accidentalSharp", "Point-entry explicit F sharp");

        state = insertPointNote(*session, secondTarget, noteWithPitch(items, 67), std::nullopt);
        expectSelection(state, 67, NATURAL, 0, "Point-entry G after F sharp");
        const std::string xml = saveSnapshot(*session, root, "point-c-after-g");
        expect(countOccurrences(xml, "<Accidental>") == 1,
               "Point-entry G inherited the prior F sharp accidental");
        expect(xml.find("<subtype>accidentalSharp</subtype>") != std::string::npos,
               "Point-entry F sharp was not preserved");
    }

    {
        auto session = openSession(root, "point-c-flat", scoreXml(0, { { 71, 19 }, { 72, 14 } }, 2));
        const auto items = scanScore(*session, { 71, 72 }, 3);
        const auto rests = restsByX(items);
        expect(rests.size() >= 3, "C flat one-shot fixture did not expose its rests");
        const LocatedItem firstTarget = rests[rests.size() - 2];
        const LocatedItem secondTarget = rests.back();
        enableQuarterNoteEntry(*session, firstTarget);

        auto state = insertPointNote(*session, firstTarget, noteWithPitch(items, 71), FLAT);
        expectSelection(state, 70, FLAT, 0, "Point-entry explicit B flat");

        state = insertPointNote(*session, secondTarget, noteWithPitch(items, 72), std::nullopt);
        expectSelection(state, 72, NATURAL, 0, "Point-entry C after B flat");
        const std::string xml = saveSnapshot(*session, root, "point-c-after-flat-c");
        expect(countOccurrences(xml, "<Accidental>") == 1,
               "Point-entry C inherited the prior B flat accidental");
        expect(xml.find("<subtype>accidentalFlat</subtype>") != std::string::npos,
               "Point-entry B flat was not preserved");
    }
}

void testPointEntryKeySignatures(const std::filesystem::path& root)
{
    struct KeyCase {
        std::string name;
        int key = 0;
        NoteSpec impliedNote;
        int naturalPitch = 60;
    };

    const std::vector<KeyCase> cases = {
        { "g", 1, { 66, 20 }, 65 },
        { "f", -1, { 70, 12 }, 71 },
        { "eb", -3, { 68, 10 }, 69 }
    };

    for (const KeyCase& testCase : cases) {
        auto session = openSession(root,
                                   "point-key-" + testCase.name,
                                   scoreXml(testCase.key, { testCase.impliedNote }, 2));
        const auto items = scanScore(*session, { testCase.impliedNote.pitch }, 2);
        const auto rests = restsByX(items);
        expect(rests.size() >= 2, testCase.name + " fixture did not expose two target rests");
        const LocatedItem firstTarget = rests[rests.size() - 2];
        const LocatedItem secondTarget = rests.back();
        const LocatedItem pitchReference = noteWithPitch(items, testCase.impliedNote.pitch);
        enableQuarterNoteEntry(*session, firstTarget);

        auto state = insertPointNote(*session, firstTarget, pitchReference, std::nullopt);
        expectSelection(state,
                        testCase.impliedNote.pitch,
                        testCase.key > 0 ? SHARP : FLAT,
                        testCase.key,
                        testCase.name + " point-entry implied accidental");
        expectExplicitAccidental(saveSnapshot(*session, root, "point-key-" + testCase.name + "-implied"),
                                 std::nullopt,
                                 testCase.name + " point-entry implied accidental");

        state = insertPointNote(*session, secondTarget, pitchReference, NATURAL);
        expectSelection(state,
                        testCase.naturalPitch,
                        NATURAL,
                        testCase.key,
                        testCase.name + " point-entry explicit natural");
        expectExplicitAccidental(saveSnapshot(*session, root, "point-key-" + testCase.name + "-natural"),
                                 "accidentalNatural",
                                 testCase.name + " point-entry explicit natural");
    }
}

void testLinearScoresOpenInPageMode(const std::filesystem::path& root)
{
    std::string xml = scoreXml(0, { { 60, 14 } }, 99);
    const size_t scoreTagStart = xml.find("<Score>");
    expect(scoreTagStart != std::string::npos, "Could not add the linear layout fixture tag");
    const size_t scoreTagEnd = scoreTagStart + std::string("<Score>").size();
    xml.insert(scoreTagEnd, "\n    <layoutMode>line</layoutMode>");

    auto session = openSession(root, "linear-layout", xml);
    expect(session->totalPageCount() > 1, "A linear-view score did not normalize to physical pages");

    const std::string saved = saveSnapshot(*session, root, "linear-layout-saved");
    expect(saved.find("<layoutMode>line</layoutMode>") != std::string::npos,
           "Saving did not preserve the score's preferred MuseScore desktop view");
}

void testHorizontalFrameCanBeSelectedAndDeleted(const std::filesystem::path& root)
{
    auto session = openSession(root, "horizontal-frame", horizontalFrameScoreXml());
    bool deletedFrame = false;
    std::string error;

    for (double y = 0.02; y <= 0.98 && !deletedFrame; y += 0.01) {
        for (double x = 0.02; x <= 0.98 && !deletedFrame; x += 0.01) {
            msr::render::ScoreEditState state;
            expect(session->selectElement(0, x, y, 1.0, state, error), "Horizontal-frame hit testing failed: " + error);
            const auto& selection = state.selection;
            const bool isOtherElement = selection.hasSelection
                && !selection.isNote
                && !selection.isRest
                && !selection.isBar
                && !selection.isMeasure
                && !selection.isTimeSignature
                && !selection.isKeySignature
                && !selection.isTempo
                && !selection.isLayoutBreak
                && !selection.isExpressionSpanner
                && !selection.isInstrumentName
                && !selection.isInstrumentChange
                && !selection.isEditableText;
            if (!isOtherElement) {
                continue;
            }

            expect(session->deleteSelection(state, error), "Could not delete the selected horizontal frame: " + error);
            deletedFrame = true;
        }
    }

    expect(deletedFrame, "Could not select the horizontal frame through page hit testing");
    const std::string saved = saveSnapshot(*session, root, "horizontal-frame-deleted");
    expect(saved.find("<HBox>") == std::string::npos, "Deleting the horizontal-frame selection left it in the score");
}

void testMeasureSelectionCarriesInstrumentContext(const std::filesystem::path& root)
{
    auto session = openSession(root, "measure-instrument-context", scoreXml(0, { { 60, 14 } }, 1));
    const std::vector<LocatedItem> items = scanScore(*session, { 60 }, 1);
    const std::vector<LocatedItem> rests = restsByX(items);
    expect(!rests.empty(), "Could not locate a measure-selection target rest");

    const LocatedItem target = rests.back();
    msr::render::ScoreEditState state;
    std::string error;
    expect(session->selectMeasureRange(
               target.pageIndex,
               target.x,
               target.y,
               target.x,
               target.y,
               state,
               error),
           "Could not select the target measure: " + error);
    expect(state.selection.isMeasure, "Measure selection did not return measure state");
    expect(!state.selection.partId.empty(), "Measure selection did not identify its part");
    expect(state.selection.instrumentId == "violin", "Measure selection returned the wrong instrument ID");
    expect(state.selection.instrumentName == "Violin", "Measure selection returned the wrong instrument name");
    expect(state.selection.measureIndex >= 0, "Measure selection did not return a measure index");
    expect(state.selection.tick > 0, "Test did not select a later measure for an instrument change");

    msr::render::ScoreEditState changedState;
    expect(session->setInstrumentFromTick(
               state.selection.partId,
               state.selection.tick,
               "strings.viola",
               changedState,
               error),
           "Could not change instrument from the selected measure: " + error);

    const std::string saved = saveSnapshot(*session, root, "measure-instrument-context-saved");
    expect(saved.find("<InstrumentChange>") != std::string::npos,
           "Measure-level replacement did not save an instrument change");
    expect(saved.find("<instrumentId>strings.viola</instrumentId>") != std::string::npos,
           "Measure-level replacement saved the wrong instrument");
}

std::vector<double> staffTextOffsets(const std::string& xml)
{
    std::vector<double> offsets;
    size_t start = 0;
    while ((start = xml.find("<StaffText>", start)) != std::string::npos) {
        const size_t end = xml.find("</StaffText>", start);
        const size_t offset = xml.find("<offset x=\"", start);
        expect(end != std::string::npos && offset < end, "Staff text has no explicit offset");
        offsets.push_back(std::stod(xml.substr(offset + std::string("<offset x=\"").size())));
        start = end;
    }
    expect(offsets.size() == 3, "Expected left-, center-, and right-aligned staff text");
    return offsets;
}

void testLegacyStaffTextCompatibility(const std::filesystem::path& root, const std::string& version)
{
    std::string xml = scoreXml(0, { { 60, 14 } }, 0);
    xml.replace(xml.find("4.70"), 4, version);
    std::string texts;
    for (const std::string alignment : { "left", "center", "right" }) {
        texts += "<StaffText><autoplace>0</autoplace><align>" + alignment
            + ",top</align><offset x=\"0.7\" y=\"-0.65\"/>";
        if (version == "4.70") {
            texts += "<position>" + alignment + "</position>";
        }
        texts += "<text>" + alignment + "</text></StaffText>";
    }
    xml.insert(xml.find("<Chord>"), texts);
    const std::string name = "staff-text-compat-" + version;
    auto session = openSession(root, name, xml);
    const std::string saved = saveSnapshot(*session, root, name + "-saved");
    const auto offsets = staffTextOffsets(saved);
    constexpr double tolerance = 0.00001;
    expect(std::abs(offsets[0] - 0.7) < tolerance, "Left-aligned staff text moved");
    if (version == "4.70") {
        expect(std::abs(offsets[1] - 0.7) < tolerance && std::abs(offsets[2] - 0.7) < tolerance,
               "Current-format staff text must not receive legacy adjustments");
    } else {
        const double halfNotehead = 0.7 - offsets[1];
        expect(halfNotehead > 0.4 && halfNotehead < 0.9,
               "Legacy centered text did not receive the half-notehead adjustment");
        expect(std::abs((0.7 - offsets[2]) - 2.0 * halfNotehead) < tolerance,
               "Legacy right-aligned text did not receive the full-notehead adjustment");
    }

    // Rendering and saving must not reapply this non-idempotent import migration.
    msr::render::RenderedPage page;
    std::string error;
    expect(session->renderPage(0, 144, page, error), "Could not render compatibility fixture: " + error);
    const auto renderedOffsets = staffTextOffsets(saveSnapshot(*session, root, name + "-rendered"));
    auto reopened = openSession(root, name + "-reopened", saved);
    const auto reopenedOffsets = staffTextOffsets(saveSnapshot(*reopened, root, name + "-resaved"));
    for (size_t index = 0; index < offsets.size(); ++index) {
        expect(std::abs(renderedOffsets[index] - offsets[index]) < tolerance,
               "Rendering reapplied the compatibility adjustment");
        expect(std::abs(reopenedOffsets[index] - offsets[index]) < tolerance,
               "Save/reopen reapplied the compatibility adjustment");
    }
}

std::string savedPartTrackName(const std::string& xml)
{
    // The part's own <trackName> precedes <Instrument>; the instrument's is inside it.
    const size_t part = xml.find("<Part");
    const size_t instrument = xml.find("<Instrument", part);
    const size_t open = xml.find("<trackName>", part);
    expect(part != std::string::npos && open < instrument, "Saved part has no <trackName> of its own");
    const size_t start = open + std::string("<trackName>").size();
    return xml.substr(start, xml.find("</trackName>", start) - start);
}

void testPartNamesSurviveSave(const std::filesystem::path& testRoot)
{
    // Folder-style .mscx saves replace their whole directory, so use one of our own.
    const std::filesystem::path root = testRoot / "part-names";
    std::filesystem::create_directories(root);
    // MuseScore 4.7 keeps a part name separate from the instrument name. Aria must
    // write it back unchanged (escaped once), follow an instrument replacement the
    // way MuseScore does, and restore it on undo.
    auto session = openSession(root, "part-names", customPartNameScoreXml());
    std::string saved = savedPartTrackName(saveSnapshot(*session, root, "part-names-saved"));
    expect(saved == "Keys &amp; Synth", "Custom part name was not preserved: " + saved);

    const std::vector<msr::render::ScorePartInfo> parts = session->partInfoList();
    expect(parts.size() == 1, "Expected one part");
    msr::render::ScoreEditState state;
    std::string error;
    expect(session->replacePartInstrument(parts.front().partId, "flute", state, error), "Could not replace instrument: " + error);
    saved = savedPartTrackName(saveSnapshot(*session, root, "part-names-replaced"));
    expect(saved == "Flute", "Replaced instrument kept a stale part name: " + saved);

    expect(session->undo(state, error), "Could not undo instrument replacement: " + error);
    saved = savedPartTrackName(saveSnapshot(*session, root, "part-names-undone"));
    expect(saved == "Keys &amp; Synth", "Undo did not restore the custom part name: " + saved);
}

std::string savedExcerptXml(const std::filesystem::path& root)
{
    for (const auto& entry : std::filesystem::recursive_directory_iterator(root / "Excerpts")) {
        if (entry.path().extension() == ".mscx") {
            return readFile(entry.path());
        }
    }
    fail("Saved score has no part (excerpt) file");
}

void testNewDynamicsAndTextReachLinkedParts(const std::filesystem::path& testRoot)
{
    // Folder-style .mscx saves replace their whole directory, so use one of our own.
    const std::filesystem::path root = testRoot / "linked-parts";
    std::filesystem::create_directories(root);
    // Items added in the full score are copied into linked parts as they are added;
    // their type and default text must reach those copies too.
    auto session = openSession(root, "linked-parts", scoreXml(0, { { 60, 14 } }, 0));
    int pageCount = 0;
    std::string error;
    expect(session->setActivePartIndex(0, pageCount, error), "Could not create the linked part: " + error);
    expect(session->setActivePartIndex(std::nullopt, pageCount, error), "Could not return to the full score: " + error);

    const LocatedItem note = noteWithPitch(scanScore(*session, { 60 }, 0), 60);
    msr::render::ScoreEditState state;
    selectAt(*session, note);
    expect(session->addExpression("mf", state, error), "Could not add a dynamic: " + error);
    selectAt(*session, note);
    expect(session->addText("staff", state, error), "Could not add staff text: " + error);

    const std::string score = saveSnapshot(*session, root, "linked-parts-saved");
    const std::string part = savedExcerptXml(root);
    expect(countOccurrences(score, "<subtype>mf</subtype>") == 1, "Full score is missing the new mf dynamic");
    expect(countOccurrences(part, "<subtype>mf</subtype>") == 1, "Linked part did not receive the new mf dynamic");
    expect(countOccurrences(part, "other-dynamics") == 0, "Linked part received a blank dynamic");
    expect(countOccurrences(part, "Staff Text") == 1, "Linked part did not receive the new staff text");

    expect(session->undo(state, error) && session->undo(state, error), "Could not undo the additions: " + error);
    const std::string undoneScore = saveSnapshot(*session, root, "linked-parts-undone");
    const std::string undonePart = savedExcerptXml(root);
    expect(countOccurrences(undoneScore + undonePart, "<Dynamic>") == 0, "Undo left a dynamic behind");
    expect(countOccurrences(undoneScore + undonePart, "Staff Text") == 0, "Undo left staff text behind");
}

void testJumpsAndMarkersReachLinkedParts(const std::filesystem::path& testRoot)
{
    // Folder-style .mscx saves replace their whole directory, so use one of our own.
    const std::filesystem::path root = testRoot / "linked-jumps";
    std::filesystem::create_directories(root);

    // Jumps and markers are system items: MuseScore shows them in every part.
    auto session = openSession(root, "linked-jumps", scoreXml(0, { { 60, 14 } }, 1));
    int pageCount = 0;
    std::string error;
    expect(session->setActivePartIndex(0, pageCount, error), "Could not create the linked part: " + error);
    expect(session->setActivePartIndex(std::nullopt, pageCount, error), "Could not return to the full score: " + error);

    const LocatedItem note = noteWithPitch(scanScore(*session, { 60 }, 0), 60);
    msr::render::ScoreEditState state;
    selectAt(*session, note);
    expect(session->addRepeatJump("segno", state, error), "Could not add a segno: " + error);
    selectAt(*session, note);
    expect(session->addRepeatJump("dsalcoda", state, error), "Could not add D.S. al Coda: " + error);

    saveSnapshot(*session, root, "linked-jumps-saved");
    const std::string part = savedExcerptXml(root);
    expect(countOccurrences(part, "<Marker>") == 1, "Linked part did not receive the segno");
    expect(countOccurrences(part, "<Jump>") == 1, "Linked part did not receive the D.S. al Coda");
}

std::filesystem::path savedExcerptPath(const std::filesystem::path& root)
{
    for (const auto& entry : std::filesystem::recursive_directory_iterator(root / "Excerpts")) {
        if (entry.path().extension() == ".mscx") {
            return entry.path();
        }
    }
    fail("Saved score has no part (excerpt) file");
}

void testBlankPartDynamicsRequireApproval(const std::filesystem::path& testRoot)
{
    // Folder-style .mscx saves replace their whole directory, so use one of our own.
    const std::filesystem::path root = testRoot / "blank-dynamics";
    std::filesystem::create_directories(root);
    // Scores saved before the addExpression fix carry blank "other-dynamics" copies in
    // their parts. Recreate one and check that opening alone never changes it.
    auto session = openSession(root, "blank-dynamics", scoreXml(0, { { 60, 14 } }, 0));
    int pageCount = 0;
    std::string error;
    expect(session->setActivePartIndex(0, pageCount, error), "Could not create the linked part: " + error);
    expect(session->setActivePartIndex(std::nullopt, pageCount, error), "Could not return to the full score: " + error);
    msr::render::ScoreEditState state;
    selectAt(*session, noteWithPitch(scanScore(*session, { 60 }, 0), 60));
    expect(session->addExpression("mf", state, error), "Could not add a dynamic: " + error);
    saveSnapshot(*session, root, "blank-dynamics-saved");
    session.reset();

    const std::filesystem::path partPath = savedExcerptPath(root);
    std::string part = readFile(partPath);
    const size_t mf = part.find("<subtype>mf</subtype>");
    expect(mf != std::string::npos, "Linked part did not receive the new mf dynamic");
    part.replace(mf, std::string("<subtype>mf</subtype>").size(), "<subtype>other-dynamics</subtype>");
    writeFile(partPath, part);

    std::unique_ptr<msr::render::ScoreRenderSession> reopened
        = msr::render::ScoreRenderSession::open((root / "blank-dynamics-saved.mscx").string(), error);
    expect(reopened != nullptr, "Could not reopen the damaged score: " + error);
    std::vector<msr::render::ScoreLegacyRepairIssue> issues;
    expect(reopened->legacyRepairIssues(issues, error), "Could not scan old repair issues: " + error);
    expect(issues.size() == 1 && issues.front().kind == "dynamic", "The blank dynamic was not offered as an explicit repair");
    saveSnapshot(*reopened, root, "blank-dynamics-unchanged");
    expect(countOccurrences(savedExcerptXml(root), "other-dynamics") > 0, "Opening or saving silently repaired the dynamic");
    expect(reopened->applyLegacyRepairs({ issues.front().index }, state, error), "Could not apply the selected repair: " + error);
    expect(reopened->legacyRepairIssues(issues, error) && issues.empty(), "The repair did not clear the detected issue");
    saveSnapshot(*reopened, root, "blank-dynamics-repaired");
    const std::string repaired = savedExcerptXml(root);
    expect(countOccurrences(repaired, "other-dynamics") == 0, "Blank part dynamic was not repaired");
    expect(countOccurrences(repaired, "<subtype>mf</subtype>") == 1, "Repaired part dynamic is not mf");
}

void testOldPartTempoRequiresApproval(const std::filesystem::path& testRoot)
{
    const std::filesystem::path root = testRoot / "old-part-tempo";
    std::filesystem::create_directories(root);
    auto session = openSession(root, "old-part-tempo", scoreXml(0, { { 60, 14 } }, 0));
    int pageCount = 0;
    std::string error;
    expect(session->setActivePartIndex(0, pageCount, error), "Could not create the linked part: " + error);
    expect(session->setActivePartIndex(std::nullopt, pageCount, error), "Could not return to the full score: " + error);
    msr::render::ScoreEditState state;
    selectAt(*session, noteWithPitch(scanScore(*session, { 60 }, 0), 60));
    expect(session->addTempo("quarter", 90, state, error), "Could not add a tempo: " + error);
    saveSnapshot(*session, root, "old-part-tempo-saved");
    session.reset();

    const std::filesystem::path partPath = savedExcerptPath(root);
    std::string part = readFile(partPath);
    expect(part.find("<followText>1</followText>") != std::string::npos, "The linked tempo did not serialize followText");
    part.replace(part.find("<followText>1</followText>"), std::string("<followText>1</followText>").size(), "<followText>0</followText>");
    part = std::regex_replace(part, std::regex("<tempo>[^<]+</tempo>"), "<tempo>2</tempo>");
    writeFile(partPath, part);

    auto reopened = msr::render::ScoreRenderSession::open((root / "old-part-tempo-saved.mscx").string(), error);
    expect(reopened != nullptr, "Could not reopen the old tempo score: " + error);
    std::vector<msr::render::ScoreLegacyRepairIssue> issues;
    expect(reopened->legacyRepairIssues(issues, error), "Could not scan old tempo issues: " + error);
    expect(issues.size() == 1 && issues.front().kind == "tempo", "The default-tempo linked copy was not offered as a repair");
    expect(readFile(partPath) == part, "Opening silently changed the old part tempo file");
    saveSnapshot(*reopened, root, "old-part-tempo-unchanged");
    const std::string noOpPart = savedExcerptXml(root);
    expect(noOpPart.find("<tempo>2</tempo>") != std::string::npos,
           "A no-op save silently changed the old part tempo: " + noOpPart);
    expect(reopened->applyLegacyRepairs({ issues.front().index }, state, error), "Could not repair the old part tempo: " + error);
    expect(reopened->legacyRepairIssues(issues, error) && issues.empty(), "The tempo repair did not clear the issue");
    saveSnapshot(*reopened, root, "old-part-tempo-repaired");
    expect(savedExcerptXml(root).find("<followText>1</followText>") != std::string::npos,
           "The repaired part tempo did not save its followText property");
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
    TestDirectory testDirectory;
    bool passed = true;
    for (const std::string version : { "3.02", "4.60", "4.70" }) {
        passed &= runTest("staff-text import compatibility " + version,
                          [&] { testLegacyStaffTextCompatibility(testDirectory.path, version); });
    }
    passed &= runTest("selected accidentals across key signatures", [&] { testSelectedAccidentals(testDirectory.path); });
    passed &= runTest("point-entry accidentals are one-shot", [&] { testPointEntryAccidentalsAreOneShot(testDirectory.path); });
    passed &= runTest("point-entry key-signature accidentals", [&] { testPointEntryKeySignatures(testDirectory.path); });
    passed &= runTest("linear scores render pages and preserve their desktop view", [&] { testLinearScoresOpenInPageMode(testDirectory.path); });
    passed &= runTest("horizontal frames can be selected and deleted", [&] { testHorizontalFrameCanBeSelectedAndDeleted(testDirectory.path); });
    passed &= runTest("measure selections carry instrument context", [&] { testMeasureSelectionCarriesInstrumentContext(testDirectory.path); });
    passed &= runTest("part names survive save and follow instrument replacement", [&] { testPartNamesSurviveSave(testDirectory.path); });
    passed &= runTest("new dynamics and text reach linked parts", [&] { testNewDynamicsAndTextReachLinkedParts(testDirectory.path); });
    passed &= runTest("blank part dynamics require approval", [&] { testBlankPartDynamicsRequireApproval(testDirectory.path); });
    passed &= runTest("old part tempo requires approval", [&] { testOldPartTempoRequiresApproval(testDirectory.path); });
    passed &= runTest("jumps and markers reach linked parts", [&] { testJumpsAndMarkersReachLinkedParts(testDirectory.path); });
    return passed ? 0 : 1;
}
