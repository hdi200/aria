#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <memory>
#include <numeric>
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
          <Clef><concertClefType>G</concertClefType><isHeader>1</isHeader></Clef>
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

std::string fermataScoreXml()
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
          <Fermata><subtype>fermataAbove</subtype></Fermata>
          <Chord><durationType>whole</durationType><Note><pitch>72</pitch><tpc>14</tpc></Note></Chord>
        </voice>
      </Measure>
    </Staff>
  </Score>
</museScore>
)MSCX";
}

std::string tappableElementsScoreXml()
{
    return R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <Instrument id="piano">
        <trackName>Piano</trackName>
        <instrumentId>keyboard.piano</instrumentId>
        <Channel><program value="0"/></Channel>
      </Instrument>
    </Part>
    <Staff id="1">
      <Measure>
        <voice>
          <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
          <Clef><concertClefType>G</concertClefType></Clef>
          <Chord>
            <durationType>quarter</durationType>
            <Note>
              <pitch>72</pitch><tpc>14</tpc>
              <Spanner type="Glissando">
                <Glissando><diagonal>1</diagonal></Glissando>
                <next><location><fractions>1/4</fractions></location></next>
              </Spanner>
            </Note>
          </Chord>
          <Chord>
            <durationType>quarter</durationType>
            <Note>
              <Spanner type="Glissando">
                <prev><location><fractions>-1/4</fractions></location></prev>
              </Spanner>
              <pitch>76</pitch><tpc>18</tpc>
            </Note>
          </Chord>
          <Tuplet>
            <normalNotes>2</normalNotes>
            <actualNotes>3</actualNotes>
            <baseNote>eighth</baseNote>
            <Number><style>tuplet</style><text>3</text></Number>
          </Tuplet>
          <Chord><durationType>eighth</durationType><Note><pitch>67</pitch><tpc>15</tpc></Note></Chord>
          <Chord><durationType>eighth</durationType><Note><pitch>69</pitch><tpc>17</tpc></Note></Chord>
          <Chord><durationType>eighth</durationType><Note><pitch>71</pitch><tpc>19</tpc></Note></Chord>
          <endTuplet/>
          <Rest><durationType>quarter</durationType></Rest>
        </voice>
      </Measure>
      <Measure>
        <voice>
          <Chord>
            <durationType>half</durationType>
            <Arpeggio><subtype>0</subtype></Arpeggio>
            <Note><pitch>60</pitch><tpc>14</tpc></Note>
            <Note><pitch>64</pitch><tpc>18</tpc></Note>
            <Note><pitch>67</pitch><tpc>15</tpc></Note>
          </Chord>
          <Clef><concertClefType>F</concertClefType></Clef>
          <Chord><durationType>half</durationType><Note><pitch>48</pitch><tpc>14</tpc></Note></Chord>
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
    // Enough bars to need a second page even on A4 (100 empty bars fit on one).
    std::string xml = scoreXml(0, { { 60, 14 } }, 199);
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
            if (saveSnapshot(*session, root, "horizontal-frame-probe").find("<HBox>") != std::string::npos) {
                // Something other than the frame was hit; undo it if it changed the score, then keep looking.
                session->undo(state, error);
                continue;
            }
            deletedFrame = true;
        }
    }

    expect(deletedFrame, "Could not select the horizontal frame through page hit testing");
    const std::string saved = saveSnapshot(*session, root, "horizontal-frame-deleted");
    expect(saved.find("<HBox>") == std::string::npos, "Deleting the horizontal-frame selection left it in the score");
}

void testFermataCanBeSelectedDraggedAndDeleted(const std::filesystem::path& root)
{
    auto session = openSession(root, "fermata", fermataScoreXml());
    expect(saveSnapshot(*session, root, "fermata-original").find("<Fermata>") != std::string::npos,
           "The fermata test score did not load its fermata");
    bool deletedFermata = false;
    std::string error;

    for (double y = 0.02; y <= 0.5 && !deletedFermata; y += 0.005) {
        for (double x = 0.02; x <= 0.98 && !deletedFermata; x += 0.005) {
            msr::render::ScoreEditState state;
            expect(session->selectElement(0, x, y, 1.0, state, error), "Fermata hit testing failed: " + error);
            const auto& selection = state.selection;
            const bool isFermata = selection.hasSelection
                && selection.canDragMovableElement
                && !selection.isNote
                && !selection.isRest
                && !selection.isMeasure
                && !selection.isEditableText;
            if (!isFermata) {
                continue;
            }

            const double centerX = selection.normalizedX + selection.normalizedWidth * 0.5;
            const double centerY = selection.normalizedY + selection.normalizedHeight * 0.5;
            expect(session->dragSelectedMovableElement(0, centerX, centerY - 0.02, state, error),
                   "Could not drag the selected fermata: " + error);
            expect(saveSnapshot(*session, root, "fermata-dragged").find("<offset") != std::string::npos,
                   "Dragging the fermata did not store an offset");
            expect(state.selection.hasSelection && state.selection.canDragMovableElement,
                   "The fermata did not stay selected after dragging");
            expect(session->deleteSelection(state, error), "Could not delete the selected fermata: " + error);
            deletedFermata = true;
        }
    }

    expect(deletedFermata, "Could not select the fermata through page hit testing");
    const std::string saved = saveSnapshot(*session, root, "fermata-deleted");
    expect(saved.find("<Fermata>") == std::string::npos, "Deleting the fermata selection left it in the score");
    expect(saved.find("<Chord>") != std::string::npos, "Deleting the fermata also removed its note");
}

// Taps across the first page until deleting the tapped element removes one `tag` from the saved file.
// Other elements that get hit along the way are deleted and undone again.
bool deleteTappedElementUntilTagCountDrops(msr::render::ScoreRenderSession& session,
                                           const std::filesystem::path& root,
                                           const std::string& name,
                                           const std::string& tag)
{
    const size_t originalCount = countOccurrences(saveSnapshot(session, root, name + "-original"), tag);
    expect(originalCount > 0, name + ": the test score did not load any " + tag);
    std::vector<std::array<double, 4>> triedRects;
    std::string error;
    for (double y = 0.02; y <= 0.4; y += 0.004) {
        for (double x = 0.02; x <= 0.98; x += 0.004) {
            msr::render::ScoreEditState state;
            expect(session.selectElement(0, x, y, 1.0, state, error), name + ": hit testing failed: " + error);
            const auto& selection = state.selection;
            if (!selection.hasSelection || selection.isNote || selection.isRest || selection.isMeasure
                || selection.isBar || selection.isTimeSignature) {
                continue;
            }
            const std::array<double, 4> rect { selection.normalizedX, selection.normalizedY,
                                               selection.normalizedWidth, selection.normalizedHeight };
            if (std::find(triedRects.begin(), triedRects.end(), rect) != triedRects.end()) {
                continue;
            }
            triedRects.push_back(rect);

            expect(session.deleteSelection(state, error), name + ": could not delete the selection: " + error);
            if (countOccurrences(saveSnapshot(session, root, name + "-probe"), tag) < originalCount) {
                return true;
            }
            session.undo(state, error);
        }
    }
    return false;
}

void testElementCanBeTappedAndDeleted(const std::filesystem::path& root, const std::string& name, const std::string& tag)
{
    auto session = openSession(root, name, tappableElementsScoreXml());
    expect(deleteTappedElementUntilTagCountDrops(*session, root, name, tag),
           "Could not select and delete " + tag + " through page hit testing");
}

std::map<int, LocatedItem> locateNotesByPitch(msr::render::ScoreRenderSession& session, const int pageIndex = 0)
{
    std::map<int, LocatedItem> notes;
    std::string error;
    for (double y = 0.02; y <= 0.4; y += 0.004) {
        for (double x = 0.02; x <= 0.98; x += 0.004) {
            msr::render::ScoreEditState state;
            expect(session.selectElement(pageIndex, x, y, 1.0, state, error), "Note hit testing failed: " + error);
            if (state.selection.isNote && !notes.count(state.selection.midiPitch)) {
                notes[state.selection.midiPitch] = locatedItem(state.selection);
            }
        }
    }
    return notes;
}

void testRangeDragIncludesTheBeatItEndsOn(const std::filesystem::path& root)
{
    auto session = openSession(root, "range-drag", scoreXml(0, { { 60, 14 }, { 62, 16 }, { 64, 18 }, { 65, 13 } }, 1));
    std::map<int, LocatedItem> notes = locateNotesByPitch(*session);
    expect(notes.count(60) && notes.count(65), "Could not locate the first and last notes");
    const LocatedItem first = notes[60];
    const LocatedItem last = notes[65];

    msr::render::ScoreEditState state;
    std::string error;
    expect(session->selectElement(0, last.x, last.y, 1.0, state, error), "Could not select the last note: " + error);
    const double lastNoteRight = state.selection.normalizedX + state.selection.normalizedWidth;

    expect(session->selectMeasureRange(0, first.x, first.y, last.x, last.y, state, error),
           "Dragging from the first to the last note failed: " + error);
    expect(state.selection.isMeasure && !state.selection.highlightRects.empty(), "The drag did not produce a range highlight");
    const auto& highlight = state.selection.highlightRects.front();
    expect(highlight.normalizedX + highlight.normalizedWidth >= lastNoteRight,
           "The range highlight stops before the last note it was dragged onto");

    expect(session->deleteSelection(state, error), "Could not delete the dragged range: " + error);
    const std::string saved = saveSnapshot(*session, root, "range-drag-deleted");
    expect(saved.find("<Chord>") == std::string::npos, "Dragging onto the last note left it out of the range");

    expect(session->selectMeasureRange(0, first.x, first.y, last.x, std::min(last.y + 0.3, 0.99), state, error),
           "A drag that ends in the margin below the system should still select a range: " + error);
    expect(state.selection.isMeasure, "A drag ending in the margin did not select a range");
}

void testFermataButtonTogglesOnNotesRestsAndRanges(const std::filesystem::path& root)
{
    auto session = openSession(root, "fermata-button", scoreXml(0, { { 60, 14 }, { 62, 16 }, { 64, 18 } }, 1));
    std::map<int, LocatedItem> notes = locateNotesByPitch(*session);
    expect(notes.count(60) && notes.count(64), "Could not locate the test notes");
    msr::render::ScoreEditState state;
    std::string error;

    expect(session->selectElement(0, notes[62].x, notes[62].y, 1.0, state, error), "Could not select a note: " + error);
    expect(session->addExpression("Fermata", state, error), "Could not add a fermata to a note: " + error);
    expect(countOccurrences(saveSnapshot(*session, root, "fermata-note"), "<Fermata>") == 1, "The note did not get a fermata");
    expect(state.selection.isNote, "The note did not stay selected after adding a fermata");
    expect(session->addExpression("Fermata", state, error), "Could not toggle the fermata off: " + error);
    expect(countOccurrences(saveSnapshot(*session, root, "fermata-note-off"), "<Fermata>") == 0, "Pressing Fermata again did not remove it");

    bool addedToRest = false;
    for (double x = notes[64].x + 0.01; x <= 0.6 && !addedToRest; x += 0.004) {
        expect(session->selectElement(0, x, notes[64].y, 1.0, state, error), "Rest hit testing failed: " + error);
        if (!state.selection.isRest) {
            continue;
        }
        expect(session->addExpression("Fermata", state, error), "Could not add a fermata to a rest: " + error);
        addedToRest = true;
    }
    expect(addedToRest, "Could not select the rest after the notes");
    expect(countOccurrences(saveSnapshot(*session, root, "fermata-rest"), "<Fermata>") == 1, "The rest did not get a fermata");
    expect(session->undo(state, error), "Could not undo the rest fermata: " + error);

    expect(session->selectMeasureRange(0, notes[60].x, notes[60].y, notes[64].x, notes[64].y, state, error),
           "Could not drag-select the notes: " + error);
    expect(session->addExpression("Fermata", state, error), "Could not add fermatas to a range: " + error);
    expect(countOccurrences(saveSnapshot(*session, root, "fermata-range"), "<Fermata>") == 3,
           "A range fermata should go on each of the three selected notes");
}

void testRangeHighlightCoversEveryPage(const std::filesystem::path& root)
{
    const std::string xml = R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <Instrument id="piano">
        <trackName>Piano</trackName>
        <instrumentId>keyboard.piano</instrumentId>
        <Channel><program value="0"/></Channel>
      </Instrument>
    </Part>
    <Staff id="1">
      <Measure>
        <LayoutBreak><subtype>page</subtype></LayoutBreak>
        <voice>
          <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
          <Clef><concertClefType>G</concertClefType></Clef>
          <Chord><durationType>whole</durationType><Note><pitch>60</pitch><tpc>14</tpc></Note></Chord>
        </voice>
      </Measure>
      <Measure>
        <voice>
          <Chord><durationType>whole</durationType><Note><pitch>62</pitch><tpc>16</tpc></Note></Chord>
        </voice>
      </Measure>
    </Staff>
  </Score>
</museScore>
)MSCX";
    auto session = openSession(root, "two-page-range", xml);
    msr::render::ScoreEditState state;
    std::string error;
    expect(session->selectAll(state, error), "Select All failed: " + error);
    expect(state.selection.isMeasure && state.selection.pageIndex == 0 && !state.selection.highlightRects.empty(),
           "Select All did not highlight the first page");
    expect(state.selection.otherPageHighlightRects.size() == 1
           && state.selection.otherPageHighlightRects.front().pageIndex == 1,
           "Select All did not highlight the measure on the second page");
    const auto& firstPage = state.selection.highlightRects.front();
    const auto& action = state.selection;
    expect(action.actionNormalizedY >= firstPage.normalizedY - 0.001
           && action.actionNormalizedY <= firstPage.normalizedY + firstPage.normalizedHeight,
           "The range's action anchor should stay on the first page's highlight");
}

// Page 1 holds only a tall title frame and page 2 starts with the first system, like an
// orchestral score. Pencil input on page 2 must land on page 2's staff, not page 1's.
void testPencilInputWorksOnLaterPages(const std::filesystem::path& root)
{
    const std::string xml = R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <Instrument id="piano">
        <trackName>Piano</trackName>
        <instrumentId>keyboard.piano</instrumentId>
        <Channel><program value="0"/></Channel>
      </Instrument>
    </Part>
    <Staff id="1">
      <VBox>
        <height>120</height>
        <Text><style>title</style><text>Symphony</text></Text>
        <LayoutBreak><subtype>page</subtype></LayoutBreak>
      </VBox>
      <Measure>
        <voice>
          <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
          <Clef><concertClefType>G</concertClefType></Clef>
          <Chord><durationType>whole</durationType><Note><pitch>72</pitch><tpc>14</tpc></Note></Chord>
        </voice>
      </Measure>
      <Measure>
        <voice>
          <Rest><durationType>measure</durationType><duration>4/4</duration></Rest>
        </voice>
      </Measure>
    </Staff>
  </Score>
</museScore>
)MSCX";
    auto session = openSession(root, "pencil-page-two", xml);
    msr::render::ScoreEditState state;
    std::string error;

    std::optional<LocatedItem> note;
    for (double y = 0.02; y <= 0.5 && !note; y += 0.004) {
        for (double x = 0.02; x <= 0.98 && !note; x += 0.004) {
            expect(session->selectElement(1, x, y, 1.0, state, error), "Page 2 hit testing failed: " + error);
            if (state.selection.isNote && state.selection.pageIndex == 1) {
                note = locatedItem(state.selection);
            }
        }
    }
    expect(note.has_value(), "Could not find the note on page 2");
    const double staffLineGap = state.selection.normalizedHeight; // about one staff space

    // Dragging the selected note down on page 2 lowers its pitch.
    expect(session->setSelectionPitchAtPagePosition(1, note->x, note->y + staffLineGap * 2, state, error),
           "Dragging a note's pitch on page 2 failed: " + error);
    expect(state.selection.isNote && state.selection.midiPitch < 72,
           "Dragging a note down on page 2 did not lower its pitch (got " + std::to_string(state.selection.midiPitch) + ")");

    expect(session->setNoteInputEnabled(true, state, error), "Could not enable note input: " + error);
    msr::render::NoteEntryPreviewState preview;
    expect(session->noteEntryPreview(1, note->x, note->y, 4, false, -1, preview, error), "Preview failed: " + error);
    expect(preview.hasPreview && preview.pageIndex == 1, "Hovering the Pencil over page 2's staff showed no preview");
    expect(std::abs((preview.overlayNormalizedY + preview.overlayNormalizedHeight * 0.5) - note->y) < 0.03,
           "The Pencil preview on page 2 is not drawn at page 2's staff");

    expect(session->insertNote(1, note->x, note->y - staffLineGap * 2, state, error), "Pencil insertion on page 2 failed: " + error);
    expect(state.selection.isNote && state.selection.pageIndex == 1,
           "The Pencil note was not entered on page 2");
}

// The pitch of the chord a saved fermata is attached to (it is written just before its chord).
int fermataChordPitch(const std::string& saved)
{
    const size_t fermata = saved.find("<Fermata>");
    const size_t pitch = fermata == std::string::npos ? std::string::npos : saved.find("<pitch>", fermata);
    return pitch == std::string::npos ? -1 : std::stoi(saved.substr(pitch + 7));
}

void testFermataDragShowsAnchorAndMovesToAnotherNote(const std::filesystem::path& root)
{
    auto session = openSession(root, "fermata-drag-anchor", scoreXml(0, { { 60, 14 }, { 62, 16 }, { 64, 18 }, { 65, 13 } }, 1));
    std::map<int, LocatedItem> notes = locateNotesByPitch(*session);
    expect(notes.count(60) && notes.count(64), "Could not locate the test notes");
    msr::render::ScoreEditState state;
    std::string error;
    expect(session->selectElement(0, notes[60].x, notes[60].y, 1.0, state, error), "Could not select the first note: " + error);
    expect(session->addExpression("Fermata", state, error), "Could not add a fermata: " + error);

    std::optional<LocatedItem> fermata;
    for (double y = 0.02; y <= 0.4 && !fermata; y += 0.003) {
        for (double x = 0.02; x <= 0.98 && !fermata; x += 0.003) {
            expect(session->selectElement(0, x, y, 1.0, state, error), "Fermata hit testing failed: " + error);
            if (state.selection.canDragMovableElement && !state.selection.isNote && !state.selection.isEditableText) {
                fermata = locatedItem(state.selection);
            }
        }
    }
    expect(fermata.has_value(), "Could not select the fermata");
    expect(!state.selection.overlayPngData.empty() && !state.selection.overlayPdfData.empty(),
           "A selected fermata should be highlighted by a blue copy of the symbol");
    expect(state.selection.hasAttachmentPoint && state.selection.attachmentTargets.size() == 5,
           "A selected fermata should report its anchor and the 5 notes/rests it can attach to (got "
           + std::to_string(state.selection.attachmentTargets.size()) + ")");
    expect(std::abs(state.selection.attachmentNormalizedX - notes[60].x) < 0.02,
           "The fermata's anchor should be at its note");

    // A small nudge keeps it on the same note.
    expect(session->dragSelectedMovableElement(0, fermata->x + 0.004, fermata->y - 0.01, state, error), "Nudge failed: " + error);
    expect(fermataChordPitch(saveSnapshot(*session, root, "fermata-nudged")) == 60, "A small nudge moved the fermata to another note");

    // Dropping it over the third note moves it there.
    expect(session->dragSelectedMovableElement(0, notes[64].x, fermata->y, state, error), "Drag to another note failed: " + error);
    const std::string moved = saveSnapshot(*session, root, "fermata-moved");
    expect(countOccurrences(moved, "<Fermata>") == 1, "Moving the fermata should not duplicate it");
    expect(fermataChordPitch(moved) == 64, "Dropping the fermata over the third note did not attach it there");
    expect(state.selection.canDragMovableElement && std::abs(state.selection.attachmentNormalizedX - notes[64].x) < 0.02,
           "The moved fermata should stay selected, anchored at its new note");

    expect(session->undo(state, error), "Undo failed: " + error);
    expect(fermataChordPitch(saveSnapshot(*session, root, "fermata-move-undone")) == 60, "Undo did not move the fermata back");
}

// Length in quarter notes of the first saved spanner of a type (its <next><location>).
double spannerLengthInQuarters(const std::string& saved, const std::string& type)
{
    const size_t start = saved.find("<Spanner type=\"" + type + "\"");
    const size_t next = start == std::string::npos ? std::string::npos : saved.find("<next>", start);
    const size_t end = next == std::string::npos ? std::string::npos : saved.find("</next>", next);
    if (end == std::string::npos) {
        return -1.0;
    }
    const std::string location = saved.substr(next, end - next);
    double quarters = 0.0;
    std::smatch match;
    if (std::regex_search(location, match, std::regex("<measures>(-?[0-9]+)</measures>"))) {
        quarters += std::stoi(match[1]) * 4.0;
    }
    if (std::regex_search(location, match, std::regex("<fractions>(-?[0-9]+)/([0-9]+)</fractions>"))) {
        quarters += 4.0 * std::stoi(match[1]) / std::stoi(match[2]);
    }
    return quarters;
}

void testExpressionHandlesSitOnTheLineAndClampWhenCrossed(const std::filesystem::path& root)
{
    std::ostringstream xml;
    xml << R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <Instrument id="violin"><trackName>Violin</trackName><instrumentId>strings.violin</instrumentId><Channel><program value="40"/></Channel></Instrument>
    </Part>
    <Staff id="1">
      <Measure>
        <LayoutBreak><subtype>line</subtype></LayoutBreak>
        <voice>
          <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
          <Clef><concertClefType>G</concertClefType></Clef>
)MSCX";
    const int pitches[] = { 67, 69, 71, 72, 74, 72, 71, 69 };
    for (int index = 0; index < 8; ++index) {
        if (index == 4) {
            xml << "        </voice>\n      </Measure>\n      <Measure>\n        <voice>\n";
        }
        xml << "          <Chord><durationType>quarter</durationType><Note><pitch>" << pitches[index] << "</pitch></Note></Chord>\n";
    }
    xml << "        </voice>\n      </Measure>\n    </Staff>\n  </Score>\n</museScore>\n";
    auto session = openSession(root, "expression-handles", xml.str());
    std::map<int, LocatedItem> notes = locateNotesByPitch(*session);
    expect(notes.count(67) && notes.count(69) && notes.count(71), "Could not locate the first system's notes");
    const LocatedItem note1 = notes[67];
    const LocatedItem note2 = notes[69];
    const LocatedItem note3 = notes[71];
    msr::render::ScoreEditState state;
    std::string error;

    // A crescendo over the first three notes.
    expect(session->selectMeasureRange(0, note1.x, note1.y, note3.x, note3.y, state, error), "Range select failed: " + error);
    expect(session->addExpression("crescendo", state, error), "Could not add a crescendo: " + error);
    expect(state.selection.isExpressionSpanner && state.selection.isHairpin, "The new crescendo should be selected");
    expect(!state.selection.overlayPngData.empty(), "A selected hairpin should be highlighted by a blue copy of itself");
    const double handleY = state.selection.startHandleNormalizedY;
    expect(handleY > note1.y + 0.01 && std::abs(state.selection.endHandleNormalizedY - handleY) < 0.01,
           "Hairpin handles should sit on the wedge below the staff, not on the notes");
    expect(state.selection.startHandleNormalizedX < note2.x && state.selection.endHandleNormalizedX > note3.x - 0.01,
           "Hairpin handles should be at the wedge's ends");
    expect(std::abs(spannerLengthInQuarters(saveSnapshot(*session, root, "hairpin-added"), "HairPin") - 3.0) < 0.01,
           "The crescendo should span three quarter notes");

    // The app snaps a dragged end to these targets (every note of both systems) and sends the
    // chosen one; the engine must attach exactly there.
    expect(state.selection.attachmentTargets.size() == 8,
           "A selected hairpin should offer all 8 notes as attach points, got "
           + std::to_string(state.selection.attachmentTargets.size()));
    msr::render::NormalizedPoint note2Target = state.selection.attachmentTargets.front();
    for (const auto& target : state.selection.attachmentTargets) {
        if (std::abs(target.normalizedX - note2.x) < std::abs(note2Target.normalizedX - note2.x)) {
            note2Target = target;
        }
    }
    const double hairpinEndBefore = state.selection.endHandleNormalizedX;
    expect(session->retargetSelectedExpressionEndpoint(false, 0, note2Target.normalizedX, note2Target.normalizedY, state, error),
           "Dropping the hairpin end on a snapped target failed: " + error);
    expect(state.selection.endHandleNormalizedX < hairpinEndBefore - 0.01,
           "The drawn hairpin did not shorten (its end handle stayed put) after moving its end");
    expect(std::abs(spannerLengthInQuarters(saveSnapshot(*session, root, "hairpin-snapped"), "HairPin") - 2.0) < 0.01,
           "The crescendo should end on the snapped second note");

    // Dragging the end handle at the wedge's height (no snapping) onto the second note.
    expect(session->retargetSelectedExpressionEndpoint(false, 0, note2.x, handleY, state, error),
           "Dragging the hairpin end along the wedge failed: " + error);
    expect(std::abs(spannerLengthInQuarters(saveSnapshot(*session, root, "hairpin-shortened"), "HairPin") - 2.0) < 0.01,
           "The crescendo should now end on the second note");

    // As in the app: tap the hairpin to select it, then drag its end handle with the app's
    // snapping rule (nearest system by target height, then nearest note across) and release.
    expect(session->selectElement(0, note1.x, note1.y, 1.0, state, error), "Could not select a note: " + error);
    bool tappedHairpin = false;
    for (double x = note1.x; x <= note2.x && !tappedHairpin; x += 0.002) {
        for (double dy = -0.01; dy <= 0.01 && !tappedHairpin; dy += 0.002) {
            expect(session->selectElement(0, x, handleY + dy, 1.0, state, error), "Hairpin hit testing failed: " + error);
            tappedHairpin = state.selection.isHairpin;
        }
    }
    expect(tappedHairpin, "Could not tap-select the hairpin");
    {
        const double fingerX = note3.x;
        const double fingerY = state.selection.endHandleNormalizedY;
        double systemY = state.selection.attachmentTargets.front().normalizedY;
        for (const auto& target : state.selection.attachmentTargets) {
            if (std::abs(target.normalizedY - fingerY) < std::abs(systemY - fingerY)) {
                systemY = target.normalizedY;
            }
        }
        std::optional<msr::render::NormalizedPoint> snapped;
        for (const auto& target : state.selection.attachmentTargets) {
            if (std::abs(target.normalizedY - systemY) < 0.0005
                && (!snapped || std::abs(target.normalizedX - fingerX) < std::abs(snapped->normalizedX - fingerX))) {
                snapped = target;
            }
        }
        expect(snapped.has_value(), "The app's snapping rule found no target");
        expect(session->retargetSelectedExpressionEndpoint(false, 0, snapped->normalizedX, snapped->normalizedY, state, error),
               "Releasing a tapped hairpin's end handle failed: " + error);
        expect(std::abs(spannerLengthInQuarters(saveSnapshot(*session, root, "hairpin-tapped-moved"), "HairPin") - 3.0) < 0.01,
               "A tapped hairpin's end did not move to the third note");
        expect(state.selection.isHairpin, "The hairpin should stay selected after moving its end");
    }

    // Dragging the start handle past the end keeps the line over a single note instead of failing.
    expect(session->retargetSelectedExpressionEndpoint(true, 0, note3.x, handleY, state, error),
           "Dragging the hairpin start past its end should not fail: " + error);
    expect(std::abs(spannerLengthInQuarters(saveSnapshot(*session, root, "hairpin-crossed"), "HairPin") - 1.0) < 0.01,
           "A crossed hairpin should shrink to the last note it covered");
    expect(session->deleteSelection(state, error), "Could not delete the hairpin: " + error);

    // A slur over notes 1-3; dragging its end before its start keeps two notes.
    expect(session->selectMeasureRange(0, note1.x, note1.y, note3.x, note3.y, state, error), "Range select failed: " + error);
    expect(session->addExpression("slur", state, error), "Could not add a slur: " + error);
    expect(state.selection.isSlur && !state.selection.overlayPngData.empty(), "A selected slur should be drawn in blue");
    const double slurStartBefore = state.selection.startHandleNormalizedX;
    const double slurEndBefore = state.selection.endHandleNormalizedX;
    // Plain moves: end onto the second note, then back onto the third; start onto the second.
    expect(session->retargetSelectedExpressionEndpoint(false, 0, note2.x, note2.y, state, error), "Moving the slur end failed: " + error);
    expect(std::abs(spannerLengthInQuarters(saveSnapshot(*session, root, "slur-end-moved"), "Slur") - 1.0) < 0.01,
           "The slur end did not move to the second note in the file");
    expect(state.selection.endHandleNormalizedX < slurEndBefore - 0.01, "The slur's end handle did not move left after moving its end");
    expect(session->undo(state, error), "Undoing the slur end move failed: " + error);
    expect(std::abs(spannerLengthInQuarters(saveSnapshot(*session, root, "slur-end-undone"), "Slur") - 2.0) < 0.01,
           "Undo did not restore the slur's end in the file");
    expect(session->redo(state, error), "Redoing the slur end move failed: " + error);
    expect(std::abs(spannerLengthInQuarters(saveSnapshot(*session, root, "slur-end-redone"), "Slur") - 1.0) < 0.01,
           "Redo did not re-apply the slur's end move in the file");
    // Undo/redo clears the selection; tap the slur again, as the user would.
    bool tappedSlur = false;
    for (double y = note1.y - 0.04; y <= note1.y + 0.02 && !tappedSlur; y += 0.002) {
        for (double x = note1.x; x <= note2.x && !tappedSlur; x += 0.002) {
            expect(session->selectElement(0, x, y, 1.0, state, error), "Slur hit testing failed: " + error);
            tappedSlur = state.selection.isSlur;
        }
    }
    expect(tappedSlur, "Could not tap-select the slur after redo");
    expect(session->retargetSelectedExpressionEndpoint(false, 0, note3.x, note3.y, state, error), "Moving the slur end back failed: " + error);
    expect(std::abs(state.selection.endHandleNormalizedX - slurEndBefore) < 0.01, "The slur's end handle did not return to the third note");
    expect(session->retargetSelectedExpressionEndpoint(true, 0, note2.x, note2.y, state, error), "Moving the slur start failed: " + error);
    expect(state.selection.startHandleNormalizedX > slurStartBefore + 0.01, "The slur's start handle did not move right");
    expect(std::abs(spannerLengthInQuarters(saveSnapshot(*session, root, "slur-start-moved"), "Slur") - 1.0) < 0.01,
           "The slur start did not move to the second note in the file");
    expect(session->retargetSelectedExpressionEndpoint(true, 0, note1.x, note1.y, state, error), "Moving the slur start back failed: " + error);
    expect(session->retargetSelectedExpressionEndpoint(false, 0, note1.x - 0.02, state.selection.endHandleNormalizedY, state, error),
           "Dragging the slur end before its start should not fail: " + error);
    expect(std::abs(spannerLengthInQuarters(saveSnapshot(*session, root, "slur-crossed"), "Slur") - 1.0) < 0.01,
           "A crossed slur should keep its first two notes");
}

// The clefs of staff 1 in a saved file, as "<measure>:<type>" in order.
std::vector<std::string> savedClefs(const std::string& saved)
{
    std::vector<std::string> clefs;
    const size_t staffStart = saved.find("<Staff id=\"1\">", saved.find("</Part>"));
    const size_t staffEnd = saved.find("</Staff>", staffStart);
    const std::string staff = saved.substr(staffStart, staffEnd - staffStart);
    int measure = 0;
    for (size_t offset = 0; (offset = staff.find('<', offset)) != std::string::npos; ++offset) {
        if (staff.compare(offset, 8, "<Measure") == 0) {
            ++measure;
        } else if (staff.compare(offset, 6, "<Clef>") == 0) {
            const size_t type = staff.find("<concertClefType>", offset);
            clefs.push_back(std::to_string(measure) + ":" + staff.substr(type + 17, staff.find('<', type + 17) - type - 17));
        }
    }
    return clefs;
}

void testChangeClefOnFirstNoteReplacesTheBarsClef(const std::filesystem::path& root, const bool savedWithOldBug)
{
    // A normal file marks its starting clef as the header clef. A file saved with the old Change
    // Clef bug has an unmarked clef at the start of bar 1, read as a clef change after the
    // time signature.
    const std::string name = savedWithOldBug ? "change-clef-old-bug" : "change-clef";
    std::string xml = R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <Instrument id="piano"><trackName>Piano</trackName><instrumentId>keyboard.piano</instrumentId><Channel><program value="0"/></Channel></Instrument>
    </Part>
    <Staff id="1">
      <Measure>
        <voice>
          <Clef><concertClefType>G</concertClefType>HEADER</Clef>
          <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
          <Chord><durationType>quarter</durationType><Note><pitch>60</pitch></Note></Chord>
          <Chord><durationType>quarter</durationType><Note><pitch>62</pitch></Note></Chord>
          <Chord><durationType>quarter</durationType><Note><pitch>64</pitch></Note></Chord>
          <Chord><durationType>quarter</durationType><Note><pitch>65</pitch></Note></Chord>
        </voice>
      </Measure>
      <Measure>
        <voice>
          <Chord><durationType>quarter</durationType><Note><pitch>67</pitch></Note></Chord>
          <Chord><durationType>quarter</durationType><Note><pitch>69</pitch></Note></Chord>
          <Chord><durationType>half</durationType><Note><pitch>71</pitch></Note></Chord>
        </voice>
      </Measure>
    </Staff>
  </Score>
</museScore>
)MSCX";
    xml.replace(xml.find("HEADER"), 6, savedWithOldBug ? "" : "<isHeader>1</isHeader>");
    auto session = openSession(root, name, xml);
    std::map<int, LocatedItem> notes = locateNotesByPitch(*session);
    expect(notes.count(60) && notes.count(64) && notes.count(67), "Could not locate the test notes");
    msr::render::ScoreEditState state;
    std::string error;

    const std::vector<std::string> originalClefs = savedClefs(saveSnapshot(*session, root, name + "-original"));

    // First note of the score: the starting clef becomes a bass clef, with no extra clef.
    expect(session->selectElement(0, notes[60].x, notes[60].y, 1.0, state, error), "Could not select the first note: " + error);
    expect(session->changeClef("bass", state, error), "Changing the clef failed: " + error);
    std::vector<std::string> clefs = savedClefs(saveSnapshot(*session, root, name + "-first-note"));
    expect(clefs == std::vector<std::string> { "1:F" },
           "Changing the clef on the first note should replace the starting clef, got " + [&] { std::string all; for (const auto& c : clefs) { all += c + " "; } return all; }());

    // Undo brings the treble clef back.
    expect(session->undo(state, error), "Undoing the clef change failed: " + error);
    const std::vector<std::string> undoneClefs = savedClefs(saveSnapshot(*session, root, name + "-undone"));
    if (!savedWithOldBug) {
        expect(undoneClefs == originalClefs, "Undo did not restore the original starting clef");
    }
    expect(std::find(undoneClefs.begin(), undoneClefs.end(), "1:F") == undoneClefs.end() && !undoneClefs.empty(),
           "Undo left a bass clef behind");
    expect(session->redo(state, error), "Redoing the clef change failed: " + error);

    // First note of bar 2: a clef change at the end of bar 1 (where desktop puts it).
    notes = locateNotesByPitch(*session);
    expect(session->selectElement(0, notes[67].x, notes[67].y, 1.0, state, error), "Could not select bar 2's first note: " + error);
    expect(session->changeClef("treble", state, error), "Changing the clef at bar 2 failed: " + error);
    clefs = savedClefs(saveSnapshot(*session, root, name + "-bar-two"));
    expect(clefs == std::vector<std::string> { "1:F", "1:G" },
           "A clef change at bar 2's first note should sit at the end of bar 1");

    // A note in the middle of a bar still gets a clef change right before it.
    expect(session->undo(state, error), "Undo failed: " + error);
    notes = locateNotesByPitch(*session);
    expect(session->selectElement(0, notes[64].x, notes[64].y, 1.0, state, error), "Could not select a mid-bar note: " + error);
    expect(session->changeClef("treble", state, error), "Changing the clef mid-bar failed: " + error);
    clefs = savedClefs(saveSnapshot(*session, root, name + "-mid-bar"));
    expect(clefs == std::vector<std::string> { "1:F", "1:G" }, "A mid-bar clef change should come before the selected note");
}

// A score saved by the old Change Clef bug: a starting treble clef plus a bass clef change right
// after the time signature (so the notes already read in bass clef).
void testStrayStartClefIsOfferedAsARepair(const std::filesystem::path& root)
{
    const auto scoreWith = [](const std::string& strayClef) {
        return std::string(R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <Instrument id="piano"><trackName>Piano</trackName><instrumentId>keyboard.piano</instrumentId><Channel><program value="0"/></Channel></Instrument>
    </Part>
    <Staff id="1">
      <Measure>
        <voice>
          <Clef><concertClefType>G</concertClefType><transposingClefType>G</transposingClefType><isHeader>1</isHeader></Clef>
          <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
)MSCX") + strayClef + R"MSCX(
          <Chord><durationType>half</durationType><Note><pitch>48</pitch></Note></Chord>
          <Chord><durationType>half</durationType><Note><pitch>52</pitch></Note></Chord>
        </voice>
      </Measure>
    </Staff>
  </Score>
</museScore>
)MSCX";
    };
    std::string error;

    // A normal score offers nothing.
    auto clean = openSession(root, "clef-repair-clean", scoreWith(""));
    std::vector<msr::render::ScoreLegacyRepairIssue> issues;
    expect(clean->legacyRepairIssues(issues, error), "Scanning a clean score failed: " + error);
    expect(std::none_of(issues.begin(), issues.end(), [](const auto& issue) { return issue.kind == "strayClef"; }),
           "A normal score should not be offered a clef repair");

    auto damaged = openSession(root, "clef-repair-damaged", scoreWith("<Clef><concertClefType>F</concertClefType><transposingClefType>F</transposingClefType></Clef>"));
    expect(damaged->legacyRepairIssues(issues, error), "Scanning the damaged score failed: " + error);
    const auto stray = std::find_if(issues.begin(), issues.end(), [](const auto& issue) { return issue.kind == "strayClef"; });
    expect(stray != issues.end() && stray->measureNumber == 1 && stray->staffIndex == 0,
           "The stray clef after the time signature should be offered as a repair in measure 1");
    expect(savedClefs(saveSnapshot(*damaged, root, "clef-repair-before")) == std::vector<std::string>({ "1:G", "1:F" }),
           "The damaged test score should start with a treble clef and a stray bass clef");
    const std::map<int, LocatedItem> notesBefore = locateNotesByPitch(*damaged);

    msr::render::ScoreEditState state;
    expect(damaged->applyLegacyRepairs({ stray->index }, state, error), "Applying the clef repair failed: " + error);
    const std::vector<std::string> repairedClefs = savedClefs(saveSnapshot(*damaged, root, "clef-repair-after"));
    expect(repairedClefs == std::vector<std::string>({ "1:F" }),
           "After the repair the bar should have a single bass starting clef, got "
               + std::accumulate(repairedClefs.begin(), repairedClefs.end(), std::string(), [](std::string all, const std::string& clef) {
                     return all + clef + " ";
                 }));
    const std::map<int, LocatedItem> notesAfter = locateNotesByPitch(*damaged);
    for (const int pitch : { 48, 52 }) {
        expect(notesBefore.count(pitch) && notesAfter.count(pitch) && std::abs(notesBefore.at(pitch).y - notesAfter.at(pitch).y) < 0.002,
               "The repair moved a note (pitch " + std::to_string(pitch) + ")");
    }
    expect(damaged->legacyRepairIssues(issues, error)
               && std::none_of(issues.begin(), issues.end(), [](const auto& issue) { return issue.kind == "strayClef"; }),
           "The clef repair should not be offered again once applied");
}

// Lyrics as earlier versions of Aria saved them: "_" left an empty lyric on every note (each with
// its own one-note line) instead of extending the word's line; space left empty lyrics on
// skipped notes; "-" was typed into the text. The repair sheet offers to fix both.
void testOldAriaLyricsAreOfferedAsRepairs(const std::filesystem::path& root)
{
    const auto lyric = [](const std::string& text, const std::string& extra = "") {
        return "<Lyrics>" + extra + "<text>" + text + "</text></Lyrics>";
    };
    const std::string shortLine = "<ticks_f>1/1920</ticks_f>";
    const std::string notes[] = {
        lyric("ah", shortLine), lyric("", shortLine), lyric("", shortLine), lyric(""), // ah _ _ then stopped
        lyric("glo-"), lyric("ry"), lyric(""), lyric("end"),                          // glo-ry, a skipped note, end
    };
    std::ostringstream xml;
    xml << R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <Instrument id="voice"><trackName>Voice</trackName><instrumentId>voice.vocals</instrumentId><Channel><program value="52"/></Channel></Instrument>
    </Part>
    <Staff id="1">
)MSCX";
    for (int bar = 0; bar < 2; ++bar) {
        xml << "      <Measure><voice>" << (bar == 0 ? "<TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>" : "");
        for (int beat = 0; beat < 4; ++beat) {
            xml << "<Chord><durationType>quarter</durationType>" << notes[bar * 4 + beat] << "<Note><pitch>67</pitch></Note></Chord>";
        }
        xml << "</voice></Measure>\n";
    }
    xml << "    </Staff>\n  </Score>\n</museScore>\n";

    auto session = openSession(root, "old-lyrics", xml.str());
    std::vector<msr::render::ScoreLegacyRepairIssue> issues;
    std::string error;
    expect(session->legacyRepairIssues(issues, error), "Scanning failed: " + error);
    std::vector<int> indexes;
    for (const auto& issue : issues) {
        if (issue.kind == "emptyLyrics" || issue.kind == "lyricHyphen") {
            indexes.push_back(issue.index);
        }
    }
    expect(indexes.size() == 2, "Both lyric repairs should be offered");
    msr::render::ScoreEditState state;
    expect(session->applyLegacyRepairs(indexes, state, error), "Applying the lyric repairs failed: " + error);
    const std::string saved = saveSnapshot(*session, root, "old-lyrics-repaired");
    expect(countOccurrences(saved, "<Lyrics>") == 4, "Only ah, glo, ry and end should remain");
    expect(saved.find("<ticks_f>1/2</ticks_f>") != std::string::npos, "ah's line should run over the notes _ was typed on");
    expect(saved.find("glo-") == std::string::npos && saved.find("<syllabic>begin</syllabic>") != std::string::npos
               && saved.find("<syllabic>end</syllabic>") != std::string::npos,
           "glo- ry should become glo-ry with a real hyphen");
    expect(session->legacyRepairIssues(issues, error)
               && std::none_of(issues.begin(), issues.end(), [](const auto& issue) { return issue.kind == "emptyLyrics" || issue.kind == "lyricHyphen"; }),
           "The lyric repairs should not be offered again");

    // A clean score with lyrics, including a real hyphen and extension line, is left alone.
    auto clean = openSession(root, "clean-lyrics", saved);
    expect(clean->legacyRepairIssues(issues, error)
               && std::none_of(issues.begin(), issues.end(), [](const auto& issue) { return issue.kind == "emptyLyrics" || issue.kind == "lyricHyphen"; }),
           "Correct lyrics should not be offered a repair");
}

// A drum kit on a pitched staff, as earlier versions of Aria added it.
void testDrumKitOnPitchedStaffIsOfferedAsARepair(const std::filesystem::path& root)
{
    std::string xml;
    {
        auto session = openSession(root, "drum-source", scoreXml(0, { { 60, 14 } }, 1));
        msr::render::ScoreEditState state;
        std::string error;
        expect(session->addInstrument("drumset", state, error), "Adding a drum set failed: " + error);
        xml = saveSnapshot(*session, root, "drum-source");
    }
    const size_t percussion = xml.find("<StaffType group=\"percussion\">");
    expect(percussion != std::string::npos, "The drum set should be on a percussion staff");
    xml.replace(percussion, xml.find("</StaffType>", percussion) - percussion,
                "<StaffType group=\"pitched\"><name>stdNormal</name>");

    auto session = openSession(root, "drum-damaged", xml);
    std::vector<msr::render::ScoreLegacyRepairIssue> issues;
    std::string error;
    expect(session->legacyRepairIssues(issues, error), "Scanning failed: " + error);
    const auto drum = std::find_if(issues.begin(), issues.end(), [](const auto& issue) { return issue.kind == "drumStaff"; });
    expect(drum != issues.end() && drum->staffIndex == 1, "The drum kit on a pitched staff should be offered a repair");
    msr::render::ScoreEditState state;
    expect(session->applyLegacyRepairs({ drum->index }, state, error), "Applying the drum repair failed: " + error);
    const std::string saved = saveSnapshot(*session, root, "drum-repaired");
    expect(saved.find("<StaffType group=\"percussion\">") != std::string::npos, "The drum kit should now be on a percussion staff");
    expect(session->legacyRepairIssues(issues, error)
               && std::none_of(issues.begin(), issues.end(), [](const auto& issue) { return issue.kind == "drumStaff"; }),
           "The drum repair should not be offered again");
}

// Typed text is plain text; "&" and "<" in it must be escaped in the file, or the score no
// longer opens (found by the random-edit stress test).
void testTypedTextWithAmpersandsSavesAndReopens(const std::filesystem::path& root)
{
    auto session = openSession(root, "ampersand-text", scoreXml(0, { { 60, 14 }, { 62, 16 } }, 1));
    std::map<int, LocatedItem> notes = locateNotesByPitch(*session);
    msr::render::ScoreEditState state;
    std::string error;
    expect(session->selectElement(0, notes[60].x, notes[60].y, 1.0, state, error), "Could not select a note: " + error);
    expect(session->addText("Staff Text", state, error), "Could not add staff text: " + error);
    expect(session->setSelectedText("Rit. & dim. <a tempo>", state, error), "Could not type into the staff text: " + error);
    expect(state.selection.textContent == "Rit. & dim. <a tempo>", "The typed text did not read back unchanged");
    expect(session->selectElement(0, notes[62].x, notes[62].y, 1.0, state, error), "Could not select the second note: " + error);
    expect(session->addLyricsText("rock & roll", false, state, error), "Could not add lyrics: " + error);
    expect(session->selectAttachedLyrics(state, error) && session->setSelectedText("Tom & Jerry", state, error),
           "Could not edit the lyrics: " + error);

    const std::filesystem::path saved = root / "ampersand-saved" / "ampersand-saved.mscx";
    std::filesystem::create_directories(saved.parent_path());
    expect(session->saveToPath(saved.string(), error), "Saving failed: " + error);
    auto reopened = msr::render::ScoreRenderSession::open(saved.string(), error);
    expect(reopened != nullptr, "A score with \"&\" in its text no longer opens: " + error);
    const std::string xml = readFile(saved);
    expect(xml.find("Rit. &amp; dim. &lt;a tempo&gt;") != std::string::npos, "The staff text was not escaped in the file");
    expect(xml.find("Tom &amp; Jerry") != std::string::npos, "The lyrics were not escaped in the file");
}

// An octave shift keeps the note's spelling (desktop's Ctrl+Up), even for E# or Cb.
void testOctaveShiftKeepsSpelling(const std::filesystem::path& root)
{
    // E#4 = MIDI 65 spelled with tpc 25 (E#).
    auto session = openSession(root, "octave-spelling", scoreXml(0, { { 65, 25 } }, 1));
    std::map<int, LocatedItem> notes = locateNotesByPitch(*session);
    expect(notes.count(65), "Could not locate the E#");
    msr::render::ScoreEditState state;
    std::string error;
    expect(session->selectElement(0, notes[65].x, notes[65].y, 1.0, state, error), "Could not select the note: " + error);
    expect(session->shiftSelectionPitchByOctaves(1, state, error), "Octave shift failed: " + error);
    const std::string saved = saveSnapshot(*session, root, "octave-spelling-up");
    expect(saved.find("<pitch>77</pitch>") != std::string::npos, "The note did not move up an octave");
    expect(saved.find("<tpc>25</tpc>") != std::string::npos, "An octave shift re-spelled E# (expected tpc 25)");
}

std::string savedExcerptXml(const std::filesystem::path& root);

// A tempo in half notes or dotted quarters plays at the right speed in the full score and its
// linked part ("half = 60" is 120 quarter notes a minute, stored as 2 beats a second).
void testTempoBeatUnitsReachLinkedParts(const std::filesystem::path& testRoot)
{
    const std::filesystem::path root = testRoot / "tempo-units";
    std::filesystem::create_directories(root);
    auto session = openSession(root, "tempo-units", scoreXml(0, { { 60, 14 } }, 0));
    int pageCount = 0;
    std::string error;
    expect(session->setActivePartIndex(0, pageCount, error) && session->setActivePartIndex(std::nullopt, pageCount, error),
           "Could not create the linked part: " + error);
    for (const auto& [unit, bpm, expected] : std::vector<std::tuple<std::string, int, std::string>> {
             { "half", 60, "<tempo>2</tempo>" }, { "dottedquarter", 60, "<tempo>1.5</tempo>" }, { "eighth", 120, "<tempo>1</tempo>" } }) {
        selectAt(*session, noteWithPitch(scanScore(*session, { 60 }, 0), 60));
        msr::render::ScoreEditState state;
        expect(session->addTempo(unit, bpm, state, error), "Could not add a " + unit + " tempo: " + error);
        const std::string score = saveSnapshot(*session, root, "tempo-units-" + unit);
        const std::string part = savedExcerptXml(root);
        expect(score.find(expected) != std::string::npos, unit + " = " + std::to_string(bpm) + ": full score tempo is wrong (expected " + expected + ")");
        expect(part.find(expected) != std::string::npos, unit + " = " + std::to_string(bpm) + ": linked part tempo is wrong (expected " + expected + ")");
    }
}

// Transposing bars on one staff "to key" changes the key for those bars on that staff only:
// the other staff keeps its key, and the original key returns after the passage.
// A temporary viewing key lays out a clone of the score. MasterScore::clone gave the clone no
// file info, so header and footer macros that read it ($f, $F, $m, $M, $D) crashed during that
// layout (Play Console, Android version 6).
void testViewingKeyWithFileInfoFooter(const std::filesystem::path& root)
{
    std::string xml = scoreXml(0, { { 60, 14 } }, 2);
    const size_t scoreTag = xml.find("<Score>");
    expect(scoreTag != std::string::npos, "Could not add the footer fixture style");
    xml.insert(scoreTag + std::string("<Score>").size(), R"MSCX(
    <Style>
      <showFooter>1</showFooter>
      <footerFirstPage>1</footerFirstPage>
      <footerOddEven>0</footerOddEven>
      <oddFooterL>$f $F</oddFooterL>
      <oddFooterC>$M $m</oddFooterC>
      <oddFooterR>$D</oddFooterR>
    </Style>)MSCX");

    auto session = openSession(root, "viewing-key-footer", xml);
    int pageCount = 0;
    std::string error;
    expect(session->setViewTransposeKey(2, pageCount, error), "Setting a viewing key failed: " + error);
    expect(pageCount > 0, "The transposed view has no pages");
}

void testTransposeToKeyStaysInsideTheSelection(const std::filesystem::path& root)
{
    std::ostringstream xml;
    xml << R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <Instrument id="flute"><trackName>Flute</trackName><instrumentId>wind.flutes.flute</instrumentId><Channel><program value="73"/></Channel></Instrument>
    </Part>
    <Part>
      <Staff id="2"/>
      <Instrument id="violin"><trackName>Violin</trackName><instrumentId>strings.violin</instrumentId><Channel><program value="40"/></Channel></Instrument>
    </Part>
)MSCX";
    const int pitches[2][4] = { { 72, 74, 76, 77 }, { 60, 62, 64, 65 } };
    for (int staff = 0; staff < 2; ++staff) {
        xml << "    <Staff id=\"" << staff + 1 << "\">\n";
        for (int bar = 0; bar < 4; ++bar) {
            xml << "      <Measure><voice>" << (bar == 0 ? "<TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>" : "")
                << "<Chord><durationType>whole</durationType><Note><pitch>" << pitches[staff][bar] << "</pitch></Note></Chord></voice></Measure>\n";
        }
        xml << "    </Staff>\n";
    }
    xml << "  </Score>\n</museScore>\n";
    auto session = openSession(root, "transpose-to-key", xml.str());
    std::map<int, LocatedItem> notes = locateNotesByPitch(*session);
    expect(notes.count(74), "Could not locate bar 2 of the top staff");
    msr::render::ScoreEditState state;
    std::string error;
    expect(session->selectMeasureRange(0, notes[74].x, notes[74].y, notes[74].x, notes[74].y, state, error), "Range select failed: " + error);
    // mode 2 = to key, direction 0 = up, target key 2 = D major
    expect(session->transposeSelectedMeasureRange(2, 0, 0, 2, state, error), "Transpose failed: " + error);
    const std::string saved = saveSnapshot(*session, root, "transpose-to-key");
    auto staffXml = [&saved](const int staff) {
        size_t start = saved.find("</Part>");
        for (int i = 0; i <= staff; ++i) {
            start = saved.find("<Staff id=", saved.find("<Measure", start) - 30 > start ? start : start);
            start = saved.find("<Staff id=\"" + std::to_string(i + 1) + "\">", start);
        }
        return saved.substr(start, saved.find("</Staff>", start) - start);
    };
    const std::string top = staffXml(0);
    const std::string bottom = staffXml(1);
    expect(top.find("<concertKey>2</concertKey>") != std::string::npos, "The transposed bars should be in D major");
    expect(bottom.find("<concertKey>2</concertKey>") == std::string::npos, "The unselected staff got the new key signature");
    expect(countOccurrences(top, "<KeySig>") >= 2, "The original key should return after the transposed bars");
}

void testTransposeToKeyMovesEachSelectedStaffByTheSameAmount(const std::filesystem::path& root)
{
    // Top staff in C, bottom staff in F; both selected from bar 3 to the last bar.
    std::ostringstream xml;
    xml << R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <Instrument id="flute"><trackName>Flute</trackName><instrumentId>wind.flutes.flute</instrumentId><Channel><program value="73"/></Channel></Instrument>
    </Part>
    <Part>
      <Staff id="2"/>
      <Instrument id="violin"><trackName>Violin</trackName><instrumentId>strings.violin</instrumentId><Channel><program value="40"/></Channel></Instrument>
    </Part>
)MSCX";
    const int pitches[2][4] = { { 72, 74, 76, 77 }, { 60, 62, 64, 65 } };
    for (int staff = 0; staff < 2; ++staff) {
        xml << "    <Staff id=\"" << staff + 1 << "\">\n";
        for (int bar = 0; bar < 4; ++bar) {
            xml << "      <Measure><voice>";
            if (bar == 0) {
                xml << (staff == 1 ? "<KeySig><concertKey>-1</concertKey></KeySig>" : "") << "<TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>";
            }
            xml << "<Chord><durationType>whole</durationType><Note><pitch>" << pitches[staff][bar] << "</pitch></Note></Chord></voice></Measure>\n";
        }
        xml << "    </Staff>\n";
    }
    xml << "  </Score>\n</museScore>\n";
    auto session = openSession(root, "transpose-to-key-two-keys", xml.str());
    std::map<int, LocatedItem> notes = locateNotesByPitch(*session);
    expect(notes.count(76) && notes.count(65), "Could not locate bars 3 and 4");
    msr::render::ScoreEditState state;
    std::string error;
    expect(session->selectMeasureRange(0, notes[76].x, notes[76].y, notes[65].x, notes[65].y, state, error), "Range select failed: " + error);
    // mode 2 = to key, direction 0 = up, target key 2 = D major
    expect(session->transposeSelectedMeasureRange(2, 0, 0, 2, state, error), "Transpose failed: " + error);
    const std::string saved = saveSnapshot(*session, root, "transpose-to-key-two-keys");
    const size_t bottomStart = saved.find("<Staff id=\"2\">", saved.find("</Part>", saved.find("</Part>") + 1));
    const std::string top = saved.substr(0, bottomStart);
    const std::string bottom = saved.substr(bottomStart);
    expect(top.find("<concertKey>2</concertKey>") != std::string::npos, "The top staff should move to D major");
    expect(bottom.find("<concertKey>1</concertKey>") != std::string::npos, "The F major staff should move up the same amount, to G major");
    expect(countOccurrences(top, "<KeySig>") == 1, "Nothing follows the last bar, so no key should be restored");
    expect(countOccurrences(bottom, "<KeySig>") == 2, "The bottom staff should keep its F major start and gain one key change");
}

// Lyrics entry follows desktop: "-" hyphenates, space skips without leaving empty lyrics, "_"
// extends the word's line over several notes, and closing the panel removes an empty lyric.
void testLyricsEntryMatchesDesktop(const std::filesystem::path& root)
{
    const std::vector<NoteSpec> fourNotes = { { 60, 14 }, { 62, 16 }, { 64, 18 }, { 65, 13 } };
    msr::render::ScoreEditState state;
    std::string error;
    auto selectFirst = [&](msr::render::ScoreRenderSession& session) {
        std::map<int, LocatedItem> notes = locateNotesByPitch(session);
        expect(notes.count(60), "Could not locate the first note");
        expect(session.selectElement(0, notes[60].x, notes[60].y, 1.0, state, error), "Could not select the first note: " + error);
    };

    {
        auto session = openSession(root, "lyrics-hyphen", scoreXml(0, fourNotes, 1));
        selectFirst(*session);
        expect(session->addLyricsHyphen("glo", state, error), "Hyphen failed: " + error);
        expect(session->addLyricsHyphen("ri", state, error), "Second hyphen failed: " + error);
        expect(session->addLyricsText("a", false, state, error), "Last syllable failed: " + error);
        const std::string saved = saveSnapshot(*session, root, "lyrics-hyphen");
        expect(countOccurrences(saved, "<Lyrics>") == 3, "glo-ri-a should be three lyrics");
        expect(saved.find("<syllabic>begin</syllabic>") != std::string::npos, "glo should begin the word");
        expect(saved.find("<syllabic>middle</syllabic>") != std::string::npos, "ri should be in the middle");
        expect(saved.find("<syllabic>end</syllabic>") != std::string::npos, "a should end the word");
        expect(saved.find("glo-") == std::string::npos, "The hyphen should not be typed into the text");
    }
    {
        auto session = openSession(root, "lyrics-skip", scoreXml(0, fourNotes, 1));
        selectFirst(*session);
        expect(session->addLyricsText("la", true, state, error), "Space failed: " + error);
        expect(session->addLyricsText("", true, state, error), "Skipping a note failed: " + error);
        expect(session->addLyricsText("", true, state, error), "Skipping another note failed: " + error);
        expect(session->addLyricsText("da", false, state, error), "Last lyric failed: " + error);
        const std::string saved = saveSnapshot(*session, root, "lyrics-skip");
        expect(countOccurrences(saved, "<Lyrics>") == 2, "Skipped notes should not keep empty lyrics");
    }
    {
        auto session = openSession(root, "lyrics-extension", scoreXml(0, fourNotes, 1));
        selectFirst(*session);
        expect(session->addLyricsMelisma("ah", state, error), "Extension failed: " + error);
        expect(session->addLyricsMelisma("", state, error), "Second extension failed: " + error);
        expect(session->addLyricsMelisma("", state, error), "Third extension failed: " + error);
        expect(session->addLyricsText("la", false, state, error), "Lyric after the extension failed: " + error);
        const std::string saved = saveSnapshot(*session, root, "lyrics-extension");
        expect(countOccurrences(saved, "<Lyrics>") == 2, "The extension should not leave empty lyrics on the notes it covers");
        expect(saved.find("<ticks_f>1/2</ticks_f>") != std::string::npos, "ah's line should run to the third note");
    }
    {
        // The app's burst: select a note, open lyrics (attaches an empty lyric), then type
        // "glo-ri-a in  ex__" with every command arriving back to back.
        std::string eightNotes = scoreXml(0, fourNotes, 1);
        const size_t firstBarEnd = eightNotes.find("</Measure>") + 10;
        eightNotes.insert(firstBarEnd, "\n      <Measure><voice>"
                                       "<Chord><durationType>quarter</durationType><Note><pitch>67</pitch><tpc>15</tpc></Note></Chord>"
                                       "<Chord><durationType>quarter</durationType><Note><pitch>69</pitch><tpc>17</tpc></Note></Chord>"
                                       "<Chord><durationType>quarter</durationType><Note><pitch>71</pitch><tpc>19</tpc></Note></Chord>"
                                       "<Chord><durationType>quarter</durationType><Note><pitch>72</pitch><tpc>14</tpc></Note></Chord>"
                                       "</voice></Measure>");
        auto session = openSession(root, "lyrics-burst", eightNotes);
        selectFirst(*session);
        expect(session->selectAttachedLyrics(state, error), "Opening lyrics failed: " + error);
        expect(session->addLyricsHyphen("glo", state, error), "glo- failed: " + error);
        expect(session->addLyricsHyphen("ri", state, error), "ri- failed: " + error);
        expect(session->addLyricsText("a", true, state, error), "a failed: " + error);
        expect(session->addLyricsText("in", true, state, error), "in failed: " + error);
        expect(session->addLyricsText("", true, state, error), "Skipping failed: " + error);
        expect(session->addLyricsMelisma("ex", state, error), "ex_ failed: " + error);
        expect(session->addLyricsMelisma("", state, error), "_ failed: " + error);
        expect(session->finishLyricsEntry(state, error), "Closing lyrics failed: " + error);
        const std::string saved = saveSnapshot(*session, root, "lyrics-burst");
        expect(countOccurrences(saved, "<Lyrics>") == 5, "glo ri a in ex should be the only lyrics");
    }
    {
        auto session = openSession(root, "lyrics-close", scoreXml(0, fourNotes, 1));
        selectFirst(*session);
        expect(session->addLyricsText("la", true, state, error), "Space failed: " + error);
        expect(session->finishLyricsEntry(state, error), "Closing lyrics failed: " + error);
        const std::string saved = saveSnapshot(*session, root, "lyrics-close");
        expect(countOccurrences(saved, "<Lyrics>") == 1, "Closing the panel should remove the empty next lyric");
        expect(session->undo(state, error), "Undo failed: " + error);
        expect(session->undo(state, error), "Second undo failed: " + error);
        expect(countOccurrences(saveSnapshot(*session, root, "lyrics-close-undone"), "<Lyrics>") == 0, "Undo should remove the lyrics");
    }
}

// Adding instruments follows desktop's NotationParts::insertNewParts: the new staves take the
// score's key, its staff type (percussion, tablature) and a numbered name.
void testAddedInstrumentsMatchDesktop(const std::filesystem::path& root)
{
    auto session = openSession(root, "add-instruments", scoreXml(2, { { 62, 16 } }, 2));
    msr::render::ScoreEditState state;
    std::string error;
    expect(session->addInstrument("violin", state, error), "Adding a violin failed: " + error);
    expect(session->addInstrument("drumset", state, error), "Adding a drum set failed: " + error);
    expect(session->addInstrument("guitar-steel-tablature", state, error), "Adding a tab guitar failed: " + error);
    const std::string saved = saveSnapshot(*session, root, "add-instruments");
    auto staffXml = [&saved](const int id) {
        const size_t start = saved.find("<Staff id=\"" + std::to_string(id) + "\">", saved.rfind("</Part>"));
        return start == std::string::npos ? std::string() : saved.substr(start, saved.find("</Staff>", start) - start);
    };
    expect(staffXml(2).find("<concertKey>2</concertKey>") != std::string::npos, "The new violin should be in the score's D major");
    expect(saved.find("<StaffType group=\"percussion\">") != std::string::npos, "The drum set should get a percussion staff");
    expect(saved.find("<StaffType group=\"tablature\">") != std::string::npos, "The tab guitar should get a tablature staff");
    expect(saved.find("<trackName>Violin 2</trackName>") != std::string::npos, "A second violin should be named Violin 2");

    // Replacing: the template's staff type and a desktop part name.
    const std::vector<msr::render::ScorePartInfo> parts = session->partInfoList();
    expect(parts.size() == 4, "Expected four parts");
    expect(session->replacePartInstrument(parts[1].partId, "bb-clarinet", state, error), "Replacing with a clarinet failed: " + error);
    expect(session->replacePartInstrument(parts[0].partId, "drumset", state, error), "Replacing with a drum set failed: " + error);
    const std::string replaced = saveSnapshot(*session, root, "replace-instruments");
    expect(replaced.find("<trackName>Clarinet in B♭</trackName>") != std::string::npos, "A clarinet should be named Clarinet in B♭");
    expect(countOccurrences(replaced, "<StaffType group=\"percussion\">") == 2, "The replaced drum set should get a percussion staff");

    // Replacing every instrument keeps the score's key.
    expect(session->replaceInstruments({ "flute", "violoncello" }, state, error), "Replacing all instruments failed: " + error);
    const std::string all = saveSnapshot(*session, root, "replace-all-instruments");
    expect(countOccurrences(all, "<concertKey>2</concertKey>") >= 2, "New instruments should keep the score's D major");
}

// A chord symbol naming a fret diagram moves with its diagram, as in desktop, instead of being
// pulled off it.
void testDraggingFretDiagramChordMovesTheDiagram(const std::filesystem::path& root)
{
    const std::vector<NoteSpec> fourNotes = { { 60, 14 }, { 62, 16 }, { 64, 18 }, { 65, 13 } };
    msr::render::ScoreEditState state;
    std::string error;

    // Write a chord symbol with Aria, then put it inside a fret diagram in the file.
    std::string harmonyXml;
    {
        auto session = openSession(root, "fret-source", scoreXml(0, fourNotes, 1));
        std::map<int, LocatedItem> notes = locateNotesByPitch(*session);
        expect(session->selectElement(0, notes[60].x, notes[60].y, 1.0, state, error), "Could not select the first note: " + error);
        expect(session->addText("Chord Text", state, error), "Adding a chord symbol failed: " + error);
        expect(session->setSelectedText("G", state, error), "Setting the chord failed: " + error);
        const std::string saved = saveSnapshot(*session, root, "fret-source");
        const size_t start = saved.find("<Harmony>");
        expect(start != std::string::npos, "The chord symbol was not saved");
        harmonyXml = saved.substr(start, saved.find("</Harmony>", start) + 10 - start);
    }
    std::string xml = scoreXml(0, fourNotes, 1);
    xml.insert(xml.find("<Chord>"), "<FretDiagram>" + harmonyXml + "</FretDiagram>\n          ");
    auto session = openSession(root, "fret-drag", xml);
    std::map<int, LocatedItem> notes = locateNotesByPitch(*session);

    bool selected = false;
    for (double y = 0.03; y < 0.5 && !selected; y += 0.005) {
        for (double x = 0.03; x < 0.6 && !selected; x += 0.005) {
            selected = session->selectElement(0, x, y, 1.0, state, error) && state.selection.isChordText;
        }
    }
    expect(selected, "Could not tap the diagram's chord symbol");
    expect(session->dragSelectedChordText(0, notes[64].x, state.selection.normalizedY, state, error), "Dragging the chord failed: " + error);
    const std::string saved = saveSnapshot(*session, root, "fret-drag");
    const size_t diagram = saved.find("<FretDiagram>");
    expect(diagram != std::string::npos && countOccurrences(saved, "<FretDiagram>") == 1, "The fret diagram should still be there, once");
    expect(countOccurrences(saved, "<Harmony>") == 1, "There should still be one chord symbol");
    expect(saved.find("<Harmony>", diagram) < saved.find("</FretDiagram>", diagram), "The chord symbol should still name the diagram");
    const size_t secondChord = saved.find("<Chord>", saved.find("<Chord>") + 1);
    expect(diagram > secondChord, "The diagram should have moved to the third note");
}

// The pitch of the first note written after `tag`: what an annotation is attached to.
int pitchAfter(const std::string& saved, const std::string& tag)
{
    const size_t at = saved.find(tag);
    const size_t pitch = at == std::string::npos ? std::string::npos : saved.find("<pitch>", at);
    return pitch == std::string::npos ? -1 : std::stoi(saved.substr(pitch + 7));
}

// The tap, range, expression and drag paths on page 2, in the score's first and last bars there.
void testEditingWorksOnLaterPagesAndEdgeBars(const std::filesystem::path& root)
{
    std::ostringstream xml;
    xml << R"MSCX(<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.70">
  <Score>
    <Division>480</Division>
    <Part>
      <Staff id="1"/>
      <Instrument id="piano"><trackName>Piano</trackName><instrumentId>keyboard.piano</instrumentId><Channel><program value="0"/></Channel></Instrument>
    </Part>
    <Staff id="1">
      <VBox>
        <height>120</height>
        <Text><style>title</style><text>Later pages</text></Text>
        <LayoutBreak><subtype>page</subtype></LayoutBreak>
      </VBox>
)MSCX";
    const int pitches[2][4] = { { 60, 62, 64, 65 }, { 67, 69, 71, 72 } };
    for (int bar = 0; bar < 2; ++bar) {
        xml << "      <Measure><voice>";
        if (bar == 0) {
            xml << "<TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig><Clef><concertClefType>G</concertClefType><isHeader>1</isHeader></Clef>";
        }
        for (const int pitch : pitches[bar]) {
            xml << "<Chord><durationType>quarter</durationType><Note><pitch>" << pitch << "</pitch></Note></Chord>";
        }
        xml << "</voice></Measure>\n";
    }
    xml << "    </Staff>\n  </Score>\n</museScore>\n";
    auto session = openSession(root, "later-pages", xml.str());
    std::map<int, LocatedItem> notes = locateNotesByPitch(*session, 1);
    for (const int pitch : { 60, 62, 64, 65, 67, 69, 71, 72 }) {
        expect(notes.count(pitch) && notes[pitch].pageIndex == 1, "Could not tap note " + std::to_string(pitch) + " on page 2");
    }
    msr::render::ScoreEditState state;
    std::string error;

    // Range from the first bar to the last bar on page 2.
    expect(session->selectMeasureRange(1, notes[60].x, notes[60].y, notes[72].x, notes[72].y, state, error), "Range select failed: " + error);
    expect(state.selection.hasSelection && state.selection.pageIndex == 1, "The range should be on page 2");
    expect(state.selection.normalizedX < notes[60].x && state.selection.normalizedX + state.selection.normalizedWidth > notes[72].x,
           "The range highlight should cover both bars");

    // A crescendo over it, then its end moved back to the second bar's second note.
    expect(session->addExpression("crescendo", state, error), "Could not add a crescendo: " + error);
    expect(std::abs(spannerLengthInQuarters(saveSnapshot(*session, root, "later-hairpin"), "HairPin") - 8.0) < 0.01,
           "The crescendo should cover both bars");
    msr::render::NormalizedPoint target = state.selection.attachmentTargets.front();
    for (const auto& candidate : state.selection.attachmentTargets) {
        if (std::abs(candidate.normalizedX - notes[69].x) < std::abs(target.normalizedX - notes[69].x)) {
            target = candidate;
        }
    }
    expect(session->retargetSelectedExpressionEndpoint(false, 1, target.normalizedX, target.normalizedY, state, error),
           "Moving the hairpin end on page 2 failed: " + error);
    expect(std::abs(spannerLengthInQuarters(saveSnapshot(*session, root, "later-hairpin-moved"), "HairPin") - 6.0) < 0.01,
           "The crescendo should end on the second bar's second note");
    expect(session->deleteSelection(state, error), "Could not delete the hairpin: " + error);

    // A dynamic dragged from the first bar into the last bar.
    expect(session->selectElement(1, notes[64].x, notes[64].y, 1.0, state, error), "Could not select a note: " + error);
    expect(session->addExpression("mf", state, error), "Could not add a dynamic: " + error);
    expect(session->dragSelectedMovableElement(1, notes[71].x, state.selection.normalizedY + state.selection.normalizedHeight * 0.5, state, error),
           "Dragging the dynamic on page 2 failed: " + error);
    expect(pitchAfter(saveSnapshot(*session, root, "later-dynamic"), "<Dynamic>") == 71, "The dynamic should now be on the last bar's third note");

    // A fermata dragged onto the score's very last note.
    expect(session->selectElement(1, notes[65].x, notes[65].y, 1.0, state, error), "Could not select a note: " + error);
    expect(session->addExpression("Fermata", state, error), "Could not add a fermata: " + error);
    bool tappedFermata = false;
    for (double y = notes[65].y - 0.08; y < notes[65].y && !tappedFermata; y += 0.002) {
        for (double x = notes[65].x - 0.02; x < notes[65].x + 0.02 && !tappedFermata; x += 0.002) {
            expect(session->selectElement(1, x, y, 1.0, state, error), "Fermata hit testing failed: " + error);
            tappedFermata = state.selection.canDragMovableElement && !state.selection.isNote && !state.selection.isEditableText;
        }
    }
    expect(tappedFermata, "Could not tap the fermata on page 2");
    expect(session->dragSelectedMovableElement(1, notes[72].x, state.selection.normalizedY + state.selection.normalizedHeight * 0.5, state, error),
           "Dragging the fermata on page 2 failed: " + error);
    expect(pitchAfter(saveSnapshot(*session, root, "later-fermata"), "<Fermata>") == 72, "The fermata should now be on the last note");

    // A chord symbol dragged from the first note across the barline.
    expect(session->selectElement(1, notes[60].x, notes[60].y, 1.0, state, error), "Could not select the first note: " + error);
    expect(session->addText("Chord Text", state, error), "Adding a chord symbol failed: " + error);
    expect(session->setSelectedText("C", state, error), "Setting the chord failed: " + error);
    expect(session->dragSelectedChordText(1, notes[67].x, state.selection.normalizedY + state.selection.normalizedHeight * 0.5, state, error),
           "Dragging the chord symbol on page 2 failed: " + error);
    expect(pitchAfter(saveSnapshot(*session, root, "later-chord"), "<Harmony>") == 67, "The chord symbol should now be on the second bar's first note");
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
               "viola", // template id, as the app's instrument catalog passes
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

    // The old part-view bug could instead leave the full score blank.
    reopened.reset();
    const std::filesystem::path masterPath = root / "blank-dynamics-repaired.mscx";
    std::string master = readFile(masterPath);
    const size_t masterMf = master.find("<subtype>mf</subtype>");
    expect(masterMf != std::string::npos, "The repaired full score has no mf dynamic");
    master.replace(masterMf, std::string("<subtype>mf</subtype>").size(), "<subtype>other-dynamics</subtype>");
    writeFile(masterPath, master);
    reopened = msr::render::ScoreRenderSession::open(masterPath.string(), error);
    expect(reopened != nullptr, "Could not reopen the damaged full score: " + error);
    expect(reopened->legacyRepairIssues(issues, error), "Could not scan the damaged full score: " + error);
    expect(issues.size() == 1 && issues.front().location == "Full score", "The full-score dynamic was not offered as a repair");
    expect(reopened->applyLegacyRepairs({ issues.front().index }, state, error), "Could not repair the full score: " + error);
    saveSnapshot(*reopened, root, "blank-full-score-repaired");
    expect(readFile(root / "blank-full-score-repaired.mscx").find("other-dynamics") == std::string::npos,
           "The full-score dynamic was not saved after repair");
}

// Aria's engine before 4.7.5 left a few MuseScore 5-only style tags in every save;
// repairs for that engine's bugs are only offered for files carrying them.
void markSavedByOldAria(const std::filesystem::path& root, const std::string& name)
{
    static const std::string oldEngineTag = "<groupBracketOffset x=\"0\" y=\"0\"/>";
    const std::filesystem::path stylePath = root / "score_style.mss";
    const std::filesystem::path scorePath = root / (name + ".mscx");
    const std::filesystem::path path = std::filesystem::exists(stylePath) ? stylePath : scorePath;
    std::string xml = readFile(path);
    const size_t style = xml.find("<Style>");
    expect(style != std::string::npos, "Saved score has no style to mark as old Aria: " + path.string());
    xml.insert(style + std::string("<Style>").size(), oldEngineTag);
    writeFile(path, xml);
}

std::vector<msr::render::ScoreLegacyRepairIssue> reopenAndScan(const std::filesystem::path& root, const std::string& name,
                                                               std::unique_ptr<msr::render::ScoreRenderSession>* keep = nullptr)
{
    std::string error;
    auto reopened = msr::render::ScoreRenderSession::open((root / (name + ".mscx")).string(), error);
    expect(reopened != nullptr, "Could not reopen " + name + ": " + error);
    std::vector<msr::render::ScoreLegacyRepairIssue> issues;
    expect(reopened->legacyRepairIssues(issues, error), "Could not scan " + name + ": " + error);
    if (keep) {
        *keep = std::move(reopened);
    }
    return issues;
}

size_t countIssues(const std::vector<msr::render::ScoreLegacyRepairIssue>& issues, const std::string& kind)
{
    return static_cast<size_t>(std::count_if(issues.begin(), issues.end(), [&](const auto& issue) { return issue.kind == kind; }));
}

std::string removeBlocks(std::string xml, const std::string& tag)
{
    return std::regex_replace(xml, std::regex("<" + tag + ">[\\s\\S]*?</" + tag + ">"), "");
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

    // A part tempo that differs from the full score can be deliberate in a file saved
    // by anything other than the pre-4.7.5 Aria engine.
    expect(countIssues(reopenAndScan(root, "old-part-tempo-saved"), "tempo") == 0,
           "A differing part tempo was offered as a repair in a file not saved by old Aria");
    markSavedByOldAria(root, "old-part-tempo-saved");
    part = readFile(partPath);

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

void testOldAriaMissingRepeatsRequireApproval(const std::filesystem::path& testRoot)
{
    const std::filesystem::path root = testRoot / "old-missing-repeats";
    std::filesystem::create_directories(root);
    auto session = openSession(root, "old-missing-repeats", scoreXml(0, { { 60, 14 } }, 1));
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
    saveSnapshot(*session, root, "old-missing-repeats-saved");
    session.reset();

    // Older Aria added jumps and markers to the full score only.
    const std::filesystem::path partPath = savedExcerptPath(root);
    writeFile(partPath, removeBlocks(removeBlocks(readFile(partPath), "Jump"), "Marker"));
    expect(countIssues(reopenAndScan(root, "old-missing-repeats-saved"), "missingRepeat") == 0,
           "A part without repeat signs was offered as a repair in a file not saved by old Aria");

    markSavedByOldAria(root, "old-missing-repeats-saved");
    const std::string partBefore = readFile(partPath);
    std::unique_ptr<msr::render::ScoreRenderSession> reopened;
    std::vector<msr::render::ScoreLegacyRepairIssue> issues = reopenAndScan(root, "old-missing-repeats-saved", &reopened);
    expect(countIssues(issues, "missingRepeat") == 2, "The segno and D.S. al Coda missing from the part were not offered");
    expect(readFile(partPath) == partBefore, "Opening silently changed the part");

    std::vector<int> indexes;
    for (const auto& issue : issues) {
        indexes.push_back(issue.index);
    }
    expect(reopened->applyLegacyRepairs(indexes, state, error), "Could not repair the missing repeat signs: " + error);
    expect(reopened->legacyRepairIssues(issues, error) && countIssues(issues, "missingRepeat") == 0,
           "The repeat-sign repair did not clear the issues");
    const std::string score = saveSnapshot(*reopened, root, "old-missing-repeats-repaired");
    const std::string part = savedExcerptXml(root);
    expect(countOccurrences(part, "<Marker>") == 1 && countOccurrences(part, "<Jump>") == 1,
           "The repaired part did not receive exactly one segno and one D.S. al Coda");
    expect(countOccurrences(score, "<Marker>") == 1 && countOccurrences(score, "<Jump>") == 1,
           "The repair duplicated repeat signs in the full score");
    expect(reopened->undo(state, error), "Could not undo the repeat-sign repair: " + error);
    saveSnapshot(*reopened, root, "old-missing-repeats-undone");
    expect(countOccurrences(savedExcerptXml(root), "<Jump>") == 0, "Undo did not remove the restored D.S. al Coda from the part");
}

void testOldAriaPartOnlyTempoRequiresApproval(const std::filesystem::path& testRoot)
{
    const std::filesystem::path root = testRoot / "old-part-only-tempo";
    std::filesystem::create_directories(root);
    auto session = openSession(root, "old-part-only-tempo", scoreXml(0, { { 60, 14 } }, 0));
    int pageCount = 0;
    std::string error;
    expect(session->setActivePartIndex(0, pageCount, error), "Could not create the linked part: " + error);
    expect(session->setActivePartIndex(std::nullopt, pageCount, error), "Could not return to the full score: " + error);
    msr::render::ScoreEditState state;
    selectAt(*session, noteWithPitch(scanScore(*session, { 60 }, 0), 60));
    expect(session->addTempo("quarter", 90, state, error), "Could not add a tempo: " + error);
    saveSnapshot(*session, root, "old-part-only-tempo-saved");
    session.reset();

    // Older Aria kept a tempo added while viewing a part in that part only.
    const std::filesystem::path scorePath = root / "old-part-only-tempo-saved.mscx";
    writeFile(scorePath, removeBlocks(readFile(scorePath), "Tempo"));
    expect(countIssues(reopenAndScan(root, "old-part-only-tempo-saved"), "missingTempo") == 0,
           "A part-only tempo was offered as a repair in a file not saved by old Aria");

    markSavedByOldAria(root, "old-part-only-tempo-saved");
    std::unique_ptr<msr::render::ScoreRenderSession> reopened;
    std::vector<msr::render::ScoreLegacyRepairIssue> issues = reopenAndScan(root, "old-part-only-tempo-saved", &reopened);
    expect(countIssues(issues, "missingTempo") == 1, "The tempo found only in the part was not offered");
    const auto tempoIssue = std::find_if(issues.begin(), issues.end(), [](const auto& issue) { return issue.kind == "missingTempo"; });
    expect(tempoIssue->location == "Part 1", "The part-only tempo was reported in the wrong place: " + tempoIssue->location);

    expect(reopened->applyLegacyRepairs({ tempoIssue->index }, state, error), "Could not repair the part-only tempo: " + error);
    expect(reopened->legacyRepairIssues(issues, error) && countIssues(issues, "missingTempo") == 0,
           "The part-only tempo repair did not clear the issue");
    const std::string score = saveSnapshot(*reopened, root, "old-part-only-tempo-repaired");
    const std::string part = savedExcerptXml(root);
    expect(countOccurrences(score, "<Tempo>") == 1 && score.find("<tempo>1.5</tempo>") != std::string::npos,
           "The full score did not receive the part's 90 BPM tempo: " + score);
    expect(countOccurrences(part, "<Tempo>") == 1, "The repair duplicated the tempo in the part");
}

// Desktop MuseScore allows chord symbols that exist only in a part, so files it saved
// must stay saveable. The pre-4.7.5 engine produced the same shape by mistake when
// editing parts, so in files it saved the save guard keeps blocking them.
void testPartOnlyChordSymbolsFromDesktopCanBeSaved(const std::filesystem::path& testRoot)
{
    const std::filesystem::path root = testRoot / "part-only-chords";
    std::filesystem::create_directories(root);
    auto session = openSession(root, "part-only-chords", scoreXml(0, { { 60, 14 } }, 0));
    int pageCount = 0;
    std::string error;
    expect(session->setActivePartIndex(0, pageCount, error), "Could not create the linked part: " + error);
    expect(session->setActivePartIndex(std::nullopt, pageCount, error), "Could not return to the full score: " + error);
    msr::render::ScoreEditState state;
    selectAt(*session, noteWithPitch(scanScore(*session, { 60 }, 0), 60));
    expect(session->addText("chord", state, error), "Could not add a chord symbol: " + error);
    expect(session->setSelectedText("C7", state, error), "Could not set the chord symbol: " + error);
    saveSnapshot(*session, root, "part-only-chords-saved");
    session.reset();

    // As desktop writes it: the chord symbol only in the part, with no link to the full score.
    const std::filesystem::path scorePath = root / "part-only-chords-saved.mscx";
    writeFile(scorePath, removeBlocks(readFile(scorePath), "Harmony"));
    const std::filesystem::path partPath = savedExcerptPath(root);
    writeFile(partPath, std::regex_replace(readFile(partPath), std::regex("<linkedTo>[^<]*</linkedTo>"), ""));
    expect(countOccurrences(savedExcerptXml(root), "<Harmony") == 1, "The part lost its chord symbol before the test");

    auto reopened = msr::render::ScoreRenderSession::open(scorePath.string(), error);
    expect(reopened != nullptr, "Could not reopen the desktop-style file: " + error);
    const std::string resaved = saveSnapshot(*reopened, root, "part-only-chords-resaved");
    expect(countOccurrences(resaved, "<Harmony") == 0, "Saving copied the part-only chord symbol into the full score");
    expect(countOccurrences(savedExcerptXml(root), "<Harmony") == 1, "Saving dropped the part-only chord symbol");
    reopened.reset();

    markSavedByOldAria(root, "part-only-chords-resaved");
    auto oldEngineFile = msr::render::ScoreRenderSession::open((root / "part-only-chords-resaved.mscx").string(), error);
    expect(oldEngineFile != nullptr, "Could not reopen the old-engine file: " + error);
    error.clear();
    expect(!oldEngineFile->saveToPath((root / "part-only-chords-blocked.mscx").string(), error),
           "A part-only chord symbol in a file saved by the old engine was not blocked");
    expect(error.find("chord symbol") != std::string::npos, "The old-engine file was blocked for another reason: " + error);
}

// Deleting every chord symbol looks like the pre-4.7.5 engine losing them, so the
// save pauses; once the user confirms, it saves without them.
void testRemovingAllChordSymbolsNeedsApproval(const std::filesystem::path& testRoot)
{
    const std::filesystem::path root = testRoot / "chord-removal";
    std::filesystem::create_directories(root);
    auto session = openSession(root, "chord-removal", scoreXml(0, { { 60, 14 }, { 62, 16 }, { 64, 18 } }, 0));
    msr::render::ScoreEditState state;
    std::string error;
    for (const int pitch : { 60, 62, 64 }) {
        selectAt(*session, noteWithPitch(scanScore(*session, { 60, 62, 64 }, 0), pitch));
        expect(session->addText("chord", state, error), "Could not add a chord symbol: " + error);
        expect(session->setSelectedText("C", state, error), "Could not set the chord symbol: " + error);
    }
    expect(countOccurrences(saveSnapshot(*session, root, "chord-removal-with-chords"), "<Harmony") == 3,
           "The three chord symbols were not saved");

    for (const int pitch : { 60, 62, 64 }) {
        selectAt(*session, noteWithPitch(scanScore(*session, { 60, 62, 64 }, 0), pitch));
        expect(session->selectAttachedChordText(state, error), "Could not select the chord symbol: " + error);
        expect(session->deleteSelection(state, error), "Could not delete the chord symbol: " + error);
    }
    const std::string blockedPath = (root / "chord-removal-blocked.mscx").string();
    error.clear();
    expect(!session->saveToPath(blockedPath, error), "Removing every chord symbol saved without confirmation");
    expect(session->chordSymbolRemovalNeedsApproval(), "The paused save did not ask for approval");

    session->acceptChordSymbolRemoval();
    expect(!session->chordSymbolRemovalNeedsApproval(), "Approval was still requested after confirming");
    expect(countOccurrences(saveSnapshot(*session, root, "chord-removal-confirmed"), "<Harmony") == 0,
           "The confirmed save still contains chord symbols");
}

void testOldAriaPartNamesRequireApproval(const std::filesystem::path& testRoot)
{
    const std::filesystem::path root = testRoot / "old-part-names";
    std::filesystem::create_directories(root);
    auto session = openSession(root, "old-part-names", scoreXml(0, { { 60, 14 } }, 0));
    int pageCount = 0;
    std::string error;
    expect(session->setActivePartIndex(0, pageCount, error), "Could not create the linked part: " + error);
    expect(session->setActivePartIndex(std::nullopt, pageCount, error), "Could not return to the full score: " + error);
    saveSnapshot(*session, root, "old-part-names-saved");
    session.reset();

    // Older Aria escaped "&" twice, so "Keys & Synth" read back as "Keys &amp; Synth".
    const std::regex trackName("<trackName>[^<]*</trackName>");
    const std::string doubled = "<trackName>Keys &amp;amp; Synth</trackName>";
    const std::filesystem::path scorePath = root / "old-part-names-saved.mscx";
    const std::filesystem::path partPath = savedExcerptPath(root);
    writeFile(scorePath, std::regex_replace(readFile(scorePath), trackName, doubled));
    writeFile(partPath, std::regex_replace(readFile(partPath), trackName, doubled));
    expect(countIssues(reopenAndScan(root, "old-part-names-saved"), "partName") == 0,
           "A part name was offered as a repair in a file not saved by old Aria");

    markSavedByOldAria(root, "old-part-names-saved");
    std::unique_ptr<msr::render::ScoreRenderSession> reopened;
    std::vector<msr::render::ScoreLegacyRepairIssue> issues = reopenAndScan(root, "old-part-names-saved", &reopened);
    expect(countIssues(issues, "partName") == 1, "The double-escaped part name was not offered as one repair");
    const auto nameIssue = std::find_if(issues.begin(), issues.end(), [](const auto& issue) { return issue.kind == "partName"; });
    msr::render::ScoreEditState state;
    expect(reopened->applyLegacyRepairs({ nameIssue->index }, state, error), "Could not repair the part name: " + error);
    expect(reopened->legacyRepairIssues(issues, error) && countIssues(issues, "partName") == 0,
           "The part-name repair did not clear the issue");
    const std::string score = saveSnapshot(*reopened, root, "old-part-names-repaired");
    const std::string part = savedExcerptXml(root);
    expect(savedPartTrackName(score) == "Keys &amp; Synth", "The full score kept the double-escaped name: " + savedPartTrackName(score));
    expect(savedPartTrackName(part) == "Keys &amp; Synth", "The part kept the double-escaped name: " + savedPartTrackName(part));
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
    passed &= runTest("fermatas can be selected, dragged and deleted", [&] { testFermataCanBeSelectedDraggedAndDeleted(testDirectory.path); });
    for (const auto& [name, tag] : std::vector<std::pair<std::string, std::string>> {
             { "tappable-glissando", "<Glissando" },
             { "tappable-tuplet", "<Tuplet" },
             { "tappable-arpeggio", "<Arpeggio" },
             { "tappable-clef", "<Clef" } }) {
        passed &= runTest(tag.substr(1) + " can be tapped and deleted",
                          [&] { testElementCanBeTappedAndDeleted(testDirectory.path, name, tag); });
    }
    passed &= runTest("range drags include the beat they end on", [&] { testRangeDragIncludesTheBeatItEndsOn(testDirectory.path); });
    passed &= runTest("fermata button toggles on notes, rests and ranges",
                      [&] { testFermataButtonTogglesOnNotesRestsAndRanges(testDirectory.path); });
    passed &= runTest("range highlights cover every page", [&] { testRangeHighlightCoversEveryPage(testDirectory.path); });
    passed &= runTest("pencil input works on later pages", [&] { testPencilInputWorksOnLaterPages(testDirectory.path); });
    passed &= runTest("editing works on later pages and edge bars", [&] { testEditingWorksOnLaterPagesAndEdgeBars(testDirectory.path); });
    passed &= runTest("fermata drag shows its anchor and can move to another note",
                      [&] { testFermataDragShowsAnchorAndMovesToAnotherNote(testDirectory.path); });
    passed &= runTest("expression handles sit on the line and clamp when crossed",
                      [&] { testExpressionHandlesSitOnTheLineAndClampWhenCrossed(testDirectory.path); });
    passed &= runTest("change clef on a bar's first note replaces the bar's clef",
                      [&] { testChangeClefOnFirstNoteReplacesTheBarsClef(testDirectory.path, false); });
    passed &= runTest("change clef repairs scores saved with the stray-clef bug",
                      [&] { testChangeClefOnFirstNoteReplacesTheBarsClef(testDirectory.path, true); });
    passed &= runTest("a stray start-of-bar clef is offered as a repair", [&] { testStrayStartClefIsOfferedAsARepair(testDirectory.path); });
    passed &= runTest("typed text with ampersands saves and reopens", [&] { testTypedTextWithAmpersandsSavesAndReopens(testDirectory.path); });
    passed &= runTest("octave shift keeps spelling", [&] { testOctaveShiftKeepsSpelling(testDirectory.path); });
    passed &= runTest("tempo beat units reach linked parts", [&] { testTempoBeatUnitsReachLinkedParts(testDirectory.path); });
    passed &= runTest("transpose to key stays inside the selection", [&] { testTransposeToKeyStaysInsideTheSelection(testDirectory.path); });
    passed &= runTest("a viewing key works with file-info footer macros",
                      [&] { testViewingKeyWithFileInfoFooter(testDirectory.path); });
    passed &= runTest("dragging a fret diagram's chord moves the diagram",
                      [&] { testDraggingFretDiagramChordMovesTheDiagram(testDirectory.path); });
    passed &= runTest("added instruments match desktop", [&] { testAddedInstrumentsMatchDesktop(testDirectory.path); });
    passed &= runTest("old Aria lyrics are offered as repairs", [&] { testOldAriaLyricsAreOfferedAsRepairs(testDirectory.path); });
    passed &= runTest("drum kit on a pitched staff is offered as a repair",
                      [&] { testDrumKitOnPitchedStaffIsOfferedAsARepair(testDirectory.path); });
    passed &= runTest("lyrics entry matches desktop", [&] { testLyricsEntryMatchesDesktop(testDirectory.path); });
    passed &= runTest("transpose to key moves each selected staff by the same amount",
                      [&] { testTransposeToKeyMovesEachSelectedStaffByTheSameAmount(testDirectory.path); });
    passed &= runTest("measure selections carry instrument context", [&] { testMeasureSelectionCarriesInstrumentContext(testDirectory.path); });
    passed &= runTest("part names survive save and follow instrument replacement", [&] { testPartNamesSurviveSave(testDirectory.path); });
    passed &= runTest("new dynamics and text reach linked parts", [&] { testNewDynamicsAndTextReachLinkedParts(testDirectory.path); });
    passed &= runTest("blank part dynamics require approval", [&] { testBlankPartDynamicsRequireApproval(testDirectory.path); });
    passed &= runTest("old part tempo requires approval", [&] { testOldPartTempoRequiresApproval(testDirectory.path); });
    passed &= runTest("jumps and markers reach linked parts", [&] { testJumpsAndMarkersReachLinkedParts(testDirectory.path); });
    passed &= runTest("old Aria repeat signs missing from parts require approval",
                      [&] { testOldAriaMissingRepeatsRequireApproval(testDirectory.path); });
    passed &= runTest("old Aria part-only tempo requires approval", [&] { testOldAriaPartOnlyTempoRequiresApproval(testDirectory.path); });
    passed &= runTest("old Aria double-escaped part names require approval", [&] { testOldAriaPartNamesRequireApproval(testDirectory.path); });
    passed &= runTest("part-only chord symbols from desktop can be saved",
                      [&] { testPartOnlyChordSymbolsFromDesktopCanBeSaved(testDirectory.path); });
    passed &= runTest("removing all chord symbols needs approval",
                      [&] { testRemovingAllChordSymbolsNeedsApproval(testDirectory.path); });
    return passed ? 0 : 1;
}
