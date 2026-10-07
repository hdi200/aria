// Random-edit stress test for Aria's editing engine.
//
// Opens a score and applies a seeded, reproducible sequence of random edits through the same
// ScoreRenderSession API the app uses: taps and range selections on any page, expressions,
// text, repeats, note entry, pitch and duration changes, clefs, key and time signatures,
// measures, clipboard, layout settings, instruments, part views, drags, undo and redo.
// Commands may refuse (that is normal); what counts as a bug:
//
//   crash      the process dies (the driver script reports it)
//   state      the edit state is unavailable or has an impossible selection rectangle
//   corruption Aria's own corruption scan reports a damaged score
//   save       saving fails (other than the chord-symbol approval guard)
//   reopen     the saved file does not open
//   stale      the live layout differs from the saved file reopened (layoutFingerprint)
//   roundtrip  saving the reopened file again gives a different file
//   undo       undoing an edit does not restore the file exactly
//
// usage: score_render_fuzz --score <file> [--seed N] [--steps N] [--check-every N] --out <dir>
// Every failure prints a REPRO line; re-running it with the same seed replays the same edits.
// compat/fuzz_edits.py runs this over many scores and checks the final files in desktop 4.7.5.

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <optional>
#include <random>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "score_render_core.h"

namespace {
namespace fs = std::filesystem;

struct Options {
    fs::path score;
    fs::path out;
    unsigned seed = 1;
    int steps = 200;
    int checkEvery = 10;
    bool listRepairs = false;
};

struct Target {
    int page = 0;
    double x = 0.0;
    double y = 0.0;
};

std::string readFile(const fs::path& path)
{
    std::ifstream stream(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
}

// The saved score (full score, style and every part), without the ids that change on every save.
std::string savedScoreText(const fs::path& folder, const std::string& name)
{
    std::vector<fs::path> files = { folder / (name + ".mscx"), folder / "score_style.mss" };
    if (fs::exists(folder / "Excerpts")) {
        for (const auto& entry : fs::recursive_directory_iterator(folder / "Excerpts")) {
            if (entry.is_regular_file()) {
                files.push_back(entry.path());
            }
        }
    }
    std::sort(files.begin() + 2, files.end());
    std::ostringstream text;
    for (const fs::path& file : files) {
        if (!fs::exists(file)) {
            continue;
        }
        // Name the main file generically: each copy is saved under its own name.
        text << "=== " << (file.extension() == ".mscx" && file.parent_path() == folder ? std::string("main.mscx") : fs::relative(file, folder).string())
             << "\n";
        std::istringstream lines(readFile(file));
        std::string line;
        // Multi-measure rests are written as extra <Measure> blocks copied from the current layout
        // and rebuilt on open, so a part not laid out since the last edit writes old copies.
        // An empty <Beam> is a beam read from the file with no settings of its own; once layout
        // rebuilds it (after undo, for example) it is automatic and not written. Same beaming.
        std::string measure;
        bool inMeasure = false;
        bool pendingBeam = false;
        while (std::getline(lines, line)) {
            if (line.find("<eid>") != std::string::npos || line.find("<linkedTo>") != std::string::npos
                || line.find("<linkedMain>") != std::string::npos || line.find("<linked>") != std::string::npos) {
                continue;
            }
            const bool beamOpen = line.find_first_not_of(' ') != std::string::npos && line.substr(line.find_first_not_of(' ')) == "<Beam>";
            if (pendingBeam) {
                pendingBeam = false;
                if (line.find("</Beam>") != std::string::npos && line.find_first_not_of(' ') == line.find("</Beam>")) {
                    continue;
                }
                const std::string open = "<Beam>\n";
                if (inMeasure) {
                    measure += open;
                } else {
                    text << open;
                }
            }
            if (beamOpen) {
                pendingBeam = true;
                continue;
            }
            if (!inMeasure && line.find("<Measure") != std::string::npos && line.find("/>") == std::string::npos) {
                inMeasure = true;
                measure.clear();
            }
            if (!inMeasure) {
                text << line << "\n";
                continue;
            }
            measure += line + "\n";
            if (line.find("</Measure>") != std::string::npos) {
                inMeasure = false;
                if (measure.find("<multiMeasureRest>") == std::string::npos) {
                    text << measure;
                }
            }
        }
        text << measure.substr(0, inMeasure ? measure.size() : 0);
    }
    return text.str();
}

// Fingerprint entries are "page type x y width" in tenths of a staff space. A pair that differs
// by at most one unit in each number is rounding, not stale layout; drop both.
void dropNearMatches(std::vector<std::string>& onlyLive, std::vector<std::string>& onlyFresh)
{
    auto parse = [](const std::string& entry, std::string& key, long long values[3]) {
        std::istringstream in(entry);
        std::string page;
        std::string type;
        in >> page >> type >> values[0] >> values[1] >> values[2];
        key = page + " " + type;
        return static_cast<bool>(in);
    };
    for (auto live = onlyLive.begin(); live != onlyLive.end();) {
        std::string liveKey;
        long long liveValues[3] = {};
        auto match = onlyFresh.end();
        if (parse(*live, liveKey, liveValues)) {
            match = std::find_if(onlyFresh.begin(), onlyFresh.end(), [&](const std::string& fresh) {
                std::string freshKey;
                long long freshValues[3] = {};
                return parse(fresh, freshKey, freshValues) && freshKey == liveKey
                       && std::abs(freshValues[0] - liveValues[0]) <= 1 && std::abs(freshValues[1] - liveValues[1]) <= 1
                       && std::abs(freshValues[2] - liveValues[2]) <= 1;
            });
        }
        if (match != onlyFresh.end()) {
            onlyFresh.erase(match);
            live = onlyLive.erase(live);
        } else {
            ++live;
        }
    }
}

std::string firstDifference(const std::string& a, const std::string& b)
{
    std::istringstream left(a);
    std::istringstream right(b);
    std::string l;
    std::string r;
    int lineNumber = 0;
    std::string section;
    while (true) {
        const bool hasLeft = static_cast<bool>(std::getline(left, l));
        const bool hasRight = static_cast<bool>(std::getline(right, r));
        ++lineNumber;
        if (hasLeft && l.rfind("=== ", 0) == 0) {
            section = l;
        }
        if (!hasLeft && !hasRight) {
            return "";
        }
        if (!hasLeft || !hasRight || l != r) {
            auto trim = [](std::string text) {
                text.erase(0, text.find_first_not_of(" \t"));
                return text.size() > 120 ? text.substr(0, 120) + "..." : text;
            };
            return section + " line " + std::to_string(lineNumber) + ": [" + (hasLeft ? trim(l) : "<end>") + "] vs ["
                   + (hasRight ? trim(r) : "<end>") + "]";
        }
    }
}

class Fuzzer {
public:
    Fuzzer(const Options& options, std::unique_ptr<msr::render::ScoreRenderSession> session)
        : m_options(options), m_session(std::move(session)), m_rng(options.seed)
    {
        m_name = m_options.score.stem().string();
        for (char& c : m_name) {
            if (!std::isalnum(static_cast<unsigned char>(c))) {
                c = '_';
            }
        }
        buildActions();
    }

    int run()
    {
        refreshTargets();
        for (m_step = 1; m_step <= m_options.steps; ++m_step) {
            const Action& action = pickAction();
            std::cout << "STEP " << m_step << " " << action.name << std::flush;
            std::string detail;
            const bool ok = action.run(detail);
            std::cout << (ok ? " ok" : " refused") << (detail.empty() ? "" : " " + detail) << std::endl;
            if (std::getenv("ARIA_FUZZ_PARANOID")) {
                // Lay the whole score out after every edit, so a crash that a bad edit would only
                // cause at some later relayout happens right after the edit that caused it.
                int pages = 0;
                std::string ignored;
                m_session->setContinuousLayout(true, pages, ignored);
                m_session->setContinuousLayout(false, pages, ignored);
                std::cout << "RELAYOUT " << m_step << " ok" << std::endl;
            }
            if (std::getenv("ARIA_FUZZ_TRACE_CORRUPTION") && !m_corruptionSeen) {
                // Read-only, so it does not change the run: name the edit that first damages a bar.
                msr::render::ScoreCorruptionReport report;
                std::string ignored;
                if (m_session->scoreCorruptionReport(report, ignored) && report.corrupted) {
                    m_corruptionSeen = true;
                    std::cout << "FIRST-CORRUPTION after step " << m_step << " " << action.name << ": " << report.details.substr(0, 200) << std::endl;
                }
            }
            checkState(action.name);
            if (m_step % m_options.checkEvery == 0 || m_step == m_options.steps) {
                checkpoint(m_step == m_options.steps);
                refreshTargets();
            }
        }
        std::cout << "DONE " << m_failures << " failure(s)" << std::endl;
        return m_failures == 0 ? 0 : 1;
    }

private:
    struct Action {
        std::string name;
        int weight = 1;
        std::function<bool(std::string&)> run;
    };

    // ---- randomness -------------------------------------------------------------------
    int randomInt(const int low, const int high) { return std::uniform_int_distribution<int>(low, high)(m_rng); }
    double randomReal(const double low, const double high) { return std::uniform_real_distribution<double>(low, high)(m_rng); }
    bool chance(const double probability) { return randomReal(0.0, 1.0) < probability; }
    template <typename T>
    const T& pick(const std::vector<T>& values) { return values.at(static_cast<size_t>(randomInt(0, static_cast<int>(values.size()) - 1))); }

    int pageCount() const { return std::max(1, m_session->totalPageCount()); }

    // A note or rest found by the last scan (any page), or a random spot.
    Target randomTarget()
    {
        if (!m_targets.empty() && chance(0.85)) {
            Target target = pick(m_targets);
            target.x += randomReal(-0.004, 0.004);
            target.y += randomReal(-0.004, 0.004);
            return target;
        }
        return { randomInt(0, pageCount() - 1), randomReal(0.02, 0.98), randomReal(0.02, 0.98) };
    }

    void refreshTargets()
    {
        m_targets.clear();
        std::set<std::pair<long, long>> seen;
        const int pages = std::min(pageCount(), 4);
        msr::render::ScoreEditState state;
        std::string error;
        for (int page = 0; page < pages; ++page) {
            for (double y = 0.03; y < 0.97; y += 0.022) {
                for (double x = 0.03; x < 0.97; x += 0.022) {
                    if (!m_session->selectElement(page, x, y, 1.0, state, error) || !(state.selection.isNote || state.selection.isRest)) {
                        continue;
                    }
                    const auto& s = state.selection;
                    const double cx = s.normalizedX + s.normalizedWidth / 2;
                    const double cy = s.normalizedY + s.normalizedHeight / 2;
                    if (seen.insert({ std::lround(cx * 400) + page * 1000, std::lround(cy * 400) }).second) {
                        m_targets.push_back({ page, cx, cy });
                    }
                }
            }
        }
        m_session->clearSelection(state, error);
    }

    // ---- actions ------------------------------------------------------------------------
    using Command = std::function<bool(msr::render::ScoreEditState&, std::string&)>;

    void add(const std::string& name, const int weight, const Command& command)
    {
        m_actions.push_back({ name, weight, [this, command](std::string& detail) {
                                   msr::render::ScoreEditState state;
                                   std::string error;
                                   const bool ok = command(state, error);
                                   if (!ok) {
                                       detail = error;
                                   }
                                   return ok;
                               } });
    }

    bool tap(const Target& target, msr::render::ScoreEditState& state, std::string& error)
    {
        return m_session->selectElement(target.page, target.x, target.y, 1.0, state, error);
    }

    void buildActions()
    {
        auto& s = *m_session;
        // Selection
        add("tap-note", 12, [&](auto& st, auto& e) { return tap(randomTarget(), st, e); });
        add("tap-anywhere", 4, [&](auto& st, auto& e) {
            return s.selectElement(randomInt(0, pageCount() - 1), randomReal(0, 1), randomReal(0, 1), 1.0, st, e);
        });
        add("range-select", 6, [&](auto& st, auto& e) {
            const Target a = randomTarget();
            Target b = randomTarget();
            b.page = a.page;
            return s.selectMeasureRange(a.page, a.x, a.y, b.x, b.y, st, e);
        });
        add("select-all", 1, [&](auto& st, auto& e) { return s.selectAll(st, e); });
        add("select-adjacent", 2, [&](auto& st, auto& e) { return s.selectAdjacentElement(chance(0.5), st, e); });
        add("clear-selection", 1, [&](auto& st, auto& e) { return s.clearSelection(st, e); });

        // Markings
        add("expression", 8, [&](auto& st, auto& e) {
            static const std::vector<std::string> kinds = { "slur", "crescendo", "decrescendo", "fermata", "accent", "staccato",
                                                            "tenuto", "marcato", "p", "f", "mf", "sfz", "pp", "8va", "8vb" };
            return s.addExpression(pick(kinds), st, e);
        });
        add("text", 3, [&](auto& st, auto& e) {
            static const std::vector<std::string> kinds = { "Staff Text", "System Text", "Rehearsal Mark" };
            return s.addText(pick(kinds), st, e) && s.setSelectedText("fuzz & <text>", st, e);
        });
        add("repeat-jump", 3, [&](auto& st, auto& e) {
            static const std::vector<std::string> kinds = { "Start repeat", "End repeat", "First ending", "Second ending", "Segno",
                                                            "Coda", "To Coda", "D.C. al Fine", "D.S. al Coda" };
            return s.addRepeatJump(pick(kinds), st, e);
        });
        add("tempo", 2, [&](auto& st, auto& e) { return s.addTempo(pick(std::vector<std::string> { "quarter", "half", "eighth" }), randomInt(40, 200), st, e); });
        add("lyrics", 2, [&](auto& st, auto& e) { return s.addLyricsText("la", chance(0.5), st, e); });
        add("drag-element", 4, [&](auto& st, auto& e) {
            const Target t = randomTarget();
            return s.dragSelectedMovableElement(t.page, t.x, t.y - 0.02, st, e);
        });
        add("retarget-endpoint", 4, [&](auto& st, auto& e) {
            const Target t = randomTarget();
            return s.retargetSelectedExpressionEndpoint(chance(0.5), t.page, t.x, t.y, st, e);
        });

        // Notes
        add("delete", 6, [&](auto& st, auto& e) { return s.deleteSelection(st, e); });
        add("duration", 5, [&](auto& st, auto& e) { return s.applyDuration(pick(std::vector<int> { 1, 2, 4, 8, 16 }), st, e); });
        add("dot", 2, [&](auto& st, auto& e) { return s.toggleDot(st, e); });
        add("rest", 2, [&](auto& st, auto& e) { return s.toggleRest(st, e); });
        add("tie", 2, [&](auto& st, auto& e) { return s.toggleTie(st, e); });
        add("tuplet", 2, [&](auto& st, auto& e) { return s.addTuplet(pick(std::vector<int> { 2, 3, 5 }), st, e); });
        add("pitch-step", 4, [&](auto& st, auto& e) { return s.moveSelectionPitch(chance(0.5), st, e); });
        add("pitch-semitones", 2, [&](auto& st, auto& e) { return s.shiftSelectionPitchBySemitones(randomInt(-12, 12), st, e); });
        add("pitch-octave", 1, [&](auto& st, auto& e) { return s.shiftSelectionPitchByOctaves(chance(0.5) ? 1 : -1, st, e); });
        add("accidental", 2, [&](auto& st, auto& e) { return s.changeSelectionAccidental(randomInt(0, 4), st, e); });
        add("enharmonic", 1, [&](auto& st, auto& e) { return s.changeSelectionEnharmonicSpelling(st, e); });
        add("flip-stem", 1, [&](auto& st, auto& e) { return s.flipSelectionStemDirection(st, e); });
        add("drag-pitch", 2, [&](auto& st, auto& e) {
            const Target t = randomTarget();
            return s.setSelectionPitchAtPagePosition(t.page, t.x, t.y + randomReal(-0.02, 0.02), st, e);
        });
        add("note-entry", 6, [&](auto& st, auto& e) {
            const Target t = randomTarget();
            const bool ok = s.setNoteInputEnabled(true, st, e)
                && s.insertNote(t.page, t.x + randomReal(-0.01, 0.01), t.y + randomReal(-0.015, 0.015), st, e);
            std::string ignored;
            s.setNoteInputEnabled(false, st, ignored);
            return ok;
        });
        add("cursor-pitch", 2, [&](auto& st, auto& e) {
            const bool ok = s.setNoteInputEnabled(true, st, e) && s.insertMIDIPitchAtCursor(randomInt(48, 84), chance(0.5), chance(0.3), st, e);
            std::string ignored;
            s.setNoteInputEnabled(false, st, ignored);
            return ok;
        });
        add("voice", 1, [&](auto& st, auto& e) { return s.setCurrentVoice(randomInt(0, 3), st, e); });
        add("slashes", 1, [&](auto& st, auto& e) { return chance(0.5) ? s.fillSelectionWithSlashes(st, e) : s.replaceSelectionWithRhythmicSlashes(st, e); });

        // Structure
        add("clef", 3, [&](auto& st, auto& e) { return s.changeClef(pick(std::vector<std::string> { "treble", "bass", "alto", "tenor" }), st, e); });
        add("time-signature", 2, [&](auto& st, auto& e) {
            static const std::vector<std::pair<int, int>> sigs = { { 4, 4 }, { 3, 4 }, { 2, 4 }, { 6, 8 }, { 5, 4 }, { 7, 8 }, { 2, 2 } };
            const auto sig = pick(sigs);
            return s.updateTimeSignature(sig.first, sig.second, false, sig == std::make_pair(2, 2), chance(0.3), st, e);
        });
        add("key-signature", 2, [&](auto& st, auto& e) { return s.updateKeySignature(randomInt(-7, 7), chance(0.3), st, e); });
        add("add-measures", 2, [&](auto& st, auto& e) { return s.addMeasures(randomInt(1, 3), st, e); });
        add("remove-measure", 2, [&](auto& st, auto& e) { return s.removeSelectedMeasure(st, e); });
        add("clear-measure", 1, [&](auto& st, auto& e) { return s.clearSelectedMeasure(st, e); });
        add("copy-paste", 3, [&](auto& st, auto& e) {
            if (!s.copySelectedMeasureRange(st, e)) {
                return false;
            }
            const Target t = randomTarget();
            return tap(t, st, e) && s.pasteMeasureRange(st, e);
        });
        add("cut", 1, [&](auto& st, auto& e) { return s.cutSelectedMeasureRange(st, e); });
        add("transpose", 1, [&](auto& st, auto& e) { return s.transposeSelectedMeasureRange(1, randomInt(0, 1), randomInt(1, 4), 0, st, e); });
        add("layout-break", 2, [&](auto& st, auto& e) {
            return chance(0.7) ? s.addLayoutBreak(pick(std::vector<std::string> { "system", "page", "keepMeasuresTogether" }), st, e)
                               : s.removeLayoutBreak(st, e);
        });
        add("pickup", 1, [&](auto& st, auto& e) { return chance(0.6) ? s.createFirstPickupMeasure(1, 4, st, e) : s.clearFirstMeasurePickup(st, e); });

        // Layout settings
        add("page-layout", 1, [&](auto& st, auto& e) {
            const bool letter = chance(0.5);
            return s.updatePageLayout(letter ? 215.9 : 210.0, letter ? 279.4 : 297.0, randomInt(8, 25), randomReal(1.4, 2.0),
                                      randomReal(5.0, 9.0), randomReal(6.0, 12.0), st, e);
        });
        add("layout-options", 1, [&](auto& st, auto& e) { return s.updateLayoutOptions(chance(0.5), chance(0.5), st, e); });
        add("system-breaks", 1, [&](auto& st, auto& e) { return s.applyAutoSystemBreaks(randomInt(2, 6), false, chance(0.3), st, e); });

        // Instruments and part views
        add("add-instrument", 1, [&](auto& st, auto& e) { return s.addInstrument(pick(std::vector<std::string> { "flute", "violin", "trumpet", "piano" }), st, e); });
        add("move-instrument", 1, [&](auto& st, auto& e) {
            const int parts = static_cast<int>(s.partInfoList().size());
            return parts > 1 && s.moveInstrument(randomInt(0, parts - 1), randomInt(0, parts), st, e);
        });
        add("part-view", 2, [&](auto& st, auto& e) {
            const int parts = static_cast<int>(s.partInfoList().size());
            int pages = 0;
            const std::optional<int> part = chance(0.4) || parts == 0 ? std::nullopt : std::optional<int>(randomInt(0, parts - 1));
            const bool ok = s.setActivePartIndex(part, pages, e);
            refreshTargets();
            return ok;
        });

        // History
        add("undo", 5, [&](auto& st, auto& e) { return s.undo(st, e); });
        add("redo", 2, [&](auto& st, auto& e) { return s.redo(st, e); });
    }

    const Action& pickAction()
    {
        int total = 0;
        for (const Action& action : m_actions) {
            total += action.weight;
        }
        int roll = randomInt(1, total);
        for (const Action& action : m_actions) {
            roll -= action.weight;
            if (roll <= 0) {
                return action;
            }
        }
        return m_actions.back();
    }

    // ---- checks -------------------------------------------------------------------------
    void fail(const std::string& check, const std::string& detail)
    {
        ++m_failures;
        std::cout << "FAIL step " << m_step << " " << check << ": " << detail << std::endl;
        std::cout << "REPRO score_render_fuzz --score '" << m_options.score.string() << "' --seed " << m_options.seed << " --steps "
                  << m_step << " --check-every " << m_options.checkEvery << " --out <dir>" << std::endl;
    }

    void checkState(const std::string& action)
    {
        msr::render::ScoreEditState state;
        std::string error;
        if (!m_session->currentEditState(state, error)) {
            fail("state", "edit state unavailable after " + action + ": " + error);
            return;
        }
        const auto& s = state.selection;
        if (!s.hasSelection) {
            return;
        }
        const double values[] = { s.normalizedX, s.normalizedY, s.normalizedWidth, s.normalizedHeight };
        for (const double value : values) {
            if (!std::isfinite(value) || value < -0.01 || value > 1.01) {
                fail("state", "impossible selection rectangle after " + action);
                return;
            }
        }
    }

    // Save into its own folder (MuseScore's folder layout replaces the folder's contents).
    std::optional<fs::path> saveCopy(msr::render::ScoreRenderSession& session, const std::string& label, std::string& error)
    {
        const fs::path folder = m_options.out / "work" / (m_name + "-" + std::to_string(m_step) + "-" + label);
        fs::remove_all(folder);
        fs::create_directories(folder);
        const fs::path path = folder / (label + ".mscx");
        if (!session.saveToPath(path.string(), error)) {
            return std::nullopt;
        }
        return path;
    }

    void checkpoint(const bool final)
    {
        msr::render::ScoreEditState state;
        std::string error;
        int pages = 0;
        m_session->setActivePartIndex(std::nullopt, pages, error);
        m_session->setNoteInputEnabled(false, state, error);

        msr::render::ScoreCorruptionReport report;
        if (m_session->scoreCorruptionReport(report, error) && report.corrupted) {
            fail("corruption", report.details.substr(0, 300));
        }
        if (m_session->chordSymbolRemovalNeedsApproval()) {
            std::cout << "NOTE step " << m_step << " save needs chord-symbol approval; checkpoint skipped" << std::endl;
            return;
        }

        error.clear();
        const std::optional<fs::path> saved = saveCopy(*m_session, "live", error);
        if (!saved) {
            fail("save", error);
            return;
        }
        error.clear();
        std::unique_ptr<msr::render::ScoreRenderSession> reopened = msr::render::ScoreRenderSession::open(saved->string(), error);
        if (!reopened) {
            fail("reopen", error);
            return;
        }

        std::vector<std::string> live;
        std::vector<std::string> fresh;
        std::vector<std::string> onlyLive;
        std::vector<std::string> onlyFresh;
        if (m_session->layoutFingerprint(live, error) && reopened->layoutFingerprint(fresh, error) && live != fresh) {
            std::set_difference(live.begin(), live.end(), fresh.begin(), fresh.end(), std::back_inserter(onlyLive));
            std::set_difference(fresh.begin(), fresh.end(), live.begin(), live.end(), std::back_inserter(onlyFresh));
            dropNearMatches(onlyLive, onlyFresh);
        }
        if (!onlyLive.empty() || !onlyFresh.empty()) {
            std::string detail = std::to_string(onlyLive.size()) + " element(s) only live, " + std::to_string(onlyFresh.size()) + " only reopened;";
            for (size_t i = 0; i < std::min<size_t>(3, onlyLive.size()); ++i) {
                detail += " live[" + onlyLive[i] + "]";
            }
            for (size_t i = 0; i < std::min<size_t>(3, onlyFresh.size()); ++i) {
                detail += " reopened[" + onlyFresh[i] + "]";
            }
            fail("stale", detail);
        }

        error.clear();
        const std::optional<fs::path> resaved = saveCopy(*reopened, "resaved", error);
        if (!resaved) {
            fail("save", "saving the reopened copy failed: " + error);
        } else {
            const std::string difference = firstDifference(savedScoreText(saved->parent_path(), "live"),
                                                           savedScoreText(resaved->parent_path(), "resaved"));
            if (!difference.empty()) {
                fail("roundtrip", difference);
            }
        }

        if (final) {
            const fs::path finalFolder = m_options.out / "final" / m_name;
            fs::remove_all(finalFolder);
            fs::create_directories(finalFolder);
            m_session->saveToPath((finalFolder / (m_name + ".mscx")).string(), error);
            return;
        }

        // Undo probe: one more random edit, undone, must give back exactly the saved file.
        const std::string before = savedScoreText(saved->parent_path(), "live");
        const Action& action = pickAction();
        // Only single-command edits: actions that issue two commands (add text then type into it,
        // copy then paste, note input on then insert) need two undos, which is not a bug.
        static const std::set<std::string> notSingleUndo = { "undo", "redo", "part-view", "text", "copy-paste",
                                                               "note-entry", "cursor-pitch" };
        if (notSingleUndo.count(action.name)) {
            return;
        }
        std::string detail;
        std::cout << "PROBE " << m_step << " " << action.name << std::flush;
        const bool changed = action.run(detail);
        std::cout << (changed ? " ok" : " refused") << std::endl;
        m_session->setActivePartIndex(std::nullopt, pages, error);
        m_session->setNoteInputEnabled(false, state, error);
        error.clear();
        const std::optional<fs::path> probeSaved = saveCopy(*m_session, "probe", error);
        if (!changed || !probeSaved || savedScoreText(probeSaved->parent_path(), "probe") == before) {
            return; // nothing changed, so there is nothing to undo
        }
        if (!m_session->undo(state, error)) {
            fail("undo", "undo after " + action.name + " failed: " + error);
            return;
        }
        error.clear();
        const std::optional<fs::path> undone = saveCopy(*m_session, "undone", error);
        if (!undone) {
            fail("save", "saving after undo failed: " + error);
            return;
        }
        const std::string difference = firstDifference(before, savedScoreText(undone->parent_path(), "undone"));
        if (!difference.empty()) {
            fail("undo", "undoing " + action.name + " did not restore the score: " + difference);
        }
    }

    Options m_options;
    std::unique_ptr<msr::render::ScoreRenderSession> m_session;
    std::mt19937 m_rng;
    std::string m_name;
    std::vector<Action> m_actions;
    std::vector<Target> m_targets;
    int m_step = 0;
    int m_failures = 0;
    bool m_corruptionSeen = false;
};
} // namespace

int main(int argc, char* argv[])
{
    Options options;
    for (int i = 1; i < argc; ++i) {
        if (std::string(argv[i]) == "--list-repairs") {
            options.listRepairs = true;
        }
    }
    for (int i = 1; i + 1 < argc; i += 2) {
        const std::string flag = argv[i];
        const std::string value = argv[i + 1];
        if (flag == "--score") {
            options.score = value;
        } else if (flag == "--out") {
            options.out = value;
        } else if (flag == "--seed") {
            options.seed = static_cast<unsigned>(std::stoul(value));
        } else if (flag == "--steps") {
            options.steps = std::stoi(value);
        } else if (flag == "--check-every") {
            options.checkEvery = std::max(1, std::stoi(value));
        }
    }
    if (options.score.empty() || (options.out.empty() && !options.listRepairs)) {
        std::cerr << "usage: score_render_fuzz --score <file> --out <dir> [--seed N] [--steps N] [--check-every N]\n";
        return 2;
    }
    if (!options.out.empty()) {
        fs::create_directories(options.out);
    }

    std::string error;
    std::unique_ptr<msr::render::ScoreRenderSession> session = msr::render::ScoreRenderSession::open(options.score.string(), error);
    // --list-repairs: print what the repair sheet would offer for this file, then stop. Run over
    // desktop-made scores, anything listed is a repair that would misfire.
    if (options.listRepairs) {
        std::vector<msr::render::ScoreLegacyRepairIssue> issues;
        if (session && session->legacyRepairIssues(issues, error)) {
            for (const auto& issue : issues) {
                std::cout << "REPAIR " << issue.kind << " m" << issue.measureNumber << " " << options.score.string() << ": " << issue.message
                          << std::endl;
            }
        }
        return 0;
    }
    // Start from the score as Aria saves it. Opening a pre-4.70 file upgrades some style values
    // that its parts only take on after one save and reopen (desktop 4.7.5 does the same), which
    // the roundtrip check would otherwise report at every checkpoint.
    if (session && session->supportsEditing()) {
        const fs::path startFolder = options.out / "start" / options.score.stem();
        fs::remove_all(startFolder);
        fs::create_directories(startFolder);
        const fs::path startPath = startFolder / (options.score.stem().string() + ".mscx");
        if (session->saveToPath(startPath.string(), error)) {
            if (auto saved = msr::render::ScoreRenderSession::open(startPath.string(), error)) {
                session = std::move(saved);
            }
        }
        error.clear();
    }
    if (!session || !session->supportsEditing()) {
        std::cout << "SKIP " << options.score.string() << ": " << (session ? "not editable" : error) << std::endl;
        return 0;
    }
    std::cout << "SCORE " << options.score.string() << " seed " << options.seed << std::endl;
    Fuzzer fuzzer(options, std::move(session));
    return fuzzer.run();
}
