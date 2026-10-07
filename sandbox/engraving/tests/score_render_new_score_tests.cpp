// Creates scores the way Aria's "New Score" sheet does (MuseReaderAppModel.createScore)
// from every bundled template, across the key, time signature, pickup, measure count and
// tempo choices the sheet offers, and checks the saved file says what the user picked.
//
// usage: score_render_new_score_tests <ScoreTemplates.bundle> [output dir to keep the files]

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <optional>
#include <regex>
#include <sstream>
#include <string>
#include <vector>

#include "score_render_core.h"

namespace {
struct NewScoreOptions {
    std::string label;
    std::string title = "Test Title";
    std::string composer = "Test Composer";
    int keyValue = 0;
    int numerator = 4;
    int denominator = 4;
    bool cutTime = false;
    int measureCount = 32;
    std::optional<std::pair<int, int>> pickup;
    int bpm = 120;
    std::vector<std::string> replacementInstruments;
};

std::string readFile(const std::filesystem::path& path)
{
    std::ifstream stream(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
}

size_t countOccurrences(const std::string& haystack, const std::string& needle)
{
    size_t count = 0;
    for (size_t offset = haystack.find(needle); offset != std::string::npos; offset = haystack.find(needle, offset + needle.size())) {
        ++count;
    }
    return count;
}

// The <Staff id="1"> block that holds measures (the first one inside <Part> only describes the staff).
std::string firstStaffMusic(const std::string& xml)
{
    const size_t firstMeasure = xml.find("<Measure");
    if (firstMeasure == std::string::npos) {
        return {};
    }
    const size_t staffStart = xml.rfind("<Staff id=", firstMeasure);
    const size_t staffEnd = xml.find("</Staff>", firstMeasure);
    if (staffStart == std::string::npos || staffEnd == std::string::npos) {
        return {};
    }
    return xml.substr(staffStart, staffEnd - staffStart);
}

std::string firstMeasure(const std::string& staffMusic)
{
    const size_t start = staffMusic.find("<Measure");
    const size_t end = staffMusic.find("</Measure>", start);
    return start == std::string::npos || end == std::string::npos ? std::string() : staffMusic.substr(start, end - start);
}

std::vector<std::string> checkCreatedScore(const std::string& xml, const NewScoreOptions& options, const bool isPercussionOnly)
{
    std::vector<std::string> problems;
    auto expectThat = [&](const bool condition, const std::string& message) {
        if (!condition) {
            problems.push_back(message);
        }
    };

    expectThat(xml.find("<museScore version=\"4.70\"") != std::string::npos, "not saved as MuseScore 4.70");
    expectThat(xml.find(">" + options.title + "<") != std::string::npos, "title missing");
    expectThat(xml.find(">" + options.composer + "<") != std::string::npos, "composer missing");

    const std::string staff = firstStaffMusic(xml);
    const int expectedMeasures = options.measureCount + (options.pickup ? 1 : 0);
    const int measures = static_cast<int>(countOccurrences(staff, "<Measure"));
    expectThat(measures == expectedMeasures,
               "expected " + std::to_string(expectedMeasures) + " measures, got " + std::to_string(measures));

    const std::string measure1 = firstMeasure(staff);
    if (options.pickup) {
        const std::string len = "len=\"" + std::to_string(options.pickup->first) + "/" + std::to_string(options.pickup->second) + "\"";
        expectThat(measure1.find(len) != std::string::npos, "pickup measure missing " + len);
    } else {
        expectThat(measure1.find("len=\"") == std::string::npos, "unexpected pickup (irregular first measure)");
    }

    expectThat(measure1.find("<sigN>" + std::to_string(options.numerator) + "</sigN>") != std::string::npos
               && measure1.find("<sigD>" + std::to_string(options.denominator) + "</sigD>") != std::string::npos,
               "time signature is not " + std::to_string(options.numerator) + "/" + std::to_string(options.denominator));
    if (options.cutTime) {
        expectThat(measure1.find("<subtype>2</subtype>") != std::string::npos, "cut-time symbol missing");
    }
    // No stray time signatures from the template later in the score.
    expectThat(countOccurrences(staff, "<TimeSig>") == 1, "more than one time signature on staff 1");

    if (!isPercussionOnly) {
        const std::string concertKey = "<concertKey>" + std::to_string(options.keyValue) + "</concertKey>";
        if (options.keyValue != 0) {
            expectThat(xml.find(concertKey) != std::string::npos, "key signature " + std::to_string(options.keyValue) + " missing");
        }
        std::regex keyPattern("<concertKey>(-?[0-9]+)</concertKey>");
        for (auto it = std::sregex_iterator(xml.begin(), xml.end(), keyPattern); it != std::sregex_iterator(); ++it) {
            if (std::stoi((*it)[1]) != options.keyValue) {
                problems.push_back("found a different key signature " + std::string((*it)[1]));
                break;
            }
        }
    }

    std::smatch tempoMatch;
    const std::regex tempoPattern("<Tempo>[\\s\\S]*?<tempo>([0-9.]+)</tempo>");
    if (std::regex_search(xml, tempoMatch, tempoPattern)) {
        const double bpm = std::stod(tempoMatch[1]) * 60.0;
        expectThat(std::abs(bpm - options.bpm) < 0.01, "tempo is " + std::to_string(bpm) + " bpm");
    } else {
        problems.push_back("tempo marking missing");
    }
    // Large templates repeat system markings above other staff groups as linked copies (as desktop does).
    int originalTempoMarkings = 0;
    const std::regex tempoElement("<Tempo>[\\s\\S]*?</Tempo>");
    for (auto it = std::sregex_iterator(xml.begin(), xml.end(), tempoElement); it != std::sregex_iterator(); ++it) {
        originalTempoMarkings += it->str().find("<linkedTo>") == std::string::npos ? 1 : 0;
    }
    expectThat(originalTempoMarkings == 1, "expected exactly one tempo marking, got " + std::to_string(originalTempoMarkings));

    for (const std::string& instrument : options.replacementInstruments) {
        expectThat(xml.find("<Instrument id=\"" + instrument + "\"") != std::string::npos, "instrument " + instrument + " missing");
    }
    if (!options.replacementInstruments.empty()) {
        expectThat(countOccurrences(xml, "<Part") == options.replacementInstruments.size(),
                   "expected " + std::to_string(options.replacementInstruments.size()) + " parts");
    }
    return problems;
}

std::optional<std::string> createScore(const std::filesystem::path& templatePath,
                                       const NewScoreOptions& options,
                                       const std::filesystem::path& outputPath,
                                       std::string& error)
{
    std::unique_ptr<msr::render::ScoreRenderSession> session = msr::render::ScoreRenderSession::open(templatePath.string(), error);
    if (!session || !session->supportsEditing()) {
        error = "could not open: " + error;
        return std::nullopt;
    }
    msr::render::ScoreEditState state;
    auto step = [&](const bool ok, const std::string& name) {
        if (!ok) {
            error = name + ": " + error;
        }
        return ok;
    };
    if (!options.replacementInstruments.empty()
        && !step(session->replaceInstruments(options.replacementInstruments, state, error), "replaceInstruments")) {
        return std::nullopt;
    }
    msr::render::ScoreMetadata metadata;
    metadata.title = options.title;
    metadata.composer = options.composer;
    if (!step(session->resetTemplateMeasures(options.measureCount, state, error), "resetTemplateMeasures")
        || !step(session->updateMetadata(metadata, error), "updateMetadata")
        || !step(session->updateInitialKeySignature(options.keyValue, error), "updateInitialKeySignature")
        || !step(session->updateTimeSignature(options.numerator, options.denominator, false, options.cutTime, true, state, error),
                 "updateTimeSignature")
        || (options.pickup && !step(session->setFirstMeasurePickup(options.pickup->first, options.pickup->second, state, error),
                                    "setFirstMeasurePickup"))
        || !step(session->setRegularMeasureCount(options.measureCount, state, error), "setRegularMeasureCount")
        || !step(session->addTempo("quarter", options.bpm, state, error), "addTempo")
        || !step(session->saveToPath(outputPath.string(), error), "save")) {
        return std::nullopt;
    }
    return readFile(outputPath);
}

// Applies each layout setting to a new 32-bar piano score and checks the file, the values
// the settings sheet reads back, and undo. Returns the problems found.
std::vector<std::string> checkLayoutSettings(const std::filesystem::path& piano, const std::filesystem::path& outputDir)
{
    std::vector<std::string> problems;
    auto expectThat = [&](const bool condition, const std::string& message) {
        if (!condition) {
            problems.push_back(message);
        }
    };
    std::string error;
    NewScoreOptions options;
    options.label = "layout";
    std::filesystem::create_directories(outputDir / "layout-base");
    if (!createScore(piano, options, outputDir / "layout-base" / "layout-base.mscx", error)) {
        return { "could not create the base score: " + error };
    }
    std::unique_ptr<msr::render::ScoreRenderSession> session
        = msr::render::ScoreRenderSession::open((outputDir / "layout-base" / "layout-base.mscx").string(), error);
    if (!session) {
        return { "could not reopen the base score: " + error };
    }
    int snapshot = 0;
    auto save = [&]() {
        const std::string name = "layout-" + std::to_string(++snapshot);
        std::filesystem::create_directories(outputDir / name);
        const std::filesystem::path path = outputDir / name / (name + ".mscx");
        expectThat(session->saveToPath(path.string(), error), "save failed: " + error);
        // The folder layout keeps the style in score_style.mss beside the score.
        return readFile(path) + readFile(outputDir / name / "score_style.mss");
    };
    auto styleValue = [](const std::string& xml, const std::string& tag) -> std::optional<double> {
        std::smatch match;
        if (std::regex_search(xml, match, std::regex("<" + tag + ">([-0-9.]+)</" + tag + ">"))) {
            return std::stod(match[1]);
        }
        return std::nullopt;
    };
    auto near = [](const std::optional<double> value, const double expected) {
        return value && std::abs(*value - expected) < 0.001;
    };

    msr::render::ScoreEditState state;
    // US Letter, 12 mm margins, 1.5 mm staff space, 7 sp staff spacing, 10 sp system spacing.
    expectThat(session->updatePageLayout(215.9, 279.4, 12.0, 1.5, 7.0, 10.0, state, error), "page layout rejected: " + error);
    expectThat(std::abs(state.pageWidthMillimeters - 215.9) < 0.01 && std::abs(state.pageHeightMillimeters - 279.4) < 0.01,
               "sheet reads back a different page size");
    expectThat(std::abs(state.pageMarginMillimeters - 12.0) < 0.01, "sheet reads back a different margin");
    expectThat(std::abs(state.staffSizeMillimeters - 1.5) < 0.01, "sheet reads back a different staff size");
    expectThat(std::abs(state.staffSpacingSpatium - 7.0) < 0.01 && std::abs(state.systemSpacingSpatium - 10.0) < 0.01,
               "sheet reads back different spacing");
    std::string xml = save();
    expectThat(near(styleValue(xml, "pageWidth"), 8.5) && near(styleValue(xml, "pageHeight"), 11.0), "file page size is not Letter");
    expectThat(near(styleValue(xml, "pageOddLeftMargin"), 12.0 / 25.4) && near(styleValue(xml, "pageOddTopMargin"), 12.0 / 25.4),
               "file margins are not 12 mm");
    expectThat(near(styleValue(xml, "staffDistance"), 7.0) && near(styleValue(xml, "minSystemDistance"), 10.0),
               "file spacing does not match");
    expectThat(near(styleValue(xml, "spatium"), 1.5), "file staff size is not 1.5 mm");

    // Out-of-range input is refused without changing anything.
    expectThat(!session->updatePageLayout(215.9, 279.4, 12.0, 3.0, 7.0, 10.0, state, error), "a 3 mm staff size was accepted");
    expectThat(!session->updatePageLayout(215.9, 279.4, 120.0, 1.5, 7.0, 10.0, state, error), "margins wider than the page were accepted");
    expectThat(near(styleValue(save(), "spatium"), 1.5), "a refused change still altered the score");

    expectThat(session->updateLayoutOptions(true, true, state, error), "layout options rejected: " + error);
    expectThat(state.createMultiMeasureRests && state.hideEmptyStaves, "sheet does not read back the layout options");
    xml = save();
    expectThat(near(styleValue(xml, "createMultiMeasureRests"), 1) && near(styleValue(xml, "hideEmptyStaves"), 1),
               "file layout options do not match");
    expectThat(session->updateLayoutOptions(false, false, state, error), "turning layout options off failed: " + error);
    expectThat(!state.createMultiMeasureRests && !state.hideEmptyStaves, "layout options did not turn off");

    expectThat(session->applyAutoSystemBreaks(4, false, false, state, error), "4 bars per system rejected: " + error);
    xml = save();
    const size_t locks = countOccurrences(xml, "<systemLock>");
    expectThat(locks == 8, "4 bars per system on 32 bars should lock 8 systems, found " + std::to_string(locks));
    expectThat(session->applyAutoSystemBreaks(0, false, true, state, error), "removing system locks failed: " + error);
    xml = save();
    expectThat(countOccurrences(xml, "<systemLock>") == 0, "system locks were not removed");

    expectThat(session->updateStaffSpacing(9.0, state, error) && std::abs(state.staffSpacingSpatium - 9.0) < 0.01,
               "staff spacing slider did not apply: " + error);

    // A desktop score with a non-preset page (A3) and a system spacing below the sheet's range
    // can still switch paper size; the unusual spacing is left as it was.
    {
        const std::filesystem::path stylePath = outputDir / "layout-base" / "score_style.mss";
        std::string style = readFile(stylePath);
        const auto setStyle = [&style](const std::string& tag, const std::string& value) {
            const std::regex existing("<" + tag + ">[^<]*</" + tag + ">");
            const std::string element = "<" + tag + ">" + value + "</" + tag + ">";
            if (std::regex_search(style, existing)) {
                style = std::regex_replace(style, existing, element);
            } else {
                style.insert(style.find("</Style>"), "    " + element + "\n    ");
            }
        };
        setStyle("pageWidth", std::to_string(297.0 / 25.4));
        setStyle("pageHeight", std::to_string(420.0 / 25.4));
        setStyle("minSystemDistance", "2");
        std::ofstream(stylePath, std::ios::binary) << style;
        std::unique_ptr<msr::render::ScoreRenderSession> desktopScore
            = msr::render::ScoreRenderSession::open((outputDir / "layout-base" / "layout-base.mscx").string(), error);
        msr::render::ScoreEditState desktopState;
        expectThat(desktopScore && desktopScore->currentEditState(desktopState, error), "could not open the desktop-style score");
        if (desktopScore) {
            expectThat(std::abs(desktopState.pageWidthMillimeters - 297.0) < 0.1 && std::abs(desktopState.systemSpacingSpatium - 2.0) < 0.01,
                       "the desktop-style score did not load its A3 page and tight spacing");
            expectThat(desktopScore->updatePageLayout(210.0, 297.0, desktopState.pageMarginMillimeters, desktopState.staffSizeMillimeters,
                                                      desktopState.staffSpacingSpatium, desktopState.systemSpacingSpatium,
                                                      desktopState, error),
                       "switching to A4 was blocked by an unrelated existing value: " + error);
            expectThat(std::abs(desktopState.pageWidthMillimeters - 210.0) < 0.1, "the page did not become A4");
            expectThat(std::abs(desktopState.systemSpacingSpatium - 2.0) < 0.01, "the existing system spacing was changed");
        }
    }

    // Undo walks every change back to the original A4 page.
    for (int step = 0; step < 12 && session->undo(state, error); ++step) {
    }
    expectThat(std::abs(state.pageWidthMillimeters - 210.0) < 0.5 && std::abs(state.staffSizeMillimeters - 1.75) < 0.01,
               "undo did not restore the original page settings");
    return problems;
}

// The instrument IDs the New Score sheet lists for a template (NewScoreTemplateChoice.instruments
// with NewScoreInstrumentCatalog.canonicalInstrumentID applied).
std::vector<std::string> templateInstrumentIDs(const std::string& xml)
{
    std::vector<std::string> ids;
    const std::regex partPattern("<Part\\b[^>]*>([\\s\\S]*?)</Part>");
    const std::regex instrumentPattern("<Instrument\\b[^>]*id=\"([^\"]+)\"");
    for (auto it = std::sregex_iterator(xml.begin(), xml.end(), partPattern); it != std::sregex_iterator(); ++it) {
        const std::string part = (*it)[1];
        std::smatch match;
        std::string id = std::regex_search(part, match, instrumentPattern) ? std::string(match[1]) : "piano";
        if (id == "double-bass") {
            id = "contrabass";
        } else if (id == "bass-clarinet") {
            id = "bb-bass-clarinet";
        } else if (id == "drum-kit" || id == "drum-kit-4" || id == "drum-kit-5" || id == "percussion") {
            id = "drumset";
        }
        ids.push_back(id);
    }
    return ids;
}

std::string sanitized(std::string value)
{
    for (char& c : value) {
        if (!std::isalnum(static_cast<unsigned char>(c))) {
            c = '_';
        }
    }
    return value;
}
}

int main(int argc, char* argv[])
{
    if (argc < 2) {
        std::cerr << "usage: score_render_new_score_tests <ScoreTemplates.bundle> [output dir]\n";
        return 2;
    }
    const std::filesystem::path bundle = argv[1];
    const std::filesystem::path outputDir = argc > 2
        ? std::filesystem::path(argv[2])
        : std::filesystem::temp_directory_path() / "aria-new-score-tests";
    std::filesystem::create_directories(outputDir);

    std::vector<std::filesystem::path> templates;
    for (const auto& entry : std::filesystem::recursive_directory_iterator(bundle)) {
        if (entry.path().extension() == ".mscx") {
            templates.push_back(entry.path());
        }
    }
    std::sort(templates.begin(), templates.end());

    std::vector<NewScoreOptions> perTemplate = {
        { "defaults" },
        { "Eb-minor-6/8-pickup", "Pièce", "Compositeur", -6, 6, 8, false, 16, std::make_pair(1, 8), 72 },
        { "C#-cut-one-bar-pickup", "One", "C", 7, 2, 2, true, 1, std::make_pair(1, 2), 60 },
        { "Cb-7/8-256", "Long", "L", -7, 7, 8, false, 256, std::make_pair(3, 8), 200 },
    };

    int failures = 0;
    int runs = 0;
    auto run = [&](const std::filesystem::path& templatePath, const NewScoreOptions& options) {
        ++runs;
        // Quick Start templates reuse file names from the main catalogue, so include the folder.
        const std::string name = sanitized(templatePath.parent_path().filename().string() + "-" + templatePath.stem().string()
                                           + "-" + options.label);
        // Saving .mscx writes MuseScore's folder layout and replaces the folder, so each score gets its own.
        std::filesystem::create_directories(outputDir / name);
        const std::filesystem::path outputPath = outputDir / name / (name + ".mscx");
        const bool isPercussionOnly = templatePath.stem().string().find("Percussion") != std::string::npos;
        std::string error;
        const auto startedAt = std::chrono::steady_clock::now();
        const std::optional<std::string> xml = createScore(templatePath, options, outputPath, error);
        const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - startedAt).count();
        if (!xml) {
            ++failures;
            std::cout << "FAIL " << name << ": " << error << "\n";
            return;
        }
        const std::vector<std::string> problems = checkCreatedScore(*xml, options, isPercussionOnly);
        if (problems.empty()) {
            std::cout << "PASS " << name << " (" << seconds << "s)\n";
            return;
        }
        ++failures;
        std::cout << "FAIL " << name << ":";
        for (const std::string& problem : problems) {
            std::cout << " [" << problem << "]";
        }
        std::cout << "\n";
    };

    for (const auto& templatePath : templates) {
        for (const NewScoreOptions& options : perTemplate) {
            run(templatePath, options);
        }
        // Editing the instrument list (here: removing the last instrument) must work on every template.
        const std::vector<std::string> ids = templateInstrumentIDs(readFile(templatePath));
        if (ids.size() > 1) {
            NewScoreOptions edited;
            edited.label = "one-instrument-removed";
            edited.replacementInstruments.assign(ids.begin(), ids.end() - 1);
            run(templatePath, edited);
        }
    }

    // Every key and time signature the sheet offers, on the Piano quick template.
    const std::filesystem::path piano = bundle / "Piano" / "04-Piano.mscx";
    for (int key = -7; key <= 7; ++key) {
        NewScoreOptions options;
        options.label = "key" + std::to_string(key);
        options.keyValue = key;
        run(piano, options);
    }
    for (const auto& [numerator, denominator, cut] : std::vector<std::tuple<int, int, bool>> {
             { 4, 4, false }, { 3, 4, false }, { 2, 4, false }, { 6, 8, false }, { 2, 2, true }, { 5, 4, false },
             { 7, 8, false }, { 12, 8, false } }) {
        NewScoreOptions options;
        options.label = "time" + std::to_string(numerator) + "-" + std::to_string(denominator);
        options.numerator = numerator;
        options.denominator = denominator;
        options.cutTime = cut;
        run(piano, options);
    }

    // Custom instrument lists replace the Treble Clef template's staff.
    NewScoreOptions custom;
    custom.label = "custom-instruments";
    custom.replacementInstruments = { "flute", "violin", "trumpet", "piano" };
    run(bundle / "Blank" / "01-Treble_Clef.mscx", custom);

    const std::vector<std::string> layoutProblems = checkLayoutSettings(piano, outputDir);
    ++runs;
    if (layoutProblems.empty()) {
        std::cout << "PASS layout settings\n";
    } else {
        ++failures;
        std::cout << "FAIL layout settings:";
        for (const std::string& problem : layoutProblems) {
            std::cout << " [" << problem << "]";
        }
        std::cout << "\n";
    }

    std::cout << (runs - failures) << "/" << runs << " new scores matched their options\n";
    return failures == 0 ? 0 : 1;
}
