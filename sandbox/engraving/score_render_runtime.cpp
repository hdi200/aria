namespace {

using muse::IApplication;

constexpr auto kRuntimeMode = IApplication::RunMode::GuiApp;
constexpr int kFluidSynthSampleRate = 48000;
constexpr int kFluidSynthChannelCount = 2;
constexpr int kFluidSynthRenderBlockFrames = 512;
constexpr int kFluidSynthTailSeconds = 1;
constexpr double kFluidSynthChunkPrerollSeconds = 0.5;

using SteadyClock = std::chrono::steady_clock;

double elapsedSecondsSince(const SteadyClock::time_point startTime)
{
    return std::chrono::duration<double>(SteadyClock::now() - startTime).count();
}

mu::engraving::EngravingItem* linkedItemInScore(mu::engraving::EngravingItem* item,
                                                mu::engraving::Score* targetScore)
{
    if (!item || !targetScore) {
        return nullptr;
    }

    if (item->score() == targetScore) {
        return item;
    }

    for (mu::engraving::EngravingObject* linked : item->linkList()) {
        if (!linked || !linked->isEngravingItem()) {
            continue;
        }

        auto* linkedItem = static_cast<mu::engraving::EngravingItem*>(linked);
        if (linkedItem->score() == targetScore) {
            return linkedItem;
        }
    }

    return nullptr;
}

int harmonyCountInScore(const mu::engraving::Score* score)
{
    if (!score) {
        return 0;
    }

    int count = 0;
    for (mu::engraving::Measure* measure = score->firstMeasure(); measure; measure = measure->nextMeasure()) {
        for (mu::engraving::Segment* segment = measure->first(); segment && segment->measure() == measure; segment = segment->next()) {
            for (const mu::engraving::EngravingItem* annotation : segment->annotations()) {
                if (annotation && annotation->isHarmony()) {
                    ++count;
                } else if (annotation && annotation->isFretDiagram() && mu::engraving::toFretDiagram(annotation)->harmony()) {
                    // A chord symbol attached to a fret diagram is the diagram's child, not
                    // a segment annotation, but the source-file count includes it.
                    ++count;
                }
            }
        }
    }

    return count;
}

// Only identify repairs backed by a single, unambiguous value in linked views.
// Scanning must never modify the score: the user sees and approves these first.
struct LegacyRepairCandidate {
    msr::render::ScoreLegacyRepairIssue issue;
    mu::engraving::EngravingItem* target = nullptr;
    mu::engraving::EngravingItem* source = nullptr;
    // partName repairs
    std::vector<mu::engraving::Part*> parts;
    muse::String newPartName;
    // lyrics, lyricHyphen and drumStaff repairs
    std::vector<mu::engraving::Lyrics*> lyrics;
    std::vector<std::pair<mu::engraving::Lyrics*, mu::engraving::Fraction>> lyricExtensions;
    mu::engraving::Staff* staff = nullptr;
};

bool isLinkedSystemMarking(const mu::engraving::EngravingItem* item)
{
    return item && (item->isJump() || item->isMarker() || item->isTempoText());
}

muse::String systemMarkingName(const mu::engraving::EngravingItem* item)
{
    using mu::engraving::MarkerType;
    if (item->isTempoText()) {
        return u"tempo marking";
    }
    if (item->isJump()) {
        const muse::String text = mu::engraving::toJump(item)->plainText().simplified();
        return text.empty() ? muse::String(u"jump") : text;
    }
    switch (mu::engraving::toMarker(item)->markerType()) {
    case MarkerType::SEGNO:
    case MarkerType::VARSEGNO:
        return u"Segno";
    case MarkerType::CODA:
    case MarkerType::VARCODA:
    case MarkerType::CODETTA:
        return u"Coda";
    case MarkerType::FINE:
        return u"Fine";
    case MarkerType::TOCODA:
    case MarkerType::TOCODASYM:
        return u"To Coda";
    default:
        return u"repeat marker";
    }
}

// An unlinked marking of the same kind at the same place, e.g. one the user re-added
// by hand. Adding another copy there would duplicate it.
bool scoreHasSameMarkingAt(mu::engraving::Score* score, const mu::engraving::EngravingItem* item)
{
    mu::engraving::Measure* measure = score->tick2measure(item->tick());
    if (!measure) {
        return false;
    }
    if (item->isTempoText()) {
        for (mu::engraving::Segment* segment = measure->first(); segment && segment->measure() == measure; segment = segment->next()) {
            if (segment->tick() != item->tick()) {
                continue;
            }
            for (mu::engraving::EngravingItem* annotation : segment->annotations()) {
                if (annotation && annotation->isTempoText()) {
                    return true;
                }
            }
        }
        return false;
    }
    for (mu::engraving::EngravingItem* element : measure->el()) {
        if (!element || element->type() != item->type()) {
            continue;
        }
        if (item->isJump() && mu::engraving::toJump(element)->jumpType() == mu::engraving::toJump(item)->jumpType()) {
            return true;
        }
        if (item->isMarker() && mu::engraving::toMarker(element)->markerType() == mu::engraving::toMarker(item)->markerType()) {
            return true;
        }
    }
    return false;
}

muse::String scoreDisplayName(mu::engraving::Score* score)
{
    if (score->isMaster()) {
        return u"the full score";
    }
    const mu::engraving::Excerpt* excerpt = score->excerpt();
    return excerpt && !excerpt->name().empty() ? excerpt->name() : muse::String(u"a part");
}

// Older Aria added jumps and markers to the full score only, and tempo markings made
// while viewing a part to that part only. Such a marking is missing from scores that
// MuseScore always gives every system marking to.
void scanMissingSystemMarkings(mu::engraving::MasterScore* masterScore, std::vector<LegacyRepairCandidate>& candidates)
{
    const auto scoreList = masterScore->scoreList();
    const std::vector<mu::engraving::Score*> scores(scoreList.begin(), scoreList.end());
    if (scores.size() < 2) {
        return;
    }

    std::unordered_set<const void*> seenLinkSets;
    for (size_t scoreIndex = 0; scoreIndex < scores.size(); ++scoreIndex) {
        mu::engraving::Score* score = scores.at(scoreIndex);
        for (mu::engraving::Measure* measure = score->firstMeasure(); measure; measure = measure->nextMeasure()) {
            std::vector<mu::engraving::EngravingItem*> markings;
            for (mu::engraving::EngravingItem* element : measure->el()) {
                if (element && (element->isJump() || element->isMarker())) {
                    markings.push_back(element);
                }
            }
            for (mu::engraving::Segment* segment = measure->first(); segment && segment->measure() == measure; segment = segment->next()) {
                for (mu::engraving::EngravingItem* annotation : segment->annotations()) {
                    if (annotation && annotation->isTempoText()) {
                        markings.push_back(annotation);
                    }
                }
            }

            for (mu::engraving::EngravingItem* marking : markings) {
                const void* linkSet = marking->links() ? static_cast<const void*>(marking->links()) : marking;
                if (!seenLinkSets.insert(linkSet).second) {
                    continue;
                }

                std::unordered_set<const mu::engraving::Score*> covered;
                mu::engraving::EngravingItem* masterCopy = nullptr;
                for (mu::engraving::EngravingObject* linked : marking->linkList()) {
                    covered.insert(linked->score());
                    if (linked->score() == masterScore && linked->isEngravingItem()) {
                        auto* item = mu::engraving::toEngravingItem(linked);
                        if (!masterCopy || item->track() < masterCopy->track()) {
                            masterCopy = item;
                        }
                    }
                }

                std::vector<mu::engraving::Score*> missing;
                bool conflicting = false;
                for (mu::engraving::Score* candidateScore : scores) {
                    if (covered.count(candidateScore)) {
                        continue;
                    }
                    missing.push_back(candidateScore);
                    conflicting |= scoreHasSameMarkingAt(candidateScore, marking);
                }
                if (missing.empty() || conflicting) {
                    continue;
                }

                muse::String missingNames;
                for (mu::engraving::Score* missingScore : missing) {
                    missingNames += (missingNames.empty() ? u"" : u", ") + scoreDisplayName(missingScore);
                }
                const muse::String name = systemMarkingName(marking);

                msr::render::ScoreLegacyRepairIssue issue;
                issue.index = static_cast<int>(candidates.size());
                issue.measureNumber = measure->no() + 1;
                issue.staffIndex = 0;
                issue.kind = marking->isTempoText() ? "missingTempo" : "missingRepeat";
                if (masterCopy) {
                    issue.location = "Full score";
                    issue.message = (u"Add this " + name + u" to " + missingNames + u", where it is missing.").toStdString();
                } else {
                    issue.location = scoreIndex == 0 ? "Full score" : "Part " + std::to_string(scoreIndex);
                    issue.message = (u"This " + name + u" is only in " + scoreDisplayName(score) + u". Add it to "
                                     + missingNames + u"."
                                     + (marking->isTempoText() ? u" Playback follows it from this bar." : u"")).toStdString();
                }
                candidates.push_back({ issue, nullptr, masterCopy ? masterCopy : marking, {}, {} });
            }
        }
    }
}

// Older Aria escaped "&" in part names twice, so "Horn in F 1 & 2" came back as
// "Horn in F 1 &amp; 2". Nobody names a part with a literal "&amp;".
void scanDoubleEscapedPartNames(mu::engraving::MasterScore* masterScore, std::vector<LegacyRepairCandidate>& candidates)
{
    static const muse::String escapedAmpersand(u"&amp;");
    std::vector<muse::String> names;
    std::vector<std::vector<mu::engraving::Part*> > partsByName;
    for (mu::engraving::Score* score : masterScore->scoreList()) {
        for (mu::engraving::Part* part : score->parts()) {
            const muse::String name = part->partName();
            if (!name.contains(escapedAmpersand)) {
                continue;
            }
            auto it = std::find(names.begin(), names.end(), name);
            if (it == names.end()) {
                names.push_back(name);
                partsByName.push_back({ part });
            } else {
                partsByName.at(static_cast<size_t>(it - names.begin())).push_back(part);
            }
        }
    }

    for (size_t i = 0; i < names.size(); ++i) {
        muse::String fixed = names.at(i);
        while (fixed.contains(escapedAmpersand)) {
            fixed.replace(escapedAmpersand, u"&");
        }
        msr::render::ScoreLegacyRepairIssue issue;
        issue.index = static_cast<int>(candidates.size());
        issue.measureNumber = 0;
        issue.staffIndex = 0;
        issue.kind = "partName";
        issue.location = "Full score and parts";
        issue.message = (u"Rename \u201C" + names.at(i) + u"\u201D to \u201C" + fixed + u"\u201D.").toStdString();
        candidates.push_back({ issue, nullptr, nullptr, partsByName.at(i), fixed });
    }
}

// A clef change at the very start of the score, right after the time signature, drawn as
// "clef, 4/4, clef". Aria's Change Clef on the first note made these (as can desktop's clef
// palette applied to that note). That clef change already decides the clef the notes use, so
// making it the starting clef and removing it changes nothing musically.
// Only the first bar of the score: after a section break desktop itself puts clef changes at
// the start of the bar (e.g. every variation of the Goldberg demo), so those are wanted.
void scanStrayStartClefs(mu::engraving::MasterScore* masterScore, std::vector<LegacyRepairCandidate>& candidates)
{
    mu::engraving::Measure* measure = masterScore->firstMeasure();
    mu::engraving::Segment* segment = measure
        ? measure->findSegmentR(mu::engraving::SegmentType::Clef, mu::engraving::Fraction(0, 1))
        : nullptr;
    if (!segment) {
        return;
    }
    for (mu::engraving::staff_idx_t staffIdx = 0; staffIdx < masterScore->nstaves(); ++staffIdx) {
        mu::engraving::EngravingItem* element = segment->element(mu::engraving::staff2track(staffIdx));
        if (!element || !element->isClef() || element->generated()) {
            continue;
        }
        msr::render::ScoreLegacyRepairIssue issue;
        issue.index = static_cast<int>(candidates.size());
        issue.measureNumber = measure->no() + 1;
        issue.staffIndex = static_cast<int>(staffIdx);
        issue.kind = "strayClef";
        issue.location = "Full score and parts";
        issue.message = "A second clef follows the time signature (as Change Clef on the first note made in earlier "
                        "versions of Aria). Make it the starting clef instead; the notes keep their positions.";
        candidates.push_back({ issue, element, nullptr, {}, {} });
    }
}

// The lyric of the same verse on the next chord of `lyrics`'s voice, or nullptr.
mu::engraving::Lyrics* nextLyricsInVoice(const mu::engraving::Lyrics* lyrics)
{
    const mu::engraving::ChordRest* chordRest = lyrics->chordRest();
    if (!chordRest) {
        return nullptr;
    }
    for (mu::engraving::Segment* segment = chordRest->segment()->next1(mu::engraving::SegmentType::ChordRest); segment;
         segment = segment->next1(mu::engraving::SegmentType::ChordRest)) {
        mu::engraving::EngravingItem* item = segment->element(chordRest->track());
        if (item && item->isChord()) {
            return mu::engraving::toChordRest(item)->lyrics(lyrics->verse(), lyrics->placement());
        }
    }
    return nullptr;
}

// Lyrics left by earlier versions of Aria's lyric entry, which desktop never saves: empty lyrics
// (space on a note to skip it, or "_" repeated, left one on every note), whose extension lines
// stopped at the first note; and "-" typed into the text ("glo-") instead of a syllable hyphen.
void scanAriaLyrics(mu::engraving::MasterScore* masterScore, std::vector<LegacyRepairCandidate>& candidates)
{
    LegacyRepairCandidate empty;
    LegacyRepairCandidate hyphens;
    int emptyMeasure = 0;
    int hyphenMeasure = 0;
    for (mu::engraving::Segment* segment = masterScore->firstSegment(mu::engraving::SegmentType::ChordRest); segment;
         segment = segment->next1(mu::engraving::SegmentType::ChordRest)) {
        for (mu::engraving::EngravingItem* item : segment->elist()) {
            if (!item || !item->isChordRest()) {
                continue;
            }
            for (mu::engraving::Lyrics* lyrics : mu::engraving::toChordRest(item)->lyrics()) {
                const muse::String text = lyrics->plainText().trimmed();
                if (text.empty()) {
                    if (empty.lyrics.empty()) {
                        emptyMeasure = segment->measure()->no() + 1;
                    }
                    empty.lyrics.push_back(lyrics);
                    continue;
                }
                // An extension line followed by empty lyrics that also had one: the line was
                // meant to run to the last of them.
                if (lyrics->ticks().isNotZero()) {
                    mu::engraving::Fraction lastTick;
                    for (mu::engraving::Lyrics* next = nextLyricsInVoice(lyrics);
                         next && next->plainText().trimmed().empty() && next->ticks().isNotZero(); next = nextLyricsInVoice(next)) {
                        lastTick = next->segment()->tick();
                    }
                    const mu::engraving::Fraction ticks = lastTick - lyrics->segment()->tick();
                    if (lastTick.isNotZero() && ticks > lyrics->ticks()) {
                        empty.lyricExtensions.emplace_back(lyrics, ticks);
                    }
                }
                const bool joinsNext = lyrics->syllabic() == mu::engraving::LyricsSyllabic::SINGLE
                                       || lyrics->syllabic() == mu::engraving::LyricsSyllabic::END;
                if (text.size() > 1 && text.endsWith(u'-') && !text.endsWith(u"--") && joinsNext && nextLyricsInVoice(lyrics)) {
                    if (hyphens.lyrics.empty()) {
                        hyphenMeasure = segment->measure()->no() + 1;
                    }
                    hyphens.lyrics.push_back(lyrics);
                }
            }
        }
    }
    if (!empty.lyrics.empty()) {
        const size_t count = empty.lyrics.size();
        std::string message = "Remove " + std::to_string(count) + " empty lyric" + (count == 1 ? "" : "s")
                              + " left by lyric entry in earlier versions of Aria. They print nothing but take space under the staff";
        if (!empty.lyricExtensions.empty()) {
            const size_t lines = empty.lyricExtensions.size();
            message += ", and extend " + std::to_string(lines) + " extension line" + (lines == 1 ? "" : "s")
                       + " over the notes " + (lines == 1 ? "it was" : "they were") + " typed across";
        }
        empty.issue.index = static_cast<int>(candidates.size());
        empty.issue.measureNumber = emptyMeasure;
        empty.issue.kind = "emptyLyrics";
        empty.issue.location = "Full score and parts";
        empty.issue.message = message + ".";
        candidates.push_back(std::move(empty));
    }
    if (!hyphens.lyrics.empty()) {
        const size_t count = hyphens.lyrics.size();
        hyphens.issue.index = static_cast<int>(candidates.size());
        hyphens.issue.measureNumber = hyphenMeasure;
        hyphens.issue.kind = "lyricHyphen";
        hyphens.issue.location = "Full score and parts";
        hyphens.issue.message = "Turn " + std::to_string(count) + " hyphen" + (count == 1 ? "" : "s")
                                + " typed into lyrics (like \u201Cglo-\u201D) into syllable hyphens between the notes, as earlier versions "
                                  "of Aria should have made.";
        candidates.push_back(std::move(hyphens));
    }
}

// A drum kit or other drum-set instrument on an ordinary five-line pitched staff, as earlier
// versions of Aria made when adding one. Its notes then show at their sound's MIDI pitch.
void scanDrumsOnPitchedStaves(mu::engraving::MasterScore* masterScore, std::vector<LegacyRepairCandidate>& candidates)
{
    for (mu::engraving::Staff* staff : masterScore->staves()) {
        const mu::engraving::Instrument* instrument = staff->part()->instrument(mu::engraving::Fraction(0, 1));
        if (!instrument || !instrument->useDrumset() || !staff->staffType(mu::engraving::Fraction(0, 1))
            || staff->staffType(mu::engraving::Fraction(0, 1))->group() != mu::engraving::StaffGroup::STANDARD) {
            continue;
        }
        LegacyRepairCandidate candidate;
        candidate.issue.index = static_cast<int>(candidates.size());
        candidate.issue.measureNumber = 1;
        candidate.issue.staffIndex = static_cast<int>(staff->idx());
        candidate.issue.kind = "drumStaff";
        candidate.issue.location = "Full score and parts";
        candidate.issue.message = "\u201C" + staff->part()->partName().toStdString()
                                  + "\u201D is on a pitched staff, as earlier versions of Aria added drum kits. Switch it to a "
                                    "percussion staff so each drum shows on its own line.";
        candidate.staff = staff;
        candidates.push_back(std::move(candidate));
    }
}

// Must run inside an undo command.
void repairAriaLyrics(mu::engraving::MasterScore* masterScore, const LegacyRepairCandidate& candidate)
{
    if (candidate.issue.kind == "emptyLyrics") {
        for (const auto& [lyrics, ticks] : candidate.lyricExtensions) {
            lyrics->undoChangeProperty(mu::engraving::Pid::LYRIC_TICKS, ticks);
        }
        for (mu::engraving::Lyrics* lyrics : candidate.lyrics) {
            masterScore->undoRemoveElement(lyrics);
        }
        return;
    }
    for (mu::engraving::Lyrics* lyrics : candidate.lyrics) {
        muse::String text = lyrics->plainText().trimmed();
        text.chop(1);
        lyrics->undoChangeProperty(mu::engraving::Pid::TEXT, mu::engraving::TextBase::plainToXmlText(text));
        lyrics->undoChangeProperty(mu::engraving::Pid::SYLLABIC,
                                   int(lyrics->syllabic() == mu::engraving::LyricsSyllabic::END ? mu::engraving::LyricsSyllabic::MIDDLE
                                                                                                  : mu::engraving::LyricsSyllabic::BEGIN));
        if (mu::engraving::Lyrics* next = nextLyricsInVoice(lyrics)) {
            if (next->syllabic() == mu::engraving::LyricsSyllabic::SINGLE) {
                next->undoChangeProperty(mu::engraving::Pid::SYLLABIC, int(mu::engraving::LyricsSyllabic::END));
            } else if (next->syllabic() == mu::engraving::LyricsSyllabic::BEGIN) {
                next->undoChangeProperty(mu::engraving::Pid::SYLLABIC, int(mu::engraving::LyricsSyllabic::MIDDLE));
            }
        }
    }
}

// Must run inside an undo command.
void repairDrumStaff(mu::engraving::Staff* staff)
{
    const mu::engraving::StaffType* preset = mu::engraving::StaffType::getDefaultPreset(mu::engraving::StaffGroup::PERCUSSION);
    for (mu::engraving::Staff* linked : staff->staffList()) {
        const mu::engraving::StaffType* current = linked->staffType(mu::engraving::Fraction(0, 1));
        if (current && current->group() == mu::engraving::StaffGroup::STANDARD) {
            linked->score()->undo(new mu::engraving::ChangeStaffType(linked, *preset));
        }
    }
}

// Make a stray start-of-bar clef change the bar's starting clef. Must run inside an undo command.
void repairStrayStartClef(mu::engraving::MasterScore* masterScore, mu::engraving::EngravingItem* strayClef)
{
    mu::engraving::Clef* clef = mu::engraving::toClef(strayClef);
    mu::engraving::Staff* staff = clef->staff();
    mu::engraving::Measure* measure = clef->measure();
    const mu::engraving::ClefType clefType = clef->clefType();
    masterScore->undoRemoveElement(clef);
    masterScore->undoChangeClef(staff, measure, clefType);
}

// Rebuild a system marking as a complete linked set: remove the incomplete set, then
// add a copy to the full score's top staff. undoAddElement copies system markings into
// every part (and the full score's system-object staves), as when a user adds one.
// Must run inside an undo command.
void repairMissingSystemMarking(mu::engraving::MasterScore* masterScore, mu::engraving::EngravingItem* source)
{
    const mu::engraving::Fraction tick = source->isTempoText() ? source->tick() : source->findMeasure()->tick();
    mu::engraving::EngravingItem* copy = source->clone();
    copy->setScore(masterScore);
    copy->setSelected(false);
    copy->setTrack(0);

    source->score()->undoRemoveElement(source);

    mu::engraving::Measure* measure = masterScore->tick2measure(tick);
    if (copy->isTempoText()) {
        copy->setParent(measure->undoGetSegment(mu::engraving::SegmentType::ChordRest, tick));
    } else {
        copy->setParent(measure);
    }
    masterScore->undoAddElement(copy);

    if (copy->isTempoText()) {
        auto* tempo = mu::engraving::toTempoText(copy);
        tempo->updateTempo();
        masterScore->setTempo(tempo->segment(), tempo->tempo());
    }
}

std::vector<LegacyRepairCandidate> scanLegacyRepairCandidates(mu::engraving::MasterScore* masterScore,
                                                              const bool savedByOldAriaEngine)
{
    static const muse::String blankDynamicText(u"other-dynamics");
    std::vector<LegacyRepairCandidate> candidates;
    int scoreIndex = 0;
    for (mu::engraving::Score* score : masterScore->scoreList()) {
        for (mu::engraving::Measure* measure = score->firstMeasure(); measure; measure = measure->nextMeasure()) {
            for (mu::engraving::Segment* segment = measure->first(); segment && segment->measure() == measure; segment = segment->next()) {
                for (mu::engraving::EngravingItem* annotation : segment->annotations()) {
                    if (!annotation) {
                        continue;
                    }
                    mu::engraving::EngravingItem* source = nullptr;
                    bool conflicting = false;
                    std::string kind;
                    std::string message;
                    if (annotation->isDynamic()) {
                        auto* target = mu::engraving::toDynamic(annotation);
                        if (target->dynamicType() != mu::engraving::DynamicType::OTHER
                            || !(target->xmlText().empty() || target->xmlText() == blankDynamicText)) {
                            continue;
                        }
                        for (mu::engraving::EngravingObject* linked : target->linkList()) {
                            if (linked == target || !linked->isDynamic()) { continue; }
                            auto* possible = mu::engraving::toDynamic(linked);
                            if (possible->dynamicType() == mu::engraving::DynamicType::OTHER) { continue; }
                            if (source) {
                                auto* first = mu::engraving::toDynamic(source);
                                if (first->dynamicType() != possible->dynamicType() || first->xmlText() != possible->xmlText()) {
                                    conflicting = true;
                                }
                            } else {
                                source = possible;
                            }
                        }
                        kind = "dynamic";
                        message = "Restore a blank dynamic from its matching linked marking.";
                    } else if (annotation->isTempoText() && savedByOldAriaEngine) {
                        auto* target = mu::engraving::toTempoText(annotation);
                        // Loading can normalize the in-memory BPM from the linked
                        // master even when this part serialized 120 BPM. The
                        // stale followText flag survives and identifies the bug.
                        if (target->followText()) { continue; }
                        for (mu::engraving::EngravingObject* linked : target->linkList()) {
                            if (linked == target || !linked->isTempoText()) { continue; }
                            auto* possible = mu::engraving::toTempoText(linked);
                            if (!possible->followText() || std::abs(possible->tempoBpm() - 120.0) < 0.01
                                || possible->xmlText() != target->xmlText()) { continue; }
                            if (source && std::abs(mu::engraving::toTempoText(source)->tempoBpm() - possible->tempoBpm()) > 0.01) {
                                conflicting = true;
                            } else if (!source) {
                                source = possible;
                            }
                        }
                        kind = "tempo";
                        message = "Restore this tempo setting from its matching linked marking.";
                    }
                    if (!source || conflicting) { continue; }
                    msr::render::ScoreLegacyRepairIssue issue;
                    issue.index = static_cast<int>(candidates.size());
                    issue.measureNumber = measure->no() + 1;
                    issue.staffIndex = static_cast<int>(annotation->staffIdx());
                    issue.kind = kind;
                    issue.location = scoreIndex == 0 ? "Full score" : "Part " + std::to_string(scoreIndex);
                    issue.message = message;
                    candidates.push_back({ issue, annotation, source, {}, {} });
                }
            }
        }
        ++scoreIndex;
    }

    // The checks below undo bugs of the pre-4.7.5 engine. A file last saved by any
    // other version may have the same shapes on purpose, so leave those alone.
    if (savedByOldAriaEngine) {
        scanMissingSystemMarkings(masterScore, candidates);
        scanDoubleEscapedPartNames(masterScore, candidates);
    }
    // Change Clef made stray starting clefs with every engine version; the repair is musically neutral.
    scanStrayStartClefs(masterScore, candidates);
    // Shapes desktop never saves, so these are safe whichever version saved the file.
    scanAriaLyrics(masterScore, candidates);
    scanDrumsOnPitchedStaves(masterScore, candidates);
    return candidates;
}

//! Chord symbols in parts that have no linked copy in the full score.
std::unordered_set<const mu::engraving::EngravingItem*> unlinkedPartHarmonies(mu::engraving::MasterScore* masterScore)
{
    std::unordered_set<const mu::engraving::EngravingItem*> result;
    if (!masterScore) {
        return result;
    }

    for (mu::engraving::Excerpt* excerpt : masterScore->excerpts()) {
        mu::engraving::Score* excerptScore = excerpt ? excerpt->excerptScore() : nullptr;
        if (!excerptScore) {
            continue;
        }
        for (mu::engraving::Measure* measure = excerptScore->firstMeasure(); measure; measure = measure->nextMeasure()) {
            for (mu::engraving::Segment* segment = measure->first(); segment && segment->measure() == measure; segment = segment->next()) {
                for (mu::engraving::EngravingItem* annotation : segment->annotations()) {
                    if (annotation && annotation->isHarmony() && !linkedItemInScore(annotation, masterScore)) {
                        result.insert(annotation);
                    }
                }
            }
        }
    }
    return result;
}

//! Blocks saving when a part has a chord symbol with no linked copy in the full
//! score, which the pre-4.7.5 engine produced when editing parts. Chord symbols
//! that were already part-only in a file desktop MuseScore saved are legitimate
//! and passed in `fileUnlinkedHarmonies`.
bool validatePartHarmonyLinksBeforeSave(mu::engraving::MasterScore* masterScore,
                                        const std::unordered_set<const mu::engraving::EngravingItem*>& fileUnlinkedHarmonies,
                                        std::string& errorMessage)
{
    if (!masterScore) {
        return true;
    }

    int excerptIndex = 0;
    for (mu::engraving::Excerpt* excerpt : masterScore->excerpts()) {
        mu::engraving::Score* excerptScore = excerpt ? excerpt->excerptScore() : nullptr;
        if (!excerptScore) {
            ++excerptIndex;
            continue;
        }

        for (mu::engraving::Measure* measure = excerptScore->firstMeasure(); measure; measure = measure->nextMeasure()) {
            for (mu::engraving::Segment* segment = measure->first(); segment && segment->measure() == measure; segment = segment->next()) {
                for (mu::engraving::EngravingItem* annotation : segment->annotations()) {
                    if (!annotation || !annotation->isHarmony()) {
                        continue;
                    }

                    if (linkedItemInScore(annotation, masterScore) || fileUnlinkedHarmonies.count(annotation) > 0) {
                        continue;
                    }

                    std::cout << "Aria save guard: blocked unlinked part chord symbol"
                              << " excerptIndex=" << excerptIndex
                              << " tick=" << segment->tick().ticks()
                              << " track=" << annotation->track()
                              << " score=" << excerptScore
                              << std::endl;
                    errorMessage = "A chord symbol in this part is not linked to the saved full score. Switch to Full Score and retry the edit before saving.";
                    return false;
                }
            }
        }

        ++excerptIndex;
    }

    return true;
}

//! The full score had several chord symbols and now has none. The pre-4.7.5
//! engine could lose them this way, so saving asks the user to confirm it.
bool masterHarmoniesCollapsed(mu::engraving::MasterScore* masterScore, const int maxObservedMasterHarmonyCount)
{
    return maxObservedMasterHarmonyCount >= 3 && harmonyCountInScore(masterScore) == 0;
}

bool validateMasterHarmonyRetainedBeforeSave(mu::engraving::MasterScore* masterScore,
                                             const int maxObservedMasterHarmonyCount,
                                             std::string& errorMessage)
{
    const int currentHarmonyCount = harmonyCountInScore(masterScore);
    if (masterHarmoniesCollapsed(masterScore, maxObservedMasterHarmonyCount)) {
        std::cout << "Aria save guard: blocked master chord symbol collapse"
                  << " maxObserved=" << maxObservedMasterHarmonyCount
                  << " current=" << currentHarmonyCount
                  << std::endl;
        errorMessage = "All chord symbols were removed from the full score. Save without them, or use Undo to keep them.";
        return false;
    }

    return true;
}

mu::engraving::Prefer keyboardPitchPreference(const bool preferFlats)
{
    return preferFlats ? mu::engraving::Prefer::FLATS : mu::engraving::Prefer::SHARPS;
}

bool normalizeNoteValueTpcs(mu::engraving::NoteVal& noteValue,
                            const mu::engraving::Staff* staff,
                            const mu::engraving::Fraction& tick,
                            const bool preferFlats)
{
    if (!staff || !mu::engraving::pitchIsValid(noteValue.pitch)) {
        return false;
    }

    const mu::engraving::Interval transpose = staff->transpose(tick);
    if (!mu::engraving::tpcIsValid(noteValue.tpc1)) {
        if (!mu::engraving::tpcIsValid(noteValue.tpc2)) {
            noteValue.tpc1 = mu::engraving::pitch2tpc(noteValue.pitch, staff->concertKey(tick), keyboardPitchPreference(preferFlats));
        } else if (transpose.isZero()) {
            noteValue.tpc1 = noteValue.tpc2;
        } else {
            noteValue.tpc1 = mu::engraving::Transpose::transposeTpc(noteValue.tpc2, transpose, true);
        }
    }

    if (!mu::engraving::tpcIsValid(noteValue.tpc2)) {
        if (transpose.isZero()) {
            noteValue.tpc2 = noteValue.tpc1;
        } else {
            mu::engraving::Interval flippedTranspose = transpose;
            flippedTranspose.flip();
            noteValue.tpc2 = mu::engraving::Transpose::transposeTpc(noteValue.tpc1, flippedTranspose, true);
        }
    }

    return mu::engraving::tpcIsValid(noteValue.tpc1) && mu::engraving::tpcIsValid(noteValue.tpc2);
}

bool isMusicXmlFile(const std::string& suffix)
{
    return suffix == "xml" || suffix == "musicxml" || suffix == "mxl";
}

std::string normalizedSuffix(const muse::io::path_t& path)
{
    std::string suffix = muse::io::suffix(path);
    std::transform(suffix.begin(), suffix.end(), suffix.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return suffix;
}

int sourceHarmonyCountInScoreFile(const muse::io::path_t& path)
{
    const auto ioMode = mu::engraving::mscIoModeBySuffix(normalizedSuffix(path));
    if (ioMode == mu::engraving::MscIoMode::Unknown) {
        return 0;
    }

    mu::engraving::MscReader::Params params;
    params.filePath = path;
    params.mode = ioMode;

    mu::engraving::MscReader reader(params);
    if (!reader.open()) {
        return 0;
    }

    const muse::ByteArray scoreData = reader.readScoreFile();
    if (scoreData.empty()) {
        return 0;
    }

    const std::string xml(scoreData.constChar(), scoreData.size());
    int count = 0;
    size_t pos = xml.find("<Harmony");
    while (pos != std::string::npos) {
        ++count;
        pos = xml.find("<Harmony", pos + 1);
    }

    return count;
}

// Aria's engine before 4.7.5 was a MuseScore 5.0 development snapshot. It stamped its
// saves as 4.70 / 4.7.2 (69af3e1), the same stamp desktop 4.7.2 writes, but it also
// wrote a few 5.0-only style tags (<groupBracket...>). Desktop 4.7.x and this engine
// drop those tags on save, so they mark a file last saved by that older Aria. Repairs
// for its bugs are only offered for such files, never for later deliberate edits.
bool scoreFileSavedByOldAriaEngine(const muse::io::path_t& path)
{
    const auto ioMode = mu::engraving::mscIoModeBySuffix(normalizedSuffix(path));
    if (ioMode == mu::engraving::MscIoMode::Unknown) {
        return false;
    }

    mu::engraving::MscReader::Params params;
    params.filePath = path;
    params.mode = ioMode;

    mu::engraving::MscReader reader(params);
    if (!reader.open()) {
        return false;
    }

    const muse::ByteArray scoreData = reader.readScoreFile();
    const std::string xml(scoreData.constChar(), scoreData.size());
    if (xml.substr(0, 512).find("<museScore version=\"4.70\"") == std::string::npos) {
        return false;
    }
    if (xml.find("<groupBracket") != std::string::npos) {
        return true; // single-file .mscx embeds its style
    }

    const muse::ByteArray styleData = reader.readStyleFile();
    const std::string style(styleData.constChar(), styleData.size());
    return style.find("<groupBracket") != std::string::npos;
}

// Mirrors EngravingProject::setupMasterScore, which desktop runs after every load and
// import. Loading replaces the score's style in place, so the padding table (horizontal
// spacing) must be rebuilt from the file's style, and ties and MIDI mapping connected.
// Updates stay locked: Aria lays the score out itself right after opening it.
void setupLoadedMasterScore(mu::engraving::MasterScore* score)
{
    score->createPaddingTable();
    score->connectTies();
    score->undoRemoveStaleTieJumpPoints(false);

    for (mu::engraving::Part* part : score->parts()) {
        part->updateHarmonyChannels(false);
    }

    score->rebuildMidiMapping();

    for (mu::engraving::Score* s : score->scoreList()) {
        s->setPlaylistDirty();
        s->setLayoutAll();
        s->createPaddingTable();
    }

    score->updateChannel();
}

muse::Ret loadScoreForRenderCore(mu::engraving::MasterScore* score, const muse::io::path_t& path)
{
    const std::string suffix = normalizedSuffix(path);

    if (mu::engraving::mscIoModeBySuffix(suffix) != mu::engraving::MscIoMode::Unknown) {
        muse::Ret result = mu::engraving::compat::loadMsczOrMscx(score, path, false);
        if (!result && result.code() == static_cast<int>(mu::engraving::Err::FileTooNew)) {
            // Files from MuseScore 5 (format 5.00+). Open them anyway, like desktop
            // 4.7.5's "Open anyway"; saving writes them back as 4.70.
            std::cout << "Aria load: newer-format file, opening anyway path=\"" << path.toStdString() << "\"" << std::endl;
            result = mu::engraving::compat::loadMsczOrMscx(score, path, true);
        }
        if (result) {
            // Same order as NotationProject::doLoad: set up the master score, then the
            // pre-layout migrations (including legacy staff-text alignment), then capo.
            // Apply them once on native-file import, never on later relayouts or
            // MusicXML imports. The engine gates the migrations by source version.
            score->lockUpdates(true);
            setupLoadedMasterScore(score);
            mu::engraving::compat::EngravingCompat::doPreLayoutCompatIfNeeded(score);
            score->updateCapo(/* ignoreNotationUpdate */ true);
            score->lockUpdates(false);
        }
        return result;
    }

    if (!isMusicXmlFile(suffix)) {
        return mu::engraving::make_ret(mu::engraving::Err::FileUnknownType, path);
    }

    score->checkChordList();

    mu::engraving::Err err = mu::engraving::Err::FileUnknownType;
    if (suffix == "mxl") {
        err = mu::iex::musicxml::importCompressedMusicXml(score, path.toString(), false);
    } else {
        err = mu::iex::musicxml::importMusicXml(score, path.toString(), false);
    }

    if (err != mu::engraving::Err::NoError) {
        return mu::engraving::make_ret(err, path);
    }

    score->lockUpdates(true);
    setupLoadedMasterScore(score);
    score->lockUpdates(false);

    score->setMetaTag(u"originalFormat", QString::fromStdString(suffix));
    return muse::make_ok();
}

// JSON keys, mirroring src/framework/mpe/internal/articulationprofilesrepository.cpp
// so the embedded profiles parse identically to the desktop loader.
const QString kMpeSupportedFamiliesKey = "supportedFamilies";
const QString kMpePatternsKey = "patterns";
const QString kMpePatternPosKey = "patternPosition";
const QString kMpeOffsetPosKey = "offsetPosition";
const QString kMpeOffsetValKey = "offsetValue";
const QString kMpeArrangementPatternKey = "arrangementPattern";
const QString kMpeDurationFactorKey = "durationFactor";
const QString kMpeTimestampOffsetKey = "timestampOffset";
const QString kMpePitchPatternKey = "pitchPattern";
const QString kMpePitchOffsetsKey = "pitchOffsets";
const QString kMpeExpressionPatternKey = "expressionPattern";
const QString kMpeDynamicOffsetsKey = "dynamicOffsets";

muse::mpe::ArrangementPattern arrangementPatternFromJson(const QJsonObject& obj)
{
    muse::mpe::ArrangementPattern result;
    result.durationFactor = obj.value(kMpeDurationFactorKey).toInt();
    result.timestampOffset = obj.value(kMpeTimestampOffsetKey).toInt();
    return result;
}

muse::mpe::PitchPattern pitchPatternFromJson(const QJsonObject& obj)
{
    muse::mpe::PitchPattern result;
    const QJsonArray offsets = obj.value(kMpePitchOffsetsKey).toArray();
    for (const QJsonValue pitchOffset : offsets) {
        const QJsonObject offsetObj = pitchOffset.toObject();
        result.pitchOffsetMap.emplace(offsetObj.value(kMpeOffsetPosKey).toInt(),
                                      offsetObj.value(kMpeOffsetValKey).toInt());
    }
    return result;
}

muse::mpe::ExpressionPattern expressionPatternFromJson(const QJsonObject& obj)
{
    muse::mpe::ExpressionPattern result;
    const QJsonArray offsets = obj.value(kMpeDynamicOffsetsKey).toArray();
    for (const QJsonValue offset : offsets) {
        const QJsonObject offsetObj = offset.toObject();
        result.dynamicOffsetMap.emplace(offsetObj.value(kMpeOffsetPosKey).toInt(),
                                        offsetObj.value(kMpeOffsetValKey).toInt());
    }
    return result;
}

muse::mpe::ArticulationPattern patternsScopeFromJson(const QJsonArray& array)
{
    muse::mpe::ArticulationPattern result;
    for (const QJsonValue& val : array) {
        const QJsonObject patternObj = val.toObject();
        const muse::mpe::duration_percentage_t position = patternObj.value(kMpePatternPosKey).toInt();

        muse::mpe::ArticulationPatternSegment articulation;
        articulation.arrangementPattern = arrangementPatternFromJson(patternObj.value(kMpeArrangementPatternKey).toObject());
        articulation.pitchPattern = pitchPatternFromJson(patternObj.value(kMpePitchPatternKey).toObject());
        articulation.expressionPattern = expressionPatternFromJson(patternObj.value(kMpeExpressionPatternKey).toObject());

        result.emplace(position, std::move(articulation));
    }
    return result;
}

muse::mpe::ArticulationsProfilePtr makeStandardOnlyArticulationProfile()
{
    muse::mpe::ArticulationsProfilePtr profile = std::make_shared<muse::mpe::ArticulationsProfile>();
    muse::mpe::ArticulationPattern standardPattern;
    standardPattern[0] = muse::mpe::ArticulationPatternSegment();
    standardPattern[muse::mpe::HUNDRED_PERCENT] = muse::mpe::ArticulationPatternSegment();
    profile->setPattern(muse::mpe::ArticulationType::Standard, standardPattern);
    return profile;
}

muse::mpe::ArticulationsProfilePtr parseArticulationProfileJson(const std::string& json)
{
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(QByteArray::fromStdString(json), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        return nullptr;
    }

    const QJsonObject rootObj = doc.object();
    muse::mpe::ArticulationsProfilePtr result = std::make_shared<muse::mpe::ArticulationsProfile>();

    const QJsonArray families = rootObj.value(kMpeSupportedFamiliesKey).toArray();
    for (const QJsonValue& val : families) {
        result->supportedFamilies.push_back(muse::mpe::articulationFamilyFromString(val.toString()));
    }

    const QJsonObject patterns = rootObj.value(kMpePatternsKey).toObject();
    for (const QString& key : patterns.keys()) {
        const muse::mpe::ArticulationType type = muse::mpe::articulationTypeFromString(key);
        if (type == muse::mpe::ArticulationType::Undefined) {
            continue;
        }
        result->setPattern(type, patternsScopeFromJson(patterns.value(key).toArray()));
    }

    // Always guarantee a Standard pattern so notes without a mapped articulation
    // still render, matching the previous fallback behavior.
    if (!result->contains(muse::mpe::ArticulationType::Standard)) {
        muse::mpe::ArticulationPattern standardPattern;
        standardPattern[0] = muse::mpe::ArticulationPatternSegment();
        standardPattern[muse::mpe::HUNDRED_PERCENT] = muse::mpe::ArticulationPatternSegment();
        result->setPattern(muse::mpe::ArticulationType::Standard, standardPattern);
    }

    return result;
}

const char* embeddedProfileKeyForFamily(const muse::mpe::ArticulationFamily family)
{
    switch (family) {
    case muse::mpe::ArticulationFamily::Strings:     return "strings";
    case muse::mpe::ArticulationFamily::Winds:       return "winds";
    case muse::mpe::ArticulationFamily::Keyboards:   return "keyboard";
    case muse::mpe::ArticulationFamily::Percussions: return "percussion";
    case muse::mpe::ArticulationFamily::Voices:      return "voice";
    case muse::mpe::ArticulationFamily::Undefined:
    default:                                         return nullptr;
    }
}

// Provides MuseScore's real per-family articulation patterns (loaded from the
// embedded copies of src/framework/mpe/resources/*.json) so playback-affecting
// articulations such as pizzicato survive note rendering instead of being
// stripped by an empty profile.
class RenderCoreArticulationProfilesRepository : public muse::mpe::IArticulationProfilesRepository
{
public:
    muse::mpe::ArticulationsProfilePtr createNew() const override
    {
        return std::make_shared<muse::mpe::ArticulationsProfile>();
    }

    muse::mpe::ArticulationsProfilePtr defaultProfile(const muse::mpe::ArticulationFamily family) const override
    {
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            auto it = m_cache.find(family);
            if (it != m_cache.end()) {
                return it->second;
            }
        }

        muse::mpe::ArticulationsProfilePtr profile = buildProfileForFamily(family);
        if (!profile) {
            profile = makeStandardOnlyArticulationProfile();
        }

        std::lock_guard<std::mutex> lock(m_mutex);
        m_cache[family] = profile;
        return profile;
    }

    muse::mpe::ArticulationsProfilePtr loadProfile(const muse::io::path_t&) const override
    {
        return makeStandardOnlyArticulationProfile();
    }

    void saveProfile(const muse::io::path_t&, const muse::mpe::ArticulationsProfilePtr) override
    {
    }

    muse::async::Channel<muse::io::path_t> profileChanged() const override
    {
        static muse::async::Channel<muse::io::path_t> channel;
        return channel;
    }

private:
    static muse::mpe::ArticulationsProfilePtr buildProfileForFamily(const muse::mpe::ArticulationFamily family)
    {
        const char* key = embeddedProfileKeyForFamily(family);
        if (!key) {
            return nullptr;
        }

        const std::map<std::string, std::string>& profiles = msr::render::embeddedArticulationProfiles();
        auto it = profiles.find(key);
        if (it == profiles.end()) {
            return nullptr;
        }

        return parseArticulationProfileJson(it->second);
    }

    mutable std::mutex m_mutex;
    mutable std::map<muse::mpe::ArticulationFamily, muse::mpe::ArticulationsProfilePtr> m_cache;
};

class RenderCoreMusicXmlConfiguration : public mu::iex::musicxml::IMusicXmlConfiguration
{
public:
    bool importBreaks() const override { return m_importBreaks; }
    void setImportBreaks(bool value) override { m_importBreaks = value; m_importBreaksChanged.send(value); }
    muse::async::Channel<bool> importBreaksChanged() const override { return m_importBreaksChanged; }

    bool importLayout() const override { return m_importLayout; }
    void setImportLayout(bool value) override { m_importLayout = value; m_importLayoutChanged.send(value); }
    muse::async::Channel<bool> importLayoutChanged() const override { return m_importLayoutChanged; }

    bool exportLayout() const override { return m_exportLayout; }
    void setExportLayout(bool value) override { m_exportLayout = value; }

    bool exportMu3Compat() const override { return m_exportMu3Compat; }
    void setExportMu3Compat(bool value) override { m_exportMu3Compat = value; }

    MusicXmlExportBreaksType exportBreaksType() const override { return m_exportBreaksType; }
    void setExportBreaksType(MusicXmlExportBreaksType breaksType) override { m_exportBreaksType = breaksType; }

    bool exportInvisibleElements() const override { return m_exportInvisibleElements; }
    void setExportInvisibleElements(bool value) override { m_exportInvisibleElements = value; }

    bool needUseDefaultFont() const override { return m_needUseDefaultFontOverride.value_or(m_needUseDefaultFont); }
    void setNeedUseDefaultFont(bool value) override { m_needUseDefaultFont = value; m_needUseDefaultFontChanged.send(value); }
    muse::async::Channel<bool> needUseDefaultFontChanged() const override { return m_needUseDefaultFontChanged; }
    void setNeedUseDefaultFontOverride(std::optional<bool> value) override { m_needUseDefaultFontOverride = value; }

    bool needAskAboutApplyingNewStyle() const override { return m_needAskAboutApplyingNewStyle; }
    void setNeedAskAboutApplyingNewStyle(bool value) override { m_needAskAboutApplyingNewStyle = value; m_needAskAboutApplyingNewStyleChanged.send(value); }
    muse::async::Channel<bool> needAskAboutApplyingNewStyleChanged() const override { return m_needAskAboutApplyingNewStyleChanged; }

    bool inferTextType() const override { return m_inferTextTypeOverride.value_or(m_inferTextType); }
    void setInferTextType(bool value) override { m_inferTextType = value; m_inferTextTypeChanged.send(value); }
    muse::async::Channel<bool> inferTextTypeChanged() const override { return m_inferTextTypeChanged; }
    void setInferTextTypeOverride(std::optional<bool> value) override { m_inferTextTypeOverride = value; }

private:
    bool m_importBreaks = true;
    bool m_importLayout = true;
    bool m_exportLayout = true;
    bool m_exportMu3Compat = false;
    MusicXmlExportBreaksType m_exportBreaksType = MusicXmlExportBreaksType::All;
    bool m_exportInvisibleElements = false;
    bool m_needUseDefaultFont = false;
    bool m_needAskAboutApplyingNewStyle = true;
    bool m_inferTextType = false;
    std::optional<bool> m_needUseDefaultFontOverride;
    std::optional<bool> m_inferTextTypeOverride;
    mutable muse::async::Channel<bool> m_importBreaksChanged;
    mutable muse::async::Channel<bool> m_importLayoutChanged;
    mutable muse::async::Channel<bool> m_needUseDefaultFontChanged;
    mutable muse::async::Channel<bool> m_needAskAboutApplyingNewStyleChanged;
    mutable muse::async::Channel<bool> m_inferTextTypeChanged;
};

class RenderCoreMimeData : public mu::engraving::IMimeData
{
public:
    RenderCoreMimeData(std::string mimeType, muse::ByteArray data)
        : m_mimeType(std::move(mimeType)), m_data(std::move(data))
    {
    }

    std::vector<std::string> formats() const override
    {
        return m_data.empty() ? std::vector<std::string>() : std::vector<std::string> { m_mimeType };
    }

    bool hasFormat(const std::string& mimeType) const override
    {
        return !m_data.empty() && mimeType == m_mimeType;
    }

    muse::ByteArray data(const std::string& mimeType) const override
    {
        return hasFormat(mimeType) ? m_data : muse::ByteArray();
    }

    bool hasImage() const override
    {
        return false;
    }

    std::shared_ptr<muse::draw::Pixmap> imageData() const override
    {
        return nullptr;
    }

private:
    std::string m_mimeType;
    muse::ByteArray m_data;
};

template <typename Fn>
auto invokeOnMainThreadSync(Fn&& fn) -> decltype(fn())
{
    using Result = decltype(fn());

    QCoreApplication* application = QCoreApplication::instance();
    if (!application || QThread::currentThread() == application->thread()) {
        if constexpr (std::is_void_v<Result>) {
            fn();
            return;
        } else {
            return fn();
        }
    }

    if constexpr (std::is_void_v<Result>) {
        QMetaObject::invokeMethod(application, std::forward<Fn>(fn), Qt::BlockingQueuedConnection);
        return;
    } else {
        std::optional<Result> result;
        QMetaObject::invokeMethod(application, [call = std::forward<Fn>(fn), &result]() mutable {
            result.emplace(call());
        }, Qt::BlockingQueuedConnection);
        return std::move(*result);
    }
}

bool validateScorePath(const std::string& scorePath, std::string& errorMessage)
{
    if (scorePath.empty()) {
        errorMessage = "A score path is required.";
        return false;
    }

    return true;
}

bool validateDpi(const int dpi, std::string& errorMessage)
{
    if (dpi <= 0) {
        errorMessage = "The DPI must be a positive integer.";
        return false;
    }

    return true;
}

double clampUnitInterval(double value)
{
    return std::clamp(value, 0.0, 1.0);
}

QString normalizedMetadataValue(const std::string& value)
{
    return QString::fromUtf8(value.c_str()).trimmed();
}

//! NOTE The title frame carries four texts that mirror score meta tags. Keeping the two in
//! sync matters because the score text is what the user reads, while the meta tag is what
//! the Score Setup sheet, the library row and the saved <metaTag> elements read back.
muse::String metadataTagForTextStyle(const mu::engraving::TextStyleType textStyleType)
{
    switch (textStyleType) {
    case mu::engraving::TextStyleType::TITLE:
        return muse::String(u"workTitle");
    case mu::engraving::TextStyleType::SUBTITLE:
        return muse::String(u"subtitle");
    case mu::engraving::TextStyleType::COMPOSER:
        return muse::String(u"composer");
    case mu::engraving::TextStyleType::LYRICIST:
        return muse::String(u"lyricist");
    default:
        return muse::String();
    }
}

//! NOTE Must be called inside a startCmd()/endCmd() macro: the writes go through the undo
//! stack so that a single undo reverts them, and so that a later undo of an earlier edit
//! cannot silently discard them.
void setStyledMetadataText(mu::engraving::MasterScore* score,
                           const mu::engraving::TextStyleType textStyleType,
                           const QString& text)
{
    if (!score) {
        return;
    }

    const muse::String newXmlText
        = mu::engraving::TextBase::plainToXmlText(muse::String::fromQString(text));

    mu::engraving::TextBase* textItem = score->getText(textStyleType);
    if (!textItem) {
        if (newXmlText.empty()) {
            return;
        }
        // Score::addText() routes through undoAddElement(), so it joins the active macro.
        textItem = score->addText(textStyleType);
    }

    if (!textItem || textItem->xmlText() == newXmlText) {
        return;
    }

    // Clearing a field removes the text element, as MuseScore does when title text is emptied,
    // rather than leaving an invisible empty item in the title frame.
    if (newXmlText.empty()) {
        score->undoRemoveElement(textItem);
        return;
    }

    textItem->undoChangeProperty(mu::engraving::Pid::TEXT, newXmlText);
}

//! NOTE Must be called inside a startCmd()/endCmd() macro, right after the text element
//! itself was changed, so that the meta tag travels with it on undo/redo.
void syncMetaTagForStyledText(mu::engraving::MasterScore* score, const mu::engraving::EngravingItem* item)
{
    if (!score || !item || !item->isTextBase()) {
        return;
    }

    const mu::engraving::TextBase* textItem = mu::engraving::toTextBase(item);
    const muse::String tag = metadataTagForTextStyle(textItem->textStyleType());
    if (tag.empty()) {
        return;
    }

    const muse::String value = textItem->plainText();
    if (score->metaTag(tag) == value) {
        return;
    }

    score->undo(new mu::engraving::ChangeMetaText(score, tag, value));
}

mu::engraving::DurationType durationTypeForCode(const int durationCode)
{
    using mu::engraving::DurationType;

    switch (durationCode) {
    case 1:
        return DurationType::V_WHOLE;
    case 2:
        return DurationType::V_HALF;
    case 4:
        return DurationType::V_QUARTER;
    case 8:
        return DurationType::V_EIGHTH;
    case 16:
        return DurationType::V_16TH;
    default:
        return DurationType::V_INVALID;
    }
}

int durationCodeForType(const mu::engraving::DurationType durationType)
{
    using mu::engraving::DurationType;

    switch (durationType) {
    case DurationType::V_WHOLE:
    case DurationType::V_MEASURE:
        return 1;
    case DurationType::V_HALF:
        return 2;
    case DurationType::V_QUARTER:
        return 4;
    case DurationType::V_EIGHTH:
        return 8;
    case DurationType::V_16TH:
        return 16;
    default:
        return 4;
    }
}

mu::engraving::Pad padForDurationCode(const int durationCode)
{
    switch (durationCode) {
    case 1:
        return mu::engraving::Pad::NOTE1;
    case 2:
        return mu::engraving::Pad::NOTE2;
    case 4:
        return mu::engraving::Pad::NOTE4;
    case 8:
        return mu::engraving::Pad::NOTE8;
    case 16:
        return mu::engraving::Pad::NOTE16;
    default:
        return mu::engraving::Pad::NOTE4;
    }
}

bool isStandardStaff(const mu::engraving::Staff* staff, const mu::engraving::Fraction& tick)
{
    return staff && !staff->isTabStaff(tick) && !staff->isDrumStaff(tick);
}

std::string layoutBreakKind(const mu::engraving::LayoutBreak* layoutBreak)
{
    if (!layoutBreak) {
        return std::string();
    }

    switch (layoutBreak->layoutBreakType()) {
    case mu::engraving::LayoutBreakType::LINE:
        return "system";
    case mu::engraving::LayoutBreakType::PAGE:
        return "page";
    case mu::engraving::LayoutBreakType::SECTION:
        return "section";
    case mu::engraving::LayoutBreakType::NOBREAK:
        return "nobreak";
    default:
        return std::string();
    }
}

mu::engraving::RectF layoutMarkerRectForMeasureBase(const mu::engraving::MeasureBase* measureBase)
{
    if (!measureBase) {
        return mu::engraving::RectF();
    }

    const double spatium = std::max(measureBase->spatium(), 1.0);
    const double side = std::max(spatium * 2.2, 6.0);
    const mu::engraving::RectF measureRect = measureBase->pageBoundingRect();
    const double measureRight = measureRect.width() > 0.0
        ? measureRect.right()
        : measureBase->pageX() + measureBase->width();

    double x = measureRight - side - (0.5 * spatium);
    if (measureRect.width() > 0.0) {
        x = std::max(measureRect.left(), x);
    }

    const mu::engraving::System* system = measureBase->system();
    double y = measureRect.height() > 0.0
        ? measureRect.top() - (3.0 * spatium)
        : measureBase->pagePos().y() - (3.0 * spatium);
    if (system) {
        mu::engraving::staff_idx_t staffIdx = system->firstVisibleStaff();
        if (staffIdx == muse::nidx) {
            staffIdx = 0;
        }
        y = system->staffYpage(staffIdx) - (3.0 * spatium);
    }

    return mu::engraving::RectF(x, y, side, side);
}

mu::engraving::RectF layoutBreakMarkerRect(const mu::engraving::LayoutBreak* layoutBreak,
                                           const mu::engraving::MeasureBase* fallbackMeasureBase = nullptr)
{
    if (!layoutBreak) {
        return mu::engraving::RectF();
    }

    const mu::engraving::MeasureBase* measureBase = layoutBreak->measure()
        ? layoutBreak->measure()
        : fallbackMeasureBase;
    return layoutMarkerRectForMeasureBase(measureBase);
}

const mu::engraving::MeasureBase* systemLockIndicatorEndMeasureBase(const mu::engraving::SystemLockIndicator* indicator)
{
    if (!indicator || !indicator->systemLock()) {
        return nullptr;
    }

    return indicator->systemLock()->endMB();
}

mu::engraving::RectF systemLockMarkerRect(const mu::engraving::SystemLockIndicator* indicator)
{
    return layoutMarkerRectForMeasureBase(systemLockIndicatorEndMeasureBase(indicator));
}

mu::engraving::Page* pageForIndex(mu::engraving::Score* score, const int pageIndex)
{
    if (!score || pageIndex < 0 || pageIndex >= static_cast<int>(score->npages())) {
        return nullptr;
    }

    return score->pages().at(static_cast<size_t>(pageIndex));
}

mu::engraving::PointF pointForNormalizedPagePosition(const mu::engraving::Page* page,
                                                     const double normalizedX,
                                                     const double normalizedY)
{
    const double clampedX = clampUnitInterval(normalizedX);
    const double clampedY = clampUnitInterval(normalizedY);
    return mu::engraving::PointF(page->width() * clampedX, page->height() * clampedY);
}

// MuseScore's point lookups (Score::getPosition, Score::putNote) take canvas coordinates,
// where every page sits at its own offset; Aria's taps arrive relative to one page.
mu::engraving::PointF canvasPointForPagePoint(const mu::engraving::Page* page, const mu::engraving::PointF& pagePoint)
{
    return page ? pagePoint + page->pos() : pagePoint;
}

// Score::getPosition reports its position in canvas coordinates; bring it back to the page.
bool getPagePosition(mu::engraving::Score* score,
                     const mu::engraving::Page* page,
                     mu::engraving::Position* position,
                     const mu::engraving::PointF& pagePoint,
                     const mu::engraving::voice_idx_t voice)
{
    if (!score->getPosition(position, canvasPointForPagePoint(page, pagePoint), voice)) {
        return false;
    }
    if (page) {
        position->pos -= page->pos();
    }
    return true;
}

mu::engraving::RectF rectAroundPoint(const mu::engraving::PointF& point, const double radius)
{
    return mu::engraving::RectF(point.x() - radius, point.y() - radius, radius * 2.0, radius * 2.0);
}

bool isDirectlySelectable(const mu::engraving::EngravingItem* item)
{
    if (!item) {
        return false;
    }

    if (item->isRest()) {
        const mu::engraving::Measure* measure = item->findMeasure();
        if (measure && measure->isMMRest()) {
            return false;
        }
    }

    return item->isNote()
        || item->isRest()
        || item->isChord()
        || item->isBarLine()
        || item->isTimeSig()
        || item->isKeySig()
        || item->isTempoText()
        || item->isHarmony()
        || item->isArticulationOrFermata()
        || item->isBreath()
        || item->isClef()
        || item->isArpeggio()
        || item->isChordLine()
        || item->type() == mu::engraving::ElementType::TREMOLO_SINGLECHORD
        || item->type() == mu::engraving::ElementType::TREMOLO_TWOCHORD
        || item->isTuplet()
        || item->isFretDiagram()
        || item->isHarpPedalDiagram()
        || item->isBSymbol()
        || item->isLyrics()
        || item->isText()
        || item->isStaffText()
        || item->isSystemText()
        || item->isLayoutBreak()
        || item->isSystemLockIndicator()
        || item->isHBox()
        || item->isSlurTie()
        || item->isSlurTieSegment()
        || item->isSpanner()
        || item->isSpannerSegment()
        || item->isTextBase();
}

// Selections drawn by recolouring the symbol itself in the selection blue (as notes and rests
// are, and as desktop MuseScore does) rather than by a box: the shape is the whole object.
bool usesSymbolSelectionHighlight(const mu::engraving::EngravingItem* item)
{
    return item && (item->isArticulationOrFermata()
                    || item->isBreath()
                    || item->isClef()
                    || item->isKeySig()
                    || item->isTimeSig()
                    || item->isBarLine()
                    || item->isArpeggio()
                    || item->isChordLine()
                    || item->type() == mu::engraving::ElementType::TREMOLO_SINGLECHORD
                    || item->type() == mu::engraving::ElementType::TREMOLO_TWOCHORD);
}

bool isEditableTextItem(const mu::engraving::EngravingItem* item)
{
    return item && (item->isHarmony()
                    || item->isText()
                    || item->isStaffText()
                    || item->isSystemText()
                    || item->isTextBase()
                    || item->isDynamic()
                    || item->isTempoText()
                    || item->isJump()
                    || item->isMarker()
                    || item->isLyrics());
}

bool isDirectlyDraggableTextItem(const mu::engraving::EngravingItem* item)
{
    if (!item || !item->isMovable()) {
        return false;
    }

    switch (item->type()) {
    case mu::engraving::ElementType::HARMONY:
    case mu::engraving::ElementType::TEXT:
    case mu::engraving::ElementType::STAFF_TEXT:
    case mu::engraving::ElementType::SYSTEM_TEXT:
    case mu::engraving::ElementType::DYNAMIC:
    case mu::engraving::ElementType::EXPRESSION:
    case mu::engraving::ElementType::TEMPO_TEXT:
    case mu::engraving::ElementType::MARKER:
    case mu::engraving::ElementType::JUMP:
    case mu::engraving::ElementType::REHEARSAL_MARK:
    case mu::engraving::ElementType::FERMATA:
        return true;
    default:
        return false;
    }
}

mu::engraving::Note* editableNoteForItem(mu::engraving::EngravingItem* item)
{
    if (!item) {
        return nullptr;
    }

    if (item->isNote()) {
        return mu::engraving::toNote(item);
    }

    if (item->isChord()) {
        mu::engraving::Chord* chord = mu::engraving::toChord(item);
        return chord ? chord->upNote() : nullptr;
    }

    mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(item);
    if (!chordRest || !chordRest->isChord()) {
        return nullptr;
    }

    mu::engraving::Chord* chord = mu::engraving::toChord(chordRest);
    return chord ? chord->upNote() : nullptr;
}

mu::engraving::EngravingItem* noteOrRestSelectionItem(mu::engraving::EngravingItem* item)
{
    if (!item) {
        return nullptr;
    }

    if (item->isNote() || item->isRest()) {
        return item;
    }

    if (mu::engraving::Note* note = editableNoteForItem(item)) {
        return note;
    }

    return nullptr;
}

// Taps on parts of a note or chord (stem, flag, beam, dot, accidental) select the note itself.
mu::engraving::EngravingItem* selectableTargetForItem(mu::engraving::EngravingItem* item, const mu::engraving::PointF& point)
{
    if (!item) {
        return nullptr;
    }

    if (item->isBeam()) {
        mu::engraving::ChordRest* nearest = nullptr;
        double nearestDistance = std::numeric_limits<double>::max();
        for (mu::engraving::ChordRest* chordRest : mu::engraving::toBeam(item)->elements()) {
            if (!chordRest || !chordRest->isChord()) {
                continue;
            }
            const double distance = std::abs(chordRest->pageBoundingRect().center().x() - point.x());
            if (distance < nearestDistance) {
                nearestDistance = distance;
                nearest = chordRest;
            }
        }
        return nearest ? editableNoteForItem(nearest) : nullptr;
    }

    if (item->isAccidental() || item->isNoteDot()) {
        mu::engraving::EngravingItem* parent = item->parentItem();
        return parent && (parent->isNote() || parent->isRest()) && isDirectlySelectable(parent) ? parent : nullptr;
    }

    if (item->isStem() || item->isHook() || item->isStemSlash()) {
        mu::engraving::EngravingItem* parent = item->parentItem();
        return parent && parent->isChord() ? editableNoteForItem(parent) : nullptr;
    }

    return isDirectlySelectable(item) ? item : nullptr;
}

double distanceToRect(const mu::engraving::RectF& rect, const mu::engraving::PointF& point)
{
    const double dx = std::max({ rect.left() - point.x(), 0.0, point.x() - rect.right() });
    const double dy = std::max({ rect.top() - point.y(), 0.0, point.y() - rect.bottom() });
    return std::sqrt((dx * dx) + (dy * dy));
}

int selectionPriority(const mu::engraving::EngravingItem* item)
{
    if (item->isLayoutBreak() || item->isSystemLockIndicator()) {
        return -1;
    }

    if (item->isNote()) {
        return 0;
    }

    if (item->isRest()) {
        return 1;
    }

    if (item->isLyrics()) {
        return 2;
    }

    return 2;
}

struct SelectionCandidateScore {
    double edgeDistance = std::numeric_limits<double>::max();
    int priority = std::numeric_limits<int>::max();
    double centerDistance = std::numeric_limits<double>::max();
    double area = std::numeric_limits<double>::max();

    bool operator<(const SelectionCandidateScore& other) const
    {
        constexpr double epsilon = 0.001;
        if (std::abs(edgeDistance - other.edgeDistance) > epsilon) {
            return edgeDistance < other.edgeDistance;
        }

        if (priority != other.priority) {
            return priority < other.priority;
        }

        if (std::abs(centerDistance - other.centerDistance) > epsilon) {
            return centerDistance < other.centerDistance;
        }

        return area < other.area;
    }
};

SelectionCandidateScore selectionDistanceScore(const mu::engraving::EngravingItem* item, const mu::engraving::PointF& point)
{
    mu::engraving::RectF boundingRect = item->pageBoundingRect();
    if (item->isLayoutBreak()) {
        boundingRect = layoutBreakMarkerRect(mu::engraving::toLayoutBreak(item));
    } else if (item->isSystemLockIndicator()) {
        boundingRect = systemLockMarkerRect(mu::engraving::toSystemLockIndicator(item));
    }
    const mu::engraving::PointF center = boundingRect.center();
    const double dx = center.x() - point.x();
    const double dy = center.y() - point.y();
    return SelectionCandidateScore {
        distanceToRect(boundingRect, point),
        selectionPriority(item),
        std::sqrt((dx * dx) + (dy * dy)),
        std::max(boundingRect.width() * boundingRect.height(), 1.0)
    };
}

mu::engraving::EngravingItem* selectBestCandidate(const std::vector<mu::engraving::EngravingItem*>& items,
                                                  const mu::engraving::PointF& point)
{
    mu::engraving::EngravingItem* bestItem = nullptr;
    SelectionCandidateScore bestScore;

    for (mu::engraving::EngravingItem* item : items) {
        mu::engraving::EngravingItem* target = selectableTargetForItem(item, point);
        if (!target) {
            continue;
        }

        const SelectionCandidateScore score = selectionDistanceScore(item, point);
        if (score < bestScore) {
            bestScore = score;
            bestItem = target;
        }
    }

    return bestItem;
}

void appendLayoutBreakCandidates(mu::engraving::Page* page,
                                  const mu::engraving::PointF& point,
                                  const double maxEdgeDistance,
                                  std::vector<mu::engraving::EngravingItem*>& items)
{
    if (!page) {
        return;
    }

    for (mu::engraving::System* system : page->systems()) {
        if (!system) {
            continue;
        }

        for (mu::engraving::MeasureBase* measureBase : system->measures()) {
            if (!measureBase) {
                continue;
            }

            for (mu::engraving::EngravingItem* item : measureBase->el()) {
                if (!item || !item->isLayoutBreak()) {
                    continue;
                }

                const mu::engraving::RectF rect = layoutBreakMarkerRect(mu::engraving::toLayoutBreak(item), measureBase);
                if (rect.width() <= 0.0 || rect.height() <= 0.0) {
                    continue;
                }

                if (distanceToRect(rect, point) <= maxEdgeDistance) {
                    items.push_back(item);
                }
            }
        }

        for (mu::engraving::SystemLockIndicator* indicator : system->lockIndicators()) {
            const mu::engraving::RectF rect = systemLockMarkerRect(indicator);
            if (rect.width() <= 0.0 || rect.height() <= 0.0) {
                continue;
            }

            if (distanceToRect(rect, point) <= maxEdgeDistance) {
                items.push_back(indicator);
            }
        }
    }
}

mu::engraving::EngravingItem* directSelectableItemAtPoint(mu::engraving::Page* page,
                                                         const mu::engraving::PointF& point)
{
    if (!page) {
        return nullptr;
    }

    std::vector<mu::engraving::EngravingItem*> items = page->items(point);
    appendLayoutBreakCandidates(page, point, 0.0, items);
    return selectBestCandidate(items, point);
}

mu::engraving::EngravingItem* nearbySelectableItemAtPoint(mu::engraving::Page* page,
                                                         const mu::engraving::PointF& point,
                                                         const double selectionRadius,
                                                         const double maxEdgeDistance)
{
    if (!page) {
        return nullptr;
    }

    mu::engraving::EngravingItem* bestItem = nullptr;
    SelectionCandidateScore bestScore;

    std::vector<mu::engraving::EngravingItem*> items = page->items(rectAroundPoint(point, selectionRadius));
    appendLayoutBreakCandidates(page, point, maxEdgeDistance, items);

    for (mu::engraving::EngravingItem* item : items) {
        mu::engraving::EngravingItem* target = selectableTargetForItem(item, point);
        if (!target) {
            continue;
        }

        const SelectionCandidateScore score = selectionDistanceScore(item, point);
        if (score.edgeDistance <= maxEdgeDistance && score < bestScore) {
            bestScore = score;
            bestItem = target;
        }
    }

    return bestItem;
}

struct MeasureHit {
    mu::engraving::Measure* measure = nullptr;
    mu::engraving::staff_idx_t staffIdx = 0;
};

double distanceToRange(const double value, const double minimum, const double maximum)
{
    if (value < minimum) {
        return minimum - value;
    }
    if (value > maximum) {
        return value - maximum;
    }
    return 0.0;
}

mu::engraving::staff_idx_t nearestVisibleStaff(mu::engraving::Score* score,
                                               mu::engraving::System* system,
                                               const mu::engraving::PointF& pagePoint)
{
    if (!score || !system || score->nstaves() == 0) {
        return 0;
    }

    mu::engraving::staff_idx_t bestStaff = 0;
    double bestDistance = std::numeric_limits<double>::max();
    for (mu::engraving::staff_idx_t staffIdx = 0; staffIdx < score->nstaves(); ++staffIdx) {
        const mu::engraving::Staff* staff = score->staff(staffIdx);
        mu::engraving::SysStaff* sysStaff = system->staff(staffIdx);
        if (!staff || !sysStaff || !staff->show() || !sysStaff->show()) {
            continue;
        }

        const double staffTop = system->staffYpage(staffIdx);
        const double distance = distanceToRange(pagePoint.y(), staffTop, staffTop + staff->staffHeight(system->tick()));
        if (distance < bestDistance) {
            bestDistance = distance;
            bestStaff = staffIdx;
        }
    }

    return bestStaff;
}

double systemVerticalDistance(mu::engraving::Score* score,
                              mu::engraving::System* system,
                              const mu::engraving::PointF& pagePoint,
                              const double padding)
{
    if (!score || !system || score->nstaves() == 0) {
        return std::numeric_limits<double>::max();
    }

    double top = std::numeric_limits<double>::max();
    double bottom = std::numeric_limits<double>::lowest();
    for (mu::engraving::staff_idx_t staffIdx = 0; staffIdx < score->nstaves(); ++staffIdx) {
        const mu::engraving::Staff* staff = score->staff(staffIdx);
        mu::engraving::SysStaff* sysStaff = system->staff(staffIdx);
        if (!staff || !sysStaff || !staff->show() || !sysStaff->show()) {
            continue;
        }

        const double staffY = system->staffYpage(staffIdx);
        top = std::min(top, staffY - padding);
        bottom = std::max(bottom, staffY + staff->staffHeight(system->tick()) + padding);
    }

    if (top > bottom) {
        return std::numeric_limits<double>::max();
    }

    return distanceToRange(pagePoint.y(), top, bottom);
}

// With clampToNearest, points in margins or gaps resolve to the nearest measure instead of nothing.
MeasureHit measureAtPoint(mu::engraving::Page* page,
                          const mu::engraving::PointF& point,
                          const bool clampToNearest = false)
{
    if (!page) {
        return {};
    }

    mu::engraving::Score* score = page->score();
    const double spatium = page->spatium();
    const double systemPadding = std::max(spatium * 4.0, 28.0);
    mu::engraving::System* bestSystem = nullptr;
    double bestSystemDistance = std::numeric_limits<double>::max();
    for (mu::engraving::System* system : page->systems()) {
        const double systemDistance = systemVerticalDistance(score, system, point, systemPadding);
        if (systemDistance < bestSystemDistance) {
            bestSystemDistance = systemDistance;
            bestSystem = system;
        }
    }

    if (!bestSystem || (!clampToNearest && bestSystemDistance > std::max(spatium * 8.0, 64.0))) {
        return {};
    }

    mu::engraving::Measure* bestMeasure = nullptr;
    mu::engraving::staff_idx_t bestStaff = 0;
    double bestDistance = std::numeric_limits<double>::max();
    double bestCenterDistance = std::numeric_limits<double>::max();

    for (mu::engraving::MeasureBase* measureBase : bestSystem->measures()) {
            if (!measureBase || !measureBase->isMeasure()) {
                continue;
            }

            mu::engraving::Measure* measure = mu::engraving::toMeasure(measureBase);
            if (!measure) {
                continue;
            }

            const mu::engraving::RectF rect = measure->pageBoundingRect();
            if (rect.width() <= 0.0 || rect.height() <= 0.0) {
                continue;
            }

            const double distance = distanceToRect(rect, point);
            const double centerDistance = std::abs(rect.center().x() - point.x());
            if (distance < bestDistance - 0.001
                || (std::abs(distance - bestDistance) <= 0.001 && centerDistance < bestCenterDistance)) {
                bestDistance = distance;
                bestCenterDistance = centerDistance;
                bestMeasure = measure;
                bestStaff = nearestVisibleStaff(score, bestSystem, point);
            }
    }

    if (bestMeasure && (clampToNearest || bestDistance <= std::max(spatium * 6.0, 48.0))) {
        return { bestMeasure, bestStaff };
    }

    return {};
}

bool selectedMeasureRange(const mu::engraving::Score* score,
                          mu::engraving::Measure** startMeasure,
                          mu::engraving::Measure** endMeasure)
{
    if (!score || !score->selection().isRange()) {
        return false;
    }

    mu::engraving::Measure* rangeStart = nullptr;
    mu::engraving::Measure* rangeEnd = nullptr;
    if (!score->selection().measureRange(&rangeStart, &rangeEnd) || !rangeStart || !rangeEnd) {
        return false;
    }

    if (rangeStart->isMMRest()) {
        rangeStart = rangeStart->mmRestFirst();
    }
    if (rangeEnd->isMMRest()) {
        rangeEnd = rangeEnd->mmRestLast();
    }

    if (startMeasure) {
        *startMeasure = rangeStart;
    }
    if (endMeasure) {
        *endMeasure = rangeEnd;
    }
    return true;
}

bool selectedSingleOrMMRestMeasureRange(const mu::engraving::Score* score,
                                        mu::engraving::Measure** startMeasure,
                                        mu::engraving::Measure** endMeasure,
                                        mu::engraving::staff_idx_t* staffStart,
                                        mu::engraving::staff_idx_t* staffEnd)
{
    if (!score || score->nstaves() == 0) {
        return false;
    }

    mu::engraving::Measure* rawStartMeasure = nullptr;
    mu::engraving::Measure* rawEndMeasure = nullptr;
    if (!score->selection().measureRange(&rawStartMeasure, &rawEndMeasure) || !rawStartMeasure || !rawEndMeasure) {
        return false;
    }

    mu::engraving::Measure* expandedStartMeasure = nullptr;
    mu::engraving::Measure* expandedEndMeasure = nullptr;
    if (!selectedMeasureRange(score, &expandedStartMeasure, &expandedEndMeasure) || !expandedStartMeasure || !expandedEndMeasure) {
        return false;
    }

    const bool selectedMMRest = rawStartMeasure->isMMRest() || rawEndMeasure->isMMRest();
    if (expandedStartMeasure != expandedEndMeasure && !selectedMMRest) {
        return false;
    }

    if (startMeasure) {
        *startMeasure = expandedStartMeasure;
    }
    if (endMeasure) {
        *endMeasure = expandedEndMeasure;
    }
    if (staffStart) {
        *staffStart = std::min(score->selection().staffStart(), score->nstaves() - 1);
    }
    if (staffEnd) {
        *staffEnd = std::clamp(score->selection().staffEnd(), score->selection().staffStart() + 1, score->nstaves());
    }
    return true;
}

bool chordRestCountsAsVoiceOneContent(const mu::engraving::ChordRest* chordRest)
{
    if (!chordRest) {
        return false;
    }

    if (chordRest->isChord()) {
        return true;
    }

    return chordRest->isRest()
        && chordRest->durationType().type() != mu::engraving::DurationType::V_MEASURE;
}

bool selectedMeasureRangeHasVoiceOneContent(const mu::engraving::Score* score,
                                            mu::engraving::Measure* startMeasure,
                                            mu::engraving::Measure* endMeasure)
{
    if (!score || !startMeasure || !endMeasure || score->nstaves() == 0) {
        return false;
    }

    const mu::engraving::staff_idx_t staffStart = std::min(score->selection().staffStart(), score->nstaves() - 1);
    const mu::engraving::staff_idx_t staffEnd = std::clamp(score->selection().staffEnd(), staffStart + 1, score->nstaves());
    for (mu::engraving::Measure* measure = startMeasure; measure; measure = measure->nextMeasure()) {
        for (mu::engraving::Segment* segment = measure->first(mu::engraving::SegmentType::ChordRest);
             segment && segment->measure() == measure;
             segment = segment->next1(mu::engraving::SegmentType::ChordRest)) {
            for (mu::engraving::staff_idx_t staffIndex = staffStart; staffIndex < staffEnd; ++staffIndex) {
                const mu::engraving::track_idx_t voiceOneTrack = staffIndex * mu::engraving::VOICES;
                const mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(segment->element(voiceOneTrack));
                if (chordRestCountsAsVoiceOneContent(chordRest)) {
                    return true;
                }
            }
        }

        if (measure == endMeasure) {
            break;
        }
    }

    return false;
}

mu::engraving::ChordRest* firstStandardChordRestInMeasure(const mu::engraving::Score* score,
                                                          mu::engraving::Measure* measure,
                                                          const mu::engraving::staff_idx_t preferredStaff = muse::nidx)
{
    if (!score || !measure) {
        return nullptr;
    }

    if (measure->isMMRest()) {
        measure = measure->mmRestFirst();
        if (!measure) {
            return nullptr;
        }
    }

    for (mu::engraving::Segment* segment = measure->first(mu::engraving::SegmentType::ChordRest);
         segment && segment->measure() == measure;
         segment = segment->next1(mu::engraving::SegmentType::ChordRest)) {
        const mu::engraving::staff_idx_t firstStaff = preferredStaff == muse::nidx ? 0 : std::min(preferredStaff, score->nstaves() - 1);
        const mu::engraving::staff_idx_t staffLimit = preferredStaff == muse::nidx ? score->nstaves() : firstStaff + 1;
        for (mu::engraving::staff_idx_t staffIndex = firstStaff; staffIndex < staffLimit; ++staffIndex) {
            const mu::engraving::Staff* staff = score->staff(staffIndex);
            if (!isStandardStaff(staff, measure->tick())) {
                continue;
            }

            const mu::engraving::track_idx_t primaryTrack = staffIndex * mu::engraving::VOICES;
            if (mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(segment->element(primaryTrack))) {
                return chordRest;
            }

            for (mu::engraving::track_idx_t voice = 1; voice < mu::engraving::VOICES; ++voice) {
                const mu::engraving::track_idx_t track = primaryTrack + voice;
                if (mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(segment->element(track))) {
                    return chordRest;
                }
            }
        }
    }

    return nullptr;
}

mu::engraving::ChordRest* firstChordRestAtSegment(const mu::engraving::Score* score,
                                                 mu::engraving::Segment* segment,
                                                 const mu::engraving::staff_idx_t preferredStaff)
{
    if (!score || !segment || score->nstaves() == 0) {
        return nullptr;
    }

    const mu::engraving::staff_idx_t staffIdx = std::min(preferredStaff, score->nstaves() - 1);
    const mu::engraving::track_idx_t primaryTrack = staffIdx * mu::engraving::VOICES;
    if (mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(segment->element(primaryTrack))) {
        return chordRest;
    }

    for (mu::engraving::track_idx_t voice = 1; voice < mu::engraving::VOICES; ++voice) {
        const mu::engraving::track_idx_t track = primaryTrack + voice;
        if (mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(segment->element(track))) {
            return chordRest;
        }
    }

    return nullptr;
}

mu::engraving::Segment* chordRestSegmentAtPoint(mu::engraving::Measure* measure,
                                                const mu::engraving::PointF& pagePoint,
                                                const mu::engraving::staff_idx_t staffIdx)
{
    if (!measure) {
        return nullptr;
    }

    const mu::engraving::track_idx_t startTrack = staffIdx * mu::engraving::VOICES;
    const mu::engraving::track_idx_t endTrack = startTrack + mu::engraving::VOICES;
    const double measureX = pagePoint.x() - measure->pageBoundingRect().left();
    return measure->searchSegment(
        measureX,
        mu::engraving::SegmentType::ChordRest,
        startTrack,
        endTrack
    );
}

bool selectMeasureRange(mu::engraving::Score* score,
                        mu::engraving::Segment* startSegment,
                        mu::engraving::Segment* endSegment,
                        const mu::engraving::staff_idx_t staffStartIdx = 0,
                        const mu::engraving::staff_idx_t staffEndIdx = 1)
{
    if (!score || !startSegment || !endSegment || score->nstaves() == 0) {
        return false;
    }

    if (startSegment->tick() > endSegment->tick()) {
        std::swap(startSegment, endSegment);
    }
    // Selection ranges stop before their end segment, so step past the segment the drag ended on.
    if (mu::engraving::Segment* nextSegment = endSegment->next(mu::engraving::SegmentType::ChordRest)) {
        endSegment = nextSegment;
    } else if (mu::engraving::Measure* measure = endSegment->measure()) {
        endSegment = measure->last();
    }

    score->deselectAll();
    const mu::engraving::staff_idx_t staffStart = std::min(staffStartIdx, score->nstaves() - 1);
    const mu::engraving::staff_idx_t staffEnd = std::clamp(
        staffEndIdx,
        staffStart + 1,
        score->nstaves()
    );
    score->selection().setRange(startSegment, endSegment, staffStart, staffEnd);
    score->selection().updateSelectedElements();
    score->selection().setActiveTrack(staffStart * mu::engraving::VOICES);
    if (mu::engraving::ChordRest* chordRest = firstChordRestAtSegment(score, startSegment, staffStart)) {
        score->inputState().setTrack(chordRest->track());
        score->inputState().moveInputPos(chordRest);
    } else if (mu::engraving::ChordRest* chordRest = firstStandardChordRestInMeasure(score, startSegment->measure(), staffStart)) {
        score->inputState().setTrack(chordRest->track());
        score->inputState().moveInputPos(chordRest);
    }
    score->setUpdateAll();
    return true;
}

void selectMeasureRange(mu::engraving::Score* score,
                        mu::engraving::Measure* firstMeasure,
                        mu::engraving::Measure* lastMeasure,
                        const mu::engraving::staff_idx_t staffStartIdx = 0,
                        const mu::engraving::staff_idx_t staffEndIdx = 1)
{
    if (!score || !firstMeasure || !lastMeasure) {
        return;
    }

    if (firstMeasure->tick() > lastMeasure->tick()) {
        std::swap(firstMeasure, lastMeasure);
    }

    mu::engraving::Segment* startSegment = firstMeasure->first(mu::engraving::SegmentType::ChordRest);
    mu::engraving::Segment* endSegment = lastMeasure->last();
    if (!startSegment || !endSegment) {
        return;
    }

    score->deselectAll();
    const mu::engraving::staff_idx_t staffStart = std::min(staffStartIdx, score->nstaves() - 1);
    const mu::engraving::staff_idx_t staffEnd = std::clamp(
        staffEndIdx,
        staffStart + 1,
        score->nstaves()
    );
    score->selection().setRange(startSegment, endSegment, staffStart, staffEnd);
    score->selection().updateSelectedElements();
    score->selection().setActiveTrack(staffStart * mu::engraving::VOICES);
    if (mu::engraving::ChordRest* chordRest = firstStandardChordRestInMeasure(score, firstMeasure, staffStart)) {
        score->inputState().setTrack(chordRest->track());
        score->inputState().moveInputPos(chordRest);
    }
    score->setUpdateAll();
}

std::string fractionLabel(const mu::engraving::Fraction& value)
{
    return std::to_string(value.ticks()) + " ticks";
}

std::string corruptionScoreLabel(const mu::engraving::Score* score)
{
    if (!score || score->isMaster()) {
        return "Full score";
    }

    const std::string name = score->name().toStdString();
    return name.empty() ? "Part score" : "Part score: " + name;
}

void logCorruptionReportIssues(const char* prefix,
                               const msr::render::ScoreCorruptionReport& report,
                               const size_t limit = 8)
{
    std::cout << prefix << " issueCount=" << report.issues.size() << std::endl;
    const size_t issueLimit = std::min(limit, report.issues.size());
    for (size_t index = 0; index < issueLimit; ++index) {
        const msr::render::ScoreCorruptionIssue& issue = report.issues.at(index);
        std::cout << prefix
                  << " issue[" << index << "]"
                  << " scoreIndex=" << issue.scoreIndex
                  << " fullScore=" << (issue.fullScore ? "true" : "false")
                  << " measure=" << issue.measureNumber
                  << " staff=" << issue.staffIndex
                  << " voice=" << issue.voice
                  << " kind=\"" << issue.kind << "\""
                  << " message=\"" << issue.message << "\""
                  << std::endl;
    }
    if (report.issues.size() > issueLimit) {
        std::cout << prefix
                  << " omittedIssues=" << (report.issues.size() - issueLimit)
                  << std::endl;
    }
}

mu::engraving::Measure* measureByVisibleNumber(mu::engraving::Score* score, const int measureNumber)
{
    if (!score || measureNumber <= 0) {
        return nullptr;
    }

    int currentNumber = 1;
    for (mu::engraving::Measure* measure = score->firstMeasure(); measure; measure = measure->nextMeasure()) {
        if (currentNumber == measureNumber) {
            return measure;
        }
        ++currentNumber;
    }

    return nullptr;
}

void appendCorruptionIssue(msr::render::ScoreCorruptionReport& report,
                           const mu::engraving::Score* score,
                           const int scoreIndex,
                           const int measureNumber,
                           const int staffIndex,
                           const int voice,
                           const std::string& kind,
                           const std::string& message)
{
    msr::render::ScoreCorruptionIssue issue;
    issue.scoreIndex = scoreIndex;
    issue.fullScore = !score || score->isMaster();
    issue.measureNumber = measureNumber;
    issue.staffIndex = staffIndex;
    issue.voice = voice;
    issue.repairable = issue.fullScore;
    issue.kind = kind;
    issue.message = message;
    report.issues.push_back(issue);
    if (!report.details.empty()) {
        report.details += "\n";
    }
    report.details += message;
}

msr::render::ScoreCorruptionReport scanScoreCorruptions(mu::engraving::MasterScore* masterScore)
{
    msr::render::ScoreCorruptionReport report;
    if (!masterScore) {
        return report;
    }

    int scoreIndex = 0;
    for (mu::engraving::Score* score : masterScore->scoreList()) {
        if (!score) {
            ++scoreIndex;
            continue;
        }

        score->setHasCorruptedMeasures(false);
        const std::string scoreLabel = corruptionScoreLabel(score);
        int measureNumber = 1;

        for (mu::engraving::Measure* measure = score->firstMeasure(); measure; measure = measure->nextMeasure(), ++measureNumber) {
            const mu::engraving::Fraction measureLength = measure->ticks();
            const size_t staffCount = score->staves().size();

            for (size_t staffIndex = 0; staffIndex < staffCount; ++staffIndex) {
                mu::engraving::Rest* fullMeasureRest = nullptr;
                mu::engraving::Fraction voices[mu::engraving::VOICES];

                measure->setCorrupted(staffIndex, false);

                for (mu::engraving::Segment* segment = measure->first(mu::engraving::SegmentType::ChordRest);
                     segment;
                     segment = segment->next(mu::engraving::SegmentType::ChordRest)) {
                    for (mu::engraving::voice_idx_t voice = 0; voice < mu::engraving::VOICES; ++voice) {
                        mu::engraving::EngravingItem* element = segment->element(static_cast<int>(staffIndex * mu::engraving::VOICES + voice));
                        if (!element) {
                            continue;
                        }

                        mu::engraving::ChordRest* chordRest = mu::engraving::toChordRest(element);
                        if (!chordRest) {
                            continue;
                        }

                        voices[voice] += chordRest->actualTicks();
                        if (voice == 0 && chordRest->isRest()) {
                            mu::engraving::Rest* rest = mu::engraving::toRest(chordRest);
                            if (rest && rest->durationType().isMeasure()) {
                                fullMeasureRest = rest;
                            }
                        }
                    }
                }

                const bool repeatsValid = !measure->isMeasureRepeatGroup(staffIndex) || measure->measureRepeatElement(staffIndex) != nullptr;
                if (!repeatsValid) {
                    const std::string message = "Corrupted measure: " + scoreLabel
                        + ", measure " + std::to_string(measureNumber)
                        + ", staff " + std::to_string(staffIndex + 1) + ".";
                    appendCorruptionIssue(report, score, scoreIndex, measureNumber, static_cast<int>(staffIndex), 0, "Corrupted measure", message);
                    measure->setCorrupted(staffIndex, true);
                    score->setHasCorruptedMeasures(true);
                }

                if (voices[0] != measureLength) {
                    const std::string message = "Incomplete measure: " + scoreLabel
                        + ", measure " + std::to_string(measureNumber)
                        + ", staff " + std::to_string(staffIndex + 1)
                        + ". Found: " + fractionLabel(voices[0])
                        + ". Expected: " + fractionLabel(measureLength) + ".";
                    appendCorruptionIssue(report, score, scoreIndex, measureNumber, static_cast<int>(staffIndex), 1, "Incomplete measure", message);
                    measure->setCorrupted(staffIndex, true);
                    score->setHasCorruptedMeasures(true);
                    if (fullMeasureRest) {
                        fullMeasureRest->setTicks(measureLength);
                    }
                }

                for (mu::engraving::voice_idx_t voice = 1; voice < mu::engraving::VOICES; ++voice) {
                    if (voices[voice] > measureLength) {
                        const std::string message = "Voice too long: " + scoreLabel
                            + ", measure " + std::to_string(measureNumber)
                            + ", staff " + std::to_string(staffIndex + 1)
                            + ", voice " + std::to_string(voice + 1)
                            + ". Found: " + fractionLabel(voices[voice])
                            + ". Expected: " + fractionLabel(measureLength) + ".";
                        appendCorruptionIssue(report, score, scoreIndex, measureNumber, static_cast<int>(staffIndex), static_cast<int>(voice + 1), "Voice too long", message);
                        measure->setCorrupted(staffIndex, true);
                        score->setHasCorruptedMeasures(true);
                    }
                }
            }
        }

        ++scoreIndex;
    }

    report.corrupted = !report.issues.empty();
    return report;
}

bool blockDelayedSubsystemIfCorrupted(mu::engraving::MasterScore* masterScore,
                                      const char* subsystem,
                                      std::string& errorMessage)
{
    msr::render::ScoreCorruptionReport report = scanScoreCorruptions(masterScore);
    if (!report.corrupted) {
        return false;
    }

    std::cout << "Aria corruption guard: block subsystem=\"" << subsystem << "\""
              << " remainingIssues=" << report.issues.size()
              << std::endl;
    logCorruptionReportIssues("Aria corruption guard", report);
    errorMessage = std::string("Repair all detected score corruption before ") + subsystem + ".";
    return true;
}

void resetBrokenMeasureRepeatGroup(mu::engraving::Score* score,
                                   mu::engraving::Measure* measure,
                                   const mu::engraving::staff_idx_t staffIndex)
{
    if (!score || !measure || staffIndex >= score->nstaves() || !measure->isMeasureRepeatGroup(staffIndex)) {
        return;
    }

    std::cout << "Aria corruption repair: reset measure repeat group begin"
              << " tick=" << measure->tick().ticks()
              << " staff=" << staffIndex
              << " count=" << measure->measureRepeatCount(staffIndex)
              << std::endl;

    if (mu::engraving::MeasureRepeat* measureRepeat = measure->measureRepeatElement(staffIndex)) {
        if (mu::engraving::Segment* segment = measureRepeat->segment()) {
            std::cout << "Aria corruption repair: detach measure repeat element"
                      << " tick=" << segment->tick().ticks()
                      << " track=" << measureRepeat->track()
                      << std::endl;
            segment->removeElement(measureRepeat->track());
            segment->setElement(measureRepeat->track(), nullptr);
        }
        measureRepeat->setParent(nullptr);
        measureRepeat->setSelected(false);
    }

    mu::engraving::Measure* firstMeasure = measure->firstOfMeasureRepeatGroup(staffIndex);
    if (!firstMeasure) {
        firstMeasure = measure;
    }

    int expectedCount = firstMeasure->measureRepeatCount(staffIndex);
    for (mu::engraving::Measure* current = firstMeasure; current && current->isMeasureRepeatGroup(staffIndex); current = current->nextMeasure()) {
        const int currentCount = current->measureRepeatCount(staffIndex);
        if (current != firstMeasure && currentCount != expectedCount + 1) {
            break;
        }

        mu::engraving::Measure* nextMeasure = current->nextMeasure();
        current->setMeasureRepeatCount(0, staffIndex);
        current->setNoBreak(false);
        expectedCount = currentCount;
        if (!nextMeasure || nextMeasure->measureRepeatCount(staffIndex) != currentCount + 1) {
            break;
        }
    }

    std::cout << "Aria corruption repair: reset measure repeat group end" << std::endl;
}

bool trackInRange(const mu::engraving::track_idx_t track,
                  const mu::engraving::track_idx_t startTrack,
                  const mu::engraving::track_idx_t endTrack)
{
    return track != muse::nidx && track >= startTrack && track < endTrack;
}

bool itemTrackInRange(const mu::engraving::EngravingItem* item,
                      const mu::engraving::track_idx_t startTrack,
                      const mu::engraving::track_idx_t endTrack)
{
    return item && trackInRange(item->track(), startTrack, endTrack);
}

void detachScoreSpannerRaw(mu::engraving::Score* score,
                           mu::engraving::Spanner* spanner,
                           std::unordered_set<mu::engraving::Spanner*>& detachedSpanners,
                           const char* reason)
{
    if (!score || !spanner || !detachedSpanners.insert(spanner).second) {
        return;
    }

    mu::engraving::EngravingItem* startElement = spanner->startElement();
    mu::engraving::EngravingItem* endElement = spanner->endElement();
    std::cout << "Aria corruption repair: detach spanner"
              << " score=\"" << corruptionScoreLabel(score) << "\""
              << " type=" << spanner->typeName()
              << " tick=" << spanner->tick().ticks()
              << " tick2=" << spanner->tick2().ticks()
              << " track=" << spanner->track()
              << " track2=" << spanner->effectiveTrack2()
              << " startType=" << (startElement ? startElement->typeName() : "null")
              << " endType=" << (endElement ? endElement->typeName() : "null")
              << " reason=" << reason
              << std::endl;

    if (startElement && startElement->isNote()) {
        mu::engraving::toNote(startElement)->removeSpannerFor(spanner);
    }
    if (endElement && endElement->isNote()) {
        mu::engraving::toNote(endElement)->removeSpannerBack(spanner);
    }
    score->removeSpanner(spanner);
    spanner->setStartElement(nullptr);
    spanner->setEndElement(nullptr);
    spanner->setParent(nullptr);
    spanner->setSelected(false);
}

void detachTieRaw(mu::engraving::Tie* tie,
                  std::unordered_set<mu::engraving::Tie*>& detachedTies)
{
    if (!tie || !detachedTies.insert(tie).second) {
        return;
    }

    mu::engraving::Note* startNote = tie->startNote();
    mu::engraving::Note* endNote = tie->endNote();
    std::cout << "Aria corruption repair: detach tie"
              << " type=" << tie->typeName()
              << " tick=" << tie->tick().ticks()
              << " track=" << tie->track()
              << " start=" << startNote
              << " end=" << endNote
              << std::endl;

    if (startNote) {
        startNote->setTieFor(nullptr);
    }
    if (endNote) {
        endNote->setTieBack(nullptr);
    }
    tie->setStartNote(nullptr);
    tie->setEndNote(nullptr);
    tie->setParent(nullptr);
    tie->setSelected(false);
}

void detachChordRestAnchorsRaw(mu::engraving::Score* score,
                               mu::engraving::ChordRest* chordRest,
                               std::unordered_set<mu::engraving::Spanner*>& detachedSpanners,
                               std::unordered_set<mu::engraving::Tie*>& detachedTies)
{
    if (!score || !chordRest || !chordRest->isChord()) {
        return;
    }

    mu::engraving::Chord* chord = mu::engraving::toChord(chordRest);
    std::vector<mu::engraving::Spanner*> chordSpanners;
    chordSpanners.insert(chordSpanners.end(), chord->startingSpanners().begin(), chord->startingSpanners().end());
    chordSpanners.insert(chordSpanners.end(), chord->endingSpanners().begin(), chord->endingSpanners().end());
    for (mu::engraving::Spanner* spanner : chordSpanners) {
        detachScoreSpannerRaw(score, spanner, detachedSpanners, "chord-anchor");
    }

    for (mu::engraving::Note* note : chord->notes()) {
        detachTieRaw(note->tieFor(), detachedTies);
        detachTieRaw(note->tieBack(), detachedTies);

        std::vector<mu::engraving::Spanner*> noteSpanners;
        noteSpanners.insert(noteSpanners.end(), note->spannerFor().begin(), note->spannerFor().end());
        noteSpanners.insert(noteSpanners.end(), note->spannerBack().begin(), note->spannerBack().end());
        for (mu::engraving::Spanner* spanner : noteSpanners) {
            detachScoreSpannerRaw(score, spanner, detachedSpanners, "note-anchor");
        }
    }
}

int detachOverlappingSpannersRaw(mu::engraving::Score* score,
                                 mu::engraving::Measure* measure,
                                 const mu::engraving::track_idx_t startTrack,
                                 const mu::engraving::track_idx_t endTrack,
                                 std::unordered_set<mu::engraving::Spanner*>& detachedSpanners)
{
    if (!score || !measure) {
        return 0;
    }

    std::vector<mu::engraving::Spanner*> spannersToDetach;
    const auto& spanners = score->spannerMap().findOverlapping(measure->tick().ticks(), measure->endTick().ticks());
    for (auto interval : spanners) {
        mu::engraving::Spanner* spanner = interval.value;
        if (!spanner || spanner->systemFlag() || spanner->isVolta()) {
            continue;
        }
        const bool trackMatches = trackInRange(spanner->track(), startTrack, endTrack)
            || trackInRange(spanner->effectiveTrack2(), startTrack, endTrack)
            || itemTrackInRange(spanner->startElement(), startTrack, endTrack)
            || itemTrackInRange(spanner->endElement(), startTrack, endTrack);
        if (trackMatches) {
            spannersToDetach.push_back(spanner);
        }
    }

    for (mu::engraving::Spanner* spanner : spannersToDetach) {
        detachScoreSpannerRaw(score, spanner, detachedSpanners, "measure-overlap");
    }

    return static_cast<int>(spannersToDetach.size());
}

int detachAnnotationsRaw(mu::engraving::Measure* measure,
                         const mu::engraving::track_idx_t startTrack,
                         const mu::engraving::track_idx_t endTrack)
{
    if (!measure) {
        return 0;
    }

    int detachedCount = 0;
    for (mu::engraving::Segment* segment = measure->first();
         segment && segment->measure() == measure;
         segment = segment->next1()) {
        std::vector<mu::engraving::EngravingItem*> annotations = segment->annotations();
        for (mu::engraving::EngravingItem* annotation : annotations) {
            if (!annotation || annotation->systemFlag() || !trackInRange(annotation->track(), startTrack, endTrack)) {
                continue;
            }

            std::cout << "Aria corruption repair: detach annotation"
                      << " tick=" << segment->tick().ticks()
                      << " track=" << annotation->track()
                      << " type=" << annotation->typeName()
                      << std::endl;
            segment->remove(annotation);
            annotation->setParent(nullptr);
            annotation->setSelected(false);
            ++detachedCount;
        }
    }
    return detachedCount;
}

void prepareScoreForRawRepair(mu::engraving::Score* score)
{
    if (!score) {
        return;
    }

    mu::engraving::InputState& inputState = score->inputState();
    std::cout << "Aria corruption repair: reset transient edit state"
              << " score=\"" << corruptionScoreLabel(score) << "\""
              << " selectionNone=" << (score->selection().isNone() ? "true" : "false")
              << " noteEntry=" << (inputState.noteEntryMode() ? "true" : "false")
              << " inputTrack=" << inputState.track()
              << std::endl;
    score->deselectAll();
    inputState.setNoteEntryMode(false);
    inputState.setRest(false);
    inputState.setSlur(nullptr);
    inputState.setSegment(nullptr);
    inputState.setLastSegment(nullptr);
    if (score->ntracks() > 0) {
        inputState.setTrack(0);
    }
}

struct LinkedRepairTarget
{
    mu::engraving::Score* score = nullptr;
    mu::engraving::Measure* measure = nullptr;
    mu::engraving::staff_idx_t staffIndex = muse::nidx;
};

bool hasRepairTarget(const std::vector<LinkedRepairTarget>& targets,
                     const mu::engraving::Score* score,
                     const mu::engraving::staff_idx_t staffIndex)
{
    return std::any_of(targets.begin(), targets.end(), [score, staffIndex](const LinkedRepairTarget& target) {
        return target.score == score && target.staffIndex == staffIndex;
    });
}

std::vector<LinkedRepairTarget> linkedRepairTargets(mu::engraving::Score* rootScore,
                                                    mu::engraving::Measure* rootMeasure,
                                                    const mu::engraving::staff_idx_t rootStaffIndex)
{
    std::vector<LinkedRepairTarget> targets;
    if (!rootScore || !rootMeasure || rootStaffIndex >= rootScore->nstaves()) {
        return targets;
    }

    mu::engraving::Staff* rootStaff = rootScore->staff(rootStaffIndex);
    if (!rootStaff) {
        return targets;
    }

    const mu::engraving::Fraction rootTick = rootMeasure->tick();
    for (mu::engraving::Staff* linkedStaff : rootStaff->staffList()) {
        if (!linkedStaff) {
            continue;
        }

        mu::engraving::Score* linkedScore = linkedStaff->score();
        if (!linkedScore) {
            continue;
        }

        const mu::engraving::staff_idx_t linkedStaffIndex = linkedStaff->idx();
        if (linkedStaffIndex >= linkedScore->nstaves() || hasRepairTarget(targets, linkedScore, linkedStaffIndex)) {
            continue;
        }

        mu::engraving::Measure* linkedMeasure = linkedScore->tick2measure(rootTick);
        if (linkedMeasure && linkedMeasure->isMMRest()) {
            linkedMeasure = linkedMeasure->mmRestFirst();
        }
        if (!linkedMeasure) {
            std::cout << "Aria corruption repair: linked target missing measure"
                      << " rootTick=" << rootTick.ticks()
                      << " score=\"" << corruptionScoreLabel(linkedScore) << "\""
                      << " staff=" << linkedStaffIndex
                      << std::endl;
            continue;
        }

        targets.push_back({ linkedScore, linkedMeasure, linkedStaffIndex });
    }

    if (targets.empty()) {
        targets.push_back({ rootScore, rootMeasure, rootStaffIndex });
    }

    return targets;
}

void detachTrackElement(mu::engraving::Score* score,
                        mu::engraving::Segment* segment,
                        const mu::engraving::track_idx_t track,
                        std::unordered_set<mu::engraving::Spanner*>& detachedSpanners,
                        std::unordered_set<mu::engraving::Tie*>& detachedTies)
{
    if (!segment) {
        return;
    }

    mu::engraving::EngravingItem* element = segment->element(track);
    if (!element) {
        return;
    }

    if (element->isChordRest()) {
        detachChordRestAnchorsRaw(score, mu::engraving::toChordRest(element), detachedSpanners, detachedTies);
    }
    segment->removeElement(track);
    segment->setElement(track, nullptr);
    element->setParent(nullptr);
    element->setSelected(false);
}

bool addFullMeasureRestRaw(mu::engraving::Score* score,
                           mu::engraving::Measure* measure,
                           const mu::engraving::staff_idx_t staffIndex)
{
    if (!score || !measure || staffIndex >= score->nstaves()) {
        return false;
    }

    mu::engraving::Segment* segment = measure->getSegment(mu::engraving::SegmentType::ChordRest, measure->tick());
    if (!segment) {
        return false;
    }

    const mu::engraving::track_idx_t primaryTrack = staffIndex * mu::engraving::VOICES;
    mu::engraving::Rest* rest = mu::engraving::Factory::createRest(score->dummy()->segment(), mu::engraving::TDuration(mu::engraving::DurationType::V_MEASURE));
    rest->setTicks(measure->stretchedLen(score->staff(staffIndex)));
    rest->setTrack(primaryTrack);
    rest->setTuplet(nullptr);
    rest->setGenerated(false);
    segment->add(rest);
    std::cout << "Aria corruption repair: add replacement rest"
              << " tick=" << segment->tick().ticks()
              << " track=" << primaryTrack
              << " ticks=" << rest->ticks().ticks()
              << std::endl;
    return true;
}

bool clearMeasureStaffToRest(mu::engraving::Score* score,
                             mu::engraving::Measure* measure,
                             const mu::engraving::staff_idx_t staffIndex)
{
    if (!score || !measure || staffIndex >= score->nstaves()) {
        return false;
    }

    prepareScoreForRawRepair(score);
    resetBrokenMeasureRepeatGroup(score, measure, staffIndex);

    const mu::engraving::track_idx_t startTrack = staffIndex * mu::engraving::VOICES;
    const mu::engraving::track_idx_t endTrack = startTrack + mu::engraving::VOICES;
    std::unordered_set<mu::engraving::Spanner*> detachedSpanners;
    std::unordered_set<mu::engraving::Tie*> detachedTies;
    int detachedElementCount = 0;

    std::cout << "Aria corruption repair: clear measure staff begin"
              << " score=\"" << corruptionScoreLabel(score) << "\""
              << " tick=" << measure->tick().ticks()
              << " measureTicks=" << measure->ticks().ticks()
              << " staff=" << staffIndex
              << " tracks=" << startTrack << "-" << (endTrack - 1)
              << std::endl;

    const int detachedOverlappingSpannerCount = detachOverlappingSpannersRaw(score, measure, startTrack, endTrack, detachedSpanners);
    const int detachedAnnotationCount = detachAnnotationsRaw(measure, startTrack, endTrack);

    // Corrupt measures can crash normal undo/removal paths because those paths
    // inspect links, beams, tuplets, spanners, and selection state. For repair,
    // detach only the segment track slots and write a clean placeholder rest.
    for (mu::engraving::Segment* segment = measure->first(mu::engraving::SegmentType::ChordRest);
         segment && segment->measure() == measure;
         segment = segment->next1(mu::engraving::SegmentType::ChordRest)) {
        for (mu::engraving::track_idx_t track = startTrack; track < endTrack; ++track) {
            if (segment->element(track)) {
                std::cout << "Aria corruption repair: detach element"
                          << " segmentTick=" << segment->tick().ticks()
                          << " track=" << track
                          << " type=" << segment->element(track)->typeName()
                          << std::endl;
                detachTrackElement(score, segment, track, detachedSpanners, detachedTies);
                ++detachedElementCount;
            }
        }
    }

    std::cout << "Aria corruption repair: detached elements count=" << detachedElementCount
              << " spanners=" << detachedSpanners.size()
              << " overlappingSpanners=" << detachedOverlappingSpannerCount
              << " ties=" << detachedTies.size()
              << " annotations=" << detachedAnnotationCount
              << std::endl;

    if (!addFullMeasureRestRaw(score, measure, staffIndex)) {
        std::cout << "Aria corruption repair: failed to add replacement rest" << std::endl;
        return false;
    }

    measure->setCorrupted(staffIndex, false);
    score->setHasCorruptedMeasures(false);
    score->setPlaylistDirty();
    score->setLayoutAll();
    score->setUpdateAll();

    std::cout << "Aria corruption repair: clear measure staff end" << std::endl;
    return true;
}

bool clearLinkedMeasureStaffsToRest(mu::engraving::Score* score,
                                    mu::engraving::Measure* measure,
                                    const mu::engraving::staff_idx_t staffIndex)
{
    std::vector<LinkedRepairTarget> targets = linkedRepairTargets(score, measure, staffIndex);
    std::cout << "Aria corruption repair: linked repair begin"
              << " rootScore=\"" << corruptionScoreLabel(score) << "\""
              << " tick=" << (measure ? measure->tick().ticks() : -1)
              << " staff=" << staffIndex
              << " targets=" << targets.size()
              << std::endl;

    bool repairedAny = false;
    for (const LinkedRepairTarget& target : targets) {
        if (!target.score || !target.measure || target.staffIndex == muse::nidx) {
            continue;
        }

        std::cout << "Aria corruption repair: linked target"
                  << " score=\"" << corruptionScoreLabel(target.score) << "\""
                  << " tick=" << target.measure->tick().ticks()
                  << " staff=" << target.staffIndex
                  << std::endl;
        if (!clearMeasureStaffToRest(target.score, target.measure, target.staffIndex)) {
            std::cout << "Aria corruption repair: linked target failed"
                      << " score=\"" << corruptionScoreLabel(target.score) << "\""
                      << " tick=" << target.measure->tick().ticks()
                      << " staff=" << target.staffIndex
                      << std::endl;
            return false;
        }
        repairedAny = true;
    }

    std::cout << "Aria corruption repair: linked repair end"
              << " repairedAny=" << (repairedAny ? "true" : "false")
              << std::endl;
    return repairedAny;
}

double chordRestSegmentPageX(const mu::engraving::Segment* segment)
{
    const mu::engraving::Measure* measure = segment ? segment->measure() : nullptr;
    if (!measure) {
        return 0.0;
    }

    return measure->pageBoundingRect().left() + segment->x();
}

double chordRestSegmentStartBoundaryPageX(const mu::engraving::Segment* segment)
{
    const mu::engraving::Measure* measure = segment ? segment->measure() : nullptr;
    if (!measure) {
        return 0.0;
    }

    const mu::engraving::RectF measureRect = measure->pageBoundingRect();
    const mu::engraving::Segment* previousSegment = segment->prev1(mu::engraving::SegmentType::ChordRest);
    if (!previousSegment || previousSegment->measure() != measure) {
        return measureRect.left();
    }

    return std::clamp(
        (chordRestSegmentPageX(previousSegment) + chordRestSegmentPageX(segment)) * 0.5,
        measureRect.left(),
        measureRect.right()
    );
}

double chordRestSegmentSelectionBoundaryPageX(const mu::engraving::Segment* segment)
{
    const mu::engraving::Measure* measure = segment ? segment->measure() : nullptr;
    if (!measure) {
        return 0.0;
    }

    if (segment->tick() == measure->tick()) {
        return measure->pageBoundingRect().left();
    }

    return chordRestSegmentStartBoundaryPageX(segment);
}

mu::engraving::ChordRest* selectedChordRest(const mu::engraving::Score* score)
{
    if (!score) {
        return nullptr;
    }

    mu::engraving::EngravingItem* selectedItem = score->selection().element();
    if (!selectedItem && !score->selection().elements().empty()) {
        selectedItem = score->selection().elements().front();
    }

    if (selectedItem && selectedItem->isHarmony()) {
        mu::engraving::Harmony* harmony = mu::engraving::toHarmony(selectedItem);
        mu::engraving::Segment* parentSegment = harmony ? harmony->getParentSeg() : nullptr;
        if (parentSegment) {
            return mu::engraving::InputState::chordRest(parentSegment->element(harmony->track()));
        }
    }

    return mu::engraving::InputState::chordRest(selectedItem);
}

mu::engraving::ChordRest* selectedMeasureChordRest(const mu::engraving::Score* score)
{
    mu::engraving::Measure* startMeasure = nullptr;
    mu::engraving::Measure* endMeasure = nullptr;
    if (!selectedMeasureRange(score, &startMeasure, &endMeasure)) {
        return nullptr;
    }

    const mu::engraving::staff_idx_t staffIdx = std::min(score->selection().staffStart(), score->nstaves() - 1);
    return firstStandardChordRestInMeasure(score, startMeasure, staffIdx);
}

mu::engraving::ChordRest* selectedOrMeasureChordRest(const mu::engraving::Score* score)
{
    if (mu::engraving::ChordRest* chordRest = selectedChordRest(score)) {
        return chordRest;
    }

    return selectedMeasureChordRest(score);
}

bool selectedRangeChordBounds(const mu::engraving::Score* score,
                              mu::engraving::ChordRest** firstChordRest,
                              mu::engraving::ChordRest** lastChordRest)
{
    if (!score || !score->selection().isRange()) {
        return false;
    }

    const mu::engraving::staff_idx_t staffStart = std::min(score->selection().staffStart(), score->nstaves() - 1);
    const mu::engraving::staff_idx_t staffEnd = std::clamp(
        score->selection().staffEnd(),
        staffStart + 1,
        score->nstaves()
    );
    mu::engraving::ChordRest* first = nullptr;
    mu::engraving::ChordRest* last = nullptr;

    for (mu::engraving::EngravingItem* selectedItem : score->selection().elements()) {
        mu::engraving::ChordRest* chordRest = nullptr;
        if (selectedItem && selectedItem->isNote()) {
            mu::engraving::Note* note = mu::engraving::toNote(selectedItem);
            chordRest = note ? note->chord() : nullptr;
        } else {
            chordRest = mu::engraving::InputState::chordRest(selectedItem);
        }
        if (!chordRest || !chordRest->isChord()) {
            continue;
        }
        if (chordRest->staffIdx() < staffStart || chordRest->staffIdx() >= staffEnd) {
            continue;
        }

        if (!first || chordRest->tick() < first->tick()) {
            first = chordRest;
        }
        if (!last || chordRest->tick() > last->tick()) {
            last = chordRest;
        }
    }

    if (!first) {
        return false;
    }
    if (!last) {
        last = first;
    }
    if (firstChordRest) {
        *firstChordRest = first;
    }
    if (lastChordRest) {
        *lastChordRest = last;
    }
    return true;
}

mu::engraving::ChordRest* chordRestAtPointForExpressionEndpoint(mu::engraving::Score* score,
                                                               mu::engraving::Page* page,
                                                               const mu::engraving::PointF& pagePoint,
                                                               const mu::engraving::staff_idx_t preferredStaff,
                                                               const bool chordOnly)
{
    if (!score || !page) {
        return nullptr;
    }

    // Lines like hairpins sit between systems, so first decide which system the finger is
    // over (by the expression's staff), then pick the note mostly by horizontal position.
    // Searching the whole page by straight-line distance could jump to the next system.
    const mu::engraving::staff_idx_t staffIndex = preferredStaff == muse::nidx ? 0 : std::min(preferredStaff, score->nstaves() - 1);
    const mu::engraving::Staff* staff = score->staff(staffIndex);
    mu::engraving::System* bestSystem = nullptr;
    double bestSystemDistance = std::numeric_limits<double>::max();
    for (mu::engraving::System* system : page->systems()) {
        if (!system || !system->firstMeasure() || !staff) {
            continue;
        }
        const double staffTop = system->staffYpage(staffIndex);
        const double distance = distanceToRange(pagePoint.y(), staffTop, staffTop + staff->staffHeight(system->firstMeasure()->tick()));
        if (distance < bestSystemDistance) {
            bestSystemDistance = distance;
            bestSystem = system;
        }
    }
    if (!bestSystem) {
        return nullptr;
    }

    mu::engraving::ChordRest* best = nullptr;
    double bestDistance = std::numeric_limits<double>::max();
    for (mu::engraving::MeasureBase* measureBase : bestSystem->measures()) {
        if (!measureBase || !measureBase->isMeasure()) {
            continue;
        }
        mu::engraving::Measure* measure = mu::engraving::toMeasure(measureBase);
        for (mu::engraving::Segment* segment = measure->first(mu::engraving::SegmentType::ChordRest);
             segment;
             segment = segment->next(mu::engraving::SegmentType::ChordRest)) {
            for (mu::engraving::track_idx_t voice = 0; voice < mu::engraving::VOICES; ++voice) {
                mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(segment->element(staffIndex * mu::engraving::VOICES + voice));
                if (!chordRest || (chordOnly && !chordRest->isChord())) {
                    continue;
                }
                const mu::engraving::RectF rect = chordRest->pageBoundingRect();
                const double distance = std::hypot(rect.center().x() - pagePoint.x(), (rect.center().y() - pagePoint.y()) * 0.12);
                if (distance < bestDistance) {
                    bestDistance = distance;
                    best = chordRest;
                }
            }
        }
    }
    return best;
}

struct FermataAnchorTarget {
    mu::engraving::ChordRest* chordRest = nullptr;
    mu::engraving::PointF anchor;
};

// Every note or rest in the fermata's voice on its page, with the point a fermata attaches to:
// centred on the note, at the top (or, placed below, the bottom) line of the staff.
std::vector<FermataAnchorTarget> fermataAnchorTargets(const mu::engraving::Score* score, const mu::engraving::Fermata* fermata)
{
    std::vector<FermataAnchorTarget> targets;
    const mu::engraving::Segment* fermataSegment = fermata ? fermata->segment() : nullptr;
    const mu::engraving::System* fermataSystem = fermataSegment ? fermataSegment->system() : nullptr;
    const mu::engraving::Page* page = fermataSystem ? fermataSystem->page() : nullptr;
    if (!score || !page) {
        return targets;
    }

    const mu::engraving::track_idx_t track = fermata->track();
    const mu::engraving::staff_idx_t staffIdx = mu::engraving::track2staff(track);
    const bool below = fermata->placeBelow();
    for (mu::engraving::Measure* measure = score->firstMeasure(); measure; measure = measure->nextMeasure()) {
        mu::engraving::System* system = measure->system();
        if (!system || system->page() != page) {
            continue;
        }
        const mu::engraving::Staff* staff = score->staff(staffIdx);
        const double staffTop = system->staffYpage(staffIdx);
        const double anchorY = below && staff ? staffTop + staff->staffHeight(measure->tick()) : staffTop;
        for (mu::engraving::Segment* segment = measure->first(mu::engraving::SegmentType::ChordRest);
             segment;
             segment = segment->next(mu::engraving::SegmentType::ChordRest)) {
            mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(segment->element(track));
            if (chordRest) {
                targets.push_back({ chordRest, mu::engraving::PointF(chordRest->pageBoundingRect().center().x(), anchorY) });
            }
        }
    }
    return targets;
}

mu::engraving::PointF chordTextAttachmentAnchorForChordRest(mu::engraving::ChordRest* chordRest)
{
    if (!chordRest) {
        return mu::engraving::PointF();
    }

    if (chordRest->isChord()) {
        mu::engraving::Chord* chord = mu::engraving::toChord(chordRest);
        if (chord && chord->upNote()) {
            return chord->upNote()->pageBoundingRect().center();
        }
    }

    return chordRest->pageBoundingRect().center();
}

mu::engraving::ChordRest* chordRestAtPointForChordText(mu::engraving::Score* score,
                                                       mu::engraving::Page* page,
                                                       const mu::engraving::PointF& pagePoint)
{
    if (!score || !page) {
        return nullptr;
    }

    mu::engraving::ChordRest* best = nullptr;
    double bestDistance = std::numeric_limits<double>::max();
    const double horizontalWeight = 1.0;
    const double verticalWeight = 0.12;
    const double maxWeightedDistance = std::max(page->spatium() * 12.0, 80.0);

    for (mu::engraving::Measure* measure = score->firstMeasure(); measure; measure = measure->nextMeasure()) {
        if (!measure || measure->system() == nullptr || measure->system()->page() != page) {
            continue;
        }
        for (mu::engraving::Segment* segment = measure->first(mu::engraving::SegmentType::ChordRest);
             segment && segment->measure() == measure;
             segment = segment->next1(mu::engraving::SegmentType::ChordRest)) {
            for (mu::engraving::track_idx_t track = 0; track < score->nstaves() * mu::engraving::VOICES; ++track) {
                mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(segment->element(track));
                if (!chordRest) {
                    continue;
                }

                const mu::engraving::PointF anchor = chordTextAttachmentAnchorForChordRest(chordRest);
                const double dx = (anchor.x() - pagePoint.x()) * horizontalWeight;
                const double dy = (anchor.y() - pagePoint.y()) * verticalWeight;
                const double distance = std::hypot(dx, dy);
                if (distance < bestDistance) {
                    bestDistance = distance;
                    best = chordRest;
                }
            }
        }
    }

    return bestDistance <= maxWeightedDistance ? best : nullptr;
}

mu::engraving::TDuration noteEntryDurationForChordRest(const mu::engraving::ChordRest* chordRest)
{
    if (!chordRest) {
        return mu::engraving::TDuration(mu::engraving::DurationType::V_QUARTER);
    }

    const mu::engraving::DurationType durationType = chordRest->durationType().type();
    if (durationType == mu::engraving::DurationType::V_MEASURE) {
        return mu::engraving::TDuration(mu::engraving::DurationType::V_QUARTER);
    }

    mu::engraving::TDuration duration = chordRest->durationType();
    if (!duration.isValid()) {
        return mu::engraving::TDuration(mu::engraving::DurationType::V_QUARTER);
    }

    return duration;
}

void normalizePointInputPositionForPutNote(mu::engraving::Staff* staff, mu::engraving::Position& position)
{
    if (!staff || !position.segment) {
        return;
    }

    const mu::engraving::Fraction tick = position.segment->tick();
    const mu::engraving::StaffType* staffType = staff->staffType(tick);
    if (!staffType) {
        return;
    }

    const int stepOffset = staffType->stepOffset();
    const double staffTypeYOffset = staffType->yoffset().val();
    const double lineDistance = staffType->lineDistance().val();
    if (lineDistance == 0.0) {
        return;
    }

    position.line -= stepOffset + 2 * staffTypeYOffset / lineDistance;
}

bool biasDuplicatePointInputAwayFromExistingChord(mu::engraving::Score* score,
                                                  mu::engraving::Page* page,
                                                  mu::engraving::Staff* staff,
                                                  mu::engraving::PointF& pagePoint,
                                                  mu::engraving::Position& position)
{
    if (!score || !staff || !position.segment || score->inputState().rest()) {
        return false;
    }

    const mu::engraving::track_idx_t track = position.staffIdx * mu::engraving::VOICES + score->inputState().voice();
    mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(position.segment->element(track));
    if (!chordRest || !chordRest->isChord() || chordRest->durationType() != score->inputState().duration()) {
        return false;
    }

    bool error = false;
    const mu::engraving::NoteVal noteValue = score->noteValForPosition(position, score->inputState().accidentalType(), error);
    if (error) {
        return false;
    }

    mu::engraving::Chord* chord = mu::engraving::toChord(chordRest);
    mu::engraving::Note* duplicateNote = chord ? chord->findNote(noteValue.pitch) : nullptr;
    if (!duplicateNote) {
        return false;
    }

    const bool intendedAbove = pagePoint.y() < duplicateNote->pageBoundingRect().center().y();
    position.line = duplicateNote->line() + (intendedAbove ? -2 : 2);
    const double duplicateCenterY = duplicateNote->pageBoundingRect().center().y();
    const double thirdOffset = std::max(page ? page->spatium() : 0.0, 8.0);
    pagePoint = mu::engraving::PointF(pagePoint.x(), duplicateCenterY + (intendedAbove ? -thirdOffset : thirdOffset));
    return true;
}

void normalizeNoteEntryDuration(mu::engraving::InputState& inputState)
{
    if (!inputState.duration().isValid() || inputState.duration().isZero()) {
        inputState.setDuration(mu::engraving::TDuration(mu::engraving::DurationType::V_QUARTER));
        return;
    }

    if (inputState.duration().type() == mu::engraving::DurationType::V_MEASURE) {
        inputState.setDuration(mu::engraving::TDuration(mu::engraving::DurationType::V_QUARTER));
    }
}

void configureInputCursorForChordRest(mu::engraving::Score* score,
                                      mu::engraving::ChordRest* chordRest,
                                      const bool useChordRestDuration)
{
    if (!score || !chordRest) {
        return;
    }

    mu::engraving::InputState& inputState = score->inputState();
    inputState.setTrack(chordRest->track());
    inputState.moveInputPos(chordRest);
    if (useChordRestDuration) {
        inputState.setDuration(noteEntryDurationForChordRest(chordRest));
    } else {
        normalizeNoteEntryDuration(inputState);
    }
}

mu::engraving::EngravingItem* currentSelectedItem(const mu::engraving::Score* score)
{
    if (!score) {
        return nullptr;
    }

    mu::engraving::EngravingItem* selectedItem = score->selection().element();
    if (!selectedItem && !score->selection().elements().empty()) {
        selectedItem = score->selection().elements().front();
    }

    if (selectedItem) {
        return selectedItem;
    }

    return selectedChordRest(score);
}

mu::engraving::Spanner* expressionSpannerForItem(mu::engraving::EngravingItem* item)
{
    if (!item) {
        return nullptr;
    }

    auto isSupportedExpressionSpanner = [](const mu::engraving::Spanner* spanner) {
        return spanner
               && (spanner->isSlurTie()
                   || spanner->isTextLineBase());
    };

    if (item->isSpanner()) {
        mu::engraving::Spanner* spanner = mu::engraving::toSpanner(item);
        return isSupportedExpressionSpanner(spanner) ? spanner : nullptr;
    }

    if (item->isSpannerSegment() || item->isSlurTieSegment()) {
        mu::engraving::SpannerSegment* segment = mu::engraving::toSpannerSegment(item);
        mu::engraving::Spanner* spanner = segment ? segment->spanner() : nullptr;
        return isSupportedExpressionSpanner(spanner) ? spanner : nullptr;
    }

    return nullptr;
}

mu::engraving::Spanner* currentSelectedExpressionSpanner(const mu::engraving::Score* score)
{
    if (!score) {
        return nullptr;
    }

    if (mu::engraving::Spanner* spanner = expressionSpannerForItem(score->selection().element())) {
        return spanner;
    }
    for (mu::engraving::EngravingItem* item : score->selection().elements()) {
        if (mu::engraving::Spanner* spanner = expressionSpannerForItem(item)) {
            return spanner;
        }
    }
    return nullptr;
}

mu::engraving::Measure* currentSelectedMeasure(const mu::engraving::Score* score)
{
    mu::engraving::Measure* startMeasure = nullptr;
    mu::engraving::Measure* endMeasure = nullptr;
    if (selectedMeasureRange(score, &startMeasure, &endMeasure)) {
        return startMeasure;
    }

    mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score);
    if (!selectedItem || !selectedItem->isMeasure()) {
        return nullptr;
    }

    mu::engraving::Measure* measure = mu::engraving::toMeasure(selectedItem);
    if (measure && measure->isMMRest()) {
        return measure->mmRestFirst();
    }

    return measure;
}

mu::engraving::Note* currentSelectedNote(const mu::engraving::Score* score)
{
    return editableNoteForItem(currentSelectedItem(score));
}

mu::engraving::ChordRest* activeChordRest(mu::engraving::Score* score)
{
    if (!score) {
        return nullptr;
    }

    if (mu::engraving::ChordRest* chordRest = selectedChordRest(score)) {
        return chordRest;
    }

    if (mu::engraving::ChordRest* chordRest = selectedMeasureChordRest(score)) {
        return chordRest;
    }

    return score->inputState().cr();
}

mu::engraving::staff_idx_t activeStaffIndex(mu::engraving::Score* score)
{
    if (!score || score->nstaves() == 0) {
        return muse::nidx;
    }

    if (score->selection().isRange()) {
        return std::min(score->selection().staffStart(), score->nstaves() - 1);
    }

    if (mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score)) {
        return std::min(selectedItem->staffIdx(), score->nstaves() - 1);
    }

    if (mu::engraving::ChordRest* chordRest = activeChordRest(score)) {
        return std::min(chordRest->staffIdx(), score->nstaves() - 1);
    }

    return muse::nidx;
}

mu::engraving::Measure* activeMeasure(mu::engraving::Score* score, const bool fromStart = false)
{
    if (!score) {
        return nullptr;
    }

    if (fromStart) {
        return score->firstMeasure();
    }

    mu::engraving::Measure* rangeStart = nullptr;
    mu::engraving::Measure* rangeEnd = nullptr;
    if (selectedMeasureRange(score, &rangeStart, &rangeEnd) && rangeStart) {
        return rangeStart;
    }

    if (mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score)) {
        if (mu::engraving::Measure* measure = mu::engraving::toMeasure(selectedItem->findMeasure())) {
            return measure->isMMRest() ? measure->mmRestFirst() : measure;
        }
    }

    if (mu::engraving::ChordRest* chordRest = activeChordRest(score)) {
        mu::engraving::Measure* measure = chordRest->measure();
        return measure && measure->isMMRest() ? measure->mmRestFirst() : measure;
    }

    return score->firstMeasure();
}

mu::engraving::LayoutBreak* layoutBreakElement(mu::engraving::MeasureBase* measureBase,
                                               const mu::engraving::LayoutBreakType breakType)
{
    if (!measureBase) {
        return nullptr;
    }

    for (mu::engraving::EngravingItem* item : measureBase->el()) {
        if (item && item->isLayoutBreak()) {
            mu::engraving::LayoutBreak* layoutBreak = mu::engraving::toLayoutBreak(item);
            if (layoutBreak && layoutBreak->layoutBreakType() == breakType) {
                return layoutBreak;
            }
        }
    }

    return nullptr;
}

mu::engraving::EngravingItem* activeAttachmentItem(mu::engraving::Score* score)
{
    if (!score) {
        return nullptr;
    }

    if (mu::engraving::EngravingItem* selectedItem = score->selection().element()) {
        if (selectedItem->isNote() || selectedItem->isRest() || selectedItem->isChord()) {
            return selectedItem;
        }
    }

    return activeChordRest(score);
}

std::string normalizedCommandKey(std::string key)
{
    std::transform(key.begin(), key.end(), key.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });

    key.erase(std::remove_if(key.begin(), key.end(), [](unsigned char character) {
        return std::isspace(character) || character == '.' || character == '_' || character == '-';
    }), key.end());

    return key;
}

mu::engraving::Page* pageForItem(mu::engraving::EngravingItem* item)
{
    if (!item) {
        return nullptr;
    }

    if (item->isNote()) {
        mu::engraving::Note* note = mu::engraving::toNote(item);
        mu::engraving::Chord* chord = note ? note->chord() : nullptr;
        mu::engraving::Segment* segment = chord ? chord->segment() : nullptr;
        mu::engraving::System* system = segment ? segment->system() : nullptr;
        return system ? system->page() : nullptr;
    }

    if (item->isChord()) {
        mu::engraving::Chord* chord = mu::engraving::toChord(item);
        mu::engraving::Segment* segment = chord ? chord->segment() : nullptr;
        mu::engraving::System* system = segment ? segment->system() : nullptr;
        return system ? system->page() : nullptr;
    }

    if (item->isRest()) {
        mu::engraving::Rest* rest = mu::engraving::toRest(item);
        mu::engraving::Segment* segment = rest ? rest->segment() : nullptr;
        mu::engraving::System* system = segment ? segment->system() : nullptr;
        return system ? system->page() : nullptr;
    }

    if (item->isBarLine() || item->isTimeSig() || item->isKeySig()) {
        mu::engraving::EngravingItem* parent = item->parentItem();
        if (parent && parent->isSegment()) {
            mu::engraving::Segment* segment = mu::engraving::toSegment(parent);
            mu::engraving::System* system = segment ? segment->system() : nullptr;
            return system ? system->page() : nullptr;
        }
    }

    if (item->isLayoutBreak()) {
        mu::engraving::LayoutBreak* layoutBreak = mu::engraving::toLayoutBreak(item);
        mu::engraving::MeasureBase* measureBase = layoutBreak ? layoutBreak->measure() : nullptr;
        mu::engraving::System* system = measureBase ? measureBase->system() : nullptr;
        return system ? system->page() : nullptr;
    }

    if (item->isSystemLockIndicator()) {
        mu::engraving::SystemLockIndicator* indicator = mu::engraving::toSystemLockIndicator(item);
        mu::engraving::System* system = indicator ? indicator->system() : nullptr;
        return system ? system->page() : nullptr;
    }

    if (item->isHBox()) {
        mu::engraving::Box* box = static_cast<mu::engraving::Box*>(item);
        mu::engraving::System* system = box ? box->system() : nullptr;
        return system ? system->page() : nullptr;
    }

    if (mu::engraving::Spanner* spanner = expressionSpannerForItem(item)) {
        if (!spanner->segmentsEmpty()) {
            mu::engraving::SpannerSegment* segment = spanner->frontSegment();
            mu::engraving::System* system = segment ? segment->system() : nullptr;
            if (system && system->page()) {
                return system->page();
            }
        }
        if (mu::engraving::EngravingItem* startElement = spanner->startElement()) {
            return pageForItem(startElement);
        }
        if (mu::engraving::Segment* startSegment = spanner->startSegment()) {
            mu::engraving::System* system = startSegment->system();
            return system ? system->page() : nullptr;
        }
    }

    if (isEditableTextItem(item)) {
        if (item->isLyrics()) {
            mu::engraving::Lyrics* lyrics = mu::engraving::toLyrics(item);
            mu::engraving::ChordRest* chordRest = lyrics ? lyrics->chordRest() : nullptr;
            mu::engraving::Segment* segment = chordRest ? chordRest->segment() : nullptr;
            mu::engraving::System* system = segment ? segment->system() : nullptr;
            return system ? system->page() : nullptr;
        }

        mu::engraving::EngravingItem* parent = item->parentItem();
        if (parent && parent->isSegment()) {
            mu::engraving::Segment* segment = mu::engraving::toSegment(parent);
            mu::engraving::Measure* measure = segment ? segment->measure() : nullptr;
            mu::engraving::System* system = measure ? measure->system() : nullptr;
            return system ? system->page() : nullptr;
        }
        if (parent && parent->isMeasure()) {
            mu::engraving::Measure* measure = mu::engraving::toMeasure(parent);
            mu::engraving::System* system = measure ? measure->system() : nullptr;
            return system ? system->page() : nullptr;
        }
    }

    mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(item);
    if (!chordRest) {
        // Anything else laid out on a page (fermatas, articulations, clefs, tuplets, glissando segments, ...).
        mu::engraving::EngravingItem* page = item->findAncestor(mu::engraving::ElementType::PAGE);
        return page ? mu::engraving::toPage(page) : nullptr;
    }

    mu::engraving::Segment* segment = chordRest->segment();
    mu::engraving::System* system = segment ? segment->system() : nullptr;
    return system ? system->page() : nullptr;
}

mu::engraving::Page* pageForItem(const mu::engraving::Score* score, mu::engraving::EngravingItem* item)
{
    if (mu::engraving::Page* page = pageForItem(item)) {
        return page;
    }

    if (!score || !item || !isEditableTextItem(item)) {
        return nullptr;
    }

    const mu::engraving::RectF itemRect = item->pageBoundingRect();
    for (mu::engraving::Page* page : score->pages()) {
        if (!page) {
            continue;
        }

        const std::vector<mu::engraving::EngravingItem*> elements = page->elements();
        if (std::find(elements.begin(), elements.end(), item) != elements.end()) {
            return page;
        }

        if (itemRect.width() > 0.0 && itemRect.height() > 0.0) {
            const std::vector<mu::engraving::EngravingItem*> items = page->items(itemRect);
            if (std::find(items.begin(), items.end(), item) != items.end()) {
                return page;
            }
        }
    }

    return nullptr;
}

muse::midi::Program midiProgramForSetup(const muse::mpe::PlaybackSetupData& setupData);

mu::engraving::RectF paddedSelectionRect(mu::engraving::RectF rect, const double spatium)
{
    if (rect.width() <= 0.0 || rect.height() <= 0.0) {
        return rect;
    }

    const double padding = std::max(spatium * 0.18, 0.8);
    rect.adjust(-padding, -padding, padding, padding);

    const double minimumSize = std::max(spatium * 0.55, 2.0);
    if (rect.width() < minimumSize) {
        const double delta = (minimumSize - rect.width()) * 0.5;
        rect.adjust(-delta, 0.0, delta, 0.0);
    }
    if (rect.height() < minimumSize) {
        const double delta = (minimumSize - rect.height()) * 0.5;
        rect.adjust(0.0, -delta, 0.0, delta);
    }

    return rect;
}

void appendHighlightRect(msr::render::ScoreSelectionState& selectionState,
                         const mu::engraving::Page* page,
                         mu::engraving::RectF rect,
                         const double spatium)
{
    if (!page || page->width() <= 0.0 || page->height() <= 0.0) {
        return;
    }

    rect = paddedSelectionRect(rect, spatium);
    if (rect.width() <= 0.0 || rect.height() <= 0.0) {
        return;
    }

    const double left = clampUnitInterval(rect.left() / page->width());
    const double top = clampUnitInterval(rect.top() / page->height());
    const double right = clampUnitInterval(rect.right() / page->width());
    const double bottom = clampUnitInterval(rect.bottom() / page->height());
    if (right <= left || bottom <= top) {
        return;
    }

    selectionState.highlightRects.push_back({
        left,
        top,
        right - left,
        bottom - top
    });
}

void appendNoteHighlightRects(msr::render::ScoreSelectionState& selectionState,
                              const mu::engraving::Page* page,
                              mu::engraving::Note* note)
{
    if (!note || !page) {
        return;
    }

    const double spatium = page->spatium();
    appendHighlightRect(selectionState, page, note->pageBoundingRect(), spatium);
    if (mu::engraving::Accidental* accidental = note->accidental()) {
        appendHighlightRect(selectionState, page, accidental->pageBoundingRect(), spatium);
    }
    for (mu::engraving::NoteDot* dot : note->dots()) {
        if (dot) {
            appendHighlightRect(selectionState, page, dot->pageBoundingRect(), spatium);
        }
    }

    mu::engraving::Chord* chord = note->chord();
    if (!chord) {
        return;
    }
    if (mu::engraving::Stem* stem = chord->stem()) {
        appendHighlightRect(selectionState, page, stem->pageBoundingRect(), spatium);
    }
    for (mu::engraving::LedgerLine* ledgerLine : chord->ledgerLines()) {
        if (ledgerLine) {
            appendHighlightRect(selectionState, page, ledgerLine->pageBoundingRect(), spatium);
        }
    }
}

void appendRestHighlightRects(msr::render::ScoreSelectionState& selectionState,
                              const mu::engraving::Page* page,
                              mu::engraving::Rest* rest)
{
    if (!rest || !page) {
        return;
    }

    const double spatium = page->spatium();
    appendHighlightRect(selectionState, page, rest->pageBoundingRect(), spatium);
    for (mu::engraving::NoteDot* dot : rest->dotList()) {
        if (dot) {
            appendHighlightRect(selectionState, page, dot->pageBoundingRect(), spatium);
        }
    }
}

muse::Color voiceSelectionColor(const int voice)
{
    switch (voice) {
    case 1:
        return muse::Color(0, 127, 0);
    case 2:
        return muse::Color(197, 63, 0);
    case 3:
        return muse::Color(195, 25, 137);
    default:
        return muse::Color(0, 101, 191);
    }
}

muse::Color selectionColorForItem(const mu::engraving::EngravingItem* item)
{
    if (!item || item->track() == muse::nidx) {
        return voiceSelectionColor(0);
    }

    return voiceSelectionColor(static_cast<int>(item->track() % mu::engraving::VOICES));
}

void appendOverlayItem(std::vector<const mu::engraving::EngravingItem*>& items,
                       const mu::engraving::EngravingItem* item)
{
    if (!item) {
        return;
    }
    if (std::find(items.begin(), items.end(), item) != items.end()) {
        return;
    }
    items.push_back(item);
}

void appendNoteOverlayItems(std::vector<const mu::engraving::EngravingItem*>& items,
                            mu::engraving::Note* note)
{
    if (!note) {
        return;
    }

    appendOverlayItem(items, note);
    appendOverlayItem(items, note->accidental());
    for (mu::engraving::NoteDot* dot : note->dots()) {
        appendOverlayItem(items, dot);
    }

    mu::engraving::Chord* chord = note->chord();
    if (!chord) {
        return;
    }
    appendOverlayItem(items, chord->stem());
    appendOverlayItem(items, chord->hook());
    appendOverlayItem(items, chord->beam());
    for (mu::engraving::LedgerLine* ledgerLine : chord->ledgerLines()) {
        appendOverlayItem(items, ledgerLine);
    }
}

void appendRestOverlayItems(std::vector<const mu::engraving::EngravingItem*>& items,
                            mu::engraving::Rest* rest)
{
    if (!rest) {
        return;
    }

    appendOverlayItem(items, rest);
    for (mu::engraving::NoteDot* dot : rest->dotList()) {
        appendOverlayItem(items, dot);
    }
}

bool selectionOverlayCropRect(const mu::engraving::Page* page,
                              const std::vector<const mu::engraving::EngravingItem*>& items,
                              mu::engraving::RectF& cropRect)
{
    if (!page || items.empty() || page->width() <= 0.0 || page->height() <= 0.0) {
        return false;
    }

    bool hasCropRect = false;
    for (const mu::engraving::EngravingItem* item : items) {
        if (!item || !item->explicitParent()) {
            continue;
        }
        const mu::engraving::RectF itemRect = item->pageBoundingRect();
        if (itemRect.width() <= 0.0 || itemRect.height() <= 0.0) {
            continue;
        }
        cropRect = hasCropRect ? cropRect.united(itemRect) : itemRect;
        hasCropRect = true;
    }

    if (!hasCropRect || cropRect.width() <= 0.0 || cropRect.height() <= 0.0) {
        return false;
    }

    const double padding = std::max(page->spatium() * 0.6, 2.0);
    cropRect.adjust(-padding, -padding, padding, padding);
    cropRect = cropRect.intersected(mu::engraving::RectF(0.0, 0.0, page->width(), page->height()));
    return cropRect.width() > 0.0 && cropRect.height() > 0.0;
}

void paintSelectionOverlayItems(muse::draw::Painter& painter,
                                const std::vector<const mu::engraving::EngravingItem*>& items)
{
    mu::engraving::rendering::PaintOptions options;
    options.isPrinting = false;
    options.overrideItemColor = [](const mu::engraving::EngravingItem* item, muse::Color) {
        return selectionColorForItem(item);
    };

    for (const mu::engraving::EngravingItem* item : items) {
        if (item) {
            mu::engraving::rendering::score::Paint::paintItem(painter, item, options);
        }
    }
}

void renderSelectionOverlayPng(msr::render::ScoreSelectionState& selectionState,
                               const mu::engraving::RectF& cropRect,
                               const std::vector<const mu::engraving::EngravingItem*>& items)
{
    selectionState.overlayPngData.clear();

    constexpr int overlayDpi = 144;
    const double scale = static_cast<double>(overlayDpi) / mu::engraving::DPI;
    const int width = std::max(1, static_cast<int>(std::ceil(cropRect.width() * scale)));
    const int height = std::max(1, static_cast<int>(std::ceil(cropRect.height() * scale)));

    QImage image(width, height, QImage::Format_ARGB32_Premultiplied);
    image.setDotsPerMeterX(std::lrint((overlayDpi * 1000.0) / mu::engraving::INCH));
    image.setDotsPerMeterY(std::lrint((overlayDpi * 1000.0) / mu::engraving::INCH));
    image.fill(Qt::transparent);

    muse::draw::Painter painter(&image, "score_selection_overlay");
    painter.setAntialiasing(true);
    painter.setViewport(muse::RectF(0.0, 0.0, width, height));
    painter.setWindow(cropRect);
    paintSelectionOverlayItems(painter, items);

    QByteArray pngData;
    QBuffer buffer(&pngData);
    if (!buffer.open(QIODevice::WriteOnly) || !image.save(&buffer, "png")) {
        return;
    }

    selectionState.overlayPixelWidth = width;
    selectionState.overlayPixelHeight = height;
    selectionState.overlayPngData.assign(pngData.begin(), pngData.end());
}

void renderSelectionOverlayPdf(msr::render::ScoreSelectionState& selectionState,
                               const mu::engraving::Page* page,
                               const mu::engraving::RectF& cropRect,
                               const std::vector<const mu::engraving::EngravingItem*>& items)
{
    selectionState.overlayPdfData.clear();
    if (!page || page->width() <= 0.0 || page->height() <= 0.0) {
        return;
    }

    const double widthInches = page->width() / mu::engraving::DPI;
    const double heightInches = page->height() / mu::engraving::DPI;
    if (widthInches <= 0.0 || heightInches <= 0.0) {
        return;
    }

    QByteArray pdfBytes;
    QBuffer buffer(&pdfBytes);
    if (!buffer.open(QIODevice::WriteOnly)) {
        return;
    }

    QPdfWriter pdfWriter(&buffer);
    pdfWriter.setResolution(mu::engraving::DPI);
    pdfWriter.setPageMargins(QMarginsF());
    pdfWriter.setPageLayout(QPageLayout(
        QPageSize(QSizeF(widthInches, heightInches), QPageSize::Inch),
        QPageLayout::Orientation::Portrait,
        QMarginsF()));
    pdfWriter.setColorModel(QPdfWriter::ColorModel::Auto);

    muse::draw::Painter painter(&pdfWriter, "score_selection_overlay_pdf");
    if (!painter.isActive()) {
        return;
    }

    painter.setAntialiasing(true);
    painter.setViewport(muse::RectF(0.0, 0.0, page->width(), page->height()));
    painter.setWindow(mu::engraving::RectF(0.0, 0.0, page->width(), page->height()));
    painter.setClipRect(cropRect);
    paintSelectionOverlayItems(painter, items);
    painter.endDraw();

    selectionState.overlayPdfData.assign(pdfBytes.constData(), pdfBytes.constData() + pdfBytes.size());
}

void renderSelectionOverlay(msr::render::ScoreSelectionState& selectionState,
                            const mu::engraving::Page* page,
                            const std::vector<const mu::engraving::EngravingItem*>& items)
{
    selectionState.overlayPngData.clear();
    selectionState.overlayPdfData.clear();
    if (!page || page->width() <= 0.0 || page->height() <= 0.0) {
        return;
    }

    mu::engraving::RectF cropRect;
    if (!selectionOverlayCropRect(page, items, cropRect)) {
        return;
    }

    selectionState.overlayNormalizedX = clampUnitInterval(cropRect.left() / page->width());
    selectionState.overlayNormalizedY = clampUnitInterval(cropRect.top() / page->height());
    selectionState.overlayNormalizedWidth = clampUnitInterval(cropRect.width() / page->width());
    selectionState.overlayNormalizedHeight = clampUnitInterval(cropRect.height() / page->height());
#if defined(Q_OS_ANDROID)
    // Android displays the selection PDF. Avoid painting/encoding an unused crop;
    // preserve the existing PNG fallback when PDF generation produces no data.
    renderSelectionOverlayPdf(selectionState, page, cropRect, items);
    if (selectionState.overlayPdfData.empty()) {
        renderSelectionOverlayPng(selectionState, cropRect, items);
    }
#else
    renderSelectionOverlayPng(selectionState, cropRect, items);
    renderSelectionOverlayPdf(selectionState, page, cropRect, items);
#endif
}

bool renderNoteEntryPreviewOverlay(msr::render::NoteEntryPreviewState& previewState,
                                   const mu::engraving::Page* page,
                                   mu::engraving::Score* score,
                                   const mu::engraving::ShadowNote& shadowNote)
{
    if (!page || !score || !score->renderer() || !shadowNote.visible() || !shadowNote.isValid() || page->width() <= 0.0 || page->height() <= 0.0) {
        return false;
    }

    mu::engraving::RectF cropRect = shadowNote.pageBoundingRect();
    if (cropRect.width() <= 0.0 || cropRect.height() <= 0.0) {
        cropRect = shadowNote.canvasBoundingRect();
    }
    if (cropRect.width() <= 0.0 || cropRect.height() <= 0.0) {
        return false;
    }

    const double padding = std::max(page->spatium() * 0.8, 2.0);
    cropRect.adjust(-padding, -padding, padding, padding);
    cropRect = cropRect.intersected(mu::engraving::RectF(0.0, 0.0, page->width(), page->height()));
    if (cropRect.width() <= 0.0 || cropRect.height() <= 0.0) {
        return false;
    }

    constexpr int overlayDpi = 144;
    const double scale = static_cast<double>(overlayDpi) / mu::engraving::DPI;
    const int width = std::max(1, static_cast<int>(std::ceil(cropRect.width() * scale)));
    const int height = std::max(1, static_cast<int>(std::ceil(cropRect.height() * scale)));

    QImage image(width, height, QImage::Format_ARGB32_Premultiplied);
    image.setDotsPerMeterX(std::lrint((overlayDpi * 1000.0) / mu::engraving::INCH));
    image.setDotsPerMeterY(std::lrint((overlayDpi * 1000.0) / mu::engraving::INCH));
    image.fill(Qt::transparent);

    muse::draw::Painter painter(&image, "score_note_entry_preview_overlay");
    painter.setAntialiasing(true);
    painter.setViewport(muse::RectF(0.0, 0.0, width, height));
    painter.setWindow(cropRect);

    mu::engraving::rendering::PaintOptions options;
    options.isPrinting = false;
    score->renderer()->drawItem(&shadowNote, &painter, options);

    QByteArray pngData;
    QBuffer buffer(&pngData);
    if (!buffer.open(QIODevice::WriteOnly) || !image.save(&buffer, "png")) {
        return false;
    }

    previewState.hasPreview = true;
    previewState.pageIndex = page->pageNumber();
    previewState.overlayNormalizedX = clampUnitInterval(cropRect.left() / page->width());
    previewState.overlayNormalizedY = clampUnitInterval(cropRect.top() / page->height());
    previewState.overlayNormalizedWidth = clampUnitInterval(cropRect.width() / page->width());
    previewState.overlayNormalizedHeight = clampUnitInterval(cropRect.height() / page->height());
    previewState.overlayPixelWidth = width;
    previewState.overlayPixelHeight = height;
    previewState.overlayPngData.assign(pngData.begin(), pngData.end());
    return true;
}

mu::engraving::Fraction currentTimeSignatureForSelection(const mu::engraving::Score* score, const mu::engraving::Measure* measure);
int currentKeyForSelection(const mu::engraving::Score* score, const mu::engraving::Measure* measure);
int currentKeyForSelection(const mu::engraving::Score* score,
                           const mu::engraving::Measure* measure,
                           mu::engraving::staff_idx_t preferredStaffStart);

bool supportsBowingArticulations(const mu::engraving::Staff* staff, const mu::engraving::Fraction& tick)
{
    const mu::engraving::Part* part = staff ? staff->part() : nullptr;
    const mu::engraving::Instrument* instrument = part ? part->instrument(tick) : nullptr;
    if (!instrument) {
        return false;
    }

    mu::engraving::PlaybackSetupDataResolver setupResolver;
    muse::mpe::PlaybackSetupData setupData;
    setupResolver.resolveSetupData(instrument, setupData);
    return setupData.category == muse::mpe::SoundCategory::Strings
        && !setupData.contains(muse::mpe::SoundSubCategory::Plucked);
}

int zeroBasedMeasureIndex(const mu::engraving::Score* score, const mu::engraving::Measure* target)
{
    if (!score || !target) {
        return -1;
    }

    int index = 0;
    for (const mu::engraving::Measure* measure = score->firstMeasure(); measure; measure = measure->nextMeasure(), ++index) {
        if (measure == target) {
            return index;
        }
    }
    return -1;
}

msr::render::ScoreSelectionState makeSelectionState(const mu::engraving::Score* score)
{
    msr::render::ScoreSelectionState selectionState;

    mu::engraving::Measure* rangeStart = nullptr;
    mu::engraving::Measure* rangeEnd = nullptr;
    if (selectedMeasureRange(score, &rangeStart, &rangeEnd)) {
        mu::engraving::Segment* selectionStartSegment = score->selection().startSegment();
        mu::engraving::Segment* selectionEndSegment = score->selection().endSegment();
        if (selectionStartSegment && selectionStartSegment->measure()) {
            rangeStart = selectionStartSegment->measure();
        }
        if (selectionEndSegment && selectionEndSegment->measure()) {
            mu::engraving::Measure* endMeasure = selectionEndSegment->measure();
            if (selectionEndSegment->tick() == endMeasure->tick() && endMeasure != rangeStart) {
                if (mu::engraving::Segment* previousSegment = selectionEndSegment->prev1(mu::engraving::SegmentType::ChordRest)) {
                    if (previousSegment->measure()) {
                        endMeasure = previousSegment->measure();
                    }
                }
            }
            rangeEnd = endMeasure;
        }

        mu::engraving::System* system = rangeStart->system();
        mu::engraving::Page* page = system ? system->page() : nullptr;
        if (!page || page->width() <= 0.0 || page->height() <= 0.0) {
            return selectionState;
        }

        const mu::engraving::staff_idx_t staffStart = std::min(score->selection().staffStart(), score->nstaves() - 1);
        const mu::engraving::staff_idx_t staffEnd = std::clamp(
            score->selection().staffEnd(),
            staffStart + 1,
            score->nstaves()
        );
        const mu::engraving::staff_idx_t lastStaff = staffEnd - 1;
        const mu::engraving::Staff* selectedStaff = score->staff(staffStart);
        const mu::engraving::Part* selectedPart = selectedStaff ? selectedStaff->part() : nullptr;
        const mu::engraving::Instrument* selectedInstrument = selectedPart
            ? selectedPart->instrument(rangeStart->tick())
            : nullptr;
        if (selectedPart) {
            selectionState.partId = std::to_string(selectedPart->id().toUint64());
        }
        if (selectedInstrument) {
            selectionState.instrumentId = selectedInstrument->id().toStdString();
            selectionState.instrumentName = selectedInstrument->trackName().toStdString();
        }
        mu::engraving::System* activeSystem = nullptr;
        mu::engraving::RectF systemRect;
        mu::engraving::RectF actionRect;
        bool hasSystemRect = false;
        auto appendSystemRect = [&]() {
            mu::engraving::Page* systemPage = activeSystem ? activeSystem->page() : nullptr;
            if (!hasSystemRect || !systemPage || systemRect.width() <= 0.0 || systemRect.height() <= 0.0
                || systemPage->width() <= 0.0 || systemPage->height() <= 0.0) {
                return;
            }
            const msr::render::NormalizedSelectionRect normalizedRect {
                systemRect.left() / systemPage->width(),
                systemRect.top() / systemPage->height(),
                systemRect.width() / systemPage->width(),
                systemRect.height() / systemPage->height()
            };
            if (systemPage == page) {
                selectionState.highlightRects.push_back(normalizedRect);
            } else {
                selectionState.otherPageHighlightRects.push_back({ static_cast<int>(systemPage->pageNumber()), normalizedRect });
            }
        };
        for (mu::engraving::Measure* measure = rangeStart; measure; measure = measure->nextMeasure()) {
            mu::engraving::System* measureSystem = measure->system();
            if (!measureSystem || !measureSystem->page()) {
                if (measure == rangeEnd) {
                    break;
                }
                continue;
            }

            if (activeSystem && activeSystem != measureSystem) {
                appendSystemRect();
                systemRect = mu::engraving::RectF();
                hasSystemRect = false;
            }
            activeSystem = measureSystem;

            const mu::engraving::RectF measureRect = measure->pageBoundingRect();
            const bool startsAtMeasureStart = selectionStartSegment
                && selectionStartSegment->measure() == measure
                && selectionStartSegment == measure->first(mu::engraving::SegmentType::ChordRest);
            const bool endsAtMeasureEnd = !selectionEndSegment
                || selectionEndSegment == measure->last()
                || selectionEndSegment->measure() != measure;
            const bool fullSingleMeasureSelection = rangeStart == rangeEnd
                && startsAtMeasureStart
                && endsAtMeasureEnd;
            double fullMeasureRight = measureRect.right();
            if (const mu::engraving::Measure* nextMeasure = measure->nextMeasure()) {
                if (nextMeasure->system() == measureSystem) {
                    fullMeasureRight = std::max(fullMeasureRight, nextMeasure->pageBoundingRect().left());
                }
            }
            double left = measureRect.left();
            double right = fullMeasureRight;
            if (!fullSingleMeasureSelection && selectionStartSegment && selectionStartSegment->measure() == measure) {
                left = chordRestSegmentSelectionBoundaryPageX(selectionStartSegment);
            }
            if (!fullSingleMeasureSelection && selectionEndSegment && selectionEndSegment->measure() == measure
                && selectionEndSegment->tick() < measure->endTick()) {
                right = chordRestSegmentSelectionBoundaryPageX(selectionEndSegment);
            }
            if (right <= left) {
                right = fullMeasureRight;
            }
            const double top = measureSystem->staffYpage(staffStart) - (page->spatium() * 2.0);
            const double bottom = measureSystem->staffYpage(lastStaff) + (page->spatium() * 6.0);
            const mu::engraving::RectF rect(
                left,
                top,
                right - left,
                std::max(bottom - top, page->spatium() * 8.0)
            );
            if (rect.width() > 0.0 && rect.height() > 0.0) {
                systemRect = hasSystemRect ? systemRect.united(rect) : rect;
                hasSystemRect = true;
                if (measure == rangeEnd && measureSystem->page() == page) {
                    actionRect = rect;
                }
            }

            if (measure == rangeEnd) {
                break;
            }
        }
        appendSystemRect();

        if (selectionState.highlightRects.empty()) {
            return selectionState;
        }

        const msr::render::NormalizedSelectionRect& primaryRect = selectionState.highlightRects.front();
        selectionState.hasSelection = true;
        selectionState.isMeasure = true;
        selectionState.isSingleMeasure = rangeStart == rangeEnd;
        if (rangeStart) {
            selectionState.measureIndex = zeroBasedMeasureIndex(score, rangeStart);
            selectionState.tick = rangeStart->tick().ticks();
            const mu::engraving::Fraction nominal = currentTimeSignatureForSelection(score, rangeStart);
            selectionState.currentTimeSignatureNumerator = nominal.numerator();
            selectionState.currentTimeSignatureDenominator = nominal.denominator();
            if (rangeStart == rangeEnd) {
                const mu::engraving::Measure* firstMeasure = score->firstMeasure();
                const mu::engraving::Fraction actual = rangeStart->ticks();
                selectionState.isFirstMeasure = rangeStart == firstMeasure;
                selectionState.pickupActualNumerator = actual.numerator();
                selectionState.pickupActualDenominator = actual.denominator();
                selectionState.pickupNominalNumerator = nominal.numerator();
                selectionState.pickupNominalDenominator = nominal.denominator();
                selectionState.isPickupMeasure = selectionState.isFirstMeasure
                    && (rangeStart->irregular() || actual < nominal);
            }
        }
        selectionState.canFillWithSlashes = !selectedMeasureRangeHasVoiceOneContent(score, rangeStart, rangeEnd);
        selectionState.supportsBowingArticulations = supportsBowingArticulations(
            score->staff(staffStart),
            rangeStart ? rangeStart->tick() : mu::engraving::Fraction(0, 1)
        );
        selectionState.pageIndex = page->pageNumber();
        selectionState.normalizedX = primaryRect.normalizedX;
        selectionState.normalizedY = primaryRect.normalizedY;
        selectionState.normalizedWidth = primaryRect.normalizedWidth;
        selectionState.normalizedHeight = primaryRect.normalizedHeight;
        if (actionRect.width() > 0.0 && actionRect.height() > 0.0) {
            selectionState.actionNormalizedX = actionRect.left() / page->width();
            selectionState.actionNormalizedY = actionRect.top() / page->height();
            selectionState.actionNormalizedWidth = actionRect.width() / page->width();
            selectionState.actionNormalizedHeight = actionRect.height() / page->height();
        } else {
            selectionState.actionNormalizedX = primaryRect.normalizedX;
            selectionState.actionNormalizedY = primaryRect.normalizedY;
            selectionState.actionNormalizedWidth = primaryRect.normalizedWidth;
            selectionState.actionNormalizedHeight = primaryRect.normalizedHeight;
        }
        selectionState.currentKey = currentKeyForSelection(score, rangeStart, staffStart);
        return selectionState;
    }

    mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score);
    if (!selectedItem) {
        return selectionState;
    }

    mu::engraving::EngravingItem* displayItem = selectedItem;
    if (mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(selectedItem)) {
        if (selectedItem->isChord()) {
            displayItem = chordRest;
        }
    }
    const bool barSelection = selectedItem->isBarLine();
    const bool measureSelection = selectedItem->isMeasure();
    const bool timeSignatureSelection = selectedItem->isTimeSig();
    const bool keySignatureSelection = selectedItem->isKeySig();
    const bool tempoSelection = selectedItem->isTempoText();
    const bool instrumentNameSelection = selectedItem->isInstrumentName();
    const bool instrumentChangeSelection = selectedItem->isInstrumentChange();
    const bool systemLockSelection = selectedItem->isSystemLockIndicator();
    const bool layoutBreakSelection = selectedItem->isLayoutBreak() || systemLockSelection;
    mu::engraving::Spanner* expressionSpanner = expressionSpannerForItem(selectedItem);

    mu::engraving::Page* page = pageForItem(score, displayItem);
    if (!page || page->width() <= 0.0 || page->height() <= 0.0) {
        return selectionState;
    }

    mu::engraving::RectF boundingRect = displayItem->pageBoundingRect();
    if (selectedItem->isLayoutBreak()) {
        boundingRect = layoutBreakMarkerRect(mu::engraving::toLayoutBreak(selectedItem));
    } else if (systemLockSelection) {
        boundingRect = systemLockMarkerRect(mu::engraving::toSystemLockIndicator(selectedItem));
    }
    if (mu::engraving::Note* note = editableNoteForItem(selectedItem)) {
        for (mu::engraving::NoteDot* dot : note->dots()) {
            if (dot) {
                boundingRect = boundingRect.united(dot->pageBoundingRect());
            }
        }
    }
    const double pageWidth = page->width();
    const double pageHeight = page->height();
    const bool noteLikeSelection = selectedItem->isNote() || selectedItem->isChord();
    const bool editableTextSelection = isEditableTextItem(selectedItem)
        && !instrumentNameSelection
        && !instrumentChangeSelection;
    mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(selectedItem);
    const mu::engraving::Staff* staff = chordRest ? chordRest->staff() : nullptr;
    const mu::engraving::Fraction tick = chordRest ? chordRest->tick() : mu::engraving::Fraction(0, 1);
    const mu::engraving::Measure* measure = chordRest ? chordRest->measure() : selectedItem->findMeasure();
    if (!measure && systemLockSelection) {
        const mu::engraving::MeasureBase* endMeasureBase = systemLockIndicatorEndMeasureBase(
            mu::engraving::toSystemLockIndicator(selectedItem)
        );
        if (endMeasureBase) {
            measure = endMeasureBase->isMeasure()
                ? mu::engraving::toMeasure(endMeasureBase)
                : endMeasureBase->prevMeasure();
        }
    }

    selectionState.hasSelection = true;
    selectionState.isNote = noteLikeSelection;
    selectionState.isRest = chordRest ? chordRest->isRest() : selectedItem->isRest();
    selectionState.isBar = barSelection;
    selectionState.isMeasure = measureSelection;
    selectionState.isTimeSignature = timeSignatureSelection;
    selectionState.isKeySignature = keySignatureSelection;
    selectionState.isTempo = tempoSelection;
    selectionState.isLayoutBreak = layoutBreakSelection;
    if (selectedItem->isLayoutBreak()) {
        selectionState.layoutBreakType = layoutBreakKind(mu::engraving::toLayoutBreak(selectedItem));
    } else if (systemLockSelection) {
        selectionState.layoutBreakType = "systemLock";
    }
    selectionState.isExpressionSpanner = expressionSpanner != nullptr;
    selectionState.isSlur = expressionSpanner ? expressionSpanner->isSlurTie() : false;
    selectionState.isTie = expressionSpanner ? expressionSpanner->isTie() : false;
    selectionState.isHairpin = expressionSpanner ? expressionSpanner->isHairpin() : false;
    selectionState.isInstrumentName = instrumentNameSelection;
    selectionState.isInstrumentChange = instrumentChangeSelection;
    selectionState.isEditableText = editableTextSelection;
    selectionState.isChordText = selectedItem->isHarmony();
    selectionState.canDragMovableElement = isDirectlyDraggableTextItem(selectedItem);
    if (selectedItem->isFermata()) {
        // Drag guide, as for chord symbols: the note it is attached to, and the notes it can move to.
        const mu::engraving::Fermata* fermata = mu::engraving::toFermata(selectedItem);
        for (const FermataAnchorTarget& target : fermataAnchorTargets(score, fermata)) {
            selectionState.attachmentTargets.push_back({ target.anchor.x() / pageWidth, target.anchor.y() / pageHeight });
            if (target.chordRest->segment() == fermata->segment()) {
                selectionState.hasAttachmentPoint = true;
                selectionState.attachmentNormalizedX = target.anchor.x() / pageWidth;
                selectionState.attachmentNormalizedY = target.anchor.y() / pageHeight;
            }
        }
    }
    selectionState.currentKey = currentKeyForSelection(
        score,
        measure,
        staff ? staff->idx() : static_cast<mu::engraving::staff_idx_t>(0)
    );
    if (measure) {
        selectionState.measureIndex = zeroBasedMeasureIndex(score, measure);
        selectionState.tick = measure->tick().ticks();
        const mu::engraving::Measure* firstMeasure = score->firstMeasure();
        const mu::engraving::Fraction nominal = currentTimeSignatureForSelection(score, measure);
        const mu::engraving::Fraction actual = measure->ticks();
        selectionState.isFirstMeasure = measure == firstMeasure;
        selectionState.pickupActualNumerator = actual.numerator();
        selectionState.pickupActualDenominator = actual.denominator();
        selectionState.pickupNominalNumerator = nominal.numerator();
        selectionState.pickupNominalDenominator = nominal.denominator();
        selectionState.currentTimeSignatureNumerator = nominal.numerator();
        selectionState.currentTimeSignatureDenominator = nominal.denominator();
        selectionState.isPickupMeasure = selectionState.isFirstMeasure
            && (measure->irregular() || actual < nominal);
    }
    if (instrumentNameSelection || instrumentChangeSelection) {
        const mu::engraving::Part* part = selectedItem->part();
        const mu::engraving::Instrument* instrument = nullptr;
        if (instrumentChangeSelection) {
            instrument = mu::engraving::toInstrumentChange(selectedItem)->instrument();
            selectionState.tick = selectedItem->tick().ticks();
        } else if (part) {
            instrument = part->instrument(selectedItem->tick());
        }
        if (part) {
            selectionState.partId = std::to_string(part->id().toUint64());
        }
        if (instrument) {
            selectionState.instrumentId = instrument->id().toStdString();
            selectionState.instrumentName = instrument->trackName().toStdString();
        }
    }
    if (editableTextSelection && selectedItem->isTextBase()) {
        mu::engraving::TextBase* text = mu::engraving::toTextBase(selectedItem);
        selectionState.textContent = text ? text->plainText().toStdString() : std::string();
        if (selectedItem->isHarmony()) {
            selectionState.textKind = "Chord Text";
            mu::engraving::Harmony* harmony = mu::engraving::toHarmony(selectedItem);
            if (harmony && harmony->isRealizable()) {
                for (const auto& [pitch, unusedTpc] : harmony->getRealizedHarmony().notes()) {
                    (void)unusedTpc;
                    if (pitch >= 0 && pitch <= 127) {
                        selectionState.chordMidiPitches.push_back(pitch);
                    }
                }
                std::sort(selectionState.chordMidiPitches.begin(), selectionState.chordMidiPitches.end());
            }
            if (harmony && harmony->part()) {
                mu::engraving::PlaybackSetupDataResolver setupResolver;
                muse::mpe::PlaybackSetupData setupData;
                setupResolver.resolveSetupData(harmony->part()->instrument(harmony->tick()), setupData);
                const muse::midi::Program program = midiProgramForSetup(setupData);
                selectionState.playbackBank = program.bank;
                selectionState.playbackProgram = program.program;
                selectionState.playbackSetupData = setupData.toString().toStdString();
            }
            mu::engraving::Segment* parentSegment = harmony ? harmony->getParentSeg() : nullptr;
            mu::engraving::Measure* parentMeasure = parentSegment ? parentSegment->measure() : nullptr;
            mu::engraving::System* parentSystem = parentMeasure ? parentMeasure->system() : nullptr;
            const mu::engraving::staff_idx_t harmonyStaff = harmony ? mu::engraving::track2staff(harmony->track()) : muse::nidx;
            if (parentSegment && parentMeasure && parentSystem && parentSystem->page() == page && harmonyStaff != muse::nidx) {
                mu::engraving::ChordRest* parentChordRest = mu::engraving::InputState::chordRest(parentSegment->element(harmony->track()));
                const mu::engraving::PointF anchor = parentChordRest
                    ? chordTextAttachmentAnchorForChordRest(parentChordRest)
                    : mu::engraving::PointF(parentMeasure->pageBoundingRect().left() + parentSegment->x(), parentSystem->staffYpage(harmonyStaff));
                selectionState.hasAttachmentPoint = true;
                selectionState.attachmentNormalizedX = anchor.x() / pageWidth;
                selectionState.attachmentNormalizedY = anchor.y() / pageHeight;
            }
            for (mu::engraving::Measure* anchorMeasure = score->firstMeasure(); anchorMeasure; anchorMeasure = anchorMeasure->nextMeasure()) {
                if (!anchorMeasure || anchorMeasure->system() == nullptr || anchorMeasure->system()->page() != page) {
                    continue;
                }
                for (mu::engraving::Segment* anchorSegment = anchorMeasure->first(mu::engraving::SegmentType::ChordRest);
                     anchorSegment && anchorSegment->measure() == anchorMeasure;
                     anchorSegment = anchorSegment->next1(mu::engraving::SegmentType::ChordRest)) {
                    for (mu::engraving::track_idx_t anchorTrack = 0; anchorTrack < score->nstaves() * mu::engraving::VOICES; ++anchorTrack) {
                        mu::engraving::ChordRest* anchorChordRest = mu::engraving::InputState::chordRest(anchorSegment->element(anchorTrack));
                        if (!anchorChordRest) {
                            continue;
                        }
                        const mu::engraving::PointF anchor = chordTextAttachmentAnchorForChordRest(anchorChordRest);
                        selectionState.attachmentTargets.push_back({
                            anchor.x() / pageWidth,
                            anchor.y() / pageHeight
                        });
                    }
                }
            }
        } else if (selectedItem->isStaffText()) {
            selectionState.textKind = "Staff Text";
        } else if (selectedItem->isSystemText()) {
            selectionState.textKind = "System Text";
        } else if (selectedItem->isLyrics()) {
            selectionState.textKind = "Lyrics";
        } else if (selectedItem->isDynamic()) {
            selectionState.textKind = "Dynamic";
        } else if (selectedItem->isJump()) {
            selectionState.textKind = "Jump";
        } else if (selectedItem->isMarker()) {
            selectionState.textKind = "Marker";
        } else {
            selectionState.textKind = "Text";
        }
    }
    selectionState.canChangePitch = noteLikeSelection && isStandardStaff(staff, tick);
    selectionState.supportsBowingArticulations = supportsBowingArticulations(staff, tick);
    if (chordRest) {
        selectionState.durationCode = durationCodeForType(chordRest->durationType().type());
        selectionState.isDotted = chordRest->dots() > 0;
    }
    if (mu::engraving::Note* note = editableNoteForItem(selectedItem)) {
        selectionState.midiPitch = note->pitch();
        selectionState.isTiedForward = note->tieFor() != nullptr;
        selectionState.diatonicStep = mu::engraving::tpc2step(note->tpc());
        if (mu::engraving::Chord* chord = note->chord()) {
            for (const mu::engraving::Note* chordNote : chord->notes()) {
                if (chordNote && mu::engraving::pitchIsValid(chordNote->pitch())) {
                    selectionState.chordMidiPitches.push_back(chordNote->pitch());
                }
            }
            std::sort(selectionState.chordMidiPitches.begin(), selectionState.chordMidiPitches.end());
        }
        if (note->part()) {
            mu::engraving::PlaybackSetupDataResolver setupResolver;
            muse::mpe::PlaybackSetupData setupData;
            setupResolver.resolveSetupData(note->part()->instrument(note->tick()), setupData);
            const muse::midi::Program program = midiProgramForSetup(setupData);
            selectionState.playbackBank = program.bank;
            selectionState.playbackProgram = program.program;
            selectionState.playbackSetupData = setupData.toString().toStdString();
        }
        const int alteration = static_cast<int>(mu::engraving::tpc2alter(note->tpc()));
        if (alteration < 0) {
            selectionState.accidentalKind = 2;
        } else if (alteration > 0) {
            selectionState.accidentalKind = 1;
        } else {
            selectionState.accidentalKind = 0;
        }
    }
    selectionState.pageIndex = static_cast<int>(score->pageIdx(page));
    selectionState.normalizedX = clampUnitInterval(boundingRect.left() / pageWidth);
    selectionState.normalizedY = clampUnitInterval(boundingRect.top() / pageHeight);
    selectionState.normalizedWidth = clampUnitInterval(boundingRect.width() / pageWidth);
    selectionState.normalizedHeight = clampUnitInterval(boundingRect.height() / pageHeight);
    selectionState.actionNormalizedX = selectionState.normalizedX;
    selectionState.actionNormalizedY = selectionState.normalizedY;
    selectionState.actionNormalizedWidth = selectionState.normalizedWidth;
    selectionState.actionNormalizedHeight = selectionState.normalizedHeight;
    if (expressionSpanner) {
        auto applyHandleForElement = [&](const mu::engraving::EngravingItem* element, double& x, double& y) {
            if (!element) {
                return false;
            }
            const mu::engraving::RectF rect = element->pageBoundingRect();
            if (rect.width() <= 0.0 || rect.height() <= 0.0) {
                return false;
            }
            x = clampUnitInterval(rect.center().x() / pageWidth);
            y = clampUnitInterval(rect.center().y() / pageHeight);
            return true;
        };
        auto applyHandleForSegment = [&](const mu::engraving::Segment* segment, const mu::engraving::track_idx_t track, double& x, double& y) {
            if (!segment || !segment->measure() || !segment->system()) {
                return false;
            }
            const mu::engraving::staff_idx_t staffIndex = std::min(mu::engraving::track2staff(track), score->nstaves() - 1);
            x = clampUnitInterval((segment->measure()->pageBoundingRect().left() + segment->x()) / pageWidth);
            y = clampUnitInterval(segment->system()->staffYpage(staffIndex) / pageHeight);
            return true;
        };

        // Handles sit where the line is actually drawn: the engine's own grips (as desktop
        // draws them) at the start of the first segment and the end of the last one.
        auto applyHandleForGrip = [&](const mu::engraving::SpannerSegment* segment, const mu::engraving::Grip grip, double& x, double& y) {
            if (!segment || !segment->system() || segment->system()->page() != page) {
                return false;
            }
            const std::vector<mu::engraving::PointF> grips = segment->gripsPositions(mu::engraving::EditData());
            const size_t gripIndex = static_cast<size_t>(grip);
            if (gripIndex >= grips.size()) {
                return false;
            }
            x = clampUnitInterval(grips[gripIndex].x() / pageWidth);
            y = clampUnitInterval(grips[gripIndex].y() / pageHeight);
            return true;
        };
        // Where a dragged end can attach (for the on-screen snapping guide): each note (chords
        // only, for slurs) on the line's staff, centred on the note at the middle of the staff,
        // so every target of one system shares a height. The endpoint finder agrees exactly
        // when it is handed one of these points.
        if (!expressionSpanner->isTie()) {
            const mu::engraving::staff_idx_t spannerStaff = std::min(mu::engraving::track2staff(expressionSpanner->track()), score->nstaves() - 1);
            const mu::engraving::Staff* staff = score->staff(spannerStaff);
            for (mu::engraving::System* system : page->systems()) {
                if (!system || !system->firstMeasure() || !staff) {
                    continue;
                }
                const double staffMiddle = system->staffYpage(spannerStaff) + staff->staffHeight(system->firstMeasure()->tick()) * 0.5;
                for (mu::engraving::MeasureBase* measureBase : system->measures()) {
                    if (!measureBase || !measureBase->isMeasure()) {
                        continue;
                    }
                    for (mu::engraving::Segment* segment = mu::engraving::toMeasure(measureBase)->first(mu::engraving::SegmentType::ChordRest);
                         segment;
                         segment = segment->next(mu::engraving::SegmentType::ChordRest)) {
                        for (mu::engraving::track_idx_t voice = 0; voice < mu::engraving::VOICES; ++voice) {
                            mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(segment->element(spannerStaff * mu::engraving::VOICES + voice));
                            if (!chordRest || (expressionSpanner->isSlurTie() && !chordRest->isChord())) {
                                continue;
                            }
                            selectionState.attachmentTargets.push_back({
                                clampUnitInterval(chordRest->pageBoundingRect().center().x() / pageWidth),
                                clampUnitInterval(staffMiddle / pageHeight)
                            });
                            break;
                        }
                    }
                }
            }
        }
        const bool hasSegments = !expressionSpanner->segmentsEmpty();
        if (!(hasSegments && applyHandleForGrip(expressionSpanner->frontSegment(), mu::engraving::Grip::START,
                                                selectionState.startHandleNormalizedX, selectionState.startHandleNormalizedY))
            && !applyHandleForElement(expressionSpanner->startElement(), selectionState.startHandleNormalizedX, selectionState.startHandleNormalizedY)) {
            applyHandleForSegment(expressionSpanner->startSegment(), expressionSpanner->track(), selectionState.startHandleNormalizedX, selectionState.startHandleNormalizedY);
        }
        if (!(hasSegments && applyHandleForGrip(expressionSpanner->backSegment(), mu::engraving::Grip::END,
                                                selectionState.endHandleNormalizedX, selectionState.endHandleNormalizedY))
            && !applyHandleForElement(expressionSpanner->endElement(), selectionState.endHandleNormalizedX, selectionState.endHandleNormalizedY)) {
            applyHandleForSegment(expressionSpanner->endSegment(), expressionSpanner->track2(), selectionState.endHandleNormalizedX, selectionState.endHandleNormalizedY);
        }
    }
    std::vector<const mu::engraving::EngravingItem*> overlayItems;
    if (mu::engraving::Note* note = editableNoteForItem(selectedItem)) {
        appendNoteHighlightRects(selectionState, page, note);
        appendNoteOverlayItems(overlayItems, note);
    } else if (mu::engraving::Chord* chord = selectedItem->isChord() ? mu::engraving::toChord(selectedItem) : nullptr) {
        for (mu::engraving::Note* chordNote : chord->notes()) {
            appendNoteHighlightRects(selectionState, page, chordNote);
            appendNoteOverlayItems(overlayItems, chordNote);
        }
    } else if (mu::engraving::Rest* rest = selectedItem->isRest() ? mu::engraving::toRest(selectedItem) : nullptr) {
        appendRestHighlightRects(selectionState, page, rest);
        appendRestOverlayItems(overlayItems, rest);
    } else if (usesSymbolSelectionHighlight(selectedItem)) {
        overlayItems.push_back(selectedItem);
    } else if (expressionSpanner && (expressionSpanner->isSlurTie() || expressionSpanner->isHairpin())) {
        // The curve or wedge itself turns blue: every piece of it on this page.
        for (const mu::engraving::SpannerSegment* segment : expressionSpanner->spannerSegments()) {
            if (segment && segment->system() && segment->system()->page() == page) {
                overlayItems.push_back(segment);
            }
        }
    }
    renderSelectionOverlay(selectionState, page, overlayItems);
    return selectionState;
}

int normalizedPitchClass(const int pitchClass)
{
    int value = pitchClass % 12;
    if (value < 0) {
        value += 12;
    }

    return value;
}

int diatonicNoteIndexForPitchClass(const int pitchClass, const bool preferFlats)
{
    switch (normalizedPitchClass(pitchClass)) {
    case 0:
        return 0; // C
    case 1:
        return preferFlats ? 1 : 0; // Db / C#
    case 2:
        return 1; // D
    case 3:
        return preferFlats ? 2 : 1; // Eb / D#
    case 4:
        return 2; // E
    case 5:
        return 3; // F
    case 6:
        return preferFlats ? 4 : 3; // Gb / F#
    case 7:
        return 4; // G
    case 8:
        return preferFlats ? 5 : 4; // Ab / G#
    case 9:
        return 5; // A
    case 10:
        return preferFlats ? 6 : 5; // Bb / A#
    case 11:
        return 6; // B
    default:
        return 0;
    }
}

mu::engraving::Note* noteFromChordRest(mu::engraving::ChordRest* chordRest)
{
    if (!chordRest || !chordRest->isChord()) {
        return nullptr;
    }

    mu::engraving::Chord* chord = mu::engraving::toChord(chordRest);
    return chord ? chord->upNote() : nullptr;
}

mu::engraving::Note* lastInputNote(mu::engraving::Score* score, const bool allowSelectionFallback = true)
{
    if (!score) {
        return nullptr;
    }

    mu::engraving::InputState& inputState = score->inputState();
    mu::engraving::Segment* segment = inputState.lastSegment();
    if (!segment) {
        return allowSelectionFallback ? currentSelectedNote(score) : nullptr;
    }

    const mu::engraving::track_idx_t currentTrack = inputState.track();
    if (currentTrack != muse::nidx) {
        if (mu::engraving::Note* note = noteFromChordRest(mu::engraving::InputState::chordRest(segment->element(currentTrack)))) {
            return note;
        }
    }

    const mu::engraving::track_idx_t previousTrack = inputState.prevTrack();
    if (previousTrack != muse::nidx) {
        if (mu::engraving::Note* note = noteFromChordRest(mu::engraving::InputState::chordRest(segment->element(previousTrack)))) {
            return note;
        }
    }

    return allowSelectionFallback ? currentSelectedNote(score) : nullptr;
}

void appendMeasureIfInputCursorReachedEnd(mu::engraving::Score* score)
{
    if (!score) {
        return;
    }

    mu::engraving::InputState& inputState = score->inputState();
    if (!inputState.noteEntryMode() || !inputState.endOfScore()) {
        return;
    }

    score->appendMeasures(1);
    inputState.moveToNextInputPos();
}

void continueNoteInputAfterChord(mu::engraving::Score* score, mu::engraving::ChordRest* chordRest)
{
    if (!score || !chordRest || !score->inputState().noteEntryMode()) {
        return;
    }

    configureInputCursorForChordRest(score, chordRest, false);
    score->inputState().moveToNextInputPos();
    appendMeasureIfInputCursorReachedEnd(score);
}

bool applyDiatonicPitchClassToNote(mu::engraving::Score* score,
                                   mu::engraving::Note* note,
                                   const int pitchClass,
                                   const bool preferFlats,
                                   std::string& errorMessage)
{
    if (!score || !note || !note->chord() || !note->chord()->segment() || !note->chord()->measure()) {
        errorMessage = "MuseReader could not identify the selected note.";
        return false;
    }

    mu::engraving::Chord* chord = note->chord();
    mu::engraving::Staff* staff = score->staff(chord->vStaffIdx());
    if (!staff || !isStandardStaff(staff, chord->tick())) {
        errorMessage = "Keyboard editing currently works only on standard staves.";
        return false;
    }

    const int desiredStep = diatonicNoteIndexForPitchClass(pitchClass, preferFlats);
    const int normalizedClass = normalizedPitchClass(pitchClass);
    const int octaveBase = (note->pitch() / mu::engraving::PITCH_DELTA_OCTAVE) * mu::engraving::PITCH_DELTA_OCTAVE;
    int targetPitch = octaveBase + normalizedClass;
    if (!mu::engraving::pitchIsValid(targetPitch)) {
        targetPitch += targetPitch < 0 ? mu::engraving::PITCH_DELTA_OCTAVE : -mu::engraving::PITCH_DELTA_OCTAVE;
    }

    const mu::engraving::Fraction tick = chord->tick();
    const mu::engraving::ClefType clef = staff->clef(tick);
    const mu::engraving::Key key = staff->key(tick);
    const int targetOctave = targetPitch / mu::engraving::PITCH_DELTA_OCTAVE;

    bool foundTargetLine = false;
    int bestLine = note->line();
    int bestPitchDistance = std::numeric_limits<int>::max();
    for (int octave = targetOctave - 1; octave <= targetOctave + 1; ++octave) {
        const int absStep = octave * mu::engraving::STEP_DELTA_OCTAVE + desiredStep;
        const int line = mu::engraving::ClefInfo::pitchOffset(clef) - absStep;
        const int pitch = line2pitch(line, clef, key);
        const int distance = std::abs(pitch - targetPitch);
        if (!foundTargetLine || distance < bestPitchDistance) {
            foundTargetLine = true;
            bestLine = line;
            bestPitchDistance = distance;
        }
    }

    if (!foundTargetLine) {
        errorMessage = "MuseReader could not resolve that pitch for the selected note.";
        return false;
    }

    const int absoluteStep = absStep(bestLine, clef);
    const int naturalPitch = line2pitch(bestLine, clef, mu::engraving::Key::C);
    const int accidentalOffsetValue = targetPitch - naturalPitch;
    if (accidentalOffsetValue < static_cast<int>(mu::engraving::AccidentalVal::MIN)
        || accidentalOffsetValue > static_cast<int>(mu::engraving::AccidentalVal::MAX)) {
        errorMessage = "MuseReader could not spell that pitch for the selected note.";
        return false;
    }

    const mu::engraving::AccidentalVal accidentalOffset = static_cast<mu::engraving::AccidentalVal>(accidentalOffsetValue);
    const int octave = absoluteStep / mu::engraving::STEP_DELTA_OCTAVE;
    const int writtenPitch = mu::engraving::step2pitch(absoluteStep) + octave * mu::engraving::PITCH_DELTA_OCTAVE + int(accidentalOffset);
    int tpc = mu::engraving::step2tpc(absoluteStep % mu::engraving::STEP_DELTA_OCTAVE, accidentalOffset);
    mu::engraving::NoteVal noteValue;
    noteValue.pitch = writtenPitch;

    const mu::engraving::Interval transpose = staff->transpose(tick);
    if (transpose.isZero()) {
        noteValue.tpc1 = noteValue.tpc2 = tpc;
    } else if (score->style().styleB(mu::engraving::Sid::concertPitch)) {
        mu::engraving::Interval concertTranspose = transpose;
        concertTranspose.flip();
        noteValue.tpc1 = tpc;
        noteValue.tpc2 = mu::engraving::Transpose::transposeTpc(tpc, concertTranspose, true);
    } else {
        noteValue.pitch += transpose.chromatic;
        noteValue.tpc2 = tpc;
        noteValue.tpc1 = mu::engraving::Transpose::transposeTpc(tpc, transpose, true);
    }

    if (!mu::engraving::pitchIsValid(noteValue.pitch)) {
        errorMessage = "The selected pitch is outside the supported range.";
        return false;
    }

    score->undoChangePitch(note, noteValue.pitch, noteValue.tpc1, noteValue.tpc2);
    return true;
}

std::optional<mu::engraving::AccidentalType> accidentalTypeForKind(const int accidentalKind)
{
    switch (accidentalKind) {
    case 0:
        return mu::engraving::AccidentalType::NATURAL;
    case 1:
        return mu::engraving::AccidentalType::SHARP;
    case 2:
        return mu::engraving::AccidentalType::FLAT;
    default:
        return std::nullopt;
    }
}

mu::engraving::Fraction currentTimeSignatureForSelection(const mu::engraving::Score* score, const mu::engraving::Measure* measure)
{
    if (!measure) {
        return mu::engraving::Fraction(4, 4);
    }

    if (!score || !score->sigmap()) {
        return measure->timesig();
    }

    const mu::engraving::Fraction nominal = score->sigmap()->timesig(measure->tick()).nominal();
    return nominal.isValid() ? nominal : measure->timesig();
}

int currentKeyForSelection(const mu::engraving::Score* score, const mu::engraving::Measure* measure)
{
    if (!score) {
        return 0;
    }

    const mu::engraving::staff_idx_t staffStart = score->selection().isRange()
        ? std::min(score->selection().staffStart(), score->nstaves() > 0 ? score->nstaves() - 1 : 0)
        : 0;
    return currentKeyForSelection(score, measure, staffStart);
}

int currentKeyForSelection(const mu::engraving::Score* score,
                           const mu::engraving::Measure* measure,
                           const mu::engraving::staff_idx_t preferredStaffStart)
{
    if (!score || !measure || score->nstaves() == 0) {
        return 0;
    }

    const mu::engraving::staff_idx_t staffStart = std::min(preferredStaffStart, score->nstaves() - 1);
    for (mu::engraving::staff_idx_t offset = 0; offset < score->nstaves(); ++offset) {
        const mu::engraving::staff_idx_t staffIdx = (staffStart + offset) % score->nstaves();
        const mu::engraving::Staff* staff = score->staff(staffIdx);
        if (staff && staff->isPitchedStaff(measure->tick())) {
            return static_cast<int>(staff->concertKey(measure->tick()));
        }
    }

    return 0;
}

msr::render::ScoreEditState makeEditState(const mu::engraving::Score* score, const bool includeSelection = true)
{
    msr::render::ScoreEditState editState;
    if (!score) {
        return editState;
    }

    const mu::engraving::InputState& inputState = score->inputState();
    if (includeSelection) {
        editState.selection = makeSelectionState(score);
    }
    editState.noteInputEnabled = inputState.noteEntryMode();
    editState.noteInputInsertsRests = inputState.rest();
    editState.noteInputIsDotted = inputState.duration().dots() > 0;
    editState.durationCode = durationCodeForType(inputState.duration().type());
    if (!inputState.noteEntryMode()) {
        if (const mu::engraving::ChordRest* chordRest = selectedChordRest(score)) {
            editState.currentVoice = static_cast<int>(chordRest->track() % mu::engraving::VOICES);
        } else {
            editState.currentVoice = static_cast<int>(inputState.voice());
        }
    } else {
        editState.currentVoice = static_cast<int>(inputState.voice());
    }
    if (inputState.noteEntryMode()) {
        const mu::engraving::Staff* staff = inputState.staff();
        editState.activeStaffIsPercussion = staff && staff->isDrumStaff(inputState.tick());
    } else if (const mu::engraving::ChordRest* chordRest = selectedChordRest(score)) {
        const mu::engraving::Staff* staff = score->staff(chordRest->staffIdx());
        editState.activeStaffIsPercussion = staff && staff->isDrumStaff(chordRest->tick());
    }
    editState.canUndo = score->undoStack() && score->undoStack()->canUndo();
    editState.canRedo = score->undoStack() && score->undoStack()->canRedo();
    editState.createMultiMeasureRests = score->style().styleB(mu::engraving::Sid::createMultiMeasureRests);
    editState.hideEmptyStaves = score->style().styleB(mu::engraving::Sid::hideEmptyStaves);
    editState.pageWidthMillimeters = score->style().styleD(mu::engraving::Sid::pageWidth) * mu::engraving::INCH;
    editState.pageHeightMillimeters = score->style().styleD(mu::engraving::Sid::pageHeight) * mu::engraving::INCH;
    editState.pageMarginMillimeters = score->style().styleD(mu::engraving::Sid::pageOddLeftMargin) * mu::engraving::INCH;
    editState.staffSizeMillimeters = score->style().spatium() / mu::engraving::DPI * mu::engraving::INCH;
    editState.staffSpacingSpatium = score->style().styleS(mu::engraving::Sid::staffDistance).val();
    editState.systemSpacingSpatium = score->style().styleS(mu::engraving::Sid::minSystemDistance).val();
    return editState;
}

struct SynthNoteEvent {
    enum class Kind {
        ProgramChange,
        ControlChange,
        PitchBend,
        NoteOff,
        NoteOn
    };

    int frame = 0;
    int channel = 0;
    int key = 60;
    int velocity = 90;
    bool noteOn = true;
    bool reattackAtRenderStart = true;
    Kind kind = Kind::NoteOn;
    int controller = 0;
    int value = 0;
    muse::midi::Program program;

    bool operator<(const SynthNoteEvent& other) const
    {
        if (frame != other.frame) {
            return frame < other.frame;
        }
        return static_cast<int>(kind) < static_cast<int>(other.kind);
    }
};

struct SynthChannelProgram {
    int channel = 0;
    muse::mpe::layer_idx_t layerIdx = 0;
    muse::midi::Program program;
    std::string setup;
    std::string partId = "metronome";
};

struct ActiveSynthNote {
    int count = 0;
    int velocity = 90;
    bool reattackAtRenderStart = true;
};

int activeSynthNoteKey(const SynthNoteEvent& event)
{
    return (event.channel << 8) | event.key;
}

bool hasChannelProgram(const std::vector<SynthChannelProgram>& channelPrograms, const int channel)
{
    return std::any_of(channelPrograms.cbegin(), channelPrograms.cend(), [channel](const SynthChannelProgram& channelProgram) {
        return channelProgram.channel == channel;
    });
}

std::unordered_map<int, ActiveSynthNote> activeSynthNotesAtFrame(const std::vector<SynthNoteEvent>& synthEvents,
                                                                 const int frame,
                                                                 size_t& firstWindowEventIndex)
{
    std::unordered_map<int, ActiveSynthNote> activeNotes;
    firstWindowEventIndex = 0;

    while (firstWindowEventIndex < synthEvents.size() && synthEvents[firstWindowEventIndex].frame < frame) {
        const SynthNoteEvent& event = synthEvents[firstWindowEventIndex];
        if (event.kind != SynthNoteEvent::Kind::NoteOn && event.kind != SynthNoteEvent::Kind::NoteOff) {
            firstWindowEventIndex += 1;
            continue;
        }
        const int key = activeSynthNoteKey(event);
        if (event.noteOn) {
            if (!event.reattackAtRenderStart) {
                firstWindowEventIndex += 1;
                continue;
            }
            ActiveSynthNote& activeNote = activeNotes[key];
            activeNote.count += 1;
            activeNote.velocity = event.velocity;
            activeNote.reattackAtRenderStart = event.reattackAtRenderStart;
        } else {
            auto activeNoteIt = activeNotes.find(key);
            if (activeNoteIt != activeNotes.end()) {
                activeNoteIt->second.count -= 1;
                if (activeNoteIt->second.count <= 0) {
                    activeNotes.erase(activeNoteIt);
                }
            }
        }
        firstWindowEventIndex += 1;
    }

    return activeNotes;
}

struct EventExtractionStats {
    struct LayerDebugStats {
        int channel = -1;
        std::string setup;
        bool useDynamicEvents = false;
        int noteCount = 0;
        int velocityMin = 128;
        int velocityMax = 0;
        long long velocitySum = 0;
        int nominalMin = std::numeric_limits<int>::max();
        int nominalMax = std::numeric_limits<int>::min();
        int expressionCurveMin = std::numeric_limits<int>::max();
        int expressionCurveMax = std::numeric_limits<int>::min();
        int notesWithExpressionCurve = 0;
        int notesWithVelocityOverride = 0;
        int dynamicControllerCount = 0;
    };

    int trackCount = 0;
    int invalidTrackCount = 0;
    int playbackModelTimestampCount = 0;
    int playbackModelEventCount = 0;
    int noteEventCount = 0;
    int fallbackRepeatSegmentCount = 0;
    int fallbackChordCount = 0;
    int fallbackPlayableNoteCount = 0;
    int fallbackHarmonyCount = 0;
    int fallbackHarmonyPlayableNoteCount = 0;
    int fallbackSkippedTieBackCount = 0;
    int soundPresetEventCount = 0;
    int textArticulationEventCount = 0;
    int controllerEventCount = 0;
    int dynamicControllerEventCount = 0;
    int pitchBendCurveEventCount = 0;
    bool usedEngravingFallback = false;
    std::map<muse::mpe::layer_idx_t, LayerDebugStats> layerDebug;
};

SynthNoteEvent makeNoteSynthEvent(const int frame,
                                  const int channel,
                                  const int key,
                                  const int velocity,
                                  const bool noteOn,
                                  const bool reattackAtRenderStart = true)
{
    SynthNoteEvent event;
    event.frame = frame;
    event.channel = channel;
    event.key = key;
    event.velocity = velocity;
    event.noteOn = noteOn;
    event.reattackAtRenderStart = reattackAtRenderStart;
    event.kind = noteOn ? SynthNoteEvent::Kind::NoteOn : SynthNoteEvent::Kind::NoteOff;
    return event;
}

SynthNoteEvent makeProgramSynthEvent(const int frame,
                                     const int channel,
                                     const muse::midi::Program program)
{
    SynthNoteEvent event;
    event.frame = frame;
    event.channel = channel;
    event.kind = SynthNoteEvent::Kind::ProgramChange;
    event.program = program;
    return event;
}

SynthNoteEvent makeControlSynthEvent(const int frame,
                                     const int channel,
                                     const int controller,
                                     const int value)
{
    SynthNoteEvent event;
    event.frame = frame;
    event.channel = channel;
    event.kind = SynthNoteEvent::Kind::ControlChange;
    event.controller = controller;
    event.value = value;
    return event;
}

SynthNoteEvent makePitchBendSynthEvent(const int frame,
                                       const int channel,
                                       const int value)
{
    SynthNoteEvent event;
    event.frame = frame;
    event.channel = channel;
    event.kind = SynthNoteEvent::Kind::PitchBend;
    event.value = value;
    return event;
}

muse::midi::Program midiProgramForSetup(const muse::mpe::PlaybackSetupData& setupData)
{
    if (!setupData.isValid()) {
        return muse::midi::Program(0, 0);
    }

    const std::map<muse::audio::synth::SoundMappingKey, muse::midi::Programs>& mapping
        = muse::audio::synth::mappingByCategory(setupData.category);

    muse::mpe::SoundSubCategories subCategorySet = setupData.soundSubCategories();
    muse::remove(subCategorySet, muse::mpe::SoundSubCategory::Primary);
    muse::remove(subCategorySet, muse::mpe::SoundSubCategory::Secondary);

    const muse::mpe::SoundId soundId = setupData.soundId();
    const auto exact = mapping.find({ soundId, subCategorySet });
    if (exact != mapping.cend() && !exact->second.empty()) {
        return exact->second.front();
    }

    const auto generic = mapping.find({ soundId, {} });
    if (generic != mapping.cend() && !generic->second.empty()) {
        return generic->second.front();
    }

    for (const auto& pair : mapping) {
        if (pair.first.id == soundId && !pair.second.empty()) {
            return pair.second.front();
        }
    }

    switch (setupData.category) {
    case muse::mpe::SoundCategory::Strings:
        return muse::midi::Program(0, 48);
    case muse::mpe::SoundCategory::Winds:
        return muse::midi::Program(0, 73);
    case muse::mpe::SoundCategory::Voices:
        return muse::midi::Program(0, 52);
    case muse::mpe::SoundCategory::Percussions:
        return muse::midi::Program(0, 0);
    case muse::mpe::SoundCategory::Keyboards:
    default:
        return muse::midi::Program(0, 0);
    }
}

std::string lowercasedASCII(std::string value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

muse::midi::Program midiProgramForPresetCode(const std::string& rawCode,
                                             const muse::midi::Program baseProgram)
{
    const std::string code = lowercasedASCII(rawCode);
    if (code.find("pizz") != std::string::npos || code.find("pluck") != std::string::npos) {
        return muse::midi::Program(0, 45);
    }
    if (code.find("tremolo") != std::string::npos || code.find("trem") != std::string::npos) {
        return muse::midi::Program(0, 44);
    }
    if (code.find("arco") != std::string::npos
        || code.find("ordinary") != std::string::npos
        || code.find("natural") != std::string::npos
        || code == "ord") {
        return baseProgram;
    }

    return baseProgram;
}

bool isPitchBendArticulation(const muse::mpe::ArticulationType type)
{
    switch (type) {
    case muse::mpe::ArticulationType::BrassBend:
    case muse::mpe::ArticulationType::Multibend:
    case muse::mpe::ArticulationType::SlideOutUp:
    case muse::mpe::ArticulationType::ContinuousGlissando:
    case muse::mpe::ArticulationType::Fall:
    case muse::mpe::ArticulationType::QuickFall:
    case muse::mpe::ArticulationType::Doit:
    case muse::mpe::ArticulationType::Plop:
    case muse::mpe::ArticulationType::Scoop:
    case muse::mpe::ArticulationType::SlideOutDown:
    case muse::mpe::ArticulationType::SlideInAbove:
    case muse::mpe::ArticulationType::SlideInBelow:
        return true;
    default:
        return false;
    }
}

int expressionLevelForDynamicLevel(muse::mpe::dynamic_level_t dynamicLevel);

int velocityForDynamicLevel(const muse::mpe::dynamic_level_t dynamicLevel)
{
    return expressionLevelForDynamicLevel(dynamicLevel);
}

int velocityForNoteEvent(const muse::mpe::NoteEvent& noteEvent,
                         const bool useDynamicEvents,
                         const bool useNominalDynamicFloor)
{
    const muse::mpe::ExpressionContext& expression = noteEvent.expressionCtx();
    if (expression.velocityOverride.has_value()) {
        return std::clamp(static_cast<int>(std::llround(*expression.velocityOverride * 127.0f)), 1, 127);
    }

    if (useDynamicEvents) {
        const double fraction = expression.expressionCurve.empty()
            ? 0.5
            : static_cast<double>(expression.expressionCurve.velocityFraction());
        return std::clamp(static_cast<int>(std::llround(fraction * 127.0)), 1, 127);
    }

    if (!expression.expressionCurve.empty()) {
        const double dynamicFraction = std::clamp(
            static_cast<double>(expression.expressionCurve.maxAmplitudeLevel())
            / static_cast<double>(muse::mpe::MAX_DYNAMIC_LEVEL),
            0.0,
            1.0
        );
        const int curveVelocity = std::clamp(static_cast<int>(std::llround(24.0 + (dynamicFraction * 103.0))), 1, 127);
        if (useNominalDynamicFloor) {
            return std::max(curveVelocity, velocityForDynamicLevel(expression.nominalDynamicLevel));
        }
        return curveVelocity;
    }

    return useNominalDynamicFloor ? velocityForDynamicLevel(expression.nominalDynamicLevel) : 90;
}

int expressionLevelForDynamicLevel(const muse::mpe::dynamic_level_t dynamicLevel)
{
    static constexpr muse::mpe::dynamic_level_t minSupportedDynamicsLevel
        = muse::mpe::dynamicLevelFromType(muse::mpe::DynamicType::ppp);
    static constexpr muse::mpe::dynamic_level_t maxSupportedDynamicsLevel
        = muse::mpe::dynamicLevelFromType(muse::mpe::DynamicType::fff);
    static constexpr int minSupportedVolume = 16;
    static constexpr int maxSupportedVolume = 127;
    static constexpr int volumeStep = 16;

    if (dynamicLevel <= minSupportedDynamicsLevel) {
        return minSupportedVolume;
    }
    if (dynamicLevel >= maxSupportedDynamicsLevel) {
        return maxSupportedVolume;
    }

    double stepCount = (dynamicLevel - minSupportedDynamicsLevel)
        / static_cast<double>(muse::mpe::DYNAMIC_LEVEL_STEP);
    if (dynamicLevel == muse::mpe::dynamicLevelFromType(muse::mpe::DynamicType::Natural)) {
        stepCount -= 0.5;
    }

    return std::clamp(static_cast<int>(std::llround(minSupportedVolume + (stepCount * volumeStep))),
                      minSupportedVolume,
                      maxSupportedVolume);
}

int frameForMpeTimestamp(const muse::mpe::timestamp_t timestamp)
{
    return std::max(0, static_cast<int>(std::llround(
        (static_cast<double>(timestamp) / 1000000.0) * kFluidSynthSampleRate
    )));
}

int pitchBendLevelForPitchOffset(const muse::mpe::pitch_level_t pitchLevel)
{
    static constexpr int pitchBendSemitoneStep = 4096 / 12;
    const double pitchLevelSteps = pitchLevel / static_cast<double>(muse::mpe::PITCH_LEVEL_STEP);
    const int offset = static_cast<int>(std::llround(pitchLevelSteps * pitchBendSemitoneStep));
    return std::clamp(8192 + offset, 0, 16383);
}

// Maps a note's applied articulations to a GM program override. A plain "pizz."
// playing-technique label is delivered as a per-note Pizzicato articulation
// rather than a stream sound-preset/text-articulation event, so it must be
// handled here in addition to appendAuxiliaryPlaybackEvent.
std::optional<muse::midi::Program> programOverrideForArticulations(const muse::mpe::PlaybackSetupData& setupData,
                                                                   const muse::mpe::ArticulationMap& articulations)
{
    // GM only offers dedicated string-section articulation programs.
    if (setupData.category != muse::mpe::SoundCategory::Strings) {
        return std::nullopt;
    }

    const auto hasArticulation = [&articulations](const muse::mpe::ArticulationType type) {
        return articulations.find(type) != articulations.cend();
    };

    if (hasArticulation(muse::mpe::ArticulationType::Pizzicato)
        || hasArticulation(muse::mpe::ArticulationType::SnapPizzicato)) {
        return muse::midi::Program(0, 45); // GM Pizzicato Strings
    }
    if (hasArticulation(muse::mpe::ArticulationType::Tremolo8th)
        || hasArticulation(muse::mpe::ArticulationType::Tremolo16th)
        || hasArticulation(muse::mpe::ArticulationType::Tremolo32nd)
        || hasArticulation(muse::mpe::ArticulationType::Tremolo64th)) {
        return muse::midi::Program(0, 44); // GM Tremolo Strings
    }
    return std::nullopt;
}

void appendPedalArticulationEvents(const muse::mpe::ArticulationMap& articulations,
                                   const int channel,
                                   std::set<std::string>& emittedPedalRanges,
                                   std::vector<SynthNoteEvent>& synthEvents,
                                   EventExtractionStats& stats)
{
    const auto pedalIt = articulations.find(muse::mpe::ArticulationType::Pedal);
    if (pedalIt == articulations.cend()) {
        return;
    }

    const muse::mpe::ArticulationMeta& meta = pedalIt->second.meta;
    if (!meta.hasStart()) {
        return;
    }

    const int startFrame = frameForMpeTimestamp(meta.timestamp);
    const int endFrame = meta.hasEnd()
        ? frameForMpeTimestamp(meta.timestamp + meta.overallDuration)
        : -1;
    const std::string key = std::to_string(channel) + ":" + std::to_string(startFrame) + ":" + std::to_string(endFrame);
    if (!emittedPedalRanges.insert(key).second) {
        return;
    }

    synthEvents.push_back(makeControlSynthEvent(startFrame, channel, 64, 127));
    stats.controllerEventCount += 1;

    if (meta.hasEnd()) {
        synthEvents.push_back(makeControlSynthEvent(endFrame, channel, 64, 0));
        stats.controllerEventCount += 1;
    }
}

void appendPitchCurveEvents(const muse::mpe::NoteEvent& noteEvent,
                            const int channel,
                            std::vector<SynthNoteEvent>& synthEvents,
                            EventExtractionStats& stats)
{
    const muse::mpe::PitchCurve& pitchCurve = noteEvent.pitchCtx().pitchCurve;
    if (pitchCurve.empty()) {
        return;
    }

    const muse::mpe::ArrangementContext& arrangement = noteEvent.arrangementCtx();
    const muse::mpe::timestamp_t noteEndTimestamp = arrangement.actualTimestamp + arrangement.actualDuration;

    for (const auto& artPair : noteEvent.expressionCtx().articulations) {
        if (!isPitchBendArticulation(artPair.first)) {
            continue;
        }

        const muse::mpe::ArticulationMeta& meta = artPair.second.meta;
        const muse::mpe::timestamp_t curveEnd = std::min(meta.timestamp + meta.overallDuration, noteEndTimestamp);
        synthEvents.push_back(makePitchBendSynthEvent(frameForMpeTimestamp(curveEnd), channel, 8192));
        stats.pitchBendCurveEventCount += 1;

        auto current = pitchCurve.cbegin();
        auto next = std::next(current);
        const auto end = pitchCurve.cend();
        for (; next != end; current = next, next = std::next(current)) {
            const int currentValue = pitchBendLevelForPitchOffset(current->second);
            const int nextValue = pitchBendLevelForPitchOffset(next->second);
            const muse::mpe::timestamp_t currentTime = meta.timestamp
                + static_cast<muse::mpe::timestamp_t>(std::llround(
                    meta.overallDuration * muse::mpe::percentageToFactor(current->first)
                ));
            const muse::mpe::timestamp_t nextTime = meta.timestamp
                + static_cast<muse::mpe::timestamp_t>(std::llround(
                    meta.overallDuration * muse::mpe::percentageToFactor(next->first)
                ));
            constexpr muse::mpe::pitch_level_t pointWeight = muse::mpe::PITCH_LEVEL_STEP / 10;
            const size_t pointCount = std::max<size_t>(std::abs(next->second - current->second) / pointWeight, 1);

            for (size_t point = 0; point <= pointCount; ++point) {
                const double t = static_cast<double>(point) / static_cast<double>(pointCount);
                const double oneMinusT = 1.0 - t;
                const double timestampValue = (oneMinusT * oneMinusT * currentTime)
                    + (2.0 * oneMinusT * t * nextTime)
                    + (t * t * nextTime);
                const double bendValue = (oneMinusT * oneMinusT * currentValue)
                    + (2.0 * oneMinusT * t * currentValue)
                    + (t * t * nextValue);
                const muse::mpe::timestamp_t timestamp = static_cast<muse::mpe::timestamp_t>(std::llround(timestampValue));
                if (timestamp >= curveEnd) {
                    continue;
                }

                synthEvents.push_back(makePitchBendSynthEvent(
                    frameForMpeTimestamp(timestamp),
                    channel,
                    std::clamp(static_cast<int>(std::llround(bendValue)), 0, 16383)
                ));
                stats.pitchBendCurveEventCount += 1;
            }
        }
    }
}

void recordLayerDynamicController(EventExtractionStats& stats, const muse::mpe::layer_idx_t layerIdx)
{
    stats.layerDebug[layerIdx].dynamicControllerCount += 1;
}

void recordLayerNote(EventExtractionStats& stats,
                     const muse::mpe::layer_idx_t layerIdx,
                     const muse::mpe::NoteEvent& noteEvent,
                     const int velocity)
{
    EventExtractionStats::LayerDebugStats& layerStats = stats.layerDebug[layerIdx];
    const muse::mpe::ExpressionContext& expression = noteEvent.expressionCtx();
    const int nominalLevel = static_cast<int>(expression.nominalDynamicLevel);
    layerStats.noteCount += 1;
    layerStats.velocityMin = std::min(layerStats.velocityMin, velocity);
    layerStats.velocityMax = std::max(layerStats.velocityMax, velocity);
    layerStats.velocitySum += velocity;
    layerStats.nominalMin = std::min(layerStats.nominalMin, nominalLevel);
    layerStats.nominalMax = std::max(layerStats.nominalMax, nominalLevel);
    if (!expression.expressionCurve.empty()) {
        const int expressionCurveLevel = static_cast<int>(expression.expressionCurve.maxAmplitudeLevel());
        layerStats.expressionCurveMin = std::min(layerStats.expressionCurveMin, expressionCurveLevel);
        layerStats.expressionCurveMax = std::max(layerStats.expressionCurveMax, expressionCurveLevel);
        layerStats.notesWithExpressionCurve += 1;
    }
    if (expression.velocityOverride.has_value()) {
        layerStats.notesWithVelocityOverride += 1;
    }
}

void appendDynamicControllerEvents(const muse::mpe::DynamicLevelMap& dynamics,
                                   const muse::mpe::layer_idx_t layerIdx,
                                   const int channel,
                                   std::vector<SynthNoteEvent>& synthEvents,
                                   EventExtractionStats& stats)
{
    for (const auto& dynamic : dynamics) {
        synthEvents.push_back(makeControlSynthEvent(
            frameForMpeTimestamp(dynamic.first),
            channel,
            11,
            expressionLevelForDynamicLevel(dynamic.second)
        ));
        stats.dynamicControllerEventCount += 1;
        stats.controllerEventCount += 1;
        recordLayerDynamicController(stats, layerIdx);
    }
}

muse::mpe::layer_idx_t layerIndexForPlaybackEvent(const muse::mpe::PlaybackEvent& event)
{
    if (std::holds_alternative<muse::mpe::NoteEvent>(event)) {
        const muse::mpe::ArrangementContext& arrangement = std::get<muse::mpe::NoteEvent>(event).arrangementCtx();
        return muse::mpe::makeLayerIdx(arrangement.staffLayerIndex, arrangement.voiceLayerIndex);
    }
    if (std::holds_alternative<muse::mpe::ControllerChangeEvent>(event)) {
        return std::get<muse::mpe::ControllerChangeEvent>(event).layerIdx;
    }
    if (std::holds_alternative<muse::mpe::SoundPresetChangeEvent>(event)) {
        return std::get<muse::mpe::SoundPresetChangeEvent>(event).layerIdx;
    }
    if (std::holds_alternative<muse::mpe::TextArticulationEvent>(event)) {
        return std::get<muse::mpe::TextArticulationEvent>(event).layerIdx;
    }
    if (std::holds_alternative<muse::mpe::SyllableEvent>(event)) {
        return std::get<muse::mpe::SyllableEvent>(event).layerIdx;
    }

    return 0;
}

// Returns the new channel program when this event changes the active sound,
// otherwise std::nullopt.
std::optional<muse::midi::Program> appendAuxiliaryPlaybackEvent(const muse::mpe::PlaybackEvent& event,
                                  const int frame,
                                  const int channel,
                                  const muse::midi::Program baseProgram,
                                  std::vector<SynthNoteEvent>& synthEvents,
                                  EventExtractionStats& stats)
{
    if (std::holds_alternative<muse::mpe::SoundPresetChangeEvent>(event)) {
        const muse::mpe::SoundPresetChangeEvent& presetEvent = std::get<muse::mpe::SoundPresetChangeEvent>(event);
        const muse::midi::Program program = midiProgramForPresetCode(presetEvent.code.toStdString(), baseProgram);
        synthEvents.push_back(makeProgramSynthEvent(frame, channel, program));
        stats.soundPresetEventCount += 1;
        return program;
    }

    if (std::holds_alternative<muse::mpe::TextArticulationEvent>(event)) {
        const muse::mpe::TextArticulationEvent& articulationEvent = std::get<muse::mpe::TextArticulationEvent>(event);
        const muse::midi::Program program = midiProgramForPresetCode(articulationEvent.text.toStdString(), baseProgram);
        synthEvents.push_back(makeProgramSynthEvent(frame, channel, program));
        stats.textArticulationEventCount += 1;
        return program;
    }

    if (std::holds_alternative<muse::mpe::ControllerChangeEvent>(event)) {
        const muse::mpe::ControllerChangeEvent& controllerEvent = std::get<muse::mpe::ControllerChangeEvent>(event);
        const int value7Bit = std::clamp(static_cast<int>(std::llround(controllerEvent.val * 127.0f)), 0, 127);
        switch (controllerEvent.type) {
        case muse::mpe::ControllerChangeEvent::Modulation:
            synthEvents.push_back(makeControlSynthEvent(frame, channel, 1, value7Bit));
            stats.controllerEventCount += 1;
            break;
        case muse::mpe::ControllerChangeEvent::SustainPedalOnOff:
            synthEvents.push_back(makeControlSynthEvent(frame, channel, 64, value7Bit));
            stats.controllerEventCount += 1;
            break;
        case muse::mpe::ControllerChangeEvent::PitchBend:
            synthEvents.push_back(makePitchBendSynthEvent(
                frame,
                channel,
                std::clamp(static_cast<int>(std::llround(controllerEvent.val * 16383.0f)), 0, 16383)
            ));
            stats.controllerEventCount += 1;
            break;
        case muse::mpe::ControllerChangeEvent::Undefined:
            break;
        }
    }

    return std::nullopt;
}

bool isMetronomeTrack(const mu::engraving::InstrumentTrackId& trackId)
{
    return trackId.instrumentId.toStdString() == "metronome";
}

const mu::engraving::Part* playbackPartForTrack(mu::engraving::Score* score, const mu::engraving::InstrumentTrackId& trackId)
{
    if (!score) {
        return nullptr;
    }

    for (const mu::engraving::Part* part : score->parts()) {
        if (part && part->id() == trackId.partId) {
            return part;
        }
    }

    return nullptr;
}

bool shouldIncludePlaybackTrack(mu::engraving::Score* score,
                                const mu::engraving::InstrumentTrackId& trackId,
                                const std::optional<std::uint64_t> activePartId)
{
    if (isMetronomeTrack(trackId)) {
        return true;
    }

    const mu::engraving::Part* part = playbackPartForTrack(score, trackId);
    if (!part || !part->show()) {
        return false;
    }

    return !activePartId.has_value() || trackId.partId.toUint64() == *activePartId;
}

bool shouldIncludePlaybackPart(const mu::engraving::Part* part,
                               const std::optional<std::uint64_t> activePartId)
{
    if (!part || !part->show()) {
        return false;
    }

    return !activePartId.has_value() || part->id().toUint64() == *activePartId;
}

void makeSilentPlaybackAudio(const double durationSeconds, msr::render::PlaybackAudioData& output)
{
    const int frameCount = std::max(1, static_cast<int>(std::ceil(durationSeconds * kFluidSynthSampleRate)));
    output.sampleRate = kFluidSynthSampleRate;
    output.channelCount = kFluidSynthChannelCount;
    output.durationSeconds = static_cast<double>(frameCount) / static_cast<double>(kFluidSynthSampleRate);
    output.interleavedSamples.assign(static_cast<size_t>(frameCount * kFluidSynthChannelCount), 0.0f);
    output.partSamples.clear();
}

int channelForPartId(const mu::engraving::ID partId, std::unordered_map<std::uint64_t, int>& channelsByPartId, int& nextChannel)
{
    const std::uint64_t key = partId.toUint64();
    auto existing = channelsByPartId.find(key);
    if (existing != channelsByPartId.end()) {
        return existing->second;
    }

    int channel = nextChannel;
    if (nextChannel == 9) {
        channel = 10;
    }
    nextChannel = channel + 1;

    channelsByPartId.emplace(key, channel);
    return channel;
}

void appendPlaybackModelSynthEvents(mu::engraving::Score* score,
                                    mu::engraving::PlaybackModel& playbackModel,
                                    const std::optional<std::uint64_t> activePartId,
                                    std::vector<SynthNoteEvent>& synthEvents,
                                    std::vector<SynthChannelProgram>& channelPrograms,
                                    EventExtractionStats& stats)
{
    int nextMelodicChannel = 0;
    std::set<std::string> emittedPedalRanges;

    for (const mu::engraving::InstrumentTrackId& trackId : playbackModel.existingTrackIdSet()) {
        if (!shouldIncludePlaybackTrack(score, trackId, activePartId)) {
            continue;
        }

        muse::mpe::PlaybackData& playbackData = playbackModel.resolveTrackPlaybackData(trackId);
        if (!playbackData.isValid()) {
            stats.invalidTrackCount += 1;
        }

        const muse::midi::Program baseProgram = midiProgramForSetup(playbackData.setupData);
        const std::string setupDataString = playbackData.setupData.toString().toStdString();
        stats.playbackModelTimestampCount += static_cast<int>(playbackData.originEvents.size());
        const bool isChordSymbolsTrack = playbackModel.isChordSymbolsTrack(trackId);
        const bool isKeyboardSetup = setupDataString.rfind("keyboards.", 0) == 0;
        // FluidSynth piano responds very strongly to stacked note velocity and
        // channel expression. Use MuseScore's per-note expression for keyboard
        // instruments so independent piano voices do not get double-attenuated.
        const bool useDynamicEvents = playbackData.setupData.supportsSingleNoteDynamics && !isKeyboardSetup;
        std::map<muse::mpe::layer_idx_t, int> channelsByLayer;
        std::map<int, muse::midi::Program> currentProgramsByChannel;
        std::map<int, bool> programFromArticulationByChannel;
        auto channelForLayer = [&](const muse::mpe::layer_idx_t layerIdx) {
            auto existing = channelsByLayer.find(layerIdx);
            if (existing != channelsByLayer.end()) {
                return existing->second;
            }

            int channel = 9;
            if (!isMetronomeTrack(trackId)) {
                channel = nextMelodicChannel;
                if (nextMelodicChannel == 9) {
                    channel = 10;
                }
                nextMelodicChannel = channel + 1;
            }

            channelsByLayer.emplace(layerIdx, channel);
            currentProgramsByChannel.emplace(channel, baseProgram);
            programFromArticulationByChannel.emplace(channel, false);
            channelPrograms.push_back({
                channel,
                layerIdx,
                baseProgram,
                setupDataString,
                isMetronomeTrack(trackId) ? "metronome" : std::to_string(trackId.partId.toUint64())
            });
            EventExtractionStats::LayerDebugStats& layerStats = stats.layerDebug[layerIdx];
            layerStats.channel = channel;
            layerStats.setup = setupDataString;
            layerStats.useDynamicEvents = useDynamicEvents;
            stats.trackCount += 1;
            if (useDynamicEvents) {
                synthEvents.push_back(makeControlSynthEvent(0, channel, 11, expressionLevelForDynamicLevel(
                    muse::mpe::dynamicLevelFromType(muse::mpe::DynamicType::Natural)
                )));
                stats.dynamicControllerEventCount += 1;
                stats.controllerEventCount += 1;
                recordLayerDynamicController(stats, layerIdx);
            }
            return channel;
        };

        if (useDynamicEvents) {
            for (const auto& layer : playbackData.dynamics) {
                const int channel = channelForLayer(layer.first);
                appendDynamicControllerEvents(layer.second, layer.first, channel, synthEvents, stats);
            }
        }

        for (const auto& pair : playbackData.originEvents) {
            const int eventFrame = frameForMpeTimestamp(pair.first);
            stats.playbackModelEventCount += static_cast<int>(pair.second.size());
            for (const muse::mpe::PlaybackEvent& event : pair.second) {
                const muse::mpe::layer_idx_t layerIdx = layerIndexForPlaybackEvent(event);
                const int channel = channelForLayer(layerIdx);
                muse::midi::Program& currentProgram = currentProgramsByChannel.find(channel)->second;
                bool& programFromArticulation = programFromArticulationByChannel.find(channel)->second;
                if (!std::holds_alternative<muse::mpe::NoteEvent>(event)) {
                    const std::optional<muse::midi::Program> auxProgram
                        = appendAuxiliaryPlaybackEvent(event, eventFrame, channel, baseProgram, synthEvents, stats);
                    if (auxProgram.has_value()) {
                        currentProgram = *auxProgram;
                        programFromArticulation = false;
                    }
                    continue;
                }

                const muse::mpe::NoteEvent& noteEvent = std::get<muse::mpe::NoteEvent>(event);
                const muse::mpe::ArrangementContext& arrangement = noteEvent.arrangementCtx();
                const muse::mpe::PitchContext& pitch = noteEvent.pitchCtx();
                if (arrangement.actualDuration <= 0 || arrangement.actualDuration == muse::mpe::INFINITE_DURATION) {
                    continue;
                }

                const int noteStartFrame = frameForMpeTimestamp(arrangement.actualTimestamp);
                const int noteDurationFrames = std::max(1, static_cast<int>(std::llround(
                    (static_cast<double>(arrangement.actualDuration) / 1000000.0) * kFluidSynthSampleRate
                )));
                const int key = std::clamp(
                    static_cast<int>(std::llround(static_cast<double>(pitch.nominalPitchLevel) / muse::mpe::PITCH_LEVEL_STEP))
                    + muse::mpe::ZERO_PITCH_LEVEL_MIDI_EQUIVALENT,
                    0,
                    127
                );

                const std::optional<muse::midi::Program> articulationProgram
                    = programOverrideForArticulations(playbackData.setupData, noteEvent.expressionCtx().articulations);
                appendPedalArticulationEvents(
                    noteEvent.expressionCtx().articulations,
                    channel,
                    emittedPedalRanges,
                    synthEvents,
                    stats
                );
                appendPitchCurveEvents(noteEvent, channel, synthEvents, stats);
                if (articulationProgram.has_value()) {
                    if (articulationProgram->program != currentProgram.program
                        || articulationProgram->bank != currentProgram.bank) {
                        synthEvents.push_back(makeProgramSynthEvent(noteStartFrame, channel, *articulationProgram));
                        currentProgram = *articulationProgram;
                    }
                    programFromArticulation = true;
                } else if (programFromArticulation) {
                    if (baseProgram.program != currentProgram.program || baseProgram.bank != currentProgram.bank) {
                        synthEvents.push_back(makeProgramSynthEvent(noteStartFrame, channel, baseProgram));
                    }
                    currentProgram = baseProgram;
                    programFromArticulation = false;
                }

                const int velocity = velocityForNoteEvent(noteEvent, useDynamicEvents, isKeyboardSetup);
                synthEvents.push_back(makeNoteSynthEvent(noteStartFrame, channel, key, velocity, true, !isChordSymbolsTrack));
                synthEvents.push_back(makeNoteSynthEvent(noteStartFrame + noteDurationFrames, channel, key, 0, false, !isChordSymbolsTrack));
                recordLayerNote(stats, layerIdx, noteEvent, velocity);
                stats.noteEventCount += 1;
            }
        }
    }
}

void appendMetronomeFallbackSynthEvents(mu::engraving::Score* score,
                                        std::vector<SynthNoteEvent>& synthEvents,
                                        std::vector<SynthChannelProgram>& channelPrograms)
{
    if (!score) {
        return;
    }

    if (!hasChannelProgram(channelPrograms, 9)) {
        channelPrograms.push_back({
            9,
            0,
            muse::midi::Program(0, 0),
            "MuseReader metronome fallback"
        });
    }

    const auto& repeatList = score->repeatList(true);
    for (const mu::engraving::RepeatSegment* repeatSegment : repeatList) {
        if (!repeatSegment) {
            continue;
        }

        const int tickPositionOffset = repeatSegment->utick - repeatSegment->tick;
        for (const mu::engraving::Measure* measure : repeatSegment->measureList()) {
            if (!measure) {
                continue;
            }

            const mu::engraving::Fraction measureTicks = measure->ticks();
            const int beatCount = std::max(1, measure->timesig().numerator());
            const mu::engraving::Fraction beatTicks = measureTicks / beatCount;
            const int measureStartTick = measure->tick().ticks() + tickPositionOffset;

            for (int beatIndex = 0; beatIndex < beatCount; ++beatIndex) {
                const int beatTick = measureStartTick + (beatTicks * beatIndex).ticks();
                const double beatSeconds = std::max(repeatList.utick2utime(beatTick), 0.0);
                const int noteStartFrame = std::max(0, static_cast<int>(std::llround(beatSeconds * kFluidSynthSampleRate)));
                const int noteDurationFrames = static_cast<int>(0.045 * kFluidSynthSampleRate);
                const int key = beatIndex == 0 ? 76 : 77;
                const int velocity = beatIndex == 0 ? 112 : 88;

                synthEvents.push_back(makeNoteSynthEvent(noteStartFrame, 9, key, velocity, true));
                synthEvents.push_back(makeNoteSynthEvent(noteStartFrame + noteDurationFrames, 9, key, 0, false));
            }
        }
    }
}

void appendEngravingFallbackSynthEvents(mu::engraving::Score* score,
                                        const std::optional<std::uint64_t> activePartId,
                                        std::vector<SynthNoteEvent>& synthEvents,
                                        std::vector<SynthChannelProgram>& channelPrograms,
                                        EventExtractionStats& stats)
{
    if (!score) {
        return;
    }

    mu::engraving::PlaybackSetupDataResolver setupResolver;
    std::unordered_map<std::uint64_t, int> channelsByPartId;
    std::unordered_map<std::uint64_t, int> harmonyChannelsByPartId;
    std::unordered_map<std::uint64_t, int> programsByPartId;
    std::unordered_map<std::uint64_t, int> harmonyProgramsByPartId;
    int nextMelodicChannel = 0;

    const auto& repeatList = score->repeatList(true);
    for (const mu::engraving::RepeatSegment* repeatSegment : repeatList) {
        if (!repeatSegment) {
            continue;
        }
        stats.fallbackRepeatSegmentCount += 1;

        const int tickPositionOffset = repeatSegment->utick - repeatSegment->tick;
        for (const mu::engraving::Measure* measure : repeatSegment->measureList()) {
            for (const mu::engraving::Segment* segment = measure ? measure->first() : nullptr; segment; segment = segment->next()) {
                if (!segment->isChordRestType()) {
                    continue;
                }

                for (const mu::engraving::EngravingItem* annotation : segment->annotations()) {
                    if (!annotation || !annotation->isHarmony() || !annotation->part()) {
                        continue;
                    }
                    if (!shouldIncludePlaybackPart(annotation->part(), activePartId)) {
                        continue;
                    }

                    const mu::engraving::Harmony* harmony = mu::engraving::toHarmony(annotation);
                    if (!harmony || !harmony->play() || !harmony->isRealizable()) {
                        continue;
                    }

                    const mu::engraving::track_idx_t staffIndex = harmony->track() / mu::engraving::VOICES;
                    const mu::engraving::Staff* staff = score->staff(staffIndex);
                    if (!staff || !staff->isPrimaryStaff()) {
                        continue;
                    }

                    const mu::engraving::RealizedHarmony& realizedHarmony = harmony->getRealizedHarmony();
                    const mu::engraving::RealizedHarmony::PitchMap& notes = realizedHarmony.notes();
                    if (notes.empty()) {
                        continue;
                    }
                    stats.fallbackHarmonyCount += 1;

                    const int channel = channelForPartId(annotation->part()->id(), harmonyChannelsByPartId, nextMelodicChannel);
                    const std::uint64_t partId = annotation->part()->id().toUint64();
                    if (!muse::contains(harmonyProgramsByPartId, partId)) {
                        muse::mpe::PlaybackSetupData setupData;
                        setupResolver.resolveSetupData(annotation->part()->instrument(harmony->tick()), setupData);
                        const muse::midi::Program program = midiProgramForSetup(setupData);
                        harmonyProgramsByPartId.emplace(partId, program.program);
                        channelPrograms.push_back({
                            channel,
                            0,
                            program,
                            setupData.toString().toStdString(),
                            std::to_string(partId)
                        });
                    }

                    const int harmonyStartTick = harmony->tick().ticks() + tickPositionOffset;
                    const mu::engraving::Fraction harmonyDuration = realizedHarmony.getActualDuration(harmonyStartTick);
                    const int harmonyEndTick = harmonyStartTick + std::max(1, harmonyDuration.ticks());
                    const double startSeconds = std::max(repeatList.utick2utime(harmonyStartTick), 0.0);
                    const double endSeconds = std::max(repeatList.utick2utime(harmonyEndTick), startSeconds);
                    const int noteStartFrame = std::max(0, static_cast<int>(std::llround(startSeconds * kFluidSynthSampleRate)));
                    const int noteDurationFrames = std::max(1, static_cast<int>(std::llround((endSeconds - startSeconds) * kFluidSynthSampleRate)));

                    for (const auto& [pitch, unusedTpc] : notes) {
                        (void)unusedTpc;
                        const int key = std::clamp(pitch, 0, 127);
                        synthEvents.push_back(makeNoteSynthEvent(noteStartFrame, channel, key, 74, true, false));
                        synthEvents.push_back(makeNoteSynthEvent(noteStartFrame + noteDurationFrames, channel, key, 0, false, false));
                        stats.noteEventCount += 1;
                        stats.fallbackHarmonyPlayableNoteCount += 1;
                    }
                }

                for (const mu::engraving::EngravingItem* item : segment->elist()) {
                    if (!item || !item->isChord() || !item->part()) {
                        continue;
                    }
                    if (!shouldIncludePlaybackPart(item->part(), activePartId)) {
                        continue;
                    }

                    const mu::engraving::Chord* chord = mu::engraving::toChord(item);
                    if (!chord || chord->notes().empty()) {
                        continue;
                    }
                    stats.fallbackChordCount += 1;

                    const int channel = channelForPartId(item->part()->id(), channelsByPartId, nextMelodicChannel);
                    const std::uint64_t partId = item->part()->id().toUint64();
                    if (!muse::contains(programsByPartId, partId)) {
                        muse::mpe::PlaybackSetupData setupData;
                        setupResolver.resolveSetupData(item->part()->instrument(chord->tick()), setupData);
                        const muse::midi::Program program = midiProgramForSetup(setupData);
                        programsByPartId.emplace(partId, program.program);
                        channelPrograms.push_back({
                            channel,
                            0,
                            program,
                            setupData.toString().toStdString(),
                            std::to_string(partId)
                        });
                    }

                    const int chordStartTick = chord->tick().ticks() + tickPositionOffset;
                    const int chordEndTick = chordStartTick + chord->actualTicks().ticks();
                    const double startSeconds = std::max(repeatList.utick2utime(chordStartTick), 0.0);
                    const double endSeconds = std::max(repeatList.utick2utime(chordEndTick), startSeconds);
                    const int noteStartFrame = std::max(0, static_cast<int>(std::llround(startSeconds * kFluidSynthSampleRate)));
                    const int noteDurationFrames = std::max(1, static_cast<int>(std::llround((endSeconds - startSeconds) * kFluidSynthSampleRate)));

                    for (const mu::engraving::Note* note : chord->notes()) {
                        if (!note || !note->play()) {
                            continue;
                        }
                        if (const mu::engraving::Tie* tieBack = note->tieBack(); tieBack && tieBack->playSpanner()) {
                            stats.fallbackSkippedTieBackCount += 1;
                            continue;
                        }

                        const int key = std::clamp(note->ppitch(), 0, 127);
                        synthEvents.push_back(makeNoteSynthEvent(noteStartFrame, channel, key, 90, true));
                        synthEvents.push_back(makeNoteSynthEvent(noteStartFrame + noteDurationFrames, channel, key, 0, false));
                        stats.noteEventCount += 1;
                        stats.fallbackPlayableNoteCount += 1;
                    }
                }
            }
        }
    }

    if (stats.noteEventCount > 0) {
        stats.usedEngravingFallback = true;
        stats.trackCount = std::max(stats.trackCount, static_cast<int>(channelsByPartId.size()));
    }
}

struct FluidSynthPlaybackSequence {
    std::vector<SynthNoteEvent> synthEvents;
    std::vector<SynthChannelProgram> channelPrograms;
    EventExtractionStats stats;
};

int frameForSeconds(const double seconds)
{
    return std::max(0, static_cast<int>(std::llround(seconds * kFluidSynthSampleRate)));
}

int alignFrameUp(const int frame, const int alignment)
{
    if (alignment <= 1) {
        return frame;
    }
    const int remainder = frame % alignment;
    return remainder == 0 ? frame : frame + (alignment - remainder);
}

int requiredMidiChannelCount(const std::vector<SynthNoteEvent>& synthEvents,
                             const std::vector<SynthChannelProgram>& channelPrograms)
{
    int requiredMidiChannels = 16;
    for (const SynthChannelProgram& channelProgram : channelPrograms) {
        requiredMidiChannels = std::max(requiredMidiChannels, channelProgram.channel + 1);
    }
    for (const SynthNoteEvent& event : synthEvents) {
        requiredMidiChannels = std::max(requiredMidiChannels, event.channel + 1);
    }
    return requiredMidiChannels;
}

FluidSynthPlaybackSequence makeFluidSynthPlaybackSequence(mu::engraving::Score* score,
                                                          const muse::modularity::ContextPtr& context,
                                                          const std::optional<std::uint64_t> activePartId,
                                                          const bool metronomeEnabled,
                                                          const double startTimeSeconds,
                                                          const double durationSeconds)
{
    // Swing markings only reach playback through each staff's swing map. Desktop
    // fills it when a score opens; Aria refreshes it here, as MuseScore's MIDI
    // renderer does, so loaded, part, and transposed-view scores all swing.
    score->updateSwing();

    mu::engraving::PlaybackModel playbackModel(context);
    playbackModel.setIsMetronomeEnabled(metronomeEnabled);
    playbackModel.load(score);

    FluidSynthPlaybackSequence sequence;
    appendPlaybackModelSynthEvents(score, playbackModel, activePartId, sequence.synthEvents, sequence.channelPrograms, sequence.stats);

    const bool hasMetronomeNotes = std::any_of(sequence.synthEvents.cbegin(), sequence.synthEvents.cend(), [](const SynthNoteEvent& event) {
        return event.channel == 9 && (event.kind == SynthNoteEvent::Kind::NoteOn || event.kind == SynthNoteEvent::Kind::NoteOff);
    });
    if (metronomeEnabled && !hasMetronomeNotes) {
        appendMetronomeFallbackSynthEvents(score, sequence.synthEvents, sequence.channelPrograms);
    }

    std::vector<SynthNoteEvent> fallbackSynthEvents;
    std::vector<SynthChannelProgram> fallbackChannelPrograms;
    EventExtractionStats fallbackStats;
    appendEngravingFallbackSynthEvents(score, activePartId, fallbackSynthEvents, fallbackChannelPrograms, fallbackStats);

    // Decide per part: a part that PlaybackModel left silent uses the engraving
    // fallback, and every other part keeps its model dynamics and articulations.
    // Fewer model notes alone is normal: bends, slides, let ring and linked ties
    // merge notated notes into one sounding note.
    auto noteOnCountsByPart = [](const std::vector<SynthNoteEvent>& events,
                                 const std::vector<SynthChannelProgram>& programs) {
        std::unordered_map<int, std::string> partByChannel;
        for (const SynthChannelProgram& program : programs) {
            partByChannel.emplace(program.channel, program.partId);
        }
        std::map<std::string, int> counts;
        for (const SynthNoteEvent& event : events) {
            if (event.kind != SynthNoteEvent::Kind::NoteOn) {
                continue;
            }
            auto part = partByChannel.find(event.channel);
            if (part != partByChannel.end()) {
                counts[part->second] += 1;
            }
        }
        return counts;
    };
    const std::map<std::string, int> modelNotesByPart = noteOnCountsByPart(sequence.synthEvents, sequence.channelPrograms);
    const std::map<std::string, int> fallbackNotesByPart = noteOnCountsByPart(fallbackSynthEvents, fallbackChannelPrograms);

    std::set<std::string> fallbackParts;
    for (const auto& [partId, fallbackCount] : fallbackNotesByPart) {
        const auto model = modelNotesByPart.find(partId);
        if (partId != "metronome" && fallbackCount > 0 && (model == modelNotesByPart.end() || model->second == 0)) {
            fallbackParts.insert(partId);
        }
    }

    if (!fallbackParts.empty()) {
        std::set<int> replacedChannels;
        int nextChannel = 0;
        for (const SynthChannelProgram& program : sequence.channelPrograms) {
            if (muse::contains(fallbackParts, program.partId)) {
                replacedChannels.insert(program.channel);
            }
            nextChannel = std::max(nextChannel, program.channel + 1);
        }
        sequence.channelPrograms.erase(
            std::remove_if(sequence.channelPrograms.begin(), sequence.channelPrograms.end(), [&](const SynthChannelProgram& program) {
            return muse::contains(replacedChannels, program.channel);
        }), sequence.channelPrograms.end());
        sequence.synthEvents.erase(
            std::remove_if(sequence.synthEvents.begin(), sequence.synthEvents.end(), [&](const SynthNoteEvent& event) {
            return muse::contains(replacedChannels, event.channel);
        }), sequence.synthEvents.end());

        // Fallback channels were numbered independently, so move them above the
        // model's channels, keeping clear of the percussion channel.
        std::unordered_map<int, int> remappedChannels;
        for (const SynthChannelProgram& program : fallbackChannelPrograms) {
            if (!muse::contains(fallbackParts, program.partId) || muse::contains(remappedChannels, program.channel)) {
                continue;
            }
            if (nextChannel == 9) {
                nextChannel = 10;
            }
            remappedChannels.emplace(program.channel, nextChannel++);
            SynthChannelProgram remapped = program;
            remapped.channel = remappedChannels.at(program.channel);
            sequence.channelPrograms.push_back(remapped);
        }
        int fallbackNoteCount = 0;
        for (SynthNoteEvent event : fallbackSynthEvents) {
            const auto remapped = remappedChannels.find(event.channel);
            if (remapped == remappedChannels.end()) {
                continue;
            }
            event.channel = remapped->second;
            fallbackNoteCount += event.kind == SynthNoteEvent::Kind::NoteOn ? 1 : 0;
            sequence.synthEvents.push_back(event);
        }

        std::string partCounts;
        for (const std::string& partId : fallbackParts) {
            const auto model = modelNotesByPart.find(partId);
            partCounts += " " + partId + ":" + std::to_string(model == modelNotesByPart.end() ? 0 : model->second)
                          + "/" + std::to_string(fallbackNotesByPart.at(partId));
        }
        std::cout << "MuseReader event playback extraction: using engraving fallback"
                  << " parts=" << fallbackParts.size() << " (model/fallback notes:" << partCounts << ")"
                  << " modelParts=" << modelNotesByPart.size()
                  << " invalidTracks=" << sequence.stats.invalidTrackCount
                  << " modelNotes=" << sequence.stats.noteEventCount
                  << " fallbackNotes=" << fallbackNoteCount
                  << " skippedTieBacks=" << fallbackStats.fallbackSkippedTieBackCount
                  << " start=" << startTimeSeconds
                  << " duration=" << durationSeconds
                  << std::endl;
        sequence.stats.noteEventCount += fallbackNoteCount;
        sequence.stats.usedEngravingFallback = true;
    }

    std::sort(sequence.synthEvents.begin(), sequence.synthEvents.end());
    return sequence;
}

struct FluidSettingsDeleter {
    void operator()(fluid_settings_t* settings) const
    {
        if (settings) {
            delete_fluid_settings(settings);
        }
    }
};

struct FluidSynthDeleter {
    void operator()(fluid_synth_t* synth) const
    {
        if (synth) {
            std::lock_guard<std::recursive_timed_mutex> lock(msr::render::fluidSynthLock());
            delete_fluid_synth(synth);
        }
    }
};

class FluidSynthPlaybackStream {
public:
    FluidSynthPlaybackStream(mu::engraving::Score* score,
                             std::string soundFontPath,
                             const std::optional<std::uint64_t> activePartId,
                             const bool metronomeEnabled,
                             const int revision)
        : m_score(score),
          m_soundFontPath(std::move(soundFontPath)),
          m_activePartId(activePartId),
          m_metronomeEnabled(metronomeEnabled),
          m_revision(revision)
    {
    }

    bool matches(mu::engraving::Score* score,
                 const std::string& soundFontPath,
                 const std::optional<std::uint64_t> activePartId,
                 const bool metronomeEnabled,
                 const int revision) const
    {
        return m_score == score
               && m_soundFontPath == soundFontPath
               && m_activePartId == activePartId
               && m_metronomeEnabled == metronomeEnabled
               && m_revision == revision;
    }

    bool canRenderFrom(const int startFrame) const
    {
        if (m_empty) {
            return true;
        }
        return startFrame + 2 >= m_currentFrame
               && startFrame <= m_currentFrame + kFluidSynthRenderBlockFrames;
    }

    bool initialize(mu::engraving::Score* score,
                    const muse::modularity::ContextPtr& context,
                    const int startFrame,
                    const double startTimeSeconds,
                    const double durationSeconds,
                    std::string& errorMessage)
    {
        m_sequence = makeFluidSynthPlaybackSequence(score, context, m_activePartId, m_metronomeEnabled, startTimeSeconds, durationSeconds);
        if (m_sequence.synthEvents.empty()) {
            m_empty = true;
            m_currentFrame = startFrame;
            m_lastEventFrame = startFrame;
            return true;
        }

        const int requiredMidiChannels = requiredMidiChannelCount(m_sequence.synthEvents, m_sequence.channelPrograms);
        if (requiredMidiChannels > 256) {
            errorMessage = "This score exceeds FluidSynth's 256 MIDI-channel limit.";
            return false;
        }
        // FluidSynth supports 256 MIDI channels but only 128 isolated output groups.
        // A second sampler avoids folding large-score channels onto another part.
        m_audioGroups = std::min(requiredMidiChannels, 128);
        m_settings.reset(new_fluid_settings());
        if (!m_settings) {
            errorMessage = "FluidSynth could not allocate settings.";
            return false;
        }

        fluid_settings_setnum(m_settings.get(), "synth.sample-rate", kFluidSynthSampleRate);
        fluid_settings_setnum(m_settings.get(), "synth.gain", 1.0);
        fluid_settings_setint(m_settings.get(), "synth.audio-channels", m_audioGroups);
        fluid_settings_setint(m_settings.get(), "synth.audio-groups", m_audioGroups);
        fluid_settings_setint(m_settings.get(), "synth.midi-channels", requiredMidiChannels);
        fluid_settings_setint(m_settings.get(), "synth.polyphony", 512);
        fluid_settings_setint(m_settings.get(), "synth.dynamic-sample-loading", 1);
        fluid_settings_setint(m_settings.get(), "synth.threadsafe-api", 0);
        fluid_settings_setint(m_settings.get(), "synth.lock-memory", 0);
        fluid_settings_setint(m_settings.get(), "synth.reverb.active", 0);
        fluid_settings_setint(m_settings.get(), "synth.chorus.active", 0);
        fluid_settings_setstr(m_settings.get(), "audio.sample-format", "float");

        m_synthCount = (requiredMidiChannels + m_audioGroups - 1) / m_audioGroups;
        m_lastEventFrame = m_sequence.synthEvents.back().frame + (kFluidSynthTailSeconds * kFluidSynthSampleRate);
        return positionAt(startFrame, errorMessage);
    }

    //! Moves the stream to a new position with fresh synths, reusing the event
    //! sequence. Fresh synths render exactly like an uninterrupted stream;
    //! fluid_synth_system_reset leaves small audible differences.
    bool positionAt(const int startFrame, std::string& errorMessage)
    {
        if (m_empty) {
            m_currentFrame = startFrame;
            return true;
        }

        std::lock_guard<std::recursive_timed_mutex> lock(msr::render::fluidSynthLock());
        m_synths.clear();
        for (int index = 0; index < m_synthCount; ++index) {
            std::unique_ptr<fluid_synth_t, FluidSynthDeleter> synth(new_fluid_synth(m_settings.get()));
            if (!synth) {
                errorMessage = "FluidSynth could not allocate the synthesizer.";
                return false;
            }
            if (fluid_synth_sfload(synth.get(), m_soundFontPath.c_str(), 1) == FLUID_FAILED) {
                errorMessage = "FluidSynth could not load the bundled SoundFont.";
                return false;
            }
            m_synths.push_back(std::move(synth));
        }

        for (const SynthChannelProgram& channelProgram : m_sequence.channelPrograms) {
            fluid_synth_bank_select(synthForChannel(channelProgram.channel), channelProgram.channel, channelProgram.program.bank);
            fluid_synth_program_change(synthForChannel(channelProgram.channel), channelProgram.channel, channelProgram.program.program);
        }

        const int prerollFrames = static_cast<int>(std::ceil(kFluidSynthChunkPrerollSeconds * kFluidSynthSampleRate));
        // Render blocks must sit on the absolute block grid that chunk ends are
        // aligned to. Otherwise every chunk overshoots its end, the next request
        // falls behind m_currentFrame, and the stream is rebuilt for each chunk.
        int renderStartFrame = std::max(0, startFrame - prerollFrames);
        renderStartFrame -= renderStartFrame % kFluidSynthRenderBlockFrames;
        const std::unordered_map<int, ActiveSynthNote> activeNotes
            = activeSynthNotesAtFrame(m_sequence.synthEvents, renderStartFrame, m_eventIndex);

        // Only the latest program, controller value and pitch bend per channel
        // matter at the render start. Replaying every earlier change would make
        // late seeks slower, and each program change can load samples.
        std::map<std::tuple<int, int, int>, size_t> latestStateEvents;
        for (size_t prerollEventIndex = 0; prerollEventIndex < m_eventIndex; ++prerollEventIndex) {
            const SynthNoteEvent& event = m_sequence.synthEvents[prerollEventIndex];
            if (event.kind == SynthNoteEvent::Kind::NoteOn || event.kind == SynthNoteEvent::Kind::NoteOff) {
                continue;
            }
            const int controller = event.kind == SynthNoteEvent::Kind::ControlChange ? event.controller : 0;
            latestStateEvents[{ event.channel, static_cast<int>(event.kind), controller }] = prerollEventIndex;
        }
        std::vector<size_t> stateEventIndexes;
        stateEventIndexes.reserve(latestStateEvents.size());
        for (const auto& pair : latestStateEvents) {
            stateEventIndexes.push_back(pair.second);
        }
        std::sort(stateEventIndexes.begin(), stateEventIndexes.end());
        for (const size_t index : stateEventIndexes) {
            applySynthEvent(m_sequence.synthEvents[index]);
        }

        for (const auto& pair : activeNotes) {
            const int channel = (pair.first >> 8) & 0xff;
            const int key = pair.first & 0xff;
            fluid_synth_noteon(synthForChannel(channel), channel, key, pair.second.velocity);
        }

        m_currentFrame = renderStartFrame;
        m_activeNotesAtRenderStart = static_cast<int>(activeNotes.size());
        return true;
    }

    bool render(const int requestedStartFrame,
                const double startTimeSeconds,
                const double durationSeconds,
                const bool streamReset,
                const SteadyClock::time_point started,
                msr::render::PlaybackAudioData& output,
                std::string& errorMessage,
                const bool includePartSamples,
                const msr::render::PlaybackMix* mix)
    {
        int startFrame = requestedStartFrame;
        if (m_currentFrame > startFrame && m_currentFrame - startFrame <= 2) {
            startFrame = m_currentFrame;
        }

        if (m_empty) {
            makeSilentPlaybackAudio(durationSeconds, output);
            if (includePartSamples) {
                for (const auto& program : m_sequence.channelPrograms) {
                    output.partSamples[program.partId].assign(output.interleavedSamples.size(), 0.0f);
                }
            }
            const int requestedFrames = durationSeconds > 0.0
                ? std::max(1, static_cast<int>(std::ceil(durationSeconds * kFluidSynthSampleRate)))
                : 1;
            m_currentFrame = std::max(m_currentFrame, startFrame + requestedFrames);
            logRender(startFrame, startFrame, 0, streamReset, started, output);
            return true;
        }

        const int requestedFrames = durationSeconds > 0.0
            ? std::max(1, static_cast<int>(std::ceil(durationSeconds * kFluidSynthSampleRate)))
            : std::max(1, m_lastEventFrame - startFrame);
        int endFrame = std::min(std::max(startFrame + requestedFrames, 1), m_lastEventFrame);
        if (endFrame < m_lastEventFrame) {
            endFrame = std::min(alignFrameUp(endFrame, kFluidSynthRenderBlockFrames), m_lastEventFrame);
        }

        if (startFrame >= endFrame) {
            makeSilentPlaybackAudio(durationSeconds, output);
            if (includePartSamples) {
                for (const auto& program : m_sequence.channelPrograms) {
                    output.partSamples[program.partId].assign(output.interleavedSamples.size(), 0.0f);
                }
            }
            std::cout << "MuseReader event playback render: silent tail chunk"
                      << " tracks=" << m_sequence.stats.trackCount
                      << " noteEvents=" << m_sequence.stats.noteEventCount
                      << " firstEventFrame=" << m_sequence.synthEvents.front().frame
                      << " lastEventFrame=" << m_sequence.synthEvents.back().frame
                      << " startFrame=" << startFrame
                      << " endFrame=" << endFrame
                      << " start=" << startTimeSeconds
                      << " duration=" << durationSeconds
                      << " persistent=" << (streamReset ? "reset" : "reuse")
                      << " build=" << elapsedSecondsSince(started)
                      << "s" << std::endl;
            return true;
        }

        if (startFrame < m_currentFrame) {
            errorMessage = "Persistent FluidSynth stream was asked to render before its current position.";
            return false;
        }

        std::vector<std::vector<float>> channels(m_audioGroups * m_synths.size() * 2,
            std::vector<float>(kFluidSynthRenderBlockFrames));
        std::vector<float*> channelPointers;
        for (auto& channel : channels) {
            channelPointers.push_back(channel.data());
        }
        output.partSamples.clear();
        const size_t sampleCount = static_cast<size_t>(std::max(endFrame - startFrame, 1) * 2);
        std::vector<std::pair<int, std::vector<float>*>> stemChannels;
        std::set<int> copiedChannels;
        if (includePartSamples) {
            for (const auto& program : m_sequence.channelPrograms) {
                if (!copiedChannels.insert(program.channel).second) { continue; }
                auto& stem = output.partSamples[program.partId];
                stem.resize(sampleCount, 0.0f);
                stemChannels.emplace_back(program.channel, &stem);
            }
        }
        // Gains are computed once per chunk. The fast export path never needs
        // per-part output buffers; sampler channels are balanced before summing.
        std::vector<std::pair<float, float>> gains;
        if (mix) {
            gains.assign(channels.size() / 2, { 1.0f, 1.0f });
            bool hasSolo = false;
            for (const auto& program : m_sequence.channelPrograms) {
                const auto setting = mix->find(program.partId);
                hasSolo = hasSolo || (program.partId != "metronome" && setting != mix->end() && setting->second.solo);
            }
            for (const auto& program : m_sequence.channelPrograms) {
                if (program.partId == "metronome") { continue; }
                const auto setting = mix->find(program.partId);
                const msr::render::PlaybackPartMix part = setting == mix->end()
                    ? msr::render::PlaybackPartMix {} : setting->second;
                const float volume = part.muted || (hasSolo && !part.solo) ? 0.0f : std::clamp(part.volume, 0.0f, 1.0f);
                const float pan = std::clamp(part.pan, -1.0f, 1.0f);
                gains.at(static_cast<size_t>(program.channel)) = {
                    volume * (pan > 0.0f ? 1.0f - pan : 1.0f),
                    volume * (pan < 0.0f ? 1.0f + pan : 1.0f)
                };
            }
        }
        std::vector<float> samples;
        samples.reserve(static_cast<size_t>(std::max(endFrame - startFrame, 1) * kFluidSynthChannelCount));

        while (m_currentFrame < endFrame) {
            // Per block, so the live preview synth's audio callback waits at most one block.
            msr::render::yieldFluidSynthLockToRealtime();
            std::unique_lock<std::recursive_timed_mutex> lock(msr::render::fluidSynthLock());
            while (m_eventIndex < m_sequence.synthEvents.size() && m_sequence.synthEvents[m_eventIndex].frame <= m_currentFrame) {
                const SynthNoteEvent& event = m_sequence.synthEvents[m_eventIndex];
                applySynthEvent(event);
                m_eventIndex += 1;
            }

            for (auto& channel : channels) {
                std::fill(channel.begin(), channel.end(), 0.0f);
            }
            for (size_t index = 0; index < m_synths.size(); ++index) {
                if (fluid_synth_process(m_synths[index].get(), kFluidSynthRenderBlockFrames,
                                        0, nullptr, m_audioGroups * 2,
                                        channelPointers.data() + index * m_audioGroups * 2) != FLUID_OK) {
                    errorMessage = "FluidSynth failed while rendering MuseScore playback events.";
                    return false;
                }
            }
            lock.unlock();

            const int blockStartFrame = m_currentFrame;
            const int blockEndFrame = m_currentFrame + kFluidSynthRenderBlockFrames;
            const int copyStartFrame = std::max(startFrame, blockStartFrame);
            const int copyEndFrame = std::min(endFrame, blockEndFrame);
            if (copyStartFrame < copyEndFrame) {
                for (int absoluteFrame = copyStartFrame; absoluteFrame < copyEndFrame; ++absoluteFrame) {
                    const int blockFrame = absoluteFrame - blockStartFrame;
                    float left = 0.0f;
                    float right = 0.0f;
                    const size_t sample = static_cast<size_t>(absoluteFrame - startFrame) * 2;
                    // One program entry per sampler channel; layers sharing a part sum here.
                    if (mix) {
                        for (size_t channel = 0; channel < channels.size() / 2; ++channel) {
                            left += channels[channel * 2][blockFrame] * gains[channel].first;
                            right += channels[channel * 2 + 1][blockFrame] * gains[channel].second;
                        }
                    } else {
                        for (size_t channel = 0; channel < channels.size() / 2; ++channel) {
                            left += channels[channel * 2][blockFrame];
                            right += channels[channel * 2 + 1][blockFrame];
                        }
                    }
                    samples.push_back(left);
                    samples.push_back(right);
                    for (const auto& route : stemChannels) {
                        const float routeLeft = channels[route.first * 2][blockFrame];
                        const float routeRight = channels[route.first * 2 + 1][blockFrame];
                        (*route.second)[sample] += routeLeft;
                        (*route.second)[sample + 1] += routeRight;
                    }
                }
            }

            m_currentFrame = blockEndFrame;
        }

        if (samples.empty()) {
            errorMessage = "FluidSynth rendered no audio samples from MuseScore playback events.";
            return false;
        }

        output.sampleRate = kFluidSynthSampleRate;
        output.channelCount = kFluidSynthChannelCount;
        output.durationSeconds = static_cast<double>(samples.size() / kFluidSynthChannelCount) / static_cast<double>(kFluidSynthSampleRate);
        output.interleavedSamples = std::move(samples);

        logRender(startFrame, endFrame, output.interleavedSamples.size() / kFluidSynthChannelCount, streamReset, started, output);
        return true;
    }

private:
    int m_audioGroups = 16;
    int m_synthCount = 1;

    fluid_synth_t* synthForChannel(const int channel) const
    {
        return m_synths.at(static_cast<size_t>(channel / m_audioGroups)).get();
    }

    void applySynthEvent(const SynthNoteEvent& event)
    {
        switch (event.kind) {
        case SynthNoteEvent::Kind::ProgramChange:
            fluid_synth_bank_select(synthForChannel(event.channel), event.channel, event.program.bank);
            fluid_synth_program_change(synthForChannel(event.channel), event.channel, event.program.program);
            break;
        case SynthNoteEvent::Kind::ControlChange:
            fluid_synth_cc(synthForChannel(event.channel), event.channel, event.controller, event.value);
            break;
        case SynthNoteEvent::Kind::PitchBend:
            fluid_synth_pitch_bend(synthForChannel(event.channel), event.channel, event.value);
            break;
        case SynthNoteEvent::Kind::NoteOn:
            fluid_synth_noteon(synthForChannel(event.channel), event.channel, event.key, event.velocity);
            break;
        case SynthNoteEvent::Kind::NoteOff:
            fluid_synth_noteoff(synthForChannel(event.channel), event.channel, event.key);
            break;
        }
    }

    void logRender(const int startFrame,
                   const int endFrame,
                   const size_t copiedFrames,
                   const bool streamReset,
                   const SteadyClock::time_point started,
                   const msr::render::PlaybackAudioData& output) const
    {
        if (!streamReset) {
            return;
        }

        if (m_sequence.synthEvents.empty()) {
            std::cout << "MuseReader event playback render: silent chunk, playback model note events=0"
                      << " tracks=" << m_sequence.stats.trackCount
                      << " invalidTracks=" << m_sequence.stats.invalidTrackCount
                      << " modelTimestamps=" << m_sequence.stats.playbackModelTimestampCount
                      << " modelEvents=" << m_sequence.stats.playbackModelEventCount
                      << " soundPresets=" << m_sequence.stats.soundPresetEventCount
                      << " textArticulations=" << m_sequence.stats.textArticulationEventCount
                      << " controllers=" << m_sequence.stats.controllerEventCount
                      << " fallbackRepeats=" << m_sequence.stats.fallbackRepeatSegmentCount
                      << " fallbackChords=" << m_sequence.stats.fallbackChordCount
                      << " fallbackNotes=" << m_sequence.stats.fallbackPlayableNoteCount
                      << " fallbackHarmonies=" << m_sequence.stats.fallbackHarmonyCount
                      << " fallbackHarmonyNotes=" << m_sequence.stats.fallbackHarmonyPlayableNoteCount
                      << " persistent=" << (streamReset ? "reset" : "reuse")
                      << " build=" << elapsedSecondsSince(started)
                      << "s" << std::endl;
            return;
        }

        std::cout << "MuseReader event playback render: tracks="
                  << m_sequence.stats.trackCount
                  << " invalidTracks=" << m_sequence.stats.invalidTrackCount
                  << " modelTimestamps=" << m_sequence.stats.playbackModelTimestampCount
                  << " modelEvents=" << m_sequence.stats.playbackModelEventCount
                  << " noteEvents=" << m_sequence.stats.noteEventCount
                  << " synthEvents=" << m_sequence.synthEvents.size()
                  << " fallback=" << (m_sequence.stats.usedEngravingFallback ? "engraving" : "playbackModel")
                  << " firstEventFrame=" << m_sequence.synthEvents.front().frame
                  << " lastEventFrame=" << m_sequence.synthEvents.back().frame
                  << " startFrame=" << startFrame
                  << " endFrame=" << endFrame
                  << " activeNotesAtRenderStart=" << m_activeNotesAtRenderStart
                  << " copiedFrames=" << copiedFrames
                  << " outputDuration=" << output.durationSeconds
                  << " persistent=" << (streamReset ? "reset" : "reuse")
                  << " currentFrame=" << m_currentFrame
                  << " build=" << elapsedSecondsSince(started)
                  << "s" << std::endl;

        for (const auto& layerPair : m_sequence.stats.layerDebug) {
            const EventExtractionStats::LayerDebugStats& layerStats = layerPair.second;
            const double averageVelocity = layerStats.noteCount > 0
                ? static_cast<double>(layerStats.velocitySum) / static_cast<double>(layerStats.noteCount)
                : 0.0;
            std::cout << "MuseReader event playback layer dynamics: layer="
                      << static_cast<int>(layerPair.first)
                      << " channel=" << layerStats.channel
                      << " setup=" << layerStats.setup
                      << " dynamicCC=" << (layerStats.useDynamicEvents ? "on" : "off")
                      << " dynamicEvents=" << layerStats.dynamicControllerCount
                      << " notes=" << layerStats.noteCount
                      << " velocityMin=" << (layerStats.noteCount > 0 ? layerStats.velocityMin : 0)
                      << " velocityMax=" << (layerStats.noteCount > 0 ? layerStats.velocityMax : 0)
                      << " velocityAvg=" << averageVelocity
                      << " nominalMin=" << (layerStats.noteCount > 0 ? layerStats.nominalMin : 0)
                      << " nominalMax=" << (layerStats.noteCount > 0 ? layerStats.nominalMax : 0)
                      << " curveNotes=" << layerStats.notesWithExpressionCurve
                      << " curveMin="
                      << (layerStats.notesWithExpressionCurve > 0 ? layerStats.expressionCurveMin : 0)
                      << " curveMax="
                      << (layerStats.notesWithExpressionCurve > 0 ? layerStats.expressionCurveMax : 0)
                      << " velocityOverrides=" << layerStats.notesWithVelocityOverride
                      << std::endl;
        }
    }

    mu::engraving::Score* m_score = nullptr;
    std::string m_soundFontPath;
    std::optional<std::uint64_t> m_activePartId;
    bool m_metronomeEnabled = false;
    int m_revision = 0;
    bool m_empty = false;
    FluidSynthPlaybackSequence m_sequence;
    std::unique_ptr<fluid_settings_t, FluidSettingsDeleter> m_settings;
    std::vector<std::unique_ptr<fluid_synth_t, FluidSynthDeleter>> m_synths;
    size_t m_eventIndex = 0;
    int m_currentFrame = 0;
    int m_lastEventFrame = 0;
    int m_activeNotesAtRenderStart = 0;
};

//! The pitched notes of the playback sequence the audio is rendered from, so
//! their times match the sound through repeats, pauses, fermatas and tempo.
bool collectFluidSynthPlaybackNotes(mu::engraving::Score* score,
                                    const muse::modularity::ContextPtr& context,
                                    const std::optional<std::uint64_t> activePartId,
                                    std::vector<msr::render::PlaybackNote>& output,
                                    std::string& errorMessage)
{
    output.clear();
    if (!score) {
        errorMessage = "Playback is unavailable because the score session is closed.";
        return false;
    }
    const FluidSynthPlaybackSequence sequence = makeFluidSynthPlaybackSequence(score, context, activePartId, false, 0.0, 0.0);

    // Each channel is one staff and voice of a part; the first program wins,
    // as it does for the per-part stems.
    struct ChannelStaff {
        std::string partId;
        size_t staffLayer = 0;
    };
    std::unordered_map<int, ChannelStaff> staffByChannel;
    for (const SynthChannelProgram& program : sequence.channelPrograms) {
        const bool percussion = program.program.bank == 128 || program.setup.rfind("percussion", 0) == 0;
        if (program.partId == "metronome" || percussion || staffByChannel.count(program.channel)) {
            if (!staffByChannel.count(program.channel)) {
                staffByChannel.emplace(program.channel, ChannelStaff {});
            }
            continue;
        }
        staffByChannel.emplace(program.channel, ChannelStaff { program.partId, program.layerIdx / muse::mpe::MAX_VOICES });
    }

    // Staves numbered in score order: by part, then by staff within it.
    std::map<std::string, size_t> partOrder;
    for (size_t index = 0; index < score->parts().size(); ++index) {
        if (const mu::engraving::Part* part = score->parts().at(index)) {
            partOrder.emplace(std::to_string(part->id().toUint64()), index);
        }
    }
    std::set<std::pair<size_t, size_t>> staves;
    for (const auto& [channel, staff] : staffByChannel) {
        if (!staff.partId.empty()) {
            const auto order = partOrder.find(staff.partId);
            staves.insert({ order == partOrder.end() ? partOrder.size() : order->second, staff.staffLayer });
        }
    }
    std::map<std::pair<size_t, size_t>, int> staffIndexes;
    for (const auto& staff : staves) {
        staffIndexes.emplace(staff, static_cast<int>(staffIndexes.size()));
    }

    // Events are sorted by frame with note-offs first, so a repeated key
    // releases before it sounds again.
    std::map<std::pair<int, int>, std::deque<int>> sounding;
    for (const SynthNoteEvent& event : sequence.synthEvents) {
        if (event.kind != SynthNoteEvent::Kind::NoteOn && event.kind != SynthNoteEvent::Kind::NoteOff) {
            continue;
        }
        const auto staff = staffByChannel.find(event.channel);
        if (staff == staffByChannel.end() || staff->second.partId.empty()) {
            continue;
        }
        auto& starts = sounding[{ event.channel, event.key }];
        if (event.kind == SynthNoteEvent::Kind::NoteOn) {
            starts.push_back(event.frame);
            continue;
        }
        if (starts.empty()) {
            continue;
        }
        const int startFrame = starts.front();
        starts.pop_front();
        const auto order = partOrder.find(staff->second.partId);
        const std::pair<size_t, size_t> key {
            order == partOrder.end() ? partOrder.size() : order->second, staff->second.staffLayer
        };
        output.push_back({
            event.key,
            static_cast<double>(startFrame) / kFluidSynthSampleRate,
            static_cast<double>(std::max(event.frame, startFrame + 1)) / kFluidSynthSampleRate,
            staffIndexes[key],
            staff->second.partId
        });
    }
    std::stable_sort(output.begin(), output.end(), [](const msr::render::PlaybackNote& a, const msr::render::PlaybackNote& b) {
        return a.startTimeSeconds != b.startTimeSeconds ? a.startTimeSeconds < b.startTimeSeconds : a.pitch < b.pitch;
    });
    return true;
}

bool renderFluidSynthPlaybackEvents(mu::engraving::Score* score,
                                    const muse::modularity::ContextPtr& context,
                                    const std::string& soundFontPath,
                                    const std::optional<std::uint64_t> activePartId,
                                    const double startTimeSeconds,
                                    const double durationSeconds,
                                    const bool metronomeEnabled,
                                    const int playbackRevision,
                                    std::unique_ptr<FluidSynthPlaybackStream>& playbackStream,
                                    msr::render::PlaybackAudioData& output,
                                    std::string& errorMessage,
                                    const bool includePartSamples,
                const msr::render::PlaybackMix* mix)
{
    if (!score) {
        errorMessage = "Playback is unavailable because the score session is closed.";
        return false;
    }
    if (soundFontPath.empty()) {
        errorMessage = "FluidSynth playback needs a SoundFont path.";
        return false;
    }

    const SteadyClock::time_point started = SteadyClock::now();
    const int startFrame = frameForSeconds(startTimeSeconds);
    bool streamReset = false;
    if (playbackStream
        && playbackStream->matches(score, soundFontPath, activePartId, metronomeEnabled, playbackRevision)
        && !playbackStream->canRenderFrom(startFrame)) {
        // Seek within an unchanged score: reuse the event sequence.
        streamReset = true;
        if (!playbackStream->positionAt(startFrame, errorMessage)) {
            playbackStream.reset();
            return false;
        }
    } else if (!playbackStream
               || !playbackStream->matches(score, soundFontPath, activePartId, metronomeEnabled, playbackRevision)) {
        playbackStream = std::make_unique<FluidSynthPlaybackStream>(
            score,
            soundFontPath,
            activePartId,
            metronomeEnabled,
            playbackRevision
        );
        streamReset = true;
        if (!playbackStream->initialize(score, context, startFrame, startTimeSeconds, durationSeconds, errorMessage)) {
            playbackStream.reset();
            return false;
        }
    }

    return playbackStream->render(startFrame, startTimeSeconds, durationSeconds, streamReset, started, output, errorMessage, includePartSamples, mix);
}

//! Renders MuseScore's count-in for playback starting at `startTimeSeconds`:
//! the clicks desktop plays before playback, voiced like the metronome track.
//! Starting mid-bar or on a pickup adds clicks so the last one leads into the
//! start position, as on desktop.
bool renderFluidSynthCountIn(mu::engraving::Score* score,
                             const muse::modularity::ContextPtr& context,
                             const std::string& soundFontPath,
                             const double startTimeSeconds,
                             msr::render::PlaybackCountIn& output,
                             std::string& errorMessage)
{
    output = {};
    if (!score) {
        errorMessage = "Playback is unavailable because the score session is closed.";
        return false;
    }
    if (soundFontPath.empty()) {
        errorMessage = "FluidSynth playback needs a SoundFont path.";
        return false;
    }

    const auto& repeatList = score->repeatList(true);
    const int startTick = repeatList.utick2tick(repeatList.utime2utick(std::max(startTimeSeconds, 0.0)));

    // PlaybackModel only supplies the injected articulation profiles here.
    mu::engraving::PlaybackModel profileSource(context);
    const auto profiles = profileSource.profilesRepository();
    const muse::mpe::ArticulationsProfilePtr profile = profiles
        ? profiles->defaultProfile(muse::mpe::SoundCategory::Percussions)
        : nullptr;
    if (!profile) {
        errorMessage = "The metronome articulation profile is unavailable.";
        return false;
    }

    muse::mpe::PlaybackEventsMap events;
    muse::mpe::duration_t countInDuration = 0;
    mu::engraving::PlaybackEventsRenderer().renderCountIn(score, startTick, 0, profile, events, countInDuration);
    if (events.empty() || countInDuration <= 0) {
        return true;
    }

    // The same beat grid renderCountIn uses, to number the clicks.
    const mu::engraving::Measure* measure = score->tick2measure(mu::engraving::Fraction::fromTicks(startTick));
    const int measureStartTick = measure ? measure->tick().ticks() : 0;
    const mu::engraving::TimeSigFrac timeSig = score->sigmap()->timesig(measureStartTick).nominal();
    const double bps = score->tempomap()->multipliedTempo(measureStartTick).val;
    const int stepTicks = std::max(1, timeSig.isBeatedCompound(bps) ? timeSig.beatTicks() : timeSig.dUnitTicks());
    const int beatsPerBar = std::max(1, timeSig.ticksPerMeasure() / stepTicks);
    const double stepSeconds = static_cast<double>(mu::engraving::durationFromTempoAndTicks(bps, stepTicks)) / 1000000.0;

    muse::mpe::PlaybackSetupData setupData;
    mu::engraving::PlaybackSetupDataResolver().resolveMetronomeSetupData(setupData);
    const muse::midi::Program program = midiProgramForSetup(setupData);
    const bool useDynamicEvents = setupData.supportsSingleNoteDynamics;
    constexpr int metronomeChannel = 9;

    std::vector<SynthNoteEvent> synthEvents;
    for (const auto& pair : events) {
        for (const muse::mpe::PlaybackEvent& event : pair.second) {
            if (!std::holds_alternative<muse::mpe::NoteEvent>(event)) {
                continue;
            }
            const muse::mpe::NoteEvent& noteEvent = std::get<muse::mpe::NoteEvent>(event);
            const muse::mpe::ArrangementContext& arrangement = noteEvent.arrangementCtx();
            const int startFrame = frameForMpeTimestamp(arrangement.actualTimestamp);
            const int durationFrames = std::max(1, static_cast<int>(std::llround(
                (static_cast<double>(arrangement.actualDuration) / 1000000.0) * kFluidSynthSampleRate
            )));
            const int key = std::clamp(
                static_cast<int>(std::llround(static_cast<double>(noteEvent.pitchCtx().nominalPitchLevel) / muse::mpe::PITCH_LEVEL_STEP))
                + muse::mpe::ZERO_PITCH_LEVEL_MIDI_EQUIVALENT,
                0,
                127
            );
            const int velocity = velocityForNoteEvent(noteEvent, useDynamicEvents, false);
            synthEvents.push_back(makeNoteSynthEvent(startFrame, metronomeChannel, key, velocity, true));
            synthEvents.push_back(makeNoteSynthEvent(startFrame + durationFrames, metronomeChannel, key, 0, false));

            msr::render::PlaybackCountInClick click;
            click.timeSeconds = static_cast<double>(arrangement.actualTimestamp) / 1000000.0;
            const int beatIndex = stepSeconds > 0.0 ? static_cast<int>(std::llround(click.timeSeconds / stepSeconds)) : 0;
            click.beatNumber = beatIndex % beatsPerBar + 1;
            click.isDownbeat = click.beatNumber == 1;
            output.clicks.push_back(click);
        }
    }
    std::sort(synthEvents.begin(), synthEvents.end());

    // A count-in is a few seconds of one channel, so hold the lock for all of it.
    std::lock_guard<std::recursive_timed_mutex> lock(msr::render::fluidSynthLock());
    std::unique_ptr<fluid_settings_t, FluidSettingsDeleter> settings(new_fluid_settings());
    if (!settings) {
        errorMessage = "FluidSynth could not allocate settings.";
        return false;
    }
    fluid_settings_setnum(settings.get(), "synth.sample-rate", kFluidSynthSampleRate);
    fluid_settings_setnum(settings.get(), "synth.gain", 1.0);
    fluid_settings_setint(settings.get(), "synth.dynamic-sample-loading", 1);
    fluid_settings_setint(settings.get(), "synth.threadsafe-api", 0);
    fluid_settings_setint(settings.get(), "synth.lock-memory", 0);
    fluid_settings_setint(settings.get(), "synth.reverb.active", 0);
    fluid_settings_setint(settings.get(), "synth.chorus.active", 0);
    std::unique_ptr<fluid_synth_t, FluidSynthDeleter> synth(new_fluid_synth(settings.get()));
    if (!synth) {
        errorMessage = "FluidSynth could not allocate the synthesizer.";
        return false;
    }
    if (fluid_synth_sfload(synth.get(), soundFontPath.c_str(), 1) == FLUID_FAILED) {
        errorMessage = "FluidSynth could not load the bundled SoundFont.";
        return false;
    }
    fluid_synth_bank_select(synth.get(), metronomeChannel, program.bank);
    fluid_synth_program_change(synth.get(), metronomeChannel, program.program);
    if (useDynamicEvents) {
        fluid_synth_cc(synth.get(), metronomeChannel, 11, expressionLevelForDynamicLevel(
            muse::mpe::dynamicLevelFromType(muse::mpe::DynamicType::Natural)
        ));
    }

    // Render to each event exactly, so the clicks keep the beat to the sample.
    // The buffer runs past the count-in so the last click rings out under the score.
    const int countInFrames = frameForMpeTimestamp(countInDuration);
    const int totalFrames = std::max(countInFrames, synthEvents.back().frame) + kFluidSynthSampleRate / 2;
    std::vector<float> samples(static_cast<size_t>(totalFrames) * kFluidSynthChannelCount, 0.0f);
    int currentFrame = 0;
    auto renderUntil = [&](const int frame) {
        const int endFrame = std::min(frame, totalFrames);
        while (currentFrame < endFrame) {
            const int count = std::min(endFrame - currentFrame, kFluidSynthRenderBlockFrames);
            float* block = samples.data() + static_cast<size_t>(currentFrame) * kFluidSynthChannelCount;
            if (fluid_synth_write_float(synth.get(), count, block, 0, 2, block, 1, 2) != FLUID_OK) {
                return false;
            }
            currentFrame += count;
        }
        return true;
    };
    for (const SynthNoteEvent& event : synthEvents) {
        if (!renderUntil(event.frame)) {
            errorMessage = "FluidSynth failed while rendering the count-in.";
            return false;
        }
        if (event.kind == SynthNoteEvent::Kind::NoteOn) {
            fluid_synth_noteon(synth.get(), event.channel, event.key, event.velocity);
        } else if (event.kind == SynthNoteEvent::Kind::NoteOff) {
            fluid_synth_noteoff(synth.get(), event.channel, event.key);
        }
    }
    if (!renderUntil(totalFrames)) {
        errorMessage = "FluidSynth failed while rendering the count-in.";
        return false;
    }

    output.durationSeconds = static_cast<double>(countInFrames) / kFluidSynthSampleRate;
    output.audio.sampleRate = kFluidSynthSampleRate;
    output.audio.channelCount = kFluidSynthChannelCount;
    output.audio.durationSeconds = static_cast<double>(totalFrames) / kFluidSynthSampleRate;
    output.audio.interleavedSamples = std::move(samples);
    std::cout << "MuseReader count-in render: start=" << startTimeSeconds
              << " tick=" << startTick
              << " clicks=" << output.clicks.size()
              << " duration=" << output.durationSeconds
              << "s" << std::endl;
    return true;
}

void logSaveScoreState(mu::engraving::MasterScore* score, const char* phase)
{
    if (!score) {
        std::cout << "Aria save debug: " << phase << " score=null" << std::endl;
        return;
    }

    std::cout << "Aria save debug: " << phase
              << " pages=" << score->npages()
              << " parts=" << score->parts().size()
              << " excerpts=" << score->excerpts().size()
              << " harmonies=" << harmonyCountInScore(score)
              << " midiMappings=" << score->midiMapping().size()
              << " playbackScore=\"" << corruptionScoreLabel(score->playbackScore()) << "\""
              << std::endl;

    int partIndex = 0;
    for (mu::engraving::Part* part : score->parts()) {
        std::cout << "Aria save debug: " << phase
                  << " part[" << partIndex << "]"
                  << " ptr=" << part
                  << " id=" << (part ? part->id().toUint64() : 0)
                  << " instruments=" << (part ? part->instruments().size() : 0)
                  << std::endl;
        if (!part) {
            ++partIndex;
            continue;
        }

        for (const auto& instrumentPair : part->instruments()) {
            const mu::engraving::Instrument* instrument = instrumentPair.second;
            std::cout << "Aria save debug: " << phase
                      << " part[" << partIndex << "]"
                      << " instrumentTick=" << instrumentPair.first
                      << " instrument=" << instrument
                      << " id=\"" << (instrument ? instrument->id().toStdString() : std::string("null")) << "\""
                      << " channels=" << (instrument ? instrument->channel().size() : 0)
                      << std::endl;
            if (!instrument) {
                continue;
            }

            int channelIndex = 0;
            for (const mu::engraving::InstrChannel* channel : instrument->channel()) {
                const int mappedIndex = channel ? channel->channel() : -999;
                const bool validMappedIndex = mappedIndex >= 0 && mappedIndex < static_cast<int>(score->midiMapping().size());
                const mu::engraving::InstrChannel* playbackChannel = validMappedIndex ? score->midiMapping().at(static_cast<size_t>(mappedIndex)).articulation() : nullptr;
                std::cout << "Aria save debug: " << phase
                          << " part[" << partIndex << "]"
                          << " channel[" << channelIndex << "]"
                          << " ptr=" << channel
                          << " mappedIndex=" << mappedIndex
                          << " validMappedIndex=" << (validMappedIndex ? "true" : "false")
                          << " playbackChannel=" << playbackChannel
                          << " name=\"" << (channel ? channel->name().toStdString() : std::string("null")) << "\""
                          << std::endl;
                ++channelIndex;
            }
        }
        ++partIndex;
    }

    int excerptIndex = 0;
    for (mu::engraving::Excerpt* excerpt : score->excerpts()) {
        mu::engraving::Score* excerptScore = excerpt ? excerpt->excerptScore() : nullptr;
        std::cout << "Aria save debug: " << phase
                  << " excerpt[" << excerptIndex << "]"
                  << " ptr=" << excerpt
                  << " score=" << excerptScore
                  << " label=\"" << corruptionScoreLabel(excerptScore) << "\""
                  << " parts=" << (excerptScore ? excerptScore->parts().size() : 0)
                  << " harmonies=" << harmonyCountInScore(excerptScore)
                  << std::endl;
        ++excerptIndex;
    }
}

bool writeScoreToBufferSequentially(mu::engraving::Score* score,
                                    muse::ByteArray& outputData,
                                    mu::engraving::rw::WriteInOutData& writeData,
                                    const char* label,
                                    std::string& errorMessage)
{
    outputData.clear();
    muse::io::Buffer scoreBuffer(&outputData);
    scoreBuffer.open(muse::io::IODevice::ReadWrite);
    const auto startedAt = SteadyClock::now();
    std::cout << "Aria save debug: sequential writeScore begin"
              << " label=\"" << label << "\""
              << " score=\"" << corruptionScoreLabel(score) << "\""
              << std::endl;
    if (!mu::engraving::rw::RWRegister::writer(score->iocContext())->writeScore(score, &scoreBuffer, &writeData)) {
        errorMessage = std::string("The MuseScore writer could not serialize ") + label + ".";
        std::cout << "Aria save debug: sequential writeScore failed"
                  << " label=\"" << label << "\""
                  << " elapsed=" << elapsedSecondsSince(startedAt) << "s"
                  << std::endl;
        return false;
    }
    std::cout << "Aria save debug: sequential writeScore end"
              << " label=\"" << label << "\""
              << " bytes=" << outputData.size()
              << " elapsed=" << elapsedSecondsSince(startedAt) << "s"
              << std::endl;
    return true;
}

struct PreservedExcerptPackageResources {
    muse::String fileName;
    muse::ByteArray audioSettings;
    muse::ByteArray viewSettings;
};

struct PreservedMsczResources {
    muse::ByteArray thumbnail;
    muse::ByteArray audioSettings;
    muse::ByteArray viewSettings;
    muse::ByteArray automation;
    std::vector<PreservedExcerptPackageResources> excerpts;
};

bool readPreservedMsczResources(const muse::io::path_t& sourcePath,
                                PreservedMsczResources& resources,
                                std::string& errorMessage)
{
    if (mu::engraving::mscIoModeBySuffix(normalizedSuffix(sourcePath)) != mu::engraving::MscIoMode::Zip) {
        return true;
    }

    mu::engraving::MscReader::Params params;
    params.filePath = sourcePath;
    params.mode = mu::engraving::MscIoMode::Zip;

    mu::engraving::MscReader reader(params);
    const muse::Ret openResult = reader.open();
    if (!openResult) {
        errorMessage = openResult.text().empty()
            ? "MuseReader could not reopen the original score package to preserve its resources."
            : "MuseReader could not reopen the original score package to preserve its resources: " + openResult.text();
        return false;
    }

    resources.thumbnail = reader.readThumbnailFile();
    resources.audioSettings = reader.readAudioSettingsJsonFile();
    resources.viewSettings = reader.readViewSettingsJsonFile();
    resources.automation = reader.readAutomationJsonFile();

    for (const muse::String& excerptFileName : reader.excerptFileNames()) {
        const muse::io::path_t pathPrefix = u"Excerpts/" + excerptFileName + u"/";
        PreservedExcerptPackageResources excerptResources;
        excerptResources.fileName = excerptFileName;
        excerptResources.audioSettings = reader.readAudioSettingsJsonFile(pathPrefix);
        excerptResources.viewSettings = reader.readViewSettingsJsonFile(pathPrefix);
        if (!excerptResources.audioSettings.empty() || !excerptResources.viewSettings.empty()) {
            resources.excerpts.push_back(std::move(excerptResources));
        }
    }

    reader.close();
    return true;
}

bool writeMsczSequentially(mu::engraving::MasterScore* score,
                           mu::engraving::MscWriter& writer,
                           const PreservedMsczResources& preservedResources,
                           std::string& errorMessage)
{
    if (!score || !writer.isOpened()) {
        errorMessage = "The MuseScore writer is not ready.";
        return false;
    }

    const auto packageStartedAt = SteadyClock::now();
    std::cout << "Aria save debug: sequential package write begin" << std::endl;

    {
        const auto styleStartedAt = SteadyClock::now();
        muse::ByteArray styleData;
        muse::io::Buffer styleBuffer(&styleData);
        styleBuffer.open(muse::io::IODevice::WriteOnly);
        score->style().write(&styleBuffer);
        writer.writeStyleFile(styleData);
        std::cout << "Aria save debug: sequential master style bytes=" << styleData.size()
                  << " elapsed=" << elapsedSecondsSince(styleStartedAt) << "s"
                  << std::endl;
    }

    mu::engraving::rw::WriteInOutData masterWriteData(score);
    {
        muse::ByteArray scoreData;
        if (!writeScoreToBufferSequentially(score, scoreData, masterWriteData, "master score", errorMessage)) {
            return false;
        }
        writer.writeScoreFile(scoreData);
    }

    std::vector<muse::String> writtenExcerptFileNames;
    const std::vector<mu::engraving::Excerpt*>& excerpts = score->excerpts();
    for (size_t excerptIndex = 0; excerptIndex < excerpts.size(); ++excerptIndex) {
        mu::engraving::Excerpt* excerpt = excerpts.at(excerptIndex);
        mu::engraving::Score* partScore = excerpt ? excerpt->excerptScore() : nullptr;
        if (!excerpt || !partScore || partScore == score) {
            std::cout << "Aria save debug: sequential excerpt skipped"
                      << " index=" << excerptIndex
                      << " excerpt=" << excerpt
                      << " score=" << partScore
                      << std::endl;
            continue;
        }

        excerpt->updateFileName(excerptIndex);
        const auto excerptStartedAt = SteadyClock::now();
        std::cout << "Aria save debug: sequential excerpt begin"
                  << " index=" << excerptIndex
                  << " file=\"" << excerpt->fileName().toStdString() << "\""
                  << " score=\"" << corruptionScoreLabel(partScore) << "\""
                  << std::endl;

        const auto styleStartedAt = SteadyClock::now();
        muse::ByteArray styleData;
        muse::io::Buffer styleBuffer(&styleData);
        styleBuffer.open(muse::io::IODevice::WriteOnly);
        partScore->style().write(&styleBuffer);
        const double styleElapsed = elapsedSecondsSince(styleStartedAt);

        mu::engraving::rw::WriteInOutData writeData = masterWriteData;
        muse::ByteArray scoreData;
        if (!writeScoreToBufferSequentially(partScore, scoreData, writeData, "excerpt score", errorMessage)) {
            return false;
        }

        writer.addExcerptStyleFile(excerpt->fileName(), styleData);
        writer.addExcerptFile(excerpt->fileName(), scoreData);
        writtenExcerptFileNames.push_back(excerpt->fileName());
        std::cout << "Aria save debug: sequential excerpt end"
                  << " index=" << excerptIndex
                  << " styleBytes=" << styleData.size()
                  << " scoreBytes=" << scoreData.size()
                  << " styleElapsed=" << styleElapsed << "s"
                  << " elapsed=" << elapsedSecondsSince(excerptStartedAt) << "s"
                  << std::endl;
    }

    if (mu::engraving::ChordList* chordList = score->chordList()) {
        if (chordList->customChordList() && !chordList->empty()) {
            const auto chordListStartedAt = SteadyClock::now();
            muse::ByteArray chordListData;
            muse::io::Buffer chordListBuffer(&chordListData);
            chordListBuffer.open(muse::io::IODevice::WriteOnly);
            chordList->write(&chordListBuffer);
            writer.writeChordListFile(chordListData);
            std::cout << "Aria save debug: sequential chord list bytes=" << chordListData.size()
                      << " elapsed=" << elapsedSecondsSince(chordListStartedAt) << "s"
                      << std::endl;
        }
    }

    const auto imagesStartedAt = SteadyClock::now();
    int imageCount = 0;
    for (mu::engraving::ImageStoreItem* item : mu::engraving::imageStore) {
        if (!item || !item->isUsed(score)) {
            continue;
        }

        writer.addImageFile(muse::String::fromStdString(item->hashName()), item->buffer());
        ++imageCount;
    }
    std::cout << "Aria save debug: sequential images=" << imageCount
              << " elapsed=" << elapsedSecondsSince(imagesStartedAt) << "s"
              << std::endl;

    int preservedResourceCount = 0;
    if (!preservedResources.thumbnail.empty()) {
        writer.writeThumbnailFile(preservedResources.thumbnail);
        ++preservedResourceCount;
    }
    const mu::engraving::Audio* embeddedAudio = score->audio();
    if (writer.params().mode != mu::engraving::MscIoMode::XmlFile && embeddedAudio) {
        writer.writeAudioFile(embeddedAudio->data());
        ++preservedResourceCount;
    }
    if (!preservedResources.audioSettings.empty()) {
        writer.writeAudioSettingsJsonFile(preservedResources.audioSettings);
        ++preservedResourceCount;
    }
    if (!preservedResources.viewSettings.empty()) {
        writer.writeViewSettingsJsonFile(preservedResources.viewSettings);
        ++preservedResourceCount;
    }
    if (!preservedResources.automation.empty()) {
        writer.writeAutomationJsonFile(preservedResources.automation);
        ++preservedResourceCount;
    }

    for (const PreservedExcerptPackageResources& excerptResources : preservedResources.excerpts) {
        if (std::find(writtenExcerptFileNames.begin(), writtenExcerptFileNames.end(), excerptResources.fileName)
            == writtenExcerptFileNames.end()) {
            continue;
        }

        const muse::io::path_t pathPrefix = u"Excerpts/" + excerptResources.fileName + u"/";
        if (!excerptResources.audioSettings.empty()) {
            writer.writeAudioSettingsJsonFile(excerptResources.audioSettings, pathPrefix);
            ++preservedResourceCount;
        }
        if (!excerptResources.viewSettings.empty()) {
            writer.writeViewSettingsJsonFile(excerptResources.viewSettings, pathPrefix);
            ++preservedResourceCount;
        }
    }

    std::cout << "Aria save debug: sequential preserved package resources=" << preservedResourceCount << std::endl;
    std::cout << "Aria save debug: sequential package write end"
              << " elapsed=" << elapsedSecondsSince(packageStartedAt) << "s"
              << std::endl;
    return true;
}

bool saveSingleFileScore(const muse::modularity::ContextPtr&,
                         mu::engraving::MasterScore* score,
                         const muse::io::path_t& sourcePath,
                         const muse::io::path_t& targetPath,
                         const muse::String& targetMainFileName,
                         const mu::engraving::MscIoMode ioMode,
                         std::string& errorMessage)
{
    PreservedMsczResources preservedResources;
    if (ioMode == mu::engraving::MscIoMode::Zip
        && !readPreservedMsczResources(sourcePath, preservedResources, errorMessage)) {
        return false;
    }

    muse::ByteArray outputData;
    muse::io::Buffer outputBuffer(&outputData);

    mu::engraving::MscWriter::Params params;
    params.device = &outputBuffer;
    params.filePath = targetPath;
    params.mainFileName = targetMainFileName;
    params.mode = ioMode;

    mu::engraving::MscWriter writer(params);
    const muse::Ret openResult = writer.open();
    if (!openResult) {
        errorMessage = openResult.text().empty() ? "The MuseScore writer could not open a save buffer." : openResult.text();
        return false;
    }

    const auto stateStartedAt = SteadyClock::now();
    logSaveScoreState(score, "single-file-before-write");
    std::cout << "Aria save debug: single-file state log end"
              << " elapsed=" << elapsedSecondsSince(stateStartedAt) << "s"
              << std::endl;
    const auto sequentialStartedAt = SteadyClock::now();
    std::cout << "Aria save debug: single-file sequential write begin" << std::endl;
    const bool writeSucceeded = writeMsczSequentially(score, writer, preservedResources, errorMessage);
    std::cout << "Aria save debug: single-file sequential write end"
              << " success=" << (writeSucceeded ? "true" : "false")
              << " elapsed=" << elapsedSecondsSince(sequentialStartedAt) << "s"
              << std::endl;
    const auto closeStartedAt = SteadyClock::now();
    writer.close();
    std::cout << "Aria save debug: single-file writer closed"
              << " hasError=" << (writer.hasError() ? "true" : "false")
              << " elapsed=" << elapsedSecondsSince(closeStartedAt) << "s"
              << std::endl;

    if (!writeSucceeded) {
        errorMessage = "The MuseScore writer could not serialize this score.";
        return false;
    }

    if (writer.hasError()) {
        errorMessage = "The MuseScore writer reported an error while finalizing the score package.";
        return false;
    }

    const auto diskStartedAt = SteadyClock::now();
    std::cout << "Aria save debug: single-file disk write begin bytes=" << outputData.size() << std::endl;
    QSaveFile destinationFile(targetPath.toQString());
    // Never trade the existing score for a non-atomic overwrite. If Qt cannot
    // create/commit its adjacent temporary file, surface the save failure and
    // leave the last complete package untouched.
    destinationFile.setDirectWriteFallback(false);
    if (!destinationFile.open(QIODevice::WriteOnly)) {
        const QString qtError = destinationFile.errorString().trimmed();
        errorMessage = qtError.isEmpty()
            ? "MuseReader could not open the destination file for writing."
            : "MuseReader could not open the destination file for writing: " + qtError.toStdString();
        return false;
    }

    const qint64 bytesWritten = destinationFile.write(outputData.constChar(), static_cast<qint64>(outputData.size()));
    if (bytesWritten != static_cast<qint64>(outputData.size())) {
        const QString qtError = destinationFile.errorString().trimmed();
        errorMessage = qtError.isEmpty()
            ? "MuseReader could not write the saved score to disk."
            : "MuseReader could not write the saved score to disk: " + qtError.toStdString();
        return false;
    }

    if (!destinationFile.commit()) {
        const QString qtError = destinationFile.errorString().trimmed();
        errorMessage = qtError.isEmpty()
            ? "MuseReader could not finalize the saved score file."
            : "MuseReader could not finalize the saved score file: " + qtError.toStdString();
        return false;
    }

    std::cout << "Aria save debug: single-file disk write end"
              << " elapsed=" << elapsedSecondsSince(diskStartedAt) << "s"
              << std::endl;
    return true;
}

bool directoryContainsMainScoreFile(const QString& directoryPath,
                                    const muse::String& targetMainFileName)
{
    const QFileInfo mainFileInfo(QDir(directoryPath).filePath(targetMainFileName.toQString()));
    return mainFileInfo.exists() && mainFileInfo.isFile() && mainFileInfo.size() > 0;
}

bool renameSiblingDirectory(const QString& sourcePath, const QString& destinationPath)
{
    const QFileInfo sourceInfo(sourcePath);
    const QFileInfo destinationInfo(destinationPath);
    if (sourceInfo.absolutePath() != destinationInfo.absolutePath()) {
        return false;
    }

    QDir parentDirectory(sourceInfo.absolutePath());
    return parentDirectory.rename(sourceInfo.fileName(), destinationInfo.fileName());
}

bool replaceDirectoryScore(const QString& preparedPath,
                           const QString& targetPath,
                           const QString& backupPath,
                           const muse::String& targetMainFileName,
                           std::string& errorMessage)
{
    if (!directoryContainsMainScoreFile(preparedPath, targetMainFileName)) {
        errorMessage = "MuseReader did not create a complete replacement score directory.";
        return false;
    }

    QDir targetDirectory(targetPath);
    if (!targetDirectory.exists()) {
        if (!renameSiblingDirectory(preparedPath, targetPath)) {
            errorMessage = "MuseReader could not move the new score directory into place.";
            return false;
        }
        return true;
    }

#if defined(Q_OS_DARWIN)
    Q_UNUSED(backupPath);
    // APFS/HFS provide an atomic directory exchange. After this succeeds the
    // canonical path contains the completed save, while preparedPath contains
    // the previous valid score until cleanup. There is no crash window where
    // the canonical score path is absent.
    const QByteArray preparedFileSystemPath = QFile::encodeName(preparedPath);
    const QByteArray targetFileSystemPath = QFile::encodeName(targetPath);
    errno = 0;
    if (renamex_np(preparedFileSystemPath.constData(), targetFileSystemPath.constData(), RENAME_SWAP) != 0) {
        const int exchangeError = errno;
        errorMessage = "MuseReader could not atomically replace the score directory: "
            + std::string(std::strerror(exchangeError));
        return false;
    }

    if (!directoryContainsMainScoreFile(targetPath, targetMainFileName)) {
        errno = 0;
        const bool restored = renamex_np(
            preparedFileSystemPath.constData(),
            targetFileSystemPath.constData(),
            RENAME_SWAP
        ) == 0;
        errorMessage = restored
            ? "MuseReader rejected an incomplete replacement and restored the original score directory."
            : "MuseReader rejected an incomplete replacement, but could not restore the original score directory automatically.";
        return false;
    }

    QDir previousDirectory(preparedPath);
    if (previousDirectory.exists() && !previousDirectory.removeRecursively()) {
        // The save is already committed atomically. Keep operating with the new
        // canonical directory and clear this hidden stale copy before the next save.
        std::cout << "Aria save warning: could not remove previous score directory after atomic exchange path="
                  << preparedPath.toStdString() << std::endl;
    }
    return true;
#else
    // MuseReader ships on Darwin, but keep the render-core sandbox usable on
    // other hosts with a rollback-preserving fallback.
    QDir backupDirectory(backupPath);
    if (backupDirectory.exists()) {
        if (!directoryContainsMainScoreFile(targetPath, targetMainFileName)
            || !backupDirectory.removeRecursively()) {
            errorMessage = "MuseReader could not clear a previous score-directory backup safely.";
            return false;
        }
    }

    if (!renameSiblingDirectory(targetPath, backupPath)) {
        errorMessage = "MuseReader could not protect the original score directory before replacement.";
        return false;
    }

    if (!renameSiblingDirectory(preparedPath, targetPath)) {
        const bool restored = renameSiblingDirectory(backupPath, targetPath);
        errorMessage = restored
            ? "MuseReader could not install the replacement score directory; the original was restored."
            : "MuseReader could not install the replacement score directory, and the original remains in the backup directory.";
        return false;
    }

    if (!directoryContainsMainScoreFile(targetPath, targetMainFileName)) {
        QDir invalidTarget(targetPath);
        const bool removedInvalidTarget = invalidTarget.removeRecursively();
        const bool restored = removedInvalidTarget && renameSiblingDirectory(backupPath, targetPath);
        errorMessage = restored
            ? "MuseReader rejected an incomplete replacement and restored the original score directory."
            : "MuseReader rejected an incomplete replacement, but could not restore the original score directory automatically.";
        return false;
    }

    backupDirectory.setPath(backupPath);
    if (backupDirectory.exists() && !backupDirectory.removeRecursively()) {
        std::cout << "Aria save warning: could not remove score-directory backup path="
                  << backupPath.toStdString() << std::endl;
    }
    return true;
#endif
}

bool saveDirectoryScore(const muse::modularity::ContextPtr&,
                        mu::engraving::MasterScore* score,
                        const muse::io::path_t& targetPath,
                        const muse::String& targetMainFileName,
                        std::string& errorMessage)
{
    const muse::io::path_t targetContainerPath = mu::engraving::containerPath(targetPath);
    const QFileInfo targetPathInfo(targetContainerPath.toQString());
    const QString siblingPrefix = targetPathInfo.absolutePath() + "/." + targetPathInfo.fileName();
    const QString savePath = siblingPrefix + ".aria-saving";
    const QString backupPath = siblingPrefix + ".aria-backup";

    QDir saveDir(savePath);
    if (saveDir.exists() && !saveDir.removeRecursively()) {
        errorMessage = "MuseReader could not clear the temporary save directory.";
        return false;
    }

    mu::engraving::MscWriter::Params params;
    params.filePath = muse::io::path_t(savePath);
    params.mainFileName = targetMainFileName;
    params.mode = mu::engraving::MscIoMode::Dir;

    mu::engraving::MscWriter writer(params);
    const muse::Ret openResult = writer.open();
    if (!openResult) {
        errorMessage = openResult.text().empty() ? "The MuseScore writer could not prepare the score directory." : openResult.text();
        return false;
    }

    const auto stateStartedAt = SteadyClock::now();
    logSaveScoreState(score, "directory-before-write");
    std::cout << "Aria save debug: directory state log end"
              << " elapsed=" << elapsedSecondsSince(stateStartedAt) << "s"
              << std::endl;
    const auto sequentialStartedAt = SteadyClock::now();
    std::cout << "Aria save debug: directory sequential write begin" << std::endl;
    const bool writeSucceeded = writeMsczSequentially(score, writer, PreservedMsczResources(), errorMessage);
    std::cout << "Aria save debug: directory sequential write end"
              << " success=" << (writeSucceeded ? "true" : "false")
              << " elapsed=" << elapsedSecondsSince(sequentialStartedAt) << "s"
              << std::endl;
    const auto closeStartedAt = SteadyClock::now();
    writer.close();
    std::cout << "Aria save debug: directory writer closed"
              << " hasError=" << (writer.hasError() ? "true" : "false")
              << " elapsed=" << elapsedSecondsSince(closeStartedAt) << "s"
              << std::endl;

    if (!writeSucceeded) {
        errorMessage = "The MuseScore writer could not serialize this score directory.";
        return false;
    }

    if (writer.hasError()) {
        errorMessage = "The MuseScore writer reported an error while finalizing the score directory.";
        return false;
    }

    const auto replaceStartedAt = SteadyClock::now();
    if (!replaceDirectoryScore(
            savePath,
            targetContainerPath.toQString(),
            backupPath,
            targetMainFileName,
            errorMessage)) {
        return false;
    }

    std::cout << "Aria save debug: directory replace end"
              << " elapsed=" << elapsedSecondsSince(replaceStartedAt) << "s"
              << std::endl;
    return true;
}

bool saveScoreToPath(const muse::modularity::ContextPtr& context,
                     mu::engraving::MasterScore* score,
                     const muse::io::path_t& sourcePath,
                     const muse::io::path_t& scorePath,
                     std::string& errorMessage)
{
    if (!score) {
        errorMessage = "The score session is closed.";
        return false;
    }

    const auto ioMode = mu::engraving::mscIoModeBySuffix(muse::io::suffix(scorePath));
    if (ioMode == mu::engraving::MscIoMode::Unknown) {
        errorMessage = "MuseReader does not know how to save this score format.";
        return false;
    }

    const muse::io::path_t targetMainFilePath = mu::engraving::mainFilePath(scorePath);
    const muse::String targetMainFileName = mu::engraving::mainFileName(scorePath).toString();

    const bool saveSucceeded = (ioMode == mu::engraving::MscIoMode::Dir)
        ? saveDirectoryScore(context, score, scorePath, targetMainFileName, errorMessage)
        : saveSingleFileScore(context, score, sourcePath, scorePath, targetMainFileName, ioMode, errorMessage);

    if (!saveSucceeded) {
        return false;
    }

    QFile::setPermissions(
        targetMainFilePath.toQString(),
        QFile::ReadOwner | QFile::WriteOwner | QFile::ReadUser | QFile::ReadGroup | QFile::ReadOther
    );

    return true;
}

class SessionContext
{
public:
    static std::unique_ptr<SessionContext> create(const std::vector<muse::modularity::IModuleSetup*>& modules)
    {
        return invokeOnMainThreadSync([&modules]() {
            return createOnMainThread(modules);
        });
    }

    ~SessionContext()
    {
        invokeOnMainThreadSync([this]() {
            for (auto it = m_setups.rbegin(); it != m_setups.rend(); ++it) {
                (*it)->onDeinit();
            }

            m_setups.clear();
            muse::modularity::removeIoC(m_context);
        });
    }

    const muse::modularity::ContextPtr& context() const
    {
        return m_context;
    }

private:
    static std::unique_ptr<SessionContext> createOnMainThread(const std::vector<muse::modularity::IModuleSetup*>& modules)
    {
        static int nextContextId = 1;

        auto sessionContext = std::unique_ptr<SessionContext>(new SessionContext());
        sessionContext->m_context = std::make_shared<muse::modularity::Context>(nextContextId++);

        for (muse::modularity::IModuleSetup* module : modules) {
            if (!module) {
                continue;
            }

            std::unique_ptr<muse::modularity::IContextSetup> setup(module->newContext(sessionContext->m_context));
            if (!setup) {
                continue;
            }

            setup->registerExports();
            sessionContext->m_setups.push_back(std::move(setup));
        }

        for (const auto& setup : sessionContext->m_setups) {
            setup->resolveImports();
        }

        for (const auto& setup : sessionContext->m_setups) {
            setup->onPreInit(kRuntimeMode);
        }

        for (const auto& setup : sessionContext->m_setups) {
            setup->onInit(kRuntimeMode);
        }

        for (const auto& setup : sessionContext->m_setups) {
            setup->onAllInited(kRuntimeMode);
        }

        return sessionContext;
    }

    SessionContext() = default;

    muse::modularity::ContextPtr m_context;
    std::vector<std::unique_ptr<muse::modularity::IContextSetup>> m_setups;
};

class RenderRuntime
{
public:
    static RenderRuntime& instance()
    {
        static RenderRuntime runtime;
        return runtime;
    }

    static void initializeIfNeeded()
    {
        invokeOnMainThreadSync([] {
            Q_UNUSED(instance());
        });
    }

    std::unique_ptr<SessionContext> createSessionContext() const
    {
        return SessionContext::create(m_contextModules);
    }

private:
    RenderRuntime()
    {
        if (!QGuiApplication::instance()) {
            static int argc = 1;
            static char arg0[] = "score_render_core";
            static char* argv[] = { arg0, nullptr };
            m_qapp = std::make_unique<QGuiApplication>(argc, argv);
        }

        m_modules.emplace_back(std::make_unique<muse::draw::DrawModule>());
        m_modules.emplace_back(std::make_unique<mu::engraving::EngravingModule>());

        for (const auto& module : m_modules) {
            if (module->moduleName() == "engraving") {
                m_contextModules.push_back(module.get());
            }
        }

        muse::modularity::globalIoc()->registerExport<IApplication>("score_render_core", new msr::render::RenderApplicationStub());
        muse::modularity::globalIoc()->registerExport<muse::mpe::IArticulationProfilesRepository>(
            "score_render_core",
            new RenderCoreArticulationProfilesRepository()
        );
        muse::modularity::globalIoc()->registerExport<mu::iex::musicxml::IMusicXmlConfiguration>(
            "score_render_core",
            new RenderCoreMusicXmlConfiguration()
        );

        m_globalModule.registerResources();
        m_globalModule.registerExports();
        for (const auto& module : m_modules) {
            module->registerResources();
            module->registerExports();
        }

        m_globalModule.resolveImports();
        for (const auto& module : m_modules) {
            module->resolveImports();
        }

        m_globalModule.onPreInit(kRuntimeMode);
        for (const auto& module : m_modules) {
            module->onPreInit(kRuntimeMode);
        }

        m_globalModule.onInit(kRuntimeMode);
        for (const auto& module : m_modules) {
            module->onInit(kRuntimeMode);
        }

        const bool loadedInstrumentTemplates = mu::engraving::loadInstrumentTemplates(":/engraving/instruments/instruments.xml");
        const bool loadedScoreOrders = mu::engraving::loadInstrumentTemplates(":/engraving/instruments/orders.xml");
        std::cout << "MuseReader render runtime instrument templates: instruments="
                  << (loadedInstrumentTemplates ? "loaded" : "failed")
                  << " orders=" << (loadedScoreOrders ? "loaded" : "failed")
                  << std::endl;

        m_globalModule.onAllInited(kRuntimeMode);
        for (const auto& module : m_modules) {
            module->onAllInited(kRuntimeMode);
        }

        m_globalModule.onStartApp();
        for (const auto& module : m_modules) {
            module->onStartApp();
        }
    }

    ~RenderRuntime()
    {
        for (const auto& module : m_modules) {
            module->onDeinit();
        }
        m_globalModule.onDeinit();

        for (const auto& module : m_modules) {
            module->onDestroy();
        }
        m_globalModule.onDestroy();
    }

    std::unique_ptr<QGuiApplication> m_qapp;
    muse::GlobalModule m_globalModule;
    std::vector<std::unique_ptr<muse::modularity::IModuleSetup>> m_modules;
    std::vector<muse::modularity::IModuleSetup*> m_contextModules;
};

} // namespace
