    bool setNoteInputEnabled(const bool enabled,
                             msr::render::ScoreEditState& output,
                             std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::InputState& inputState = score->inputState();
        inputState.setNoteEntryMethod(mu::engraving::NoteEntryMethod::BY_DURATION);
        inputState.setNoteEntryMode(enabled);
        // MuseReader's accidental buttons are one-shot for staff/Pencil entry.
        // Never let MuseScore's persistent InputState carry an accidental across
        // an iOS note-entry mode transition.
        inputState.setAccidentalType(mu::engraving::AccidentalType::NONE);
        normalizeNoteEntryDuration(inputState);
        if (enabled) {
            if (mu::engraving::ChordRest* chordRest = selectedOrMeasureChordRest(score)) {
                configureInputCursorForChordRest(score, chordRest, true);
                if (chordRest->isChord()) {
                    score->nextInputPos(chordRest, false);
                }
            }
        }

        output = makeEditState(score);
        return true;
    }

    bool setCurrentVoice(const int voice,
                         msr::render::ScoreEditState& output,
                         std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        if (voice < 0 || voice >= static_cast<int>(mu::engraving::VOICES)) {
            errorMessage = "MuseReader received an unsupported voice.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::InputState& inputState = score->inputState();
        if (!inputState.noteEntryMode()) {
            if (mu::engraving::ChordRest* chordRest = selectedChordRest(score)) {
                if (chordRest->voice() != static_cast<mu::engraving::voice_idx_t>(voice)) {
                    if (mu::engraving::Note* note = editableNoteForItem(score->selection().element())) {
                        score->select(note, mu::engraving::SelectType::SINGLE, note->staffIdx());
                    }
                    score->startCmd(muse::TranslatableString::untranslatable("MuseReader change voice"));
                    inputState.setVoice(static_cast<mu::engraving::voice_idx_t>(voice));
                    score->changeSelectedElementsVoice(static_cast<mu::engraving::voice_idx_t>(voice));
                    score->endCmd();
                    refreshAfterEdit();
                    output = makeEditState(score);
                    return true;
                }
            }
        }

        inputState.setVoice(static_cast<mu::engraving::voice_idx_t>(voice));
        output = makeEditState(score);
        return true;
    }

    bool applyDuration(const int durationCode,
                       msr::render::ScoreEditState& output,
                       std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        const mu::engraving::DurationType durationType = durationTypeForCode(durationCode);
        if (durationType == mu::engraving::DurationType::V_INVALID) {
            errorMessage = "MuseReader only supports whole, half, quarter, eighth, and sixteenth durations right now.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::InputState& inputState = score->inputState();
        mu::engraving::ChordRest* chordRest = selectedOrMeasureChordRest(score);
        const bool shouldChangeSelection = !inputState.noteEntryMode() && chordRest != nullptr;

        if (shouldChangeSelection) {
            if (!selectedChordRest(score)) {
                if (mu::engraving::EngravingItem* selectableItem = noteOrRestSelectionItem(chordRest)) {
                    score->select(selectableItem, mu::engraving::SelectType::SINGLE, selectableItem->staffIdx());
                }
            }
            score->startCmd(muse::TranslatableString::untranslatable("MuseReader change duration"));
            inputState.setDuration(mu::engraving::TDuration(durationType));
            inputState.setDots(0);
            score->padToggle(padForDurationCode(durationCode), true);
            score->endCmd();
            refreshAfterEdit();
        }

        inputState.setDuration(mu::engraving::TDuration(durationType));
        inputState.setDots(0);

        output = makeEditState(score);
        return true;
    }

    bool toggleRest(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::InputState& inputState = score->inputState();
        if (inputState.noteEntryMode()) {
            inputState.setRest(!inputState.rest());
        } else if (mu::engraving::ChordRest* chordRest = selectedOrMeasureChordRest(score)) {
            if (!selectedChordRest(score)) {
                if (mu::engraving::EngravingItem* selectableItem = noteOrRestSelectionItem(chordRest)) {
                    score->select(selectableItem, mu::engraving::SelectType::SINGLE, selectableItem->staffIdx());
                }
            }
            if (chordRest->isRest()) {
                inputState.setRest(false);
                output = makeEditState(score);
                return true;
            }

            score->startCmd(muse::TranslatableString::untranslatable("MuseReader toggle rest"));
            score->padToggle(mu::engraving::Pad::REST, true);
            score->endCmd();
            refreshAfterEdit();
        } else {
            errorMessage.clear();
        }

        output = makeEditState(score);
        return true;
    }

    bool enterRestAtCursor(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::InputState& inputState = score->inputState();
        if (!inputState.noteEntryMode()) {
            errorMessage = "Enable note input before entering rests at the cursor.";
            return false;
        }

        if (!inputState.isValid()) {
            errorMessage = "Tap a standard staff position before entering a rest.";
            return false;
        }

        normalizeNoteEntryDuration(inputState);
        if (!inputState.duration().isValid() || inputState.duration().isZero() || inputState.duration().isMeasure()) {
            errorMessage = "Choose a standard duration before entering a rest.";
            return false;
        }

        mu::engraving::Staff* staff = inputState.staff();
        if (!isStandardStaff(staff, inputState.tick())) {
            errorMessage = "Rest entry currently works only on standard staves.";
            return false;
        }

        const mu::engraving::TDuration duration = inputState.duration();
        mu::engraving::Segment* targetSegment = inputState.segment();
        const mu::engraving::track_idx_t targetTrack = inputState.track();
        inputState.setRest(true);
        score->cmdEnterRest(duration);
        if (targetSegment && targetTrack != muse::nidx) {
            if (mu::engraving::EngravingItem* insertedItem = targetSegment->element(targetTrack)) {
                if (insertedItem->isChordRest()) {
                    if (mu::engraving::EngravingItem* selectableItem = noteOrRestSelectionItem(mu::engraving::toChordRest(insertedItem))) {
                        score->select(selectableItem, mu::engraving::SelectType::SINGLE, selectableItem->staffIdx());
                    }
                }
            }
        }
        appendMeasureIfInputCursorReachedEnd(score);
        refreshAfterEdit();

        output = makeEditState(score);
        return true;
    }

    bool toggleDot(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::InputState& inputState = score->inputState();
        if (inputState.noteEntryMode()) {
            inputState.setDots(inputState.duration().dots() == 1 ? 0 : 1);
        } else if (mu::engraving::ChordRest* chordRest = selectedOrMeasureChordRest(score)) {
            if (!selectedChordRest(score)) {
                if (mu::engraving::EngravingItem* selectableItem = noteOrRestSelectionItem(chordRest)) {
                    score->select(selectableItem, mu::engraving::SelectType::SINGLE, selectableItem->staffIdx());
                }
            }
            score->startCmd(muse::TranslatableString::untranslatable("MuseReader toggle augmentation dot"));
            inputState.setDuration(chordRest->durationType());
            score->padToggle(mu::engraving::Pad::DOT, true);
            score->endCmd();
            refreshAfterEdit();
        }

        output = makeEditState(score);
        return true;
    }

    bool toggleTie(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (!currentSelectedNote(score) && !editableNoteForItem(currentSelectedItem(score))) {
            errorMessage = "Select a note before toggling a tie.";
            return false;
        }

        score->cmdToggleTie();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool addTuplet(const int tupletCount,
                   msr::render::ScoreEditState& output,
                   std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        if (tupletCount < 2 || tupletCount > 9) {
            errorMessage = "MuseReader supports tuplets from 2 through 9.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        const std::set<mu::engraving::ChordRest*> selectedChordRests = score->getSelectedChordRests();
        std::vector<mu::engraving::ChordRest*> chordRests(selectedChordRests.begin(), selectedChordRests.end());
        if (chordRests.empty()) {
            if (mu::engraving::ChordRest* chordRest = activeChordRest(score)) {
                chordRests.push_back(chordRest);
            }
        }
        if (chordRests.empty()) {
            errorMessage = "Select a note or rest before adding a tuplet.";
            return false;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader add tuplet"));
        const auto numberType = static_cast<mu::engraving::TupletNumberType>(
            score->style().styleI(mu::engraving::Sid::tupletNumberType)
        );
        const auto bracketType = static_cast<mu::engraving::TupletBracketType>(
            score->style().styleI(mu::engraving::Sid::tupletBracketType)
        );

        bool added = false;
        for (mu::engraving::ChordRest* chordRest : chordRests) {
            if (!chordRest || chordRest->isGrace()) {
                continue;
            }
            if (chordRest->durationType() < mu::engraving::TDuration(mu::engraving::DurationType::V_512TH)
                && chordRest->durationType() != mu::engraving::TDuration(mu::engraving::DurationType::V_MEASURE)) {
                score->endCmd(true);
                errorMessage = "Note value is too short for a tuplet.";
                return false;
            }

            if (score->inputState().noteEntryMode()
                && chordRest->durationType().type() == mu::engraving::DurationType::V_MEASURE) {
                score->changeCRlen(chordRest, mu::engraving::TDuration(mu::engraving::DurationType::V_QUARTER));
            }

            mu::engraving::Fraction ratio(tupletCount, 2);
            ratio.setDenominator(mu::engraving::Tuplet::computeTupletDenominator(tupletCount, chordRest->ticks()));
            score->addTuplet(chordRest, ratio, numberType, bracketType);
            added = true;
        }

        if (!added) {
            score->endCmd(true);
            errorMessage = "MuseScore could not add a tuplet at the current selection.";
            return false;
        }

        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool addText(const std::string& textKind,
                 msr::render::ScoreEditState& output,
                 std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::EngravingItem* item = activeAttachmentItem(score);
        if (!item) {
            errorMessage = "Select a note, rest, or chord before adding text.";
            return false;
        }

        const std::string key = normalizedCommandKey(textKind);
        mu::engraving::TextStyleType type = mu::engraving::TextStyleType::STAFF;
        muse::String defaultText;
        if (key == "stafftext" || key == "staff") {
            type = mu::engraving::TextStyleType::STAFF;
            defaultText = muse::String(u"Staff Text");
        } else if (key == "systemtext" || key == "system") {
            type = mu::engraving::TextStyleType::SYSTEM;
            defaultText = muse::String(u"System Text");
        } else if (key == "rehearsalmark" || key == "rehearsal") {
            type = mu::engraving::TextStyleType::REHEARSAL_MARK;
        } else if (key == "chordtext" || key == "chord" || key == "harmony") {
            type = mu::engraving::TextStyleType::HARMONY_A;
            defaultText = muse::String(u"C");
        } else {
            errorMessage = "MuseReader does not recognize that text type.";
            return false;
        }

        mu::engraving::Score* commandScore = score;
        mu::engraving::EngravingItem* commandItem = item;
        if (m_masterScore && score != m_masterScore.get()) {
            commandScore = m_masterScore.get();
            commandItem = linkedItemInScore(item, commandScore);
            if (!commandItem) {
                errorMessage = "That text target is not linked to the saved full score. Switch to Full Score before adding text here.";
                return false;
            }
        }

        if (type == mu::engraving::TextStyleType::HARMONY_A) {
            if (mu::engraving::ChordRest* chordRest = mu::engraving::InputState::chordRest(commandItem)) {
                const mu::engraving::Segment* segment = chordRest->segment();
                const mu::engraving::track_idx_t targetTrack = mu::engraving::trackZeroVoice(chordRest->track());
                if (segment) {
                    for (mu::engraving::EngravingItem* annotation : segment->annotations()) {
                        if (annotation && annotation->isHarmony() && annotation->track() == targetTrack) {
                            mu::engraving::EngravingItem* selectedHarmony = annotation;
                            if (commandScore != score) {
                                selectedHarmony = linkedItemInScore(annotation, score);
                            }
                            if (selectedHarmony) {
                                score->select(selectedHarmony, mu::engraving::SelectType::SINGLE, selectedHarmony->staffIdx());
                            }
                            output = makeEditState(score);
                            return true;
                        }
                    }
                }
            }
        }

        commandScore->startCmd(muse::TranslatableString::untranslatable("MuseReader add text"));
        mu::engraving::TextBase* text = commandScore->addText(type, commandItem);
        if (!text) {
            commandScore->endCmd(true);
            errorMessage = "MuseReader could not add that text at the current selection.";
            return false;
        }

        if (!defaultText.empty()) {
            // Through the undo stack, so the copies addText() made in linked parts get it too.
            text->undoChangeProperty(mu::engraving::Pid::TEXT, mu::engraving::TextBase::plainToXmlText(defaultText));
        }

        commandScore->endCmd();
        refreshAfterEdit();
        if (commandScore != score) {
            relayoutActiveScoreRange(commandItem->tick(), commandItem->tick());
        }
        mu::engraving::EngravingItem* selectedText = text;
        if (commandScore != score) {
            selectedText = linkedItemInScore(text, score);
        }
        if (selectedText) {
            score->select(selectedText, mu::engraving::SelectType::SINGLE, selectedText->staffIdx());
        }
        output = makeEditState(score);
        return true;
    }

    bool selectAttachedChordText(msr::render::ScoreEditState& output,
                                 std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score);
        if (selectedItem && selectedItem->isHarmony()) {
            output = makeEditState(score);
            return true;
        }

        mu::engraving::ChordRest* chordRest = selectedChordRest(score);
        if (!chordRest) {
            output = makeEditState(score);
            return true;
        }

        const mu::engraving::Segment* segment = chordRest->segment();
        const mu::engraving::track_idx_t targetTrack = mu::engraving::trackZeroVoice(chordRest->track());
        if (segment) {
            for (mu::engraving::EngravingItem* annotation : segment->annotations()) {
                if (annotation && annotation->isHarmony() && annotation->track() == targetTrack) {
                    score->select(annotation, mu::engraving::SelectType::SINGLE, annotation->staffIdx());
                    break;
                }
            }
        }

        output = makeEditState(score);
        return true;
    }

    bool selectAttachedLyrics(msr::render::ScoreEditState& output,
                              std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score);
        if (selectedItem && selectedItem->isLyrics()) {
            output = makeEditState(score);
            return true;
        }

        mu::engraving::ChordRest* chordRest = selectedChordRest(score);
        if (!chordRest || !chordRest->isChord()) {
            output = makeEditState(score);
            return true;
        }

        mu::engraving::EngravingItem* destinationItem = noteOrRestSelectionItem(chordRest);
        if (!destinationItem) {
            errorMessage = "Select a note before adding lyrics.";
            return false;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader add lyrics verse"));
        removeEmptyLyrics(score, nullptr);
        mu::engraving::TextBase* text = score->addText(mu::engraving::TextStyleType::LYRICS_ODD, destinationItem);
        if (!text || !text->isLyrics()) {
            score->endCmd(true);
            errorMessage = "MuseReader could not add lyrics at the current selection.";
            return false;
        }
        score->endCmd();
        refreshAfterEdit();

        mu::engraving::Lyrics* lyrics = mu::engraving::toLyrics(text);
        score->select(lyrics, mu::engraving::SelectType::SINGLE, lyrics->staffIdx());
        output = makeEditState(score);
        return true;
    }

    bool setSelectedText(const std::string& text,
                         msr::render::ScoreEditState& output,
                         std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::EngravingItem* item = currentSelectedItem(score);
        if (item && item->isMarker()) {
            errorMessage = "Coda and Segno symbols cannot be text edited.";
            return false;
        }

        if (!isEditableTextItem(item) || !item->isTextBase()) {
            errorMessage = "Select a text or chord symbol before editing its text.";
            return false;
        }

        muse::String newText = muse::String::fromUtf8(text.c_str());
        if (newText.trimmed().empty() && item->isHarmony()) {
            errorMessage = "Chord text cannot be empty.";
            return false;
        }

        mu::engraving::Score* commandScore = score;
        mu::engraving::EngravingItem* commandItem = item;
        if (m_masterScore && score != m_masterScore.get()) {
            commandScore = m_masterScore.get();
            commandItem = linkedItemInScore(item, commandScore);
            if (!commandItem || !commandItem->isTextBase()) {
                errorMessage = "That text item is not linked to the saved full score. Switch to Full Score before editing it.";
                return false;
            }
        }

        commandScore->startCmd(muse::TranslatableString::untranslatable("MuseReader edit text"));
        // The app sends plain text; the TEXT property is MuseScore's markup, so "&" or "<" typed
        // by the user must be escaped or the saved file is not valid XML and will not open.
        commandItem->undoChangeProperty(mu::engraving::Pid::TEXT, mu::engraving::TextBase::plainToXmlText(newText));
        //! NOTE Editing a title-frame text (title/subtitle/composer/lyricist) directly on the
        //! page must also move the matching meta tag, otherwise the score shows one value while
        //! the Score Setup sheet, the library row and the saved <metaTag> still hold the old one.
        //! It joins this macro so one undo reverts the text and the tag together.
        syncMetaTagForStyledText(m_masterScore.get(), commandItem);
        commandScore->endCmd();
        refreshAfterEdit();
        if (commandScore != score) {
            relayoutActiveScoreRange(commandItem->tick(), commandItem->tick());
        }
        mu::engraving::EngravingItem* selectedItem = item;
        if (commandScore != score) {
            selectedItem = linkedItemInScore(commandItem, score);
        }
        if (selectedItem) {
            score->select(selectedItem, mu::engraving::SelectType::SINGLE, selectedItem->staffIdx());
        }
        output = makeEditState(score);
        return true;
    }

    // Lyrics entry follows desktop's lyrics editing (NotationInteraction::navigateToLyrics,
    // navigateToNextSyllable and addMelisma): space moves to the next note, "-" joins syllables
    // with a hyphen and "_" extends the syllable. Aria applies the typed text first, then, as
    // desktop does when it ends editing, removes the lyric it leaves if that is still empty.
    enum class LyricsAdvance {
        None,
        Word,
        Syllable,
        Extension,
    };

    struct LyricsEntryContext {
        mu::engraving::ChordRest* chordRest = nullptr;
        mu::engraving::Lyrics* lyrics = nullptr; // nullptr when the lyric was empty and removed
        int verse = 0;
        mu::engraving::PlacementV placement = mu::engraving::PlacementV::BELOW;
        mu::engraving::PropertyFlags placementFlags = mu::engraving::PropertyFlags::STYLED;
        mu::engraving::FontStyle fontStyle = mu::engraving::FontStyle::Normal;
        mu::engraving::PropertyFlags fontStyleFlags = mu::engraving::PropertyFlags::STYLED;
        mu::engraving::TextStyleType styleType = mu::engraving::TextStyleType::LYRICS_ODD;
        bool hasStyle = false;
    };

    static mu::engraving::Lyrics* createLyricsLike(mu::engraving::ChordRest* chordRest,
                                                   const LyricsEntryContext& context,
                                                   const mu::engraving::LyricsSyllabic syllabic)
    {
        mu::engraving::Lyrics* lyrics = mu::engraving::Factory::createLyrics(chordRest);
        lyrics->setTrack(chordRest->track());
        lyrics->setParent(chordRest);
        lyrics->setVerse(context.verse);
        if (context.hasStyle) {
            lyrics->setTextStyleType(context.styleType);
        } else {
            lyrics->setTextStyleType(lyrics->isEven() ? mu::engraving::TextStyleType::LYRICS_EVEN
                                                      : mu::engraving::TextStyleType::LYRICS_ODD);
        }
        lyrics->setPlacement(context.placement);
        lyrics->setPropertyFlags(mu::engraving::Pid::PLACEMENT, context.placementFlags);
        lyrics->setSyllabic(syllabic);
        if (context.hasStyle) {
            lyrics->setFontStyle(context.fontStyle);
            lyrics->setPropertyFlags(mu::engraving::Pid::FONT_STYLE, context.fontStyleFlags);
        }
        return lyrics;
    }

    static void changeSyllabic(mu::engraving::Lyrics* lyrics, const mu::engraving::LyricsSyllabic syllabic)
    {
        if (lyrics && lyrics->syllabic() != syllabic) {
            lyrics->undoChangeProperty(mu::engraving::Pid::SYLLABIC, int(syllabic));
        }
    }

    // Opens the lyrics command: finds the lyric being typed (or the selected note's), applies the
    // text and removes the lyric if it is left empty. The caller ends the command.
    bool beginLyricsEntry(mu::engraving::Score* score,
                          const muse::String& lyricText,
                          const char* commandName,
                          LyricsEntryContext& context,
                          std::string& errorMessage)
    {
        mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score);
        mu::engraving::Lyrics* selectedLyrics = selectedItem && selectedItem->isLyrics()
            ? mu::engraving::toLyrics(selectedItem)
            : nullptr;
        context.chordRest = selectedLyrics ? selectedLyrics->chordRest() : mu::engraving::InputState::chordRest(selectedItem);
        if (!context.chordRest || (!context.chordRest->isChord() && !selectedLyrics)) {
            errorMessage = "Select a note before adding lyrics.";
            return false;
        }

        context.verse = selectedLyrics ? selectedLyrics->verse() : 0;
        context.placement = selectedLyrics ? selectedLyrics->placement() : mu::engraving::PlacementV::BELOW;
        mu::engraving::Lyrics* lyrics = selectedLyrics ? selectedLyrics : context.chordRest->lyrics(context.verse, context.placement);
        if (lyrics) {
            context.placementFlags = lyrics->propertyFlags(mu::engraving::Pid::PLACEMENT);
            context.fontStyle = lyrics->fontStyle();
            context.fontStyleFlags = lyrics->propertyFlags(mu::engraving::Pid::FONT_STYLE);
            context.styleType = lyrics->textStyleType();
            context.hasStyle = true;
        }

        score->startCmd(muse::TranslatableString::untranslatable(commandName));
        if (!lyricText.empty()) {
            if (!lyrics) {
                lyrics = createLyricsLike(context.chordRest, context, mu::engraving::LyricsSyllabic::SINGLE);
                lyrics->setPlainText(lyricText);
                score->undoAddElement(lyrics);
            } else {
                lyrics->undoChangeProperty(mu::engraving::Pid::TEXT, mu::engraving::TextBase::plainToXmlText(lyricText));
            }
            lyrics->adjustPrevious();
        } else if (lyrics && lyrics->plainText().trimmed().empty()) {
            score->undoRemoveElement(lyrics);
            lyrics = nullptr;
        }
        context.lyrics = lyrics;
        return true;
    }

    // The lyric a space, hyphen or underscore continues from: the current one, or the nearest
    // earlier one in this voice (only within the same repeat section when `adjacentOnly`).
    static mu::engraving::Lyrics* lyricsBefore(const LyricsEntryContext& context, const bool adjacentOnly, const bool stopAtRest)
    {
        if (context.lyrics) {
            return context.lyrics;
        }
        const mu::engraving::track_idx_t track = context.chordRest->track();
        mu::engraving::Segment* start = context.chordRest->segment();
        for (mu::engraving::Segment* segment = start; segment; segment = segment->prev1(mu::engraving::SegmentType::ChordRest)) {
            if (adjacentOnly && segment != start && !mu::engraving::segmentsAreAdjacent(segment, start)) {
                break;
            }
            mu::engraving::EngravingItem* item = segment->element(track);
            if (!item) {
                continue;
            }
            if (mu::engraving::Lyrics* lyrics = mu::engraving::toChordRest(item)->lyrics(context.verse, context.placement)) {
                return lyrics;
            }
            if (stopAtRest && segment != start && !item->isChord()) {
                break;
            }
        }
        return nullptr;
    }

    bool enterLyrics(const std::string& text,
                     const LyricsAdvance advance,
                     msr::render::ScoreEditState& output,
                     std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        const muse::String lyricText = muse::String::fromUtf8(text.c_str()).trimmed();
        if (lyricText.empty() && advance == LyricsAdvance::None) {
            errorMessage = "Lyrics cannot be empty.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (advance == LyricsAdvance::Extension) {
            mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score);
            if ((!selectedItem || !selectedItem->isLyrics()) && lyricText.empty()) {
                errorMessage = "Select lyrics on a note before adding an extension line.";
                return false;
            }
        }

        const char* commandName = advance == LyricsAdvance::Extension ? "MuseReader add lyrics extension line"
                                  : advance == LyricsAdvance::Syllable ? "MuseReader add lyrics hyphen"
                                  : "MuseReader edit lyrics";
        LyricsEntryContext context;
        if (!beginLyricsEntry(score, lyricText, commandName, context, errorMessage)) {
            return false;
        }

        const mu::engraving::track_idx_t track = context.chordRest->track();
        mu::engraving::Segment* segment = context.chordRest->segment();
        mu::engraving::Lyrics* selectAfter = context.lyrics;

        // The next note: any chord; for a space also a rest that already has this verse.
        mu::engraving::ChordRest* next = nullptr;
        if (advance != LyricsAdvance::None) {
            for (mu::engraving::Segment* s = segment->next1(mu::engraving::SegmentType::ChordRest); s;
                 s = s->next1(mu::engraving::SegmentType::ChordRest)) {
                mu::engraving::EngravingItem* item = s->element(track);
                if (!item) {
                    continue;
                }
                if (item->isChord()
                    || (advance == LyricsAdvance::Word && mu::engraving::toChordRest(item)->lyrics(context.verse, context.placement))) {
                    next = mu::engraving::toChordRest(item);
                    break;
                }
            }
            if (next && advance != LyricsAdvance::Word && !mu::engraving::segmentsAreAdjacent(segment, next->segment())) {
                next = nullptr;
            }
        }

        if (advance == LyricsAdvance::Word && next) {
            mu::engraving::Lyrics* from = lyricsBefore(context, false, false);
            mu::engraving::Lyrics* to = next->lyrics(context.verse, context.placement);
            const bool newLyrics = !to;
            if (to) {
                // Arrived by a space: the next lyric may start a word but not continue one.
                if (to->syllabic() == mu::engraving::LyricsSyllabic::END) {
                    changeSyllabic(to, mu::engraving::LyricsSyllabic::SINGLE);
                } else if (to->syllabic() == mu::engraving::LyricsSyllabic::MIDDLE) {
                    changeSyllabic(to, mu::engraving::LyricsSyllabic::BEGIN);
                }
            } else {
                to = createLyricsLike(next, context, mu::engraving::LyricsSyllabic::SINGLE);
            }
            if (from) {
                // Left by a space: the lyric may end a word but has no hyphen after it.
                if (from->syllabic() == mu::engraving::LyricsSyllabic::BEGIN) {
                    changeSyllabic(from, mu::engraving::LyricsSyllabic::SINGLE);
                } else if (from->syllabic() == mu::engraving::LyricsSyllabic::MIDDLE) {
                    changeSyllabic(from, mu::engraving::LyricsSyllabic::END);
                }
            }
            if (newLyrics) {
                score->undoAddElement(to);
            }
            selectAfter = to;
        } else if (advance == LyricsAdvance::Syllable && next) {
            mu::engraving::Lyrics* from = lyricsBefore(context, true, false);
            mu::engraving::Lyrics* to = next->lyrics(context.verse, context.placement);
            const bool newLyrics = !to;
            if (newLyrics) {
                to = createLyricsLike(next, context, mu::engraving::LyricsSyllabic::END);
            } else if (to->syllabic() == mu::engraving::LyricsSyllabic::BEGIN) {
                changeSyllabic(to, mu::engraving::LyricsSyllabic::MIDDLE);
            } else if (to->syllabic() == mu::engraving::LyricsSyllabic::SINGLE) {
                changeSyllabic(to, mu::engraving::LyricsSyllabic::END);
            }
            if (from) {
                // Left by a hyphen: the lyric starts or continues a word, without an extension line.
                if (from->syllabic() == mu::engraving::LyricsSyllabic::SINGLE) {
                    changeSyllabic(from, mu::engraving::LyricsSyllabic::BEGIN);
                } else if (from->syllabic() == mu::engraving::LyricsSyllabic::END) {
                    changeSyllabic(from, mu::engraving::LyricsSyllabic::MIDDLE);
                }
                if (from->ticks().isNotZero()) {
                    from->undoChangeProperty(mu::engraving::Pid::LYRIC_TICKS, mu::engraving::Fraction(0, 1));
                }
            }
            if (newLyrics) {
                score->undoAddElement(to);
            }
            selectAfter = to;
        } else if (advance == LyricsAdvance::Extension) {
            // The extension runs from the word's lyric, which may be several notes back when "_"
            // is typed repeatedly, up to the current note.
            const mu::engraving::Fraction endTick = segment->tick();
            mu::engraving::Lyrics* from = lyricsBefore(context, true, true);
            if (from) {
                if (from->syllabic() == mu::engraving::LyricsSyllabic::BEGIN
                    || from->syllabic() == mu::engraving::LyricsSyllabic::MIDDLE) {
                    changeSyllabic(from, mu::engraving::LyricsSyllabic::END);
                }
                const mu::engraving::Fraction fromTick = from->segment()->tick();
                if (fromTick < endTick) {
                    from->undoChangeProperty(mu::engraving::Pid::LYRIC_TICKS, endTick - fromTick);
                } else if (next) {
                    from->undoChangeProperty(mu::engraving::Pid::LYRIC_TICKS, mu::engraving::Lyrics::TEMP_MELISMA_TICKS);
                }
            }
            if (next) {
                mu::engraving::Lyrics* to = next->lyrics(context.verse, context.placement);
                if (!to) {
                    to = createLyricsLike(next, context, mu::engraving::LyricsSyllabic::SINGLE);
                    score->undoAddElement(to);
                } else if (to->syllabic() == mu::engraving::LyricsSyllabic::MIDDLE) {
                    changeSyllabic(to, mu::engraving::LyricsSyllabic::BEGIN);
                } else if (to->syllabic() == mu::engraving::LyricsSyllabic::END) {
                    changeSyllabic(to, mu::engraving::LyricsSyllabic::SINGLE);
                }
                selectAfter = to;
            } else {
                selectAfter = from;
            }
        }

        score->endCmd();
        refreshAfterEdit();
        if (selectAfter && selectAfter->explicitParent()) {
            score->select(selectAfter, mu::engraving::SelectType::SINGLE, selectAfter->staffIdx());
        } else if (mu::engraving::EngravingItem* note = noteOrRestSelectionItem(context.chordRest)) {
            score->select(note, mu::engraving::SelectType::SINGLE, note->staffIdx());
        }
        output = makeEditState(score);
        return true;
    }

    bool addLyricsText(const std::string& text,
                       const bool advanceToNextChord,
                       msr::render::ScoreEditState& output,
                       std::string& errorMessage)
    {
        return enterLyrics(text, advanceToNextChord ? LyricsAdvance::Word : LyricsAdvance::None, output, errorMessage);
    }

    bool addLyricsHyphen(const std::string& text,
                         msr::render::ScoreEditState& output,
                         std::string& errorMessage)
    {
        return enterLyrics(text, LyricsAdvance::Syllable, output, errorMessage);
    }

    bool addLyricsMelisma(const std::string& text,
                          msr::render::ScoreEditState& output,
                          std::string& errorMessage)
    {
        return enterLyrics(text, LyricsAdvance::Extension, output, errorMessage);
    }

    // Lyrics left empty when the user moves on (another note tapped, the panel closed) are
    // removed, as desktop removes them when lyrics editing ends. Call inside a command.
    static bool removeEmptyLyrics(mu::engraving::Score* score, const mu::engraving::Lyrics* keep)
    {
        std::vector<mu::engraving::Lyrics*> emptyLyrics;
        for (mu::engraving::Segment* segment = score->firstSegment(mu::engraving::SegmentType::ChordRest); segment;
             segment = segment->next1(mu::engraving::SegmentType::ChordRest)) {
            for (mu::engraving::EngravingItem* item : segment->elist()) {
                if (!item || !item->isChordRest()) {
                    continue;
                }
                for (mu::engraving::Lyrics* lyrics : mu::engraving::toChordRest(item)->lyrics()) {
                    if (lyrics != keep && lyrics->plainText().trimmed().empty()) {
                        emptyLyrics.push_back(lyrics);
                    }
                }
            }
        }
        for (mu::engraving::Lyrics* lyrics : emptyLyrics) {
            score->undoRemoveElement(lyrics);
        }
        return !emptyLyrics.empty();
    }

    // Closing the lyrics panel.
    bool finishLyricsEntry(msr::render::ScoreEditState& output,
                           std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        mu::engraving::Score* score = activeScore();
        mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score);
        mu::engraving::ChordRest* selectedChordRest = selectedItem && selectedItem->isLyrics()
            ? mu::engraving::toLyrics(selectedItem)->chordRest()
            : nullptr;
        score->startCmd(muse::TranslatableString::untranslatable("MuseReader remove empty lyrics"));
        const bool removed = removeEmptyLyrics(score, nullptr);
        score->endCmd(!removed);
        if (removed) {
            refreshAfterEdit();
            // The selected lyric was empty and is gone: select its note instead.
            if (selectedChordRest && !muse::contains(selectedChordRest->lyrics(), mu::engraving::toLyrics(selectedItem))) {
                if (mu::engraving::EngravingItem* note = noteOrRestSelectionItem(selectedChordRest)) {
                    score->select(note, mu::engraving::SelectType::SINGLE, note->staffIdx());
                }
            }
        }
        output = makeEditState(score);
        return true;
    }

    bool dragSelectedChordText(const int pageIndex,
                               const double normalizedX,
                               const double normalizedY,
                               msr::render::ScoreEditState& output,
                               std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::EngravingItem* item = currentSelectedItem(score);
        if (!item || !item->isHarmony()) {
            errorMessage = "Select a chord symbol before dragging it.";
            return false;
        }

        mu::engraving::Page* page = pageForIndex(score, pageIndex);
        if (!page) {
            errorMessage = "That page is unavailable in the open score session.";
            return false;
        }

        mu::engraving::Harmony* harmony = mu::engraving::toHarmony(item);
        const mu::engraving::PointF pagePoint = pointForNormalizedPagePosition(page, normalizedX, normalizedY);
        mu::engraving::ChordRest* targetChordRest = chordRestAtPointForChordText(score, page, pagePoint);
        mu::engraving::Segment* targetSegment = targetChordRest ? targetChordRest->segment() : nullptr;
        mu::engraving::System* targetSystem = targetSegment ? targetSegment->system() : nullptr;
        if (!targetChordRest || !targetSegment || !targetSystem) {
            errorMessage = "Drop the chord symbol near a note or rest.";
            return false;
        }

        // A chord symbol that names a fret diagram belongs to it: move the diagram, which carries
        // its chord symbol, rather than pulling the symbol off and leaving the diagram unnamed.
        mu::engraving::EngravingItem* moving = harmony;
        if (harmony->explicitParent() && harmony->explicitParent()->isFretDiagram()) {
            moving = mu::engraving::toFretDiagram(harmony->explicitParent());
        }
        mu::engraving::EngravingItem* moved = moving->clone();
        moved->setScore(score);
        moved->setParent(targetSegment);
        moved->setTrack(mu::engraving::trackZeroVoice(targetChordRest->track()));

        const double spatium = std::max(page->spatium(), 1.0);
        const mu::engraving::PointF anchor = chordTextAttachmentAnchorForChordRest(targetChordRest);
        const mu::engraving::PointF currentCenter = harmony->pageBoundingRect().center();
        const mu::engraving::PointF offset(
            moving == harmony ? (pagePoint.x() - anchor.x()) / spatium : moving->offset().x(),
            moving->offset().y() + ((pagePoint.y() - currentCenter.y()) / spatium)
        );
        moved->setOffset(offset);

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader drag chord symbol"));
        score->undoRemoveElement(moving);
        score->undoAddElement(moved);
        score->endCmd();

        refreshAfterEdit();
        mu::engraving::EngravingItem* movedHarmony = moved;
        if (moved->isFretDiagram() && mu::engraving::toFretDiagram(moved)->harmony()) {
            movedHarmony = mu::engraving::toFretDiagram(moved)->harmony();
        }
        score->select(movedHarmony, mu::engraving::SelectType::SINGLE, movedHarmony->staffIdx());
        output = makeEditState(score);
        return true;
    }

    bool dragSelectedMovableElement(const int pageIndex,
                                    const double normalizedX,
                                    const double normalizedY,
                                    msr::render::ScoreEditState& output,
                                    std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (score->inputState().noteEntryMode()) {
            errorMessage = "Finish note entry before moving a score element.";
            return false;
        }

        mu::engraving::EngravingItem* item = currentSelectedItem(score);
        if (!isDirectlyDraggableTextItem(item)) {
            errorMessage = "Select a movable text, dynamic, tempo, marker, fermata, or chord symbol before dragging it.";
            return false;
        }

        if (item->isHarmony()) {
            return dragSelectedChordText(pageIndex, normalizedX, normalizedY, output, errorMessage);
        }

        mu::engraving::Page* page = pageForIndex(score, pageIndex);
        mu::engraving::Page* itemPage = pageForItem(score, item);
        if (!page || page != itemPage) {
            errorMessage = "The selected element cannot be dragged to a different page.";
            return false;
        }

        if (item->isFermata()) {
            // Like chord symbols: dropping a fermata nearer another note or rest moves it there.
            // Near its own note, the drag below just nudges it.
            mu::engraving::Fermata* fermata = mu::engraving::toFermata(item);
            const mu::engraving::PointF fermataDropPoint = pointForNormalizedPagePosition(page, normalizedX, normalizedY);
            mu::engraving::ChordRest* nearestChordRest = nullptr;
            double nearestDistance = std::numeric_limits<double>::max();
            for (const FermataAnchorTarget& target : fermataAnchorTargets(score, fermata)) {
                // Same weighting as the on-screen guide: horizontal distance decides.
                const double dx = target.anchor.x() - fermataDropPoint.x();
                const double dy = (target.anchor.y() - fermataDropPoint.y()) * 0.12;
                const double distance = std::hypot(dx, dy);
                if (distance < nearestDistance) {
                    nearestDistance = distance;
                    nearestChordRest = target.chordRest;
                }
            }
            if (nearestChordRest && nearestChordRest->segment() != fermata->segment()) {
                return moveFermataToChordRest(score, fermata, nearestChordRest, output, errorMessage);
            }
        }

        std::unique_ptr<mu::engraving::ElementGroup> dragGroup = item->getDragGroup(
            [item](const mu::engraving::EngravingItem* candidate) {
                return candidate == item;
            }
        );
        if (!dragGroup || !dragGroup->enabled()) {
            errorMessage = "MuseScore cannot move that selected element.";
            return false;
        }

        const mu::engraving::PointF dropPoint = pointForNormalizedPagePosition(page, normalizedX, normalizedY);
        const mu::engraving::PointF currentCenter = item->pageBoundingRect().center();
        const mu::engraving::PointF delta = dropPoint - currentCenter;
        mu::engraving::EditData editData;
        editData.pos = dropPoint;
        editData.lastPos = currentCenter;
        editData.delta = delta;
        editData.evtDelta = delta;
        editData.moveDelta = delta;

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader drag score element"));
        dragGroup->startDrag(editData);
        dragGroup->drag(editData);
        dragGroup->endDrag(editData);
        score->endCmd();

        refreshAfterEdit();
        score->select(item, mu::engraving::SelectType::SINGLE, item->staffIdx());
        output = makeEditState(score);
        return true;
    }

    bool moveFermataToChordRest(mu::engraving::Score* score,
                                mu::engraving::Fermata* fermata,
                                mu::engraving::ChordRest* target,
                                msr::render::ScoreEditState& output,
                                std::string& errorMessage)
    {
        mu::engraving::Segment* targetSegment = target->segment();
        for (mu::engraving::EngravingItem* annotation : targetSegment->annotations()) {
            if (annotation && annotation->isFermata() && annotation->track() == fermata->track()) {
                errorMessage = "That note already has a fermata.";
                return false;
            }
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader move fermata"));
        mu::engraving::Fermata* moved = mu::engraving::Factory::createFermata(targetSegment);
        moved->setSymId(fermata->symId());
        moved->setTimeStretch(fermata->timeStretch());
        moved->setPlay(fermata->play());
        moved->setPlacement(fermata->placement());
        moved->setTrack(fermata->track());
        moved->setParent(targetSegment);
        score->undoRemoveElement(fermata);
        score->undoAddElement(moved);
        score->endCmd();
        refreshAfterEdit();
        score->select(moved, mu::engraving::SelectType::SINGLE, moved->staffIdx());
        output = makeEditState(score);
        return true;
    }

    bool addRepeatJump(const std::string& repeatJumpKind,
                       msr::render::ScoreEditState& output,
                       std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::ChordRest* chordRest = activeChordRest(score);
        mu::engraving::Measure* measure = activeMeasure(score);
        mu::engraving::Segment* segment = chordRest ? chordRest->segment() : nullptr;
        if (!segment && measure) {
            segment = measure->first(mu::engraving::SegmentType::ChordRest);
        }
        if (!measure) {
            errorMessage = "Select a bar, note, or rest before adding repeats or jumps.";
            return false;
        }

        const std::string key = normalizedCommandKey(repeatJumpKind);
        score->startCmd(muse::TranslatableString::untranslatable("MuseReader add repeat or jump"));
        mu::engraving::EngravingItem* addedItem = nullptr;

        if (key == "startrepeat" || key == "beginrepeat" || key == "beginningrepeat") {
            measure->undoChangeProperty(mu::engraving::Pid::REPEAT_START, true);
            addedItem = chordRest;
        } else if (key == "endrepeat") {
            measure->undoChangeProperty(mu::engraving::Pid::REPEAT_END, true);
            measure->undoChangeProperty(mu::engraving::Pid::REPEAT_COUNT, 2);
            addedItem = chordRest;
        } else if (key == "firstending" || key == "secondending") {
            if (!segment) {
                score->endCmd(true);
                errorMessage = "MuseReader could not find a note/rest segment for that ending.";
                return false;
            }
            mu::engraving::Volta* volta = mu::engraving::Factory::createVolta(score->dummy());
            const int ending = key == "firstending" ? 1 : 2;
            volta->setEndings({ ending });
            volta->setText(muse::String(u"%1.").arg(ending));
            const mu::engraving::staff_idx_t staffIdx = chordRest ? chordRest->staffIdx() : 0;
            score->cmdAddSpanner(volta, staffIdx, segment, segment, false);
            addedItem = volta;
        } else if (key == "coda" || key == "segno" || key == "tocoda") {
            mu::engraving::Marker* marker = mu::engraving::Factory::createMarker(measure);
            mu::engraving::MarkerType markerType = mu::engraving::MarkerType::CODA;
            if (key == "segno") {
                markerType = mu::engraving::MarkerType::SEGNO;
            } else if (key == "tocoda") {
                markerType = mu::engraving::MarkerType::TOCODA;
            }
            marker->setMarkerType(markerType);
            marker->resetProperty(mu::engraving::Pid::LABEL);
            marker->setTrack(0);
            marker->setParent(measure);
            // undoAddElement (not doUndoAddElement) also places the marker in every part.
            score->undoAddElement(marker);
            addedItem = marker;
        } else {
            mu::engraving::JumpType jumpType = mu::engraving::JumpType::USER;
            if (key == "dsalcoda") {
                jumpType = mu::engraving::JumpType::DS_AL_CODA;
            } else if (key == "dsalfine") {
                jumpType = mu::engraving::JumpType::DS_AL_FINE;
            } else if (key == "dcalcoda") {
                jumpType = mu::engraving::JumpType::DC_AL_CODA;
            } else if (key == "dcalfine") {
                jumpType = mu::engraving::JumpType::DC_AL_FINE;
            } else {
                score->endCmd(true);
                errorMessage = "MuseReader does not recognize that repeat or jump.";
                return false;
            }

            mu::engraving::Jump* jump = mu::engraving::Factory::createJump(measure);
            jump->setJumpType(jumpType);
            jump->setTrack(0);
            jump->setParent(measure);
            // undoAddElement (not doUndoAddElement) also places the jump in every part.
            score->undoAddElement(jump);
            addedItem = jump;
        }

        score->endCmd();
        refreshAfterEdit();
        if (addedItem) {
            score->select(addedItem, mu::engraving::SelectType::SINGLE, addedItem->staffIdx());
        }
        output = makeEditState(score);
        return true;
    }

    bool addExpression(const std::string& expressionKind,
                       msr::render::ScoreEditState& output,
                       std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::ChordRest* chordRest = activeChordRest(score);
        mu::engraving::EngravingItem* item = activeAttachmentItem(score);
        mu::engraving::ChordRest* rangeFirstChord = nullptr;
        mu::engraving::ChordRest* rangeLastChord = nullptr;
        const bool hasRangeChordBounds = selectedRangeChordBounds(score, &rangeFirstChord, &rangeLastChord);
        if ((!chordRest || !item) && !hasRangeChordBounds) {
            errorMessage = "Select a note or rest before adding an expression.";
            return false;
        }

        const std::string key = normalizedCommandKey(expressionKind);
        score->startCmd(muse::TranslatableString::untranslatable("MuseReader add expression"));
        mu::engraving::EngravingItem* addedItem = nullptr;

        static const std::unordered_map<std::string, std::string> dynamicTypes = {
            { "pianississimo", "ppp" },
            { "ppp", "ppp" },
            { "pianissimo", "pp" },
            { "pp", "pp" },
            { "piano", "p" },
            { "p", "p" },
            { "mezzo piano", "mp" },
            { "mezzopiano", "mp" },
            { "mp", "mp" },
            { "mezzo forte", "mf" },
            { "mezzoforte", "mf" },
            { "mf", "mf" },
            { "forte", "f" },
            { "f", "f" },
            { "fortissimo", "ff" },
            { "ff", "ff" },
            { "fortississimo", "fff" },
            { "fff", "fff" },
            { "fp", "fp" },
            { "pf", "pf" },
            { "sf", "sf" },
            { "sfz", "sfz" },
            { "sff", "sff" },
            { "sffz", "sffz" },
            { "sfp", "sfp" },
            { "rfz", "rfz" },
            { "rf", "rf" },
            { "fz", "fz" }
        };
        const auto dynamicType = dynamicTypes.find(key);
        if (dynamicType != dynamicTypes.end()) {
            mu::engraving::TextBase* text = score->addText(mu::engraving::TextStyleType::DYNAMICS, item);
            mu::engraving::Dynamic* dynamic = text && text->isDynamic() ? mu::engraving::toDynamic(text) : nullptr;
            if (!dynamic) {
                score->endCmd(true);
                errorMessage = "MuseReader could not add that dynamic at the current selection.";
                return false;
            }

            // Through the undo stack, so the copies addText() made in linked parts get the
            // type too; setting it directly left them as blank "other-dynamics".
            dynamic->undoChangeProperty(mu::engraving::Pid::DYNAMIC_TYPE, muse::String::fromUtf8(dynamicType->second));
            addedItem = dynamic;
        } else if (key == "crescendo" || key == "decrescendo") {
            const mu::engraving::HairpinType hairpinType = key == "crescendo"
                ? mu::engraving::HairpinType::CRESC_HAIRPIN
                : mu::engraving::HairpinType::DIM_HAIRPIN;
            std::vector<mu::engraving::Hairpin*> hairpins = score->addHairpins(hairpinType);
            if (hairpins.empty()) {
                score->endCmd(true);
                errorMessage = "MuseReader could not add that hairpin at the current selection.";
                return false;
            }
            addedItem = hairpins.front();
        } else if (key == "pedal") {
            mu::engraving::Pedal* pedal = mu::engraving::Factory::createPedal(score->dummy());
            score->cmdAddSpanner(pedal, chordRest->staffIdx(), chordRest->segment(), chordRest->segment(), false);
            addedItem = pedal;
        } else if (key == "laissezvib" || key == "laissezvibrer" || key == "lv") {
            if (!item || !(item->isNote() || item->isChord())) {
                score->endCmd(true);
                errorMessage = "Select a note before adding laissez vibrer.";
                return false;
            }
            if (mu::engraving::Note* note = editableNoteForItem(item)) {
                score->select(note, mu::engraving::SelectType::SINGLE, note->staffIdx());
            }
            score->endCmd(true);
            score->cmdToggleLaissezVib();
            refreshAfterEdit();
            output = makeEditState(score);
            return true;
        } else if (key == "8va" || key == "ottava8va" || key == "8vb" || key == "ottava8vb") {
            mu::engraving::ChordRest* ottavaStart = hasRangeChordBounds ? rangeFirstChord : chordRest;
            mu::engraving::ChordRest* ottavaEnd = hasRangeChordBounds ? rangeLastChord : chordRest;
            if (!ottavaStart || !ottavaEnd) {
                score->endCmd(true);
                errorMessage = "Select a note or range before adding an ottava.";
                return false;
            }
            mu::engraving::Ottava* ottava = mu::engraving::Factory::createOttava(score->dummy());
            ottava->setOttavaType((key == "8vb" || key == "ottava8vb")
                ? mu::engraving::OttavaType::OTTAVA_8VB
                : mu::engraving::OttavaType::OTTAVA_8VA);
            ottava->styleChanged();
            score->cmdAddSpanner(ottava, ottavaStart->staffIdx(), ottavaStart->segment(), ottavaEnd->segment(), false);
            addedItem = ottava;
        } else if (key == "slur") {
            mu::engraving::ChordRest* slurStart = hasRangeChordBounds ? rangeFirstChord : chordRest;
            mu::engraving::ChordRest* slurEnd = hasRangeChordBounds ? rangeLastChord : nullptr;
            if (!slurStart || !slurStart->isChord()) {
                score->endCmd(true);
                errorMessage = "Select one or more notes before adding a slur.";
                return false;
            }
            mu::engraving::Slur* slur = score->addSlur(slurStart, slurEnd, nullptr);
            addedItem = slur;
        } else if (key == "fermata") {
            // Like MuseScore's palette, a fermata goes on every note or rest in a range. Tapping
            // it again removes it, matching the articulation buttons.
            std::vector<mu::engraving::ChordRest*> targets;
            if (score->selection().isRange()) {
                const mu::engraving::track_idx_t startTrack = score->selection().staffStart() * mu::engraving::VOICES;
                const mu::engraving::track_idx_t endTrack = score->selection().staffEnd() * mu::engraving::VOICES;
                for (mu::engraving::Segment* segment = score->selection().startSegment();
                     segment && segment != score->selection().endSegment();
                     segment = segment->next1(mu::engraving::SegmentType::ChordRest)) {
                    if (score->selection().endSegment() && segment->tick() >= score->selection().endSegment()->tick()) {
                        break;
                    }
                    for (mu::engraving::track_idx_t track = startTrack; track < endTrack; ++track) {
                        mu::engraving::EngravingItem* element = segment->element(track);
                        if (element && element->isChordRest()) {
                            targets.push_back(mu::engraving::toChordRest(element));
                        }
                    }
                }
            } else if (chordRest) {
                targets.push_back(chordRest);
            }
            if (targets.empty()) {
                score->endCmd(true);
                errorMessage = "Select a note or rest before adding a fermata.";
                return false;
            }

            auto existingFermata = [](mu::engraving::ChordRest* target) -> mu::engraving::EngravingItem* {
                for (mu::engraving::EngravingItem* annotation : target->segment()->annotations()) {
                    if (annotation && annotation->isFermata() && annotation->track() == target->track()) {
                        return annotation;
                    }
                }
                return nullptr;
            };
            const bool removing = std::all_of(targets.begin(), targets.end(), [&](mu::engraving::ChordRest* target) {
                return existingFermata(target) != nullptr;
            });
            for (mu::engraving::ChordRest* target : targets) {
                mu::engraving::EngravingItem* existing = existingFermata(target);
                if (removing) {
                    score->undoRemoveElement(existing);
                } else if (!existing) {
                    mu::engraving::Fermata* fermata = mu::engraving::Factory::createFermata(target->segment());
                    fermata->setSymIdAndTimeStretch(mu::engraving::SymId::fermataAbove);
                    fermata->setPlacement(target->track() & 1 ? mu::engraving::PlacementV::BELOW : mu::engraving::PlacementV::ABOVE);
                    fermata->setTrack(target->track());
                    fermata->setParent(target->segment());
                    score->undoAddElement(fermata);
                }
            }
            addedItem = score->selection().isRange() ? rangeFirstChord : item;
        } else if (key == "accent" || key == "marcato" || key == "tenuto" || key == "staccato"
                   || key == "string up" || key == "stringup" || key == "up bow" || key == "upbow"
                   || key == "string down" || key == "stringdown" || key == "down bow" || key == "downbow") {
            mu::engraving::SymId symId = mu::engraving::SymId::articAccentAbove;
            if (key == "marcato") {
                symId = mu::engraving::SymId::articMarcatoAbove;
            } else if (key == "tenuto") {
                symId = mu::engraving::SymId::articTenutoAbove;
            } else if (key == "staccato") {
                symId = mu::engraving::SymId::articStaccatoAbove;
            } else if (key == "string up" || key == "stringup" || key == "up bow" || key == "upbow") {
                symId = mu::engraving::SymId::stringsUpBow;
            } else if (key == "string down" || key == "stringdown" || key == "down bow" || key == "downbow") {
                symId = mu::engraving::SymId::stringsDownBow;
            }

            if (score->selection().isRange()) {
                score->toggleArticulation(symId);
                addedItem = rangeFirstChord;
            } else {
                mu::engraving::Articulation* articulation = mu::engraving::Factory::createArticulation(score->dummy()->chord());
                articulation->setSymId(symId);
                if (!score->toggleArticulation(item, articulation)) {
                    delete articulation;
                } else {
                    addedItem = item;
                }
            }
        } else {
            score->endCmd(true);
            errorMessage = "MuseReader does not recognize that expression.";
            return false;
        }

        score->endCmd();
        refreshAfterEdit();
        if (addedItem) {
            score->select(addedItem, mu::engraving::SelectType::SINGLE, addedItem->staffIdx());
        }
        output = makeEditState(score);
        return true;
    }

    bool retargetSelectedExpressionEndpoint(const bool startEndpoint,
                                            const int pageIndex,
                                            const double normalizedX,
                                            const double normalizedY,
                                            msr::render::ScoreEditState& output,
                                            std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        // Only the selected line itself: with a range selected, the lookup would pick the first
        // tie or slur inside it. A tie's ends are notes and always neighbours; giving it chords as
        // ends corrupted the score and crashed a later layout (found by the stress test).
        mu::engraving::Spanner* spanner = score->selection().isRange() ? nullptr : currentSelectedExpressionSpanner(score);
        if (!spanner) {
            errorMessage = "Select an expression line before moving an endpoint.";
            return false;
        }
        if (spanner->isTie()) {
            errorMessage = "A tie always joins neighbouring notes; its ends cannot be moved.";
            return false;
        }

        mu::engraving::Page* page = pageForIndex(score, pageIndex);
        if (!page) {
            errorMessage = "That page is unavailable in the open score session.";
            return false;
        }

        const mu::engraving::PointF pagePoint = pointForNormalizedPagePosition(page, normalizedX, normalizedY);
        const mu::engraving::staff_idx_t preferredStaff = std::min(mu::engraving::track2staff(spanner->track()), score->nstaves() - 1);
        mu::engraving::ChordRest* target = chordRestAtPointForExpressionEndpoint(score, page, pagePoint, preferredStaff, spanner->isSlurTie());
        if (!target) {
            errorMessage = spanner->isSlurTie()
                ? "Drag the slur endpoint near a note."
                : "Drag the expression endpoint near a note or rest.";
            return false;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader retarget expression endpoint"));
        if (spanner->isSlurTie()) {
            mu::engraving::ChordRest* start = mu::engraving::InputState::chordRest(spanner->startElement());
            mu::engraving::ChordRest* end = mu::engraving::InputState::chordRest(spanner->endElement());
            if (!start || !end) {
                score->endCmd(true);
                errorMessage = "MuseReader could not find both slur endpoints.";
                return false;
            }
            // Dragging one end onto or past the other keeps the shortest slur instead of
            // refusing: the neighbouring chord on the other side of the fixed end.
            auto adjacentChord = [](mu::engraving::ChordRest* from, const bool forward) -> mu::engraving::ChordRest* {
                mu::engraving::Segment* segment = from->segment();
                for (segment = forward ? segment->next1(mu::engraving::SegmentType::ChordRest) : segment->prev1(mu::engraving::SegmentType::ChordRest);
                     segment;
                     segment = forward ? segment->next1(mu::engraving::SegmentType::ChordRest) : segment->prev1(mu::engraving::SegmentType::ChordRest)) {
                    mu::engraving::EngravingItem* element = segment->element(from->track());
                    if (element && element->isChord()) {
                        return mu::engraving::toChordRest(element);
                    }
                }
                return nullptr;
            };
            if (startEndpoint) {
                start = target->tick() < end->tick() ? target : adjacentChord(end, false);
            } else {
                end = target->tick() > start->tick() ? target : adjacentChord(start, true);
            }
            if (!start || !end || start->tick() >= end->tick()) {
                score->endCmd(true);
                errorMessage = "A slur needs at least two notes.";
                return false;
            }
            if (spanner->isSlur()) {
                // As desktop's SlurSegment::changeAnchor does: move the slur's ticks (what layout
                // draws from) and then its start/end chords. Changing only the chords updated the
                // file but left the slur drawn at its old notes until the score was reopened.
                for (mu::engraving::EngravingObject* linked : spanner->linkList()) {
                    mu::engraving::Spanner* linkedSpanner = mu::engraving::toSpanner(linked);
                    score->undoStack()->pushWithoutPerforming(
                        new mu::engraving::ChangeStartEndSpanner(linkedSpanner, linkedSpanner->startElement(), linkedSpanner->endElement()));
                }
                spanner->undoChangeProperty(mu::engraving::Pid::SPANNER_TICK, start->tick());
                spanner->undoChangeProperty(mu::engraving::Pid::SPANNER_TICKS, end->tick() - start->tick());
                mu::engraving::toSlur(spanner)->undoChangeStartEndElements(start, end);
            } else {
                score->undo(new mu::engraving::ChangeStartEndSpanner(spanner, start, end));
            }
        } else {
            const mu::engraving::Fraction oldStartTick = spanner->tick();
            const mu::engraving::Fraction oldEndTick = spanner->tick2();
            mu::engraving::Fraction newStartTick = startEndpoint ? target->tick() : oldStartTick;
            mu::engraving::Fraction newEndTick = startEndpoint ? oldEndTick : target->endTick();
            // Dragging one end onto or past the other keeps the line over a single note or
            // rest next to the fixed end, instead of refusing.
            if (newEndTick <= newStartTick) {
                if (startEndpoint) {
                    mu::engraving::ChordRest* lastCovered = score->findCR(oldEndTick - mu::engraving::Fraction(1, 1920), spanner->track());
                    newStartTick = lastCovered ? lastCovered->tick() : oldStartTick;
                } else {
                    mu::engraving::ChordRest* firstCovered = score->findCR(oldStartTick, spanner->track());
                    newEndTick = firstCovered ? firstCovered->endTick() : oldEndTick;
                }
            }
            if (newEndTick <= newStartTick) {
                score->endCmd(true);
                errorMessage = "Expression line start must stay before its end.";
                return false;
            }
            if (startEndpoint) {
                spanner->undoChangeProperty(mu::engraving::Pid::SPANNER_TICK, newStartTick);
            }
            spanner->undoChangeProperty(mu::engraving::Pid::SPANNER_TICKS, newEndTick - newStartTick);
        }

        score->endCmd();
        refreshAfterEdit();
        score->select(spanner, mu::engraving::SelectType::SINGLE, spanner->staffIdx());
        output = makeEditState(score);
        return true;
    }

    bool addLayoutBreak(const std::string& breakKind,
                        msr::render::ScoreEditState& output,
                        std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::Measure* measure = activeMeasure(score);
        if (!measure) {
            errorMessage = "Select a measure or barline before adding a layout break.";
            return false;
        }

        const std::string key = normalizedCommandKey(breakKind);
        const bool isPageBreak = key == "pagebreak" || key == "page";
        const bool isSystemBreak = key == "systembreak" || key == "linebreak" || key == "line" || key == "system";
        const bool isNoBreak = key == "keepbarstogether" || key == "keepmeasurestogether" || key == "nobreak";
        if (!isPageBreak && !isSystemBreak && !isNoBreak) {
            errorMessage = "MuseReader does not recognize that layout break.";
            return false;
        }

        const mu::engraving::LayoutBreakType breakType = isNoBreak
            ? mu::engraving::LayoutBreakType::NOBREAK
            : (isPageBreak ? mu::engraving::LayoutBreakType::PAGE : mu::engraving::LayoutBreakType::LINE);
        mu::engraving::Measure* selectionAnchorAfterEdit = measure;
        mu::engraving::Measure* rangeStart = nullptr;
        mu::engraving::Measure* rangeEnd = nullptr;
        const bool hasSelectedRange = selectedMeasureRange(score, &rangeStart, &rangeEnd) && rangeStart && rangeEnd;
        if (hasSelectedRange) {
            selectionAnchorAfterEdit = isNoBreak ? rangeStart : rangeEnd;
        }
        if (isNoBreak) {
            if (rangeStart) {
                selectionAnchorAfterEdit = rangeStart;
            }
        }
        bool shouldMoveInternalSystemBreakToRangeEnd = false;
        if (isNoBreak && rangeStart && rangeEnd && rangeStart != rangeEnd) {
            // Keep a pre-existing system boundary at the selected range edge instead of
            // letting no-break reflow continue into the following system.
            for (mu::engraving::Measure* m = rangeStart; m && m != rangeEnd; m = m->nextMeasureMM()) {
                if (m->lineBreak()) {
                    shouldMoveInternalSystemBreakToRangeEnd = true;
                    break;
                }
            }
            if (rangeEnd->lineBreak() || rangeEnd->pageBreak() || rangeEnd->sectionBreak()) {
                shouldMoveInternalSystemBreakToRangeEnd = false;
            }
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader add layout break"));
        score->cmdToggleLayoutBreak(breakType);
        if (shouldMoveInternalSystemBreakToRangeEnd) {
            bool internalNoBreaksApplied = true;
            for (mu::engraving::Measure* m = rangeStart; m && m != rangeEnd; m = m->nextMeasureMM()) {
                if (!m->noBreak()) {
                    internalNoBreaksApplied = false;
                    break;
                }
            }
            if (internalNoBreaksApplied) {
                mu::engraving::EditSystemLocks::removeSystemLocksOnAddLayoutBreak(score, mu::engraving::LayoutBreakType::LINE, rangeEnd);
                rangeEnd->undoSetBreak(true, mu::engraving::LayoutBreakType::LINE);
            }
        }
        score->endCmd();
        if (mu::engraving::LayoutBreak* layoutBreak = layoutBreakElement(selectionAnchorAfterEdit, breakType)) {
            score->select(layoutBreak, mu::engraving::SelectType::SINGLE, 0);
        } else {
            score->select(selectionAnchorAfterEdit, mu::engraving::SelectType::SINGLE, 0);
        }
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool removeLayoutBreak(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        const mu::engraving::SystemLock* selectedSystemLock = nullptr;
        mu::engraving::MeasureBase* selectedLayoutBreakMeasure = nullptr;
        if (mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score)) {
            if (selectedItem->isSystemLockIndicator()) {
                mu::engraving::SystemLockIndicator* indicator = mu::engraving::toSystemLockIndicator(selectedItem);
                selectedSystemLock = indicator ? indicator->systemLock() : nullptr;
            } else if (selectedItem->isLayoutBreak()) {
                mu::engraving::LayoutBreak* layoutBreak = mu::engraving::toLayoutBreak(selectedItem);
                selectedLayoutBreakMeasure = layoutBreak ? layoutBreak->measure() : nullptr;
            }
        }

        mu::engraving::Measure* measure = activeMeasure(score);
        if (!measure && selectedLayoutBreakMeasure && selectedLayoutBreakMeasure->isMeasure()) {
            measure = mu::engraving::toMeasure(selectedLayoutBreakMeasure);
        }
        if (!measure && !selectedSystemLock && !selectedLayoutBreakMeasure) {
            errorMessage = "Select a measure or barline before removing a layout break.";
            return false;
        }

        mu::engraving::MeasureBase* selectionAfterRemove = selectedLayoutBreakMeasure ? selectedLayoutBreakMeasure : measure;
        score->startCmd(muse::TranslatableString::untranslatable("MuseReader remove layout break"));
        if (selectedSystemLock) {
            selectionAfterRemove = selectedSystemLock->endMB();
            mu::engraving::EditSystemLocks::undoRemoveSystemLock(score, selectedSystemLock);
        } else if (selectionAfterRemove) {
            selectionAfterRemove->undoSetBreak(false, mu::engraving::LayoutBreakType::LINE);
            selectionAfterRemove->undoSetBreak(false, mu::engraving::LayoutBreakType::PAGE);
            selectionAfterRemove->undoSetBreak(false, mu::engraving::LayoutBreakType::NOBREAK);
        }
        score->endCmd();
        if (selectionAfterRemove) {
            score->select(selectionAfterRemove, mu::engraving::SelectType::SINGLE, 0);
        }
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool fillSelectionWithSlashes(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (!score || score->selection().isNone()) {
            errorMessage = "Select a measure or range before filling with slashes.";
            return false;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader fill with slashes"));
        score->cmdSlashFill();
        if (!score->isMaster()) {
            // cmdSlashFill() updates linked chords as a group. In an excerpt,
            // NO_STEM can arrive through that propagation before the active
            // chord records its own property command. The first result looks
            // right, but redo restores the slash head with a visible stem.
            // Force an explicit active-view command into the same transaction.
            for (mu::engraving::Note* note : score->selection().uniqueNotes()) {
                mu::engraving::Chord* chord = note ? note->chord() : nullptr;
                if (!chord || !chord->noStem()) {
                    continue;
                }
                chord->setNoStem(false);
                chord->undoChangeProperty(mu::engraving::Pid::NO_STEM, true);
            }
        }
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool replaceSelectionWithRhythmicSlashes(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (!score || score->selection().isNone()) {
            errorMessage = "Select notes or a measure range before replacing with rhythmic slash notation.";
            return false;
        }

        const auto selectedNotes = score->selection().uniqueNotes();
        score->startCmd(muse::TranslatableString::untranslatable("MuseReader replace with rhythmic slashes"));
        score->cmdSlashRhythm();
        if (score->isMaster()) {
            // Chord::setSlash() changes Note::PLAY, a property MuseScore does
            // not normally propagate between linked scores. Aria plays the
            // active part directly, so a slash made in the full score must also
            // be silent there. Keep part-originated appearance edits local, as
            // MuseScore desktop does.
            for (mu::engraving::Note* note : selectedNotes) {
                if (!note) {
                    continue;
                }
                for (mu::engraving::EngravingObject* linked : note->linkList()) {
                    if (linked && linked != note && linked->isNote()) {
                        mu::engraving::toNote(linked)->undoChangeProperty(mu::engraving::Pid::PLAY, note->play());
                    }
                }
            }
        }
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool applyAutoSystemBreaks(const int measuresPerSystem,
                               const bool lockCurrentLayout,
                               const bool removeExisting,
                               msr::render::ScoreEditState& output,
                               std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        if (!removeExisting && !lockCurrentLayout && measuresPerSystem < 1) {
            errorMessage = "Choose at least one measure per system.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (!score) {
            errorMessage = "The score is not available.";
            return false;
        }

        mu::engraving::Measure* selectedStartMeasure = nullptr;
        mu::engraving::Measure* selectedEndMeasure = nullptr;
        const bool hasMultiMeasureRange = selectedMeasureRange(score, &selectedStartMeasure, &selectedEndMeasure)
            && selectedStartMeasure
            && selectedEndMeasure
            && selectedStartMeasure != selectedEndMeasure;
        const bool appliesToWholeScore = !hasMultiMeasureRange;
        if (appliesToWholeScore) {
            mu::engraving::Measure* firstMeasure = score->firstMeasure();
            mu::engraving::Measure* lastMeasure = score->lastMeasure();
            if (!firstMeasure || !lastMeasure || score->nstaves() == 0) {
                errorMessage = "There are no measures to update.";
                return false;
            }
            ::selectMeasureRange(score, firstMeasure, lastMeasure, 0, score->nstaves());
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader auto system breaks"));
        if (removeExisting) {
            mu::engraving::EditSystemLocks::addRemoveSystemLocks(score, 0, false);
        } else if (lockCurrentLayout) {
            mu::engraving::EditSystemLocks::addRemoveSystemLocks(score, 0, true);
        } else {
            mu::engraving::EditSystemLocks::addRemoveSystemLocks(score, measuresPerSystem, false);
        }
        score->endCmd();
        refreshAfterEdit();

        if (appliesToWholeScore) {
            score->deselectAll();
        }

        output = makeEditState(score);
        return true;
    }

    bool updateStaffSpacing(const double staffDistanceSpatium,
                            msr::render::ScoreEditState& output,
                            std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        if (staffDistanceSpatium < 3.0 || staffDistanceSpatium > 16.0) {
            errorMessage = "Staff spacing must be between 3 and 16 spaces.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        const auto sameValue = [](const double lhs, const double rhs) {
            return std::abs(lhs - rhs) <= 0.0001;
        };
        if (sameValue(score->style().styleS(mu::engraving::Sid::staffDistance).val(), staffDistanceSpatium)) {
            output = makeEditState(score);
            return true;
        }

        std::unordered_map<mu::engraving::Sid, mu::engraving::PropertyValue> styleValues;
        styleValues.emplace(mu::engraving::Sid::staffDistance, mu::engraving::PropertyValue(mu::engraving::Spatium(staffDistanceSpatium)));
        styleValues.emplace(mu::engraving::Sid::akkoladeDistance, mu::engraving::PropertyValue(mu::engraving::Spatium(staffDistanceSpatium)));
        styleValues.emplace(mu::engraving::Sid::minStaffSpread, mu::engraving::PropertyValue(mu::engraving::Spatium(staffDistanceSpatium)));
        styleValues.emplace(mu::engraving::Sid::maxStaffSpread, mu::engraving::PropertyValue(mu::engraving::Spatium(staffDistanceSpatium)));
        styleValues.emplace(mu::engraving::Sid::maxAkkoladeDistance, mu::engraving::PropertyValue(mu::engraving::Spatium(staffDistanceSpatium)));

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader update staff spacing"));
        score->undoChangeStyleValues(std::move(styleValues));
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool updatePageLayout(const double pageWidthMillimeters,
                          const double pageHeightMillimeters,
                          const double marginMillimeters,
                          const double staffSizeMillimeters,
                          const double staffSpacingSpatium,
                          const double systemSpacingSpatium,
                          msr::render::ScoreEditState& output,
                          std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        const double pageWidth = pageWidthMillimeters / mu::engraving::INCH;
        const double pageHeight = pageHeightMillimeters / mu::engraving::INCH;
        const double margin = marginMillimeters / mu::engraving::INCH;
        const double printableWidth = std::max(0.0, pageWidth - (margin * 2.0));
        const double staffSize = staffSizeMillimeters / mu::engraving::INCH * mu::engraving::DPI;

        mu::engraving::Score* score = activeScore();
        const auto sameValue = [](const double lhs, const double rhs) {
            return std::abs(lhs - rhs) <= 0.0001;
        };

        const bool pageSizeChanged = !sameValue(score->style().styleD(mu::engraving::Sid::pageWidth), pageWidth)
                                     || !sameValue(score->style().styleD(mu::engraving::Sid::pageHeight), pageHeight);
        const bool marginChanged = !sameValue(score->style().styleD(mu::engraving::Sid::pageOddLeftMargin), margin);
        const bool staffSizeChanged = !sameValue(score->style().spatium(), staffSize);
        const bool staffSpacingChanged = !sameValue(score->style().styleS(mu::engraving::Sid::staffDistance).val(),
                                                    staffSpacingSpatium);
        const bool systemSpacingChanged = !sameValue(score->style().styleS(mu::engraving::Sid::minSystemDistance).val(),
                                                     systemSpacingSpatium);

        // Only check the values being changed: a score from desktop may already use a value
        // outside these ranges, and that must not block an unrelated change such as paper size.
        if (pageSizeChanged && (pageWidthMillimeters < 100.0 || pageHeightMillimeters < 100.0)) {
            errorMessage = "Page size is too small.";
            return false;
        }

        if ((pageSizeChanged || marginChanged)
            && (marginMillimeters < 0.0 || marginMillimeters * 2.0 >= pageWidthMillimeters)) {
            errorMessage = "Page margins do not fit within the selected page size.";
            return false;
        }

        if (staffSizeChanged && (staffSizeMillimeters < 1.2 || staffSizeMillimeters > 2.4)) {
            errorMessage = "Staff size must be between 1.2 mm and 2.4 mm.";
            return false;
        }

        if (staffSpacingChanged && (staffSpacingSpatium < 3.0 || staffSpacingSpatium > 16.0)) {
            errorMessage = "Staff spacing must be between 3 and 16 spaces.";
            return false;
        }

        if (systemSpacingChanged && (systemSpacingSpatium < 4.0 || systemSpacingSpatium > 24.0)) {
            errorMessage = "System spacing must be between 4 and 24 spaces.";
            return false;
        }

        std::unordered_map<mu::engraving::Sid, mu::engraving::PropertyValue> styleValues;
        if (pageSizeChanged) {
            styleValues.emplace(mu::engraving::Sid::pageWidth, mu::engraving::PropertyValue(pageWidth));
            styleValues.emplace(mu::engraving::Sid::pageHeight, mu::engraving::PropertyValue(pageHeight));
        }
        if (pageSizeChanged || marginChanged) {
            styleValues.emplace(mu::engraving::Sid::pagePrintableWidth, mu::engraving::PropertyValue(printableWidth));
        }
        if (marginChanged) {
            styleValues.emplace(mu::engraving::Sid::pageEvenLeftMargin, mu::engraving::PropertyValue(margin));
            styleValues.emplace(mu::engraving::Sid::pageOddLeftMargin, mu::engraving::PropertyValue(margin));
            styleValues.emplace(mu::engraving::Sid::pageEvenTopMargin, mu::engraving::PropertyValue(margin));
            styleValues.emplace(mu::engraving::Sid::pageOddTopMargin, mu::engraving::PropertyValue(margin));
            styleValues.emplace(mu::engraving::Sid::pageEvenBottomMargin, mu::engraving::PropertyValue(margin));
            styleValues.emplace(mu::engraving::Sid::pageOddBottomMargin, mu::engraving::PropertyValue(margin));
        }
        if (staffSizeChanged) {
            styleValues.emplace(mu::engraving::Sid::spatium, mu::engraving::PropertyValue(staffSize));
        }
        if (staffSpacingChanged) {
            styleValues.emplace(mu::engraving::Sid::staffDistance, mu::engraving::PropertyValue(mu::engraving::Spatium(staffSpacingSpatium)));
            styleValues.emplace(mu::engraving::Sid::akkoladeDistance, mu::engraving::PropertyValue(mu::engraving::Spatium(staffSpacingSpatium)));
            styleValues.emplace(mu::engraving::Sid::minStaffSpread, mu::engraving::PropertyValue(mu::engraving::Spatium(staffSpacingSpatium)));
            styleValues.emplace(mu::engraving::Sid::maxStaffSpread, mu::engraving::PropertyValue(mu::engraving::Spatium(staffSpacingSpatium)));
            styleValues.emplace(mu::engraving::Sid::maxAkkoladeDistance, mu::engraving::PropertyValue(mu::engraving::Spatium(staffSpacingSpatium)));
        }
        if (systemSpacingChanged) {
            styleValues.emplace(mu::engraving::Sid::minSystemDistance, mu::engraving::PropertyValue(mu::engraving::Spatium(systemSpacingSpatium)));
            styleValues.emplace(mu::engraving::Sid::maxSystemDistance, mu::engraving::PropertyValue(mu::engraving::Spatium(systemSpacingSpatium)));
            styleValues.emplace(mu::engraving::Sid::minSystemSpread, mu::engraving::PropertyValue(mu::engraving::Spatium(systemSpacingSpatium)));
            styleValues.emplace(mu::engraving::Sid::maxSystemSpread, mu::engraving::PropertyValue(mu::engraving::Spatium(systemSpacingSpatium)));
        }

        if (styleValues.empty()) {
            output = makeEditState(score);
            return true;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader update page settings"));
        score->undoChangeStyleValues(std::move(styleValues));
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool updateLayoutOptions(const bool createMultiMeasureRests,
                             const bool hideEmptyStaves,
                             msr::render::ScoreEditState& output,
                             std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (!score) {
            errorMessage = "The score is not available.";
            return false;
        }

        std::unordered_map<mu::engraving::Sid, mu::engraving::PropertyValue> styleValues;
        if (score->style().styleB(mu::engraving::Sid::createMultiMeasureRests) != createMultiMeasureRests) {
            styleValues.emplace(mu::engraving::Sid::createMultiMeasureRests, mu::engraving::PropertyValue(createMultiMeasureRests));
        }
        if (score->style().styleB(mu::engraving::Sid::hideEmptyStaves) != hideEmptyStaves) {
            styleValues.emplace(mu::engraving::Sid::hideEmptyStaves, mu::engraving::PropertyValue(hideEmptyStaves));
        }

        if (!styleValues.empty()) {
            score->startCmd(muse::TranslatableString::untranslatable("MuseReader update layout options"));
            score->deselectAll();
            score->undoChangeStyleValues(std::move(styleValues));
            score->endCmd();
            relayoutActiveScore();
            refreshAfterEdit();
        }

        output = makeEditState(score);
        return true;
    }

    bool addTempo(const std::string& beatUnit,
                  const int bpm,
                  msr::render::ScoreEditState& output,
                  std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        if (bpm < 20 || bpm > 300) {
            errorMessage = "Tempo must be between 20 and 300 BPM.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::Measure* measure = activeMeasure(score);
        if (!measure) {
            errorMessage = "Select a measure before adding a tempo marking.";
            return false;
        }

        mu::engraving::Segment* segment = measure->undoGetSegment(mu::engraving::SegmentType::ChordRest, measure->tick());
        if (!segment) {
            errorMessage = "MuseReader could not find a measure position for that tempo marking.";
            return false;
        }

        const std::string key = normalizedCommandKey(beatUnit);
        muse::String tempoText;
        if (key == "quarter") {
            tempoText = muse::String(u"<sym>metNoteQuarterUp</sym> = %1").arg(bpm);
        } else if (key == "eighth") {
            tempoText = muse::String(u"<sym>metNote8thUp</sym> = %1").arg(bpm);
        } else if (key == "half") {
            tempoText = muse::String(u"<sym>metNoteHalfUp</sym> = %1").arg(bpm);
        } else if (key == "dottedquarter" || key == "quarterdot") {
            tempoText = muse::String(u"<sym>metNoteQuarterUp</sym><sym>space</sym><sym>metAugmentationDot</sym> = %1").arg(bpm);
        } else {
            errorMessage = "MuseReader does not recognize that tempo beat unit.";
            return false;
        }

        mu::engraving::TempoText* tempo = nullptr;
        for (mu::engraving::EngravingItem* annotation : segment->annotations()) {
            if (annotation && annotation->isTempoText()) {
                tempo = mu::engraving::toTempoText(annotation);
                break;
            }
        }

        const mu::engraving::BeatsPerSecond requestedTempo
            = mu::engraving::BeatsPerSecond::fromBPM(mu::engraving::BeatsPerMinute(static_cast<double>(bpm)));
        score->startCmd(muse::TranslatableString::untranslatable(tempo ? "MuseReader edit tempo" : "MuseReader add tempo"));
        if (!tempo) {
            tempo = mu::engraving::Factory::createTempoText(segment);
            tempo->setParent(segment);
            tempo->setTrack(0);
            // Set every serialized property before undoAddElement() makes the
            // linked system-item copies. Changing these directly afterwards
            // leaves the parts at TempoText's default 120 BPM/followText=false.
            tempo->setXmlText(tempoText);
            tempo->setTempo(requestedTempo);
            tempo->setFollowText(true);
            score->undoAddElement(tempo);
        } else {
            mu::engraving::EngravingItem* tempoItem = tempo;
            tempoItem->undoChangeProperty(mu::engraving::Pid::TEXT, tempoText);
            tempoItem->undoChangeProperty(mu::engraving::Pid::TEMPO, requestedTempo);
            tempoItem->undoChangeProperty(mu::engraving::Pid::TEMPO_FOLLOW_TEXT, true);
        }

        tempo->updateTempo();
        score->setTempo(segment, tempo->tempo());
        score->endCmd();
        refreshAfterEdit();
        score->select(tempo, mu::engraving::SelectType::SINGLE, tempo->staffIdx());
        output = makeEditState(score);
        return true;
    }

    bool updateTimeSignature(const int numerator,
                             const int denominator,
                             const bool commonTime,
                             const bool cutTime,
                             const bool fromStart,
                             msr::render::ScoreEditState& output,
                             std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        if (numerator <= 0 || denominator <= 0) {
            errorMessage = "Time signature numerator and denominator must be positive.";
            return false;
        }
        if (denominator != 1 && denominator != 2 && denominator != 4 && denominator != 8 && denominator != 16) {
            errorMessage = "Time signature denominator must be one of 1, 2, 4, 8, or 16.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::Measure* measure = activeMeasure(score, fromStart);
        if (!measure) {
            errorMessage = "Select a measure before changing the time signature.";
            return false;
        }

        const mu::engraving::TimeSigType type = cutTime
            ? mu::engraving::TimeSigType::ALLA_BREVE
            : (commonTime ? mu::engraving::TimeSigType::FOUR_FOUR : mu::engraving::TimeSigType::NORMAL);

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader change time signature"));
        mu::engraving::TimeSig* timeSig = mu::engraving::Factory::createTimeSig(score->dummy()->segment());
        timeSig->setSig(mu::engraving::Fraction(numerator, denominator), type);
        score->cmdAddTimeSig(measure, 0, timeSig, false);
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool updateKeySignature(const int keyValue,
                            const bool fromStart,
                            msr::render::ScoreEditState& output,
                            std::string& errorMessage)
    {
        if (!updateKeySignature(keyValue, fromStart, errorMessage)) {
            return false;
        }

        output = makeEditState(activeScore());
        return true;
    }

    bool insertNote(const int pageIndex,
                    const double normalizedX,
                    const double normalizedY,
                    msr::render::ScoreEditState& output,
                    std::string& errorMessage)
    {
        return insertNoteWithPitch(pageIndex, normalizedX, normalizedY, std::nullopt, false, std::nullopt, output, errorMessage);
    }

    bool insertNoteWithAccidental(const int pageIndex,
                                  const double normalizedX,
                                  const double normalizedY,
                                  const int accidentalKind,
                                  msr::render::ScoreEditState& output,
                                  std::string& errorMessage)
    {
        return insertNoteWithPitch(pageIndex, normalizedX, normalizedY, std::nullopt, false, std::optional<int>(accidentalKind), output, errorMessage);
    }

    bool insertNoteWithPitch(const int pageIndex,
                             const double normalizedX,
                             const double normalizedY,
                             const int pitchClass,
                             const bool preferFlats,
                             msr::render::ScoreEditState& output,
                             std::string& errorMessage)
    {
        return insertNoteWithPitch(pageIndex, normalizedX, normalizedY, std::optional<int>(pitchClass), preferFlats, std::nullopt, output, errorMessage);
    }

    bool noteEntryPreview(const int pageIndex,
                          const double normalizedX,
                          const double normalizedY,
                          const int durationCode,
                          const bool rest,
                          const int accidentalKind,
                          msr::render::NoteEntryPreviewState& output,
                          std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::Page* page = pageForIndex(score, pageIndex);
        if (!page) {
            errorMessage = "That page is unavailable in the open score session.";
            return false;
        }

        mu::engraving::InputState& inputState = score->inputState();
        if (!inputState.noteEntryMode()) {
            return true;
        }

        const mu::engraving::DurationType durationType = durationTypeForCode(durationCode);
        if (durationType == mu::engraving::DurationType::V_INVALID) {
            errorMessage = "MuseReader received an unsupported note duration for preview.";
            return false;
        }

        mu::engraving::PointF pagePoint = pointForNormalizedPagePosition(page, normalizedX, normalizedY);
        mu::engraving::Position position;
        if (!getPagePosition(score, page, &position, pagePoint, inputState.voice())) {
            return true;
        }

        mu::engraving::Staff* staff = score->staff(position.staffIdx);
        if (!staff || !isStandardStaff(staff, position.segment ? position.segment->tick() : mu::engraving::Fraction(0, 1))) {
            return true;
        }
        normalizePointInputPositionForPutNote(staff, position);
        biasDuplicatePointInputAwayFromExistingChord(score, page, staff, pagePoint, position);

        mu::engraving::Segment* segment = position.segment;
        double segmentSkylineTopY = 0.0;
        double segmentSkylineBottomY = 0.0;
        if (segment) {
            if (mu::engraving::Segment* actualSegment = segment->prev1enabled()) {
                segment = actualSegment;
                segmentSkylineTopY = actualSegment->elementsTopOffsetFromSkyline(position.staffIdx);
                segmentSkylineBottomY = actualSegment->elementsBottomOffsetFromSkyline(position.staffIdx);
            }
        }
        if (!segment || !segment->measure()) {
            return true;
        }

        mu::engraving::TDuration duration(durationType);
        const mu::engraving::Fraction tick = segment->tick();
        const double mag = staff->staffMag(tick);
        mu::engraving::ShadowNote shadowNote(score);
        shadowNote.setVisible(true);
        shadowNote.mutldata()->setMag(mag);
        shadowNote.setTick(tick);
        shadowNote.setStaffIdx(position.staffIdx);
        shadowNote.setVoice(inputState.voice());
        shadowNote.setLineIndex(position.line);
        shadowNote.setColor(voiceSelectionColor(static_cast<int>(inputState.voice())));

        mu::engraving::SymId symNotehead = mu::engraving::SymId::noSym;
        if (rest) {
            mu::engraving::Rest* previewRest = mu::engraving::Factory::createRest(score->dummy()->segment(), duration.type());
            previewRest->setTicks(duration.fraction());
            symNotehead = previewRest->getSymbol(duration.type(), 0, staff->lines(tick));
            shadowNote.setState(symNotehead, duration, true, segmentSkylineTopY, segmentSkylineBottomY);
            delete previewRest;
        } else {
            symNotehead = mu::engraving::Note::noteHead(0, mu::engraving::NoteHeadGroup::HEAD_NORMAL, duration.headType());
            const std::optional<mu::engraving::AccidentalType> accidentalType = accidentalKind >= 0
                ? accidentalTypeForKind(accidentalKind)
                : std::optional<mu::engraving::AccidentalType>(mu::engraving::AccidentalType::NONE);
            shadowNote.setState(
                symNotehead,
                duration,
                false,
                segmentSkylineTopY,
                segmentSkylineBottomY,
                accidentalType.value_or(mu::engraving::AccidentalType::NONE),
                inputState.articulationIds()
            );
        }

        if (mag > 1.0) {
            const double xOffset = (mag - 1.0) * 0.5 * shadowNote.symWidth(symNotehead);
            if (shadowNote.computeUp()) {
                position.pos.rx() += xOffset;
            } else {
                position.pos.rx() -= xOffset;
            }
        }

        const double relX = position.pos.x() - segment->measure()->pageBoundingRect().left();
        position.pos.rx() -= std::min(relX - score->style().styleMM(mu::engraving::Sid::barNoteDistance), 0.0);

        score->renderer()->layoutItem(&shadowNote);
        shadowNote.setPos(position.pos);

        if (!renderNoteEntryPreviewOverlay(output, page, score, shadowNote)) {
            return true;
        }
        output.pageIndex = pageIndex;
        return true;
    }

    bool insertPitchAtCursor(const int pitchClass,
                             const bool preferFlats,
                             const bool addToCurrentChord,
                             msr::render::ScoreEditState& output,
                             std::string& errorMessage)
    {
        const int normalizedClass = normalizedPitchClass(pitchClass);
        mu::engraving::Note* selectedNote = currentSelectedNote(activeScore());
        const int basePitch = selectedNote ? selectedNote->pitch() : 60;
        const int octaveBase = (basePitch / 12) * 12;
        int targetPitch = octaveBase + normalizedClass;
        if (!mu::engraving::pitchIsValid(targetPitch)) {
            targetPitch += targetPitch < 0 ? 12 : -12;
        }

        return insertMIDIPitchAtCursor(targetPitch, preferFlats, addToCurrentChord, false, output, errorMessage);
    }

    bool insertMIDIPitchAtCursor(const int midiPitch,
                                 const bool preferFlats,
                                 const bool addToCurrentChord,
                                 msr::render::ScoreEditState& output,
                                 std::string& errorMessage)
    {
        return insertMIDIPitchAtCursor(midiPitch, preferFlats, addToCurrentChord, true, output, errorMessage);
    }

    bool insertMIDIPitchAtCursor(const int midiPitch,
                                 const bool preferFlats,
                                 const bool addToCurrentChord,
                                 const bool applyExactPitch,
                                 msr::render::ScoreEditState& output,
                                 std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::InputState& inputState = score->inputState();
        const mu::engraving::voice_idx_t requestedVoice = inputState.voice();
        if (!inputState.noteEntryMode()) {
            errorMessage = "Enable note input before using the keyboard to enter notes.";
            return false;
        }

        if (selectedMeasureRange(score, nullptr, nullptr)) {
            if (mu::engraving::ChordRest* chordRest = selectedMeasureChordRest(score)) {
                configureInputCursorForChordRest(score, chordRest, false);
                inputState.setVoice(requestedVoice);
            }
        } else if (!inputState.isValid()) {
            if (mu::engraving::ChordRest* chordRest = selectedChordRest(score)) {
                configureInputCursorForChordRest(score, chordRest, false);
                inputState.setVoice(requestedVoice);
            }
        }

        normalizeNoteEntryDuration(inputState);
        if (!inputState.isValid()) {
            errorMessage = "Tap a standard staff position before entering notes from the keyboard.";
            return false;
        }

        mu::engraving::Staff* staff = inputState.staff();
        if (!isStandardStaff(staff, inputState.tick())) {
            errorMessage = "Keyboard note entry currently works only on standard staves.";
            return false;
        }

        if (addToCurrentChord) {
            mu::engraving::Note* anchorNote = currentSelectedNote(score);
            if (!anchorNote) {
                anchorNote = lastInputNote(score);
            }
            mu::engraving::Chord* chord = anchorNote ? anchorNote->chord() : nullptr;
            if (chord) {
                if (applyExactPitch) {
                    score->startCmd(muse::TranslatableString::untranslatable("MuseReader stacked chord MIDI input"));
                    score->select(anchorNote, mu::engraving::SelectType::SINGLE, anchorNote->staffIdx());
                    configureInputCursorForChordRest(score, chord, false);
                    mu::engraving::Note* addedNote = score->addMidiPitch(midiPitch, true, true);
                    if (!addedNote) {
                        score->endCmd(true);
                        errorMessage = "MuseReader could not add that MIDI pitch to the current chord.";
                        return false;
                    }
                    score->select(addedNote, mu::engraving::SelectType::SINGLE, addedNote->staffIdx());
                    configureInputCursorForChordRest(score, chord, false);
                    score->endCmd();
                    refreshAfterEdit();
                    output = makeEditState(score);
                    return true;
                }

                mu::engraving::NoteInputParams params;
                if (!score->resolveNoteInputParams(diatonicNoteIndexForPitchClass(midiPitch, preferFlats), false, params)) {
                    errorMessage = "MuseReader could not resolve that pitch for the current chord.";
                    return false;
                }
                std::vector<mu::engraving::Note*> existingNotes = chord->notes();

                score->startCmd(muse::TranslatableString::untranslatable("MuseReader stacked chord note input"));
                score->select(anchorNote, mu::engraving::SelectType::SINGLE, anchorNote->staffIdx());
                score->cmdAddPitch(params, true, false);
                mu::engraving::Note* addedNote = nullptr;
                for (mu::engraving::Note* note : chord->notes()) {
                    if (std::find(existingNotes.begin(), existingNotes.end(), note) == existingNotes.end()) {
                        addedNote = note;
                        break;
                    }
                }
                if (!addedNote) {
                    score->endCmd(true);
                    errorMessage = "MuseReader could not add that pitch to the current chord.";
                    return false;
                }
                score->select(addedNote, mu::engraving::SelectType::SINGLE, addedNote->staffIdx());
                configureInputCursorForChordRest(score, chord, false);
                score->endCmd();
                refreshAfterEdit();
                output = makeEditState(score);
                return true;
            }
        }

        mu::engraving::Measure* selectedStartMeasure = nullptr;
        mu::engraving::Measure* selectedEndMeasure = nullptr;
        mu::engraving::staff_idx_t selectedStaffStart = 0;
        mu::engraving::staff_idx_t selectedStaffEnd = 1;
        if (requestedVoice == 0
            && selectedSingleOrMMRestMeasureRange(score, &selectedStartMeasure, &selectedEndMeasure, &selectedStaffStart, &selectedStaffEnd)) {
            score->startCmd(muse::TranslatableString::untranslatable("MuseReader replace measure with keyboard note"));
            ::selectMeasureRange(score, selectedStartMeasure, selectedEndMeasure, selectedStaffStart, selectedStaffEnd);
            score->cmdDeleteSelection();

            mu::engraving::ChordRest* replacementRest = firstStandardChordRestInMeasure(score, selectedStartMeasure, selectedStaffStart);
            if (!replacementRest) {
                score->endCmd(true);
                errorMessage = "MuseReader could not create a note entry point in that measure.";
                return false;
            }

            if (!applyExactPitch) {
                configureInputCursorForChordRest(score, replacementRest, false);
                inputState.setVoice(requestedVoice);
                inputState.setRest(false);
                normalizeNoteEntryDuration(inputState);

                mu::engraving::NoteInputParams params;
                if (!score->resolveNoteInputParams(diatonicNoteIndexForPitchClass(midiPitch, preferFlats), false, params)) {
                    score->endCmd(true);
                    errorMessage = "MuseReader could not resolve that pitch at the current cursor.";
                    return false;
                }

                score->cmdAddPitch(params, false, false);
                if (mu::engraving::Note* replacementNote = lastInputNote(score)) {
                    score->select(replacementNote, mu::engraving::SelectType::SINGLE, replacementNote->staffIdx());
                    if (addToCurrentChord && replacementNote->chord()) {
                        configureInputCursorForChordRest(score, replacementNote->chord(), false);
                    } else {
                        score->nextInputPos(replacementNote->chord(), false);
                    }
                }
                score->endCmd();
                refreshAfterEdit();
                output = makeEditState(score);
                return true;
            }

            configureInputCursorForChordRest(score, replacementRest, false);
            inputState.setVoice(requestedVoice);
            inputState.setRest(false);
            normalizeNoteEntryDuration(inputState);
            mu::engraving::Note* replacementNote = score->addMidiPitch(midiPitch, false, true);
            if (!replacementNote) {
                score->endCmd(true);
                errorMessage = "MuseReader could not enter that MIDI pitch at the current cursor.";
                return false;
            }
            score->select(replacementNote, mu::engraving::SelectType::SINGLE, replacementNote->staffIdx());
            if (addToCurrentChord && replacementNote->chord()) {
                configureInputCursorForChordRest(score, replacementNote->chord(), false);
            } else {
                score->nextInputPos(replacementNote->chord(), false);
                appendMeasureIfInputCursorReachedEnd(score);
            }
            score->endCmd();
            refreshAfterEdit();
            output = makeEditState(score);
            return true;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader keyboard note input"));
        inputState.setRest(false);
        if (applyExactPitch) {
            mu::engraving::Note* insertedNote = score->addMidiPitch(midiPitch, false, true);
            if (!insertedNote) {
                score->endCmd(true);
                errorMessage = "MuseReader could not enter that MIDI pitch at the current cursor.";
                return false;
            }
            if (addToCurrentChord && insertedNote->chord()) {
                score->select(insertedNote, mu::engraving::SelectType::SINGLE, insertedNote->staffIdx());
                configureInputCursorForChordRest(score, insertedNote->chord(), false);
            } else {
                appendMeasureIfInputCursorReachedEnd(score);
            }
            score->endCmd();
            refreshAfterEdit();
            output = makeEditState(score);
            return true;
        }

        mu::engraving::NoteInputParams params;
        if (!score->resolveNoteInputParams(diatonicNoteIndexForPitchClass(midiPitch, preferFlats), false, params)) {
            score->endCmd(true);
            errorMessage = "MuseReader could not resolve that pitch at the current cursor.";
            return false;
        }

        score->cmdAddPitch(params, false, false);
        mu::engraving::Note* insertedNote = lastInputNote(score);
        if (addToCurrentChord) {
            insertedNote = lastInputNote(score);
            if (insertedNote && insertedNote->chord()) {
                score->select(insertedNote, mu::engraving::SelectType::SINGLE, insertedNote->staffIdx());
                configureInputCursorForChordRest(score, insertedNote->chord(), false);
            }
        } else {
            appendMeasureIfInputCursorReachedEnd(score);
        }
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool insertMIDIChordAtCursor(const std::vector<int>& midiPitches,
                                 const bool preferFlats,
                                 msr::render::ScoreEditState& output,
                                 std::string& errorMessage)
    {
        if (midiPitches.empty()) {
            errorMessage = "MuseReader received an empty MIDI chord.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::UndoStack* undoStack = score ? score->undoStack() : nullptr;
        const size_t firstCommandIndex = undoStack ? undoStack->currentIndex() : 0;
        msr::render::ScoreEditState intermediateState;
        for (size_t index = 0; index < midiPitches.size(); ++index) {
            const int midiPitch = midiPitches.at(index);
            if (!mu::engraving::pitchIsValid(midiPitch)) {
                errorMessage = "MuseReader received an unsupported MIDI pitch.";
                return false;
            }

            if (!insertMIDIPitchAtCursor(midiPitch, preferFlats, index > 0, true, intermediateState, errorMessage)) {
                // Do not leave a partial chord when a later pitch fails.
                while (undoStack && undoStack->currentIndex() > firstCommandIndex) {
                    score->undoRedo(true, nullptr);
                }
                if (undoStack) {
                    undoStack->cleanRedoStack();
                }
                return false;
            }
        }

        // Each pitch uses MuseScore's normal note-entry command. Coalesce those
        // macros so the public "insert chord" operation is one user-visible undo.
        if (undoStack && undoStack->currentIndex() > firstCommandIndex) {
            undoStack->mergeCommands(firstCommandIndex);
        }

        score = activeScore();
        mu::engraving::Chord* chord = nullptr;
        if (mu::engraving::Note* selectedNote = currentSelectedNote(score)) {
            chord = selectedNote->chord();
        }
        if (!chord) {
            if (mu::engraving::ChordRest* chordRest = selectedChordRest(score); chordRest && chordRest->isChord()) {
                chord = mu::engraving::toChord(chordRest);
            }
        }

        if (chord) {
            score->nextInputPos(chord, false);
            appendMeasureIfInputCursorReachedEnd(score);
        }

        output = makeEditState(score);
        return true;
    }

    bool removeMIDIPitchFromCurrentChord(const int midiPitch,
                                         msr::render::ScoreEditState& output,
                                         std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        if (!mu::engraving::pitchIsValid(midiPitch)) {
            errorMessage = "MuseReader received an unsupported MIDI pitch.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::Note* anchorNote = currentSelectedNote(score);
        // insertMIDIChordAtCursor() advances InputState after leaving the new
        // chord selected. A MIDI note-off/removal must act on that explicit
        // selection, not on the next cursor position.
        if (!anchorNote && score->inputState().noteEntryMode()) {
            anchorNote = lastInputNote(score, false);
        }

        mu::engraving::Chord* chord = anchorNote ? anchorNote->chord() : nullptr;
        if (!chord) {
            if (mu::engraving::ChordRest* chordRest = selectedChordRest(score); chordRest && chordRest->isChord()) {
                chord = mu::engraving::toChord(chordRest);
            }
        }
        if (!chord) {
            errorMessage = "Select a chord before removing a note from it.";
            return false;
        }

        std::vector<mu::engraving::Note*> notes = chord->notes();
        if (notes.size() <= 1) {
            output = makeEditState(score);
            return true;
        }

        mu::engraving::Note* targetNote = nullptr;
        for (mu::engraving::Note* note : notes) {
            if (note && note->pitch() == midiPitch) {
                targetNote = note;
                break;
            }
        }
        if (!targetNote) {
            output = makeEditState(score);
            return true;
        }

        mu::engraving::Note* remainingNote = nullptr;
        for (mu::engraving::Note* note : notes) {
            if (note && note != targetNote) {
                remainingNote = note;
                break;
            }
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader remove chord note"));
        score->deleteItem(targetNote);
        if (remainingNote) {
            score->select(remainingNote, mu::engraving::SelectType::SINGLE, remainingNote->staffIdx());
        }
        configureInputCursorForChordRest(score, chord, false);
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool insertNoteWithPitch(const int pageIndex,
                             const double normalizedX,
                             const double normalizedY,
                             const std::optional<int> pitchClass,
                             const bool preferFlats,
                             const std::optional<int> accidentalKind,
                             msr::render::ScoreEditState& output,
                             std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::Page* page = pageForIndex(score, pageIndex);
        if (!page) {
            errorMessage = "That page is unavailable in the open score session.";
            return false;
        }

        mu::engraving::InputState& inputState = score->inputState();
        if (!inputState.noteEntryMode()) {
            errorMessage = "Enable note input before tapping the staff to enter notes.";
            return false;
        }

        mu::engraving::PointF pagePoint = pointForNormalizedPagePosition(page, normalizedX, normalizedY);
        mu::engraving::Position position;
        if (!getPagePosition(score, page, &position, pagePoint, inputState.voice())) {
            errorMessage = "Tap inside a staff to enter a note or rest.";
            return false;
        }

        mu::engraving::Staff* staff = score->staff(position.staffIdx);
        if (!isStandardStaff(staff, position.segment->tick())) {
            errorMessage = "Tap note entry currently works only on standard staves.";
            return false;
        }
        normalizePointInputPositionForPutNote(staff, position);
        biasDuplicatePointInputAwayFromExistingChord(score, page, staff, pagePoint, position);
        mu::engraving::Measure* affectedMeasure = position.segment ? position.segment->measure() : nullptr;
        const mu::engraving::staff_idx_t affectedStaffIdx = position.staffIdx;
        const mu::engraving::track_idx_t requestedTrack = affectedStaffIdx * mu::engraving::VOICES + inputState.voice();
        inputState.setTrack(requestedTrack);
        inputState.setSegment(position.segment);

        std::optional<mu::engraving::AccidentalType> requestedAccidentalType = mu::engraving::AccidentalType::NONE;
        if (accidentalKind.has_value() && !inputState.rest()) {
            requestedAccidentalType = accidentalTypeForKind(*accidentalKind);
            if (!requestedAccidentalType.has_value()) {
                errorMessage = "MuseReader does not recognize that accidental.";
                return false;
            }
        }
        // Swift owns the one-shot accidental choice. Explicitly synchronize even
        // the absence of a choice so a prior MuseScore InputState value cannot
        // sharpen or flatten a later staff/Pencil note.
        inputState.setAccidentalType(inputState.rest()
            ? mu::engraving::AccidentalType::NONE
            : *requestedAccidentalType);

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader insert note"));
        const muse::Ret insertResult = score->putNote(canvasPointForPagePoint(page, pagePoint), false, false);
        const bool insertSucceeded = static_cast<bool>(insertResult);
        inputState.setAccidentalType(mu::engraving::AccidentalType::NONE);
        if (!insertSucceeded) {
            score->endCmd(true);
            errorMessage = insertResult.text().empty() ? "MuseReader could not place a note at that position." : insertResult.text();
            return false;
        }
        if (pitchClass.has_value() && !inputState.rest()) {
            if (!applyDiatonicPitchClassToNote(score, lastInputNote(score, false), *pitchClass, preferFlats, errorMessage)) {
                score->endCmd(true);
                return false;
            }
        }
        appendMeasureIfInputCursorReachedEnd(score);
        if (affectedMeasure) {
            affectedMeasure->checkMultiVoices(affectedStaffIdx);
        }

        score->endCmd();
        refreshAfterEdit();

        if (mu::engraving::Note* insertedNote = lastInputNote(score, false)) {
            score->select(insertedNote, mu::engraving::SelectType::SINGLE, insertedNote->staffIdx());
        }

        output = makeEditState(score);
        return true;
    }

    bool deleteSelection(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (score->selection().isNone()) {
            output = makeEditState(score);
            return true;
        }

        if (mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score)) {
            if (selectedItem->isLayoutBreak() || selectedItem->isSystemLockIndicator()) {
                return removeLayoutBreak(output, errorMessage);
            }
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader delete selection"));
        score->cmdDeleteSelection();
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool clearSelectedMeasure(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::Measure* startMeasure = nullptr;
        mu::engraving::Measure* endMeasure = nullptr;
        mu::engraving::staff_idx_t staffStart = muse::nidx;
        mu::engraving::staff_idx_t staffEnd = muse::nidx;
        if (selectedMeasureRange(score, &startMeasure, &endMeasure)) {
            staffStart = std::min(score->selection().staffStart(), score->nstaves() - 1);
            staffEnd = std::clamp(score->selection().staffEnd(), staffStart + 1, score->nstaves());
        } else {
            startMeasure = currentSelectedMeasure(score);
            endMeasure = startMeasure;
            staffStart = activeStaffIndex(score);
            if (staffStart != muse::nidx) {
                staffEnd = std::min(staffStart + 1, score->nstaves());
            }
        }
        if (!startMeasure || !endMeasure) {
            errorMessage = "Select one or more measures before clearing them.";
            return false;
        }
        if (staffStart == muse::nidx || staffStart >= score->nstaves() || staffEnd <= staffStart) {
            errorMessage = "Select the staff you want to clear.";
            return false;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader clear measure"));
        ::selectMeasureRange(score, startMeasure, endMeasure, staffStart, staffEnd);
        score->cmdDeleteSelection();
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool removeSelectedMeasure(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::Measure* startMeasure = nullptr;
        mu::engraving::Measure* endMeasure = nullptr;
        if (!selectedMeasureRange(score, &startMeasure, &endMeasure)) {
            startMeasure = currentSelectedMeasure(score);
            endMeasure = startMeasure;
        }
        if (!startMeasure || !endMeasure) {
            errorMessage = "Select one or more measures before removing them.";
            return false;
        }

        mu::engraving::Score* structuralScore = score;
        mu::engraving::Measure* structuralStart = startMeasure;
        mu::engraving::Measure* structuralEnd = endMeasure;
        if (score != m_masterScore.get()) {
            structuralScore = m_masterScore.get();
            structuralStart = structuralScore ? structuralScore->tick2measure(startMeasure->tick()) : nullptr;
            structuralEnd = structuralScore ? structuralScore->tick2measure(endMeasure->tick()) : nullptr;
        }

        if (!structuralScore || !structuralStart || !structuralEnd) {
            errorMessage = "MuseReader could not map that part measure back to the full score.";
            return false;
        }
        if (structuralStart == structuralScore->firstMeasure() && structuralEnd == structuralScore->lastMeasure()) {
            errorMessage = "The last measure in a score cannot be removed.";
            return false;
        }

        structuralScore->startCmd(muse::TranslatableString::untranslatable("MuseReader remove measure"));
        structuralScore->deleteMeasures(structuralStart, structuralEnd);
        structuralScore->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool addMeasures(const int count, msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        if (count <= 0 || count > 64) {
            errorMessage = "Add between 1 and 64 measures at a time.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::Measure* insertBefore = nullptr;
        mu::engraving::Measure* startMeasure = nullptr;
        mu::engraving::Measure* endMeasure = nullptr;
        if (selectedMeasureRange(score, &startMeasure, &endMeasure) && endMeasure) {
            insertBefore = endMeasure->nextMeasure();
        } else if (mu::engraving::Measure* measure = activeMeasure(score)) {
            insertBefore = measure->nextMeasure();
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader add measures"));
        mu::engraving::MeasureBase* firstInserted = nullptr;
        mu::engraving::MeasureBase* lastInserted = nullptr;
        for (int index = 0; index < count; ++index) {
            mu::engraving::MeasureBase* inserted = score->insertMeasure(mu::engraving::ElementType::MEASURE, insertBefore);
            if (!inserted) {
                score->endCmd(true);
                errorMessage = "MuseScore could not add measures at the selected location.";
                return false;
            }
            if (!firstInserted) {
                firstInserted = inserted;
            }
            lastInserted = inserted;
        }
        score->endCmd();
        refreshAfterEdit();

        if (firstInserted && lastInserted && firstInserted->isMeasure() && lastInserted->isMeasure()) {
            ::selectMeasureRange(score, mu::engraving::toMeasure(firstInserted), mu::engraving::toMeasure(lastInserted));
        }
        output = makeEditState(score);
        return true;
    }

    bool resetTemplateMeasures(const int count, msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        if (count <= 0 || count > 256) {
            errorMessage = "Choose between 1 and 256 measures.";
            return false;
        }

        mu::engraving::Score* structuralScore = m_masterScore.get();
        if (!structuralScore || !structuralScore->firstMeasure()) {
            errorMessage = "This score has no measures.";
            return false;
        }

        structuralScore->startCmd(muse::TranslatableString::untranslatable("MuseReader reset template measures"));
        structuralScore->clearSystemLocks();

        if (mu::engraving::Measure* first = structuralScore->firstMeasure()) {
            structuralScore->deleteMeasures(first, structuralScore->lastMeasure());
        }

        mu::engraving::MeasureBase* firstInserted = nullptr;
        mu::engraving::MeasureBase* lastInserted = nullptr;
        for (int index = 0; index < count; ++index) {
            mu::engraving::MeasureBase* inserted = structuralScore->insertMeasure(mu::engraving::ElementType::MEASURE, nullptr);
            if (!inserted) {
                structuralScore->endCmd(true);
                errorMessage = "MuseScore could not create fresh template measures.";
                return false;
            }
            if (!firstInserted) {
                firstInserted = inserted;
            }
            lastInserted = inserted;
        }

        structuralScore->endCmd();
        refreshAfterEdit();

        mu::engraving::Score* score = activeScore();
        if (firstInserted && lastInserted && firstInserted->isMeasure() && lastInserted->isMeasure()) {
            ::selectMeasureRange(score, mu::engraving::toMeasure(firstInserted), mu::engraving::toMeasure(firstInserted));
        }
        output = makeEditState(score);
        return true;
    }

    bool setRegularMeasureCount(const int count, msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        if (count <= 0 || count > 256) {
            errorMessage = "Choose between 1 and 256 measures.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::Score* structuralScore = m_masterScore.get();
        if (!structuralScore || !structuralScore->firstMeasure()) {
            errorMessage = "This score has no measures.";
            return false;
        }

        mu::engraving::Measure* first = structuralScore->firstMeasure();
        const bool hasPickup = first->irregular() || (first->ticks() < first->timesig());
        const int desiredTotal = count + (hasPickup ? 1 : 0);
        int currentTotal = 0;
        for (mu::engraving::Measure* measure = structuralScore->firstMeasure(); measure; measure = measure->nextMeasure()) {
            ++currentTotal;
        }

        if (currentTotal == desiredTotal) {
            output = makeEditState(score);
            return true;
        }

        structuralScore->startCmd(muse::TranslatableString::untranslatable("MuseReader set measure count"));
        if (currentTotal < desiredTotal) {
            const int missing = desiredTotal - currentTotal;
            for (int index = 0; index < missing; ++index) {
                if (!structuralScore->insertMeasure(mu::engraving::ElementType::MEASURE, nullptr)) {
                    structuralScore->endCmd(true);
                    errorMessage = "MuseScore could not add enough measures.";
                    return false;
                }
            }
        } else {
            mu::engraving::Measure* firstToDelete = structuralScore->firstMeasure();
            for (int index = 0; index < desiredTotal && firstToDelete; ++index) {
                firstToDelete = firstToDelete->nextMeasure();
            }
            mu::engraving::Measure* last = structuralScore->lastMeasure();
            if (!firstToDelete || !last) {
                structuralScore->endCmd(true);
                errorMessage = "MuseScore could not find measures to remove.";
                return false;
            }
            structuralScore->deleteMeasures(firstToDelete, last);
        }
        structuralScore->endCmd();
        refreshAfterEdit();

        score = activeScore();
        mu::engraving::Measure* selectedMeasure = nullptr;
        if (score) {
            selectedMeasure = score->firstMeasure();
        }
        if (score && selectedMeasure) {
            ::selectMeasureRange(score, selectedMeasure, selectedMeasure);
        }
        output = makeEditState(score);
        return true;
    }

    bool firstMeasurePickupState(msr::render::PickupMeasureState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Measure* measure = m_masterScore ? m_masterScore->firstMeasure() : nullptr;
        if (!measure) {
            errorMessage = "This score has no measures.";
            return false;
        }

        const mu::engraving::Fraction nominal = measure->timesig();
        const mu::engraving::Fraction actual = measure->ticks();
        output.nominalNumerator = nominal.numerator();
        output.nominalDenominator = nominal.denominator();
        output.actualNumerator = actual.numerator();
        output.actualDenominator = actual.denominator();
        output.isPickup = measure->irregular() || (actual < nominal);
        return true;
    }

    bool setFirstMeasurePickup(const int numerator,
                               const int denominator,
                               msr::render::ScoreEditState& output,
                               std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        if (numerator <= 0 || denominator <= 0) {
            errorMessage = "Choose a valid pickup length.";
            return false;
        }

        mu::engraving::Measure* measure = m_masterScore ? m_masterScore->firstMeasure() : nullptr;
        if (!measure) {
            errorMessage = "This score has no measures to convert.";
            return false;
        }

        const mu::engraving::Fraction nominal = measure->timesig();
        mu::engraving::Fraction pickup(numerator, denominator);
        pickup.reduce();
        if (pickup <= mu::engraving::Fraction(0, 1) || pickup >= nominal) {
            errorMessage = "A pickup measure must be shorter than one full measure.";
            return false;
        }

        auto logFirstMeasureSpanners = [&](const char* phase) {
            mu::engraving::Measure* first = m_masterScore ? m_masterScore->firstMeasure() : nullptr;
            if (!m_masterScore || !first) {
                LOGD("Aria pickup %s: no first measure", phase);
                return;
            }

            LOGD("Aria pickup %s: measure tick=%d endTick=%d actual=%d/%d nominal=%d/%d exclude=%d requested=%d/%d",
                 phase,
                 first->tick().ticks(),
                 first->endTick().ticks(),
                 first->ticks().numerator(),
                 first->ticks().denominator(),
                 first->timesig().numerator(),
                 first->timesig().denominator(),
                 first->irregular() ? 1 : 0,
                 pickup.numerator(),
                 pickup.denominator());

            int index = 0;
            const auto& overlappingSpanners = m_masterScore->spannerMap().findOverlapping(first->tick().ticks(), first->endTick().ticks());
            for (auto interval : overlappingSpanners) {
                mu::engraving::Spanner* spanner = interval.value;
                if (!spanner) {
                    continue;
                }
                mu::engraving::EngravingItem* start = spanner->startElement();
                mu::engraving::EngravingItem* end = spanner->endElement();
                LOGD("Aria pickup %s: spanner[%d] type=%s ptr=%p tick=%d tick2=%d ticks=%d track=%zu track2=%zu start=%s/%p end=%s/%p",
                     phase,
                     index,
                     spanner->typeName(),
                     spanner,
                     spanner->tick().ticks(),
                     spanner->tick2().ticks(),
                     spanner->ticks().ticks(),
                     spanner->track(),
                     spanner->effectiveTrack2(),
                     start ? start->typeName() : "<null>",
                     start,
                     end ? end->typeName() : "<null>",
                     end);
                ++index;
            }
            LOGD("Aria pickup %s: overlappingSpannerCount=%d", phase, index);
        };

        logFirstMeasureSpanners("before set");
        m_masterScore->startCmd(muse::TranslatableString::untranslatable("Aria set pickup measure"));
        measure->undoChangeProperty(mu::engraving::Pid::IRREGULAR, true);
        if (measure->ticks() != pickup) {
            measure->adjustToLen(pickup);
        }
        m_masterScore->endCmd();
        logFirstMeasureSpanners("after set");
        refreshAfterEdit();

        mu::engraving::Score* score = activeScore();
        if (mu::engraving::Measure* refreshed = score ? score->firstMeasure() : nullptr) {
            ::selectMeasureRange(score, refreshed, refreshed);
        }
        output = makeEditState(score);
        return true;
    }

    bool createFirstPickupMeasure(const int numerator,
                                  const int denominator,
                                  msr::render::ScoreEditState& output,
                                  std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        if (numerator <= 0 || denominator <= 0) {
            errorMessage = "Choose a valid pickup length.";
            return false;
        }

        mu::engraving::Measure* firstMeasure = m_masterScore ? m_masterScore->firstMeasure() : nullptr;
        if (!firstMeasure) {
            errorMessage = "This score has no measures.";
            return false;
        }

        const mu::engraving::Fraction nominal = firstMeasure->timesig();
        mu::engraving::Fraction pickup(numerator, denominator);
        pickup.reduce();
        if (pickup <= mu::engraving::Fraction(0, 1) || pickup >= nominal) {
            errorMessage = "A pickup measure must be shorter than one full measure.";
            return false;
        }

        m_masterScore->startCmd(muse::TranslatableString::untranslatable("MuseReader create pickup measure"));
        mu::engraving::MeasureBase* insertedBase = m_masterScore->insertMeasure(firstMeasure);
        mu::engraving::Measure* insertedMeasure = insertedBase && insertedBase->isMeasure()
            ? mu::engraving::toMeasure(insertedBase)
            : nullptr;
        if (!insertedMeasure) {
            m_masterScore->endCmd(true);
            errorMessage = "MuseScore could not create a pickup measure before the first bar.";
            return false;
        }

        insertedMeasure->undoChangeProperty(mu::engraving::Pid::IRREGULAR, true);
        if (insertedMeasure->ticks() != pickup) {
            insertedMeasure->adjustToLen(pickup);
        }
        m_masterScore->endCmd();
        refreshAfterEdit();

        mu::engraving::Score* score = activeScore();
        if (mu::engraving::Measure* refreshed = score ? score->firstMeasure() : nullptr) {
            ::selectMeasureRange(score, refreshed, refreshed);
        }
        output = makeEditState(score);
        return true;
    }

    bool clearFirstMeasurePickup(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Measure* measure = m_masterScore ? m_masterScore->firstMeasure() : nullptr;
        if (!measure) {
            errorMessage = "This score has no measures.";
            return false;
        }

        const mu::engraving::Fraction nominal = measure->timesig();
        auto logFirstMeasureSpanners = [&](const char* phase) {
            mu::engraving::Measure* first = m_masterScore ? m_masterScore->firstMeasure() : nullptr;
            if (!m_masterScore || !first) {
                LOGD("Aria pickup %s: no first measure", phase);
                return;
            }

            LOGD("Aria pickup %s: measure tick=%d endTick=%d actual=%d/%d nominal=%d/%d exclude=%d restoring=%d/%d",
                 phase,
                 first->tick().ticks(),
                 first->endTick().ticks(),
                 first->ticks().numerator(),
                 first->ticks().denominator(),
                 first->timesig().numerator(),
                 first->timesig().denominator(),
                 first->irregular() ? 1 : 0,
                 nominal.numerator(),
                 nominal.denominator());

            int index = 0;
            const auto& overlappingSpanners = m_masterScore->spannerMap().findOverlapping(first->tick().ticks(), first->endTick().ticks());
            for (auto interval : overlappingSpanners) {
                mu::engraving::Spanner* spanner = interval.value;
                if (!spanner) {
                    continue;
                }
                mu::engraving::EngravingItem* start = spanner->startElement();
                mu::engraving::EngravingItem* end = spanner->endElement();
                LOGD("Aria pickup %s: spanner[%d] type=%s ptr=%p tick=%d tick2=%d ticks=%d track=%zu track2=%zu start=%s/%p end=%s/%p",
                     phase,
                     index,
                     spanner->typeName(),
                     spanner,
                     spanner->tick().ticks(),
                     spanner->tick2().ticks(),
                     spanner->ticks().ticks(),
                     spanner->track(),
                     spanner->effectiveTrack2(),
                     start ? start->typeName() : "<null>",
                     start,
                     end ? end->typeName() : "<null>",
                     end);
                ++index;
            }
            LOGD("Aria pickup %s: overlappingSpannerCount=%d", phase, index);
        };

        logFirstMeasureSpanners("before clear");
        m_masterScore->startCmd(muse::TranslatableString::untranslatable("Aria remove pickup measure"));
        measure->undoChangeProperty(mu::engraving::Pid::IRREGULAR, false);
        if (measure->ticks() != nominal) {
            measure->adjustToLen(nominal);
        }
        m_masterScore->endCmd();
        logFirstMeasureSpanners("after clear");
        refreshAfterEdit();

        mu::engraving::Score* score = activeScore();
        if (mu::engraving::Measure* refreshed = score ? score->firstMeasure() : nullptr) {
            ::selectMeasureRange(score, refreshed, refreshed);
        }
        output = makeEditState(score);
        return true;
    }

    bool copySelectedMeasureRange(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (score->selection().isNone()) {
            errorMessage = "Select something before copying.";
            return false;
        }
        if (!score->selection().canCopy()) {
            errorMessage = "MuseScore cannot copy this selection.";
            return false;
        }

        m_measureClipboardMimeType = score->selection().mimeType().toStdString();
        m_measureClipboard = score->selection().mimeData();
        output = makeEditState(score);
        return true;
    }

    bool cutSelectedMeasureRange(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!copySelectedMeasureRange(output, errorMessage)) {
            return false;
        }

        mu::engraving::Score* score = activeScore();
        score->startCmd(muse::TranslatableString::untranslatable("MuseReader cut selection"));
        score->cmdDeleteSelection();
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool pasteMeasureRange(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        if (m_measureClipboard.empty() || m_measureClipboardMimeType.empty()) {
            errorMessage = "Copy or cut something before pasting.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (score->selection().isNone()) {
            errorMessage = "Select a paste destination in the score.";
            return false;
        }

        RenderCoreMimeData mimeData(m_measureClipboardMimeType, m_measureClipboard);
        score->startCmd(muse::TranslatableString::untranslatable("MuseReader paste selection"));
        if (!score->cmdPaste(&mimeData, nullptr)) {
            score->endCmd(true);
            errorMessage = "MuseScore could not paste the copied selection here.";
            return false;
        }

        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool selectAll(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        score->cmdSelectAll();
        output = makeEditState(score);
        return true;
    }

    bool clearSelection(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        score->deselectAll();
        output = makeEditState(score);
        return true;
    }

    bool changeSelectionEnharmonicSpelling(msr::render::ScoreEditState& output,
                                           std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (!editableNoteForItem(score->selection().element())) {
            errorMessage = "Select a pitched note before changing enharmonic spelling.";
            return false;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader change enharmonic spelling"));
        score->changeEnharmonicSpelling(false);
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool changeSelectionAccidental(const int accidentalKind,
                                   msr::render::ScoreEditState& output,
                                   std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        const std::optional<mu::engraving::AccidentalType> accidentalType = accidentalTypeForKind(accidentalKind);
        if (!accidentalType.has_value()) {
            errorMessage = "MuseReader received an unsupported accidental.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::Note* targetNote = currentSelectedNote(score);
        // This is a selection-based command. Previous/Next navigation may leave
        // InputState::lastSegment at the newest note while selecting an older
        // one, so a valid selection must always win. Fall back to the last input
        // note only when there is no selected note at all.
        if (!targetNote && score->inputState().noteEntryMode()) {
            targetNote = lastInputNote(score, false);
        }
        if (!targetNote) {
            errorMessage = "Select a pitched note before changing its accidental.";
            return false;
        }

        mu::engraving::Staff* staff = targetNote->staff();
        if (!staff || !isStandardStaff(staff, targetNote->tick())) {
            errorMessage = "Accidental editing currently works only on standard staves.";
            return false;
        }

        mu::engraving::AccidentalType appliedAccidentalType = *accidentalType;
        if (appliedAccidentalType != mu::engraving::AccidentalType::NATURAL
            && targetNote->accidentalType() == appliedAccidentalType) {
            // Match NotationInteraction::toggleAccidentalForSelection: pressing
            // the selected Sharp/Flat again removes that explicit accidental.
            appliedAccidentalType = mu::engraving::AccidentalType::NONE;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader toggle accidental"));
        score->select(targetNote, mu::engraving::SelectType::SINGLE, targetNote->staffIdx());
        score->changeAccidental(targetNote, appliedAccidentalType);
        continueNoteInputAfterChord(score, targetNote->chord());
        score->inputState().setAccidentalType(mu::engraving::AccidentalType::NONE);
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool flipSelectionStemDirection(msr::render::ScoreEditState& output,
                                    std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (score->selection().elements().empty()) {
            errorMessage = "Select a note or chord before flipping its stem.";
            return false;
        }

        // Use the same command as MuseScore Studio. It already handles regular
        // stems, beams, cross-staff beams, and two-chord tremolos as one undo.
        score->startCmd(muse::TranslatableString::untranslatable("Aria flip stem"));
        score->cmdFlip();
        score->endCmd();

        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool transposeMeasureRangeInScore(mu::engraving::Score* score,
                                      const int mode,
                                      const int direction,
                                      const int interval,
                                      const int targetKey,
                                      const muse::TranslatableString& commandName,
                                      msr::render::ScoreEditState& output,
                                      std::string& errorMessage)
    {
        bool transposesCurrentListSelection = score->selection().isList();
        mu::engraving::Measure* startMeasure = nullptr;
        mu::engraving::Measure* endMeasure = nullptr;
        if (!transposesCurrentListSelection && !selectedMeasureRange(score, &startMeasure, &endMeasure)) {
            startMeasure = currentSelectedMeasure(score);
            endMeasure = startMeasure;
        }
        // Notes dragged across part of a bar: transpose that range only, not the whole bars.
        // Key signatures change only at bar lines, so "to key" changes those notes' pitches.
        if (!transposesCurrentListSelection && score->selection().isRange() && startMeasure && endMeasure
            && (score->selection().tickStart() != startMeasure->tick()
                || score->selection().tickEnd() != endMeasure->endTick())) {
            transposesCurrentListSelection = true;
        }
        if (!transposesCurrentListSelection && (!startMeasure || !endMeasure)) {
            errorMessage = "Select a note, rest, or measure before transposing.";
            return false;
        }

        mu::engraving::TransposeMode transposeMode = mu::engraving::TransposeMode::UNKNOWN;
        switch (mode) {
        case 0:
            transposeMode = mu::engraving::TransposeMode::DIATONICALLY;
            break;
        case 1:
            transposeMode = mu::engraving::TransposeMode::BY_INTERVAL;
            break;
        case 2:
            transposeMode = mu::engraving::TransposeMode::TO_KEY;
            break;
        default:
            errorMessage = "Unsupported transpose mode.";
            return false;
        }

        const mu::engraving::TransposeDirection transposeDirection = direction == 1
            ? mu::engraving::TransposeDirection::DOWN
            : mu::engraving::TransposeDirection::UP;
        const mu::engraving::Key key = static_cast<mu::engraving::Key>(targetKey);
        if (transposeMode == mu::engraving::TransposeMode::TO_KEY
            && (key < mu::engraving::Key::MIN || key > mu::engraving::Key::MAX)) {
            errorMessage = "Unsupported transpose target key.";
            return false;
        }
        if (transposeMode != mu::engraving::TransposeMode::TO_KEY
            && (interval <= 0 || interval >= static_cast<int>(mu::engraving::Interval::allIntervals.size()))) {
            errorMessage = "Unsupported transpose interval.";
            return false;
        }
        mu::engraving::staff_idx_t staffStart = 0;
        mu::engraving::staff_idx_t staffEnd = 1;
        if (score->selection().isRange() && score->nstaves() > 0) {
            staffStart = std::min(score->selection().staffStart(), score->nstaves() - 1);
            staffEnd = std::clamp(
                score->selection().staffEnd(),
                staffStart + 1,
                score->nstaves()
            );
        }

        // To key: the selected staves change key at the start of the range and go back to their
        // own key after it, so bars outside the selection keep reading as before.
        struct StaffKeys {
            mu::engraving::Staff* staff = nullptr;
            mu::engraving::Key startKey = mu::engraving::Key::C;
            mu::engraving::KeySigEvent keyAfter;
            bool keyChangeAfter = false;
        };
        std::vector<StaffKeys> rangeKeys;
        mu::engraving::Key referenceKey = mu::engraving::Key::C;
        mu::engraving::Fraction keyEndTick = mu::engraving::Fraction(-1, 1);
        if (transposeMode == mu::engraving::TransposeMode::TO_KEY) {
            const mu::engraving::Fraction keyTick = startMeasure ? startMeasure->tick() : score->selection().tickStart();
            bool foundReference = false;
            for (mu::engraving::staff_idx_t staffIdx = staffStart; staffIdx < staffEnd; ++staffIdx) {
                mu::engraving::Staff* staff = score->staff(staffIdx);
                if (staff && staff->isPitchedStaff(keyTick)) {
                    referenceKey = staff->concertKey(keyTick);
                    foundReference = true;
                    break;
                }
            }
            if (!foundReference || referenceKey == key) {
                output = makeEditState(score);
                return true;
            }
            if (!transposesCurrentListSelection) {
                if (endMeasure->endTick() < score->endTick()) {
                    keyEndTick = endMeasure->endTick();
                }
                for (mu::engraving::staff_idx_t staffIdx = staffStart; staffIdx < staffEnd; ++staffIdx) {
                    mu::engraving::Staff* staff = score->staff(staffIdx);
                    if (!staff || !staff->isPitchedStaff(keyTick) || staff->keySigEvent(keyTick).isAtonal()
                        || staff->keySigEvent(keyTick).custom()) {
                        continue;
                    }
                    StaffKeys keys;
                    keys.staff = staff;
                    keys.startKey = staff->concertKey(keyTick);
                    if (keyEndTick.isValid() && keyEndTick > mu::engraving::Fraction(0, 1)) {
                        keys.keyAfter = staff->keySigEvent(keyEndTick);
                        keys.keyChangeAfter = staff->keyList()->count(keyEndTick.ticks()) > 0;
                    }
                    rangeKeys.push_back(keys);
                }
            }
        }

        score->startCmd(commandName);
        if (!transposesCurrentListSelection) {
            ::selectMeasureRange(score, startMeasure, endMeasure, staffStart, staffEnd);
        }
        const bool transposeExistingKeySignatures = true;
        if (!mu::engraving::Transpose::transpose(score, transposeMode, transposeDirection, key, interval, transposeExistingKeySignatures, true, true)) {
            score->endCmd(true);
            errorMessage = "MuseScore could not transpose the current selection.";
            return false;
        }
        if (!rangeKeys.empty()) {
            const mu::engraving::Fraction tick = startMeasure->tick();
            const int fifths = static_cast<int>(key) - static_cast<int>(referenceKey);
            for (const StaffKeys& keys : rangeKeys) {
                // Staves in another key move by the same number of fifths as the first one.
                int newKey = static_cast<int>(keys.startKey) + fifths;
                while (newKey > static_cast<int>(mu::engraving::Key::MAX)) {
                    newKey -= 12;
                }
                while (newKey < static_cast<int>(mu::engraving::Key::MIN)) {
                    newKey += 12;
                }
                mu::engraving::KeySigEvent keyEvent;
                keyEvent.setConcertKey(static_cast<mu::engraving::Key>(newKey));
                keyEvent.setKey(static_cast<mu::engraving::Key>(newKey));
                score->undoChangeKeySig(keys.staff, tick, keyEvent);
            }
            if (keyEndTick.isValid() && keyEndTick > tick) {
                for (const StaffKeys& keys : rangeKeys) {
                    if (keys.keyChangeAfter || keys.keyAfter.isAtonal() || keys.keyAfter.custom()
                        || keys.staff->concertKey(keyEndTick) == keys.keyAfter.concertKey()) {
                        continue;
                    }
                    mu::engraving::KeySigEvent keyEvent;
                    keyEvent.setConcertKey(keys.keyAfter.concertKey());
                    keyEvent.setKey(keys.keyAfter.concertKey());
                    keyEvent.setMode(keys.keyAfter.mode());
                    score->undoChangeKeySig(keys.staff, keyEndTick, keyEvent);
                }
            }
        }
        score->endCmd();
        refreshAfterEdit();
        if (!transposesCurrentListSelection) {
            ::selectMeasureRange(score, startMeasure, endMeasure, staffStart, staffEnd);
        }
        output = makeEditState(score);
        return true;
    }

    bool transposeScore(const int mode,
                        const int direction,
                        const int interval,
                        const int targetKey,
                        msr::render::ScoreEditState& output,
                        std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        if (!m_masterScore || !m_masterScore->firstMeasure() || m_masterScore->nstaves() == 0) {
            errorMessage = "The score has no measures to transpose.";
            return false;
        }

        mu::engraving::Score* score = m_masterScore.get();
        const mu::engraving::Selection previousSelection = score->selection();
        score->cmdSelectAll();

        msr::render::ScoreEditState commandOutput;
        const bool succeeded = transposeMeasureRangeInScore(
            score,
            mode,
            direction,
            interval,
            targetKey,
            muse::TranslatableString::untranslatable("MuseReader transpose score"),
            commandOutput,
            errorMessage
        );

        score->setSelection(previousSelection);
        if (succeeded) {
            relayoutActiveScore();
        }
        output = makeEditState(activeScore());
        return succeeded;
    }

    bool transposeSelectedMeasureRange(const int mode,
                                       const int direction,
                                       const int interval,
                                       const int targetKey,
                                       msr::render::ScoreEditState& output,
                                       std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        return transposeMeasureRangeInScore(
            activeScore(),
            mode,
            direction,
            interval,
            targetKey,
            muse::TranslatableString::untranslatable("MuseReader transpose selection"),
            output,
            errorMessage
        );
    }

    bool moveSelectionPitch(const bool up,
                            msr::render::ScoreEditState& output,
                            std::string& errorMessage)
    {
        return shiftSelectionPitchBySemitones(up ? 1 : -1, output, errorMessage);
    }

    /// Applies MuseScore's pitch up/down command to every note in the current
    /// range selection (multi-bar or multi-staff), matching desktop behavior
    /// where EditNote::upDown operates on selection().uniqueNotes().
    bool shiftRangeSelectionPitch(const int stepDelta,
                                  const mu::engraving::UpDownMode mode,
                                  msr::render::ScoreEditState& output,
                                  std::string& errorMessage)
    {
        mu::engraving::Score* score = activeScore();
        if (score->selection().uniqueNotes().empty()) {
            errorMessage = "The selected bars have no notes to shift.";
            return false;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader change selection pitch"));
        const bool movingUp = stepDelta > 0;
        for (int i = 0; i < std::abs(stepDelta); ++i) {
            score->upDown(movingUp, mode);
        }
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    // Moves the selection by steps of `mode`: semitones (CHROMATIC) or octaves (OCTAVE, which,
    // as desktop's Ctrl+Up/Down, keeps the spelling; twelve chromatic steps re-spell E#, Cb, ...).
    bool shiftSelectionPitchSteps(const int stepDelta,
                                  const mu::engraving::UpDownMode mode,
                                  msr::render::ScoreEditState& output,
                                  std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (stepDelta == 0) {
            output = makeEditState(score);
            return true;
        }

        if (score->selection().isRange()) {
            return shiftRangeSelectionPitch(stepDelta, mode, output, errorMessage);
        }

        mu::engraving::Note* targetNote = currentSelectedNote(score);
        if (score->inputState().noteEntryMode()) {
            if (mu::engraving::Note* inputNote = lastInputNote(score, false)) {
                const mu::engraving::Segment* lastSegment = score->inputState().lastSegment();
                const mu::engraving::Segment* selectedSegment = targetNote && targetNote->chord()
                    ? targetNote->chord()->segment()
                    : nullptr;
                if (!targetNote || selectedSegment != lastSegment) {
                    targetNote = inputNote;
                }
            }
        }

        if (!targetNote) {
            errorMessage = "Select or enter a standard-staff note before changing pitch.";
            return false;
        }

        mu::engraving::Chord* targetChord = targetNote->chord();
        mu::engraving::Staff* staff = targetNote->staff();
        if (!targetChord || !staff || !isStandardStaff(staff, targetNote->tick())) {
            errorMessage = "Pitch nudge currently works only on standard-staff notes.";
            return false;
        }

        // A pitch nudge changes the note only: note input stays where it was. Selecting the
        // note moves the input position onto it, so put the position back afterwards.
        mu::engraving::InputState& inputState = score->inputState();
        const bool inNoteEntry = inputState.noteEntryMode();
        mu::engraving::Segment* inputSegment = inputState.segment();
        mu::engraving::Segment* inputLastSegment = inputState.lastSegment();
        const mu::engraving::track_idx_t inputTrack = inputState.track();

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader change pitch"));
        score->select(targetNote, mu::engraving::SelectType::SINGLE, targetNote->staffIdx());
        const bool movingUp = stepDelta > 0;
        for (int i = 0; i < std::abs(stepDelta); ++i) {
            score->upDown(movingUp, mode);
        }
        if (inNoteEntry && inputSegment) {
            inputState.setTrack(inputTrack);
            inputState.setSegment(inputSegment);
            inputState.setLastSegment(inputLastSegment);
        }
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool shiftSelectionPitchBySemitones(const int semitoneDelta,
                                        msr::render::ScoreEditState& output,
                                        std::string& errorMessage)
    {
        return shiftSelectionPitchSteps(semitoneDelta, mu::engraving::UpDownMode::CHROMATIC, output, errorMessage);
    }

    bool shiftSelectionPitchByOctaves(const int octaveDelta,
                                      msr::render::ScoreEditState& output,
                                      std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (octaveDelta == 0) {
            output = makeEditState(score);
            return true;
        }

        // OCTAVE mode preserves each note's spelling, like desktop Cmd+Up/Down.
        return shiftSelectionPitchSteps(octaveDelta, mu::engraving::UpDownMode::OCTAVE, output, errorMessage);
    }

    bool setSelectionPitchClass(const int pitchClass,
                                const bool preferFlats,
                                msr::render::ScoreEditState& output,
                                std::string& errorMessage)
    {
        const int normalizedClass = normalizedPitchClass(pitchClass);
        mu::engraving::Note* selectedNote = currentSelectedNote(activeScore());
        const int basePitch = selectedNote ? selectedNote->pitch() : 60;
        const int octaveBase = (basePitch / 12) * 12;
        int targetPitch = octaveBase + normalizedClass;
        if (!mu::engraving::pitchIsValid(targetPitch)) {
            targetPitch += targetPitch < 0 ? 12 : -12;
        }

        if (selectedNote) {
            mu::engraving::Score* score = activeScore();
            score->startCmd(muse::TranslatableString::untranslatable("MuseReader keyboard pitch"));
            score->select(selectedNote, mu::engraving::SelectType::SINGLE, selectedNote->staffIdx());
            if (!applyDiatonicPitchClassToNote(score, selectedNote, pitchClass, preferFlats, errorMessage)) {
                score->endCmd(true);
                return false;
            }
            score->endCmd();
            refreshAfterEdit();
            output = makeEditState(score);
            return true;
        }

        return setSelectionMIDIPitch(targetPitch, preferFlats, output, errorMessage);
    }

    bool setSelectionMIDIPitch(const int midiPitch,
                               const bool preferFlats,
                               msr::render::ScoreEditState& output,
                               std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score);
        mu::engraving::ChordRest* selectedChordRestItem = selectedOrMeasureChordRest(score);
        mu::engraving::Note* selectedNote = currentSelectedNote(score);
        const msr::render::ScoreSelectionState selectionState = makeSelectionState(score);
        if (!selectedChordRestItem || !selectionState.hasSelection) {
            errorMessage = "Select a standard-staff note or rest before using the keyboard.";
            return false;
        }

        mu::engraving::Staff* staff = selectedChordRestItem->staff();
        if (!isStandardStaff(staff, selectedChordRestItem->tick())) {
            errorMessage = "Keyboard editing currently works only on standard staves.";
            return false;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader keyboard pitch"));
        if (selectedNote) {
            configureInputCursorForChordRest(score, selectedNote->chord(), true);
            score->inputState().setRest(false);
            mu::engraving::NoteVal noteValue = score->noteVal(midiPitch, selectedNote->staffIdx(), true);
            if (!mu::engraving::pitchIsValid(noteValue.pitch)
                || !normalizeNoteValueTpcs(noteValue, selectedNote->staff(), selectedNote->tick(), preferFlats)) {
                score->endCmd(true);
                errorMessage = "MuseReader could not resolve that MIDI pitch for the selected note.";
                return false;
            }
            score->undoChangePitch(selectedNote, noteValue.pitch, noteValue.tpc1, noteValue.tpc2);
        } else if (selectionState.isMeasure
                   && selectedSingleOrMMRestMeasureRange(score, nullptr, nullptr, nullptr, nullptr)) {
            mu::engraving::Measure* selectedStartMeasure = nullptr;
            mu::engraving::Measure* selectedEndMeasure = nullptr;
            mu::engraving::staff_idx_t selectedStaffStart = 0;
            mu::engraving::staff_idx_t selectedStaffEnd = 1;
            selectedSingleOrMMRestMeasureRange(score, &selectedStartMeasure, &selectedEndMeasure, &selectedStaffStart, &selectedStaffEnd);

            ::selectMeasureRange(score, selectedStartMeasure, selectedEndMeasure, selectedStaffStart, selectedStaffEnd);
            score->cmdDeleteSelection();
            selectedChordRestItem = firstStandardChordRestInMeasure(score, selectedStartMeasure, selectedStaffStart);
            if (!selectedChordRestItem) {
                score->endCmd(true);
                errorMessage = "MuseReader could not create a note entry point in that measure.";
                return false;
            }

            configureInputCursorForChordRest(score, selectedChordRestItem, false);
            score->inputState().setRest(false);
            normalizeNoteEntryDuration(score->inputState());
            mu::engraving::Note* replacementNote = score->addMidiPitch(midiPitch, false, true);
            if (!replacementNote) {
                score->endCmd(true);
                errorMessage = "MuseReader could not enter that MIDI pitch at the current cursor.";
                return false;
            }
            score->select(replacementNote, mu::engraving::SelectType::SINGLE, replacementNote->staffIdx());
        } else if (selectedChordRestItem->isRest()) {
            configureInputCursorForChordRest(score, selectedChordRestItem, false);
            score->inputState().setRest(false);
            normalizeNoteEntryDuration(score->inputState());
            mu::engraving::Note* replacementNote = score->addMidiPitch(midiPitch, false, true);
            if (!replacementNote) {
                score->endCmd(true);
                errorMessage = "MuseReader could not enter that MIDI pitch at the current cursor.";
                return false;
            }
            score->select(replacementNote, mu::engraving::SelectType::SINGLE, replacementNote->staffIdx());
        } else if (selectedItem) {
            score->endCmd(true);
            errorMessage = "Select a note or rest before using the keyboard.";
            return false;
        }
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool setSelectionPitchAtPagePosition(const int pageIndex,
                                         const double normalizedX,
                                         const double normalizedY,
                                         msr::render::ScoreEditState& output,
                                         std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::Page* page = pageForIndex(score, pageIndex);
        if (!page) {
            errorMessage = "That page is unavailable in the open score session.";
            return false;
        }

        mu::engraving::Note* selectedNote = currentSelectedNote(score);
        mu::engraving::ChordRest* selectedChordRestItem = selectedChordRest(score);
        if (!selectedNote || !selectedChordRestItem) {
            errorMessage = "Select a note before dragging it.";
            return false;
        }

        mu::engraving::Staff* selectedStaff = selectedChordRestItem->staff();
        if (!isStandardStaff(selectedStaff, selectedChordRestItem->tick())) {
            errorMessage = "Note dragging currently works only on standard staves.";
            return false;
        }

        const mu::engraving::PointF pagePoint = pointForNormalizedPagePosition(page, normalizedX, normalizedY);
        mu::engraving::Position position;
        if (!getPagePosition(score, page, &position, pagePoint, selectedChordRestItem->track() % mu::engraving::VOICES)) {
            errorMessage = "Drop the note on a staff position.";
            return false;
        }

        if (position.staffIdx != selectedChordRestItem->staffIdx()) {
            position.staffIdx = selectedChordRestItem->staffIdx();
        }
        position.segment = selectedChordRestItem->segment();

        bool noteValueError = false;
        const mu::engraving::NoteVal noteValue = score->noteValForPosition(position, mu::engraving::AccidentalType::NONE, noteValueError);
        if (noteValueError || !mu::engraving::pitchIsValid(noteValue.pitch)) {
            errorMessage = "MuseReader could not resolve a pitch at that drop position.";
            return false;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader drag note"));
        score->undoChangePitch(selectedNote, noteValue.pitch, noteValue.tpc1, noteValue.tpc2);
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool selectAdjacentElement(const bool next,
                               msr::render::ScoreEditState& output,
                               std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score);
        const bool selectingFromChordText = selectedItem && selectedItem->isHarmony();
        mu::engraving::ChordRest* selectedChordRestItem = selectedChordRest(score);
        if (!selectedChordRestItem) {
            output = makeEditState(score);
            return true;
        }

        mu::engraving::ChordRestNavigateOptions options;
        options.skipGrace = true;
        options.skipMeasureRepeatRests = false;
        mu::engraving::ChordRest* targetChordRest = next
            ? mu::engraving::nextChordRest(selectedChordRestItem, options)
            : mu::engraving::prevChordRest(selectedChordRestItem, options);
        while (targetChordRest && targetChordRest->isRest() && mu::engraving::toRest(targetChordRest)->isGap()) {
            targetChordRest = next
                ? mu::engraving::nextChordRest(targetChordRest, options)
                : mu::engraving::prevChordRest(targetChordRest, options);
        }

        mu::engraving::EngravingItem* selectableTarget = nullptr;
        if (selectingFromChordText && targetChordRest) {
            const mu::engraving::Segment* segment = targetChordRest->segment();
            const mu::engraving::track_idx_t targetTrack = mu::engraving::trackZeroVoice(targetChordRest->track());
            if (segment) {
                for (mu::engraving::EngravingItem* annotation : segment->annotations()) {
                    if (annotation && annotation->isHarmony() && annotation->track() == targetTrack) {
                        selectableTarget = annotation;
                        break;
                    }
                }
            }
        }
        if (!selectableTarget) {
            selectableTarget = noteOrRestSelectionItem(targetChordRest);
        }
        if (!selectableTarget) {
            output = makeEditState(score);
            return true;
        }

        score->select(selectableTarget, mu::engraving::SelectType::SINGLE, selectableTarget->staffIdx());
        output = makeEditState(score);
        return true;
    }

    void markLinkedScoresForLayout(const mu::engraving::Score* changedScore)
    {
        for (mu::engraving::Score* linkedScore : m_masterScore->scoreList()) {
            if (linkedScore && linkedScore != changedScore) {
                linkedScore->setLayoutAll();
            }
        }
    }

    bool undo(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (!score->undoStack() || !score->undoStack()->canUndo()) {
            errorMessage = "There is nothing to undo.";
            return false;
        }

        score->undoRedo(true, nullptr);
        // The shared undo stack restores linked notation in every score, but
        // undoRedo() lays out only the score it is invoked on. Mark the other
        // views stale rather than laying them all out here, which is slow on
        // scores with many parts: saveToPath() lays out every view before
        // serializing, and a view is laid out again when it is shown.
        markLinkedScoresForLayout(score);
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool redo(msr::render::ScoreEditState& output, std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (!score->undoStack() || !score->undoStack()->canRedo()) {
            errorMessage = "There is nothing to redo.";
            return false;
        }

        score->undoRedo(false, nullptr);
        markLinkedScoresForLayout(score);
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool replacePartInstrument(const std::string& partId,
                               const std::string& instrumentId,
                               msr::render::ScoreEditState& output,
                               std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Part* part = m_masterScore->partById(muse::ID(partId));
        if (!part) {
            errorMessage = "Aria could not find the selected instrument part.";
            return false;
        }
        if (!mu::engraving::searchTemplate(u"piano")) {
            mu::engraving::loadInstrumentTemplates(":/engraving/instruments/instruments.xml");
        }
        const mu::engraving::InstrumentTemplate* instrumentTemplate
            = mu::engraving::searchTemplate(muse::String::fromUtf8(instrumentId.c_str()));
        if (!instrumentTemplate) {
            errorMessage = "Aria could not find the MuseScore instrument template: " + instrumentId;
            return false;
        }

        // As desktop's instruments panel (PartTreeItem::replaceInstrument): the template's staff
        // type (tablature, percussion) and a part name with its transposition, e.g. "Clarinet in B♭".
        const mu::engraving::Instrument replacement
            = mu::engraving::Instrument::fromTemplate(instrumentTemplate);
        const mu::engraving::StaffType* staffType = instrumentTemplate->staffTypePreset
            ? instrumentTemplate->staffTypePreset
            : mu::engraving::StaffType::getDefaultPreset(instrumentTemplate->staffGroup);
        m_masterScore->startCmd(muse::TranslatableString::untranslatable("Aria change instrument"));
        mu::engraving::EditPart::replacePartInstrument(m_masterScore.get(), part, replacement, staffType,
                                                       instrumentTitle(replacement.trackName(), replacement.trait()));
        m_masterScore->endCmd();

        refreshAfterEdit();
        output = makeEditState(activeScore());
        return true;
    }

    bool setInstrumentFromTick(const std::string& partId,
                               const int64_t tickValue,
                               const std::string& instrumentId,
                               msr::render::ScoreEditState& output,
                               std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        if (tickValue < 0) {
            errorMessage = "Select a measure before changing the instrument from that point.";
            return false;
        }

        mu::engraving::Part* part = m_masterScore->partById(muse::ID(partId));
        if (!part) {
            errorMessage = "Aria could not find the selected instrument part.";
            return false;
        }
        if (!mu::engraving::searchTemplate(u"piano")) {
            mu::engraving::loadInstrumentTemplates(":/engraving/instruments/instruments.xml");
        }
        const mu::engraving::InstrumentTemplate* instrumentTemplate
            = mu::engraving::searchTemplate(muse::String::fromUtf8(instrumentId.c_str()));
        if (!instrumentTemplate) {
            errorMessage = "Aria could not find the MuseScore instrument template: " + instrumentId;
            return false;
        }

        const mu::engraving::Instrument replacement
            = mu::engraving::Instrument::fromTemplate(instrumentTemplate);
        const mu::engraving::Fraction tick = mu::engraving::Fraction::fromTicks(tickValue);
        if (tick.isZero()) {
            return replacePartInstrument(partId, instrumentId, output, errorMessage);
        }

        mu::engraving::Segment* segment = m_masterScore->tick2segment(
            tick,
            true,
            mu::engraving::SegmentType::ChordRest
        );
        if (!segment) {
            errorMessage = "Aria could not find the selected measure in the score.";
            return false;
        }

        m_masterScore->startCmd(muse::TranslatableString::untranslatable("Aria change instrument from measure"));
        if (!mu::engraving::EditPart::replaceInstrumentAtTick(m_masterScore.get(), part, tick, replacement)) {
            const mu::engraving::Instrument* currentInstrument = part->instrument(tick);
            if (!currentInstrument) {
                m_masterScore->endCmd(true);
                errorMessage = "Aria could not read the instrument at the selected measure.";
                return false;
            }

            const mu::engraving::staff_idx_t staffIndex = mu::engraving::track2staff(part->startTrack());
            mu::engraving::ChordRest* chordRest = firstChordRestAtSegment(m_masterScore.get(), segment, staffIndex);
            if (!chordRest) {
                chordRest = firstStandardChordRestInMeasure(m_masterScore.get(), segment->measure(), staffIndex);
            }
            if (!chordRest) {
                m_masterScore->endCmd(true);
                errorMessage = "Aria could not find a note or rest for the instrument change.";
                return false;
            }

            mu::engraving::TextBase* text = m_masterScore->addText(
                mu::engraving::TextStyleType::INSTRUMENT_CHANGE,
                chordRest
            );
            if (!text || !text->isInstrumentChange()) {
                m_masterScore->endCmd(true);
                errorMessage = "Aria could not add the instrument change at the selected measure.";
                return false;
            }

            mu::engraving::InstrumentChange* instrumentChange = mu::engraving::toInstrumentChange(text);
            // addText() has already created linked copies. The init flag is not
            // a Pid, so set it on every copy before setupInstrument() writes the
            // linked instruments and label text.
            for (mu::engraving::EngravingObject* linked : instrumentChange->linkList()) {
                if (linked && linked->isInstrumentChange()) {
                    mu::engraving::toInstrumentChange(linked)->setInit(true);
                }
            }
            instrumentChange->setupInstrument(&replacement);
        }
        m_masterScore->endCmd();

        refreshAfterEdit();
        output = makeEditState(activeScore());
        return true;
    }

    bool replaceInstruments(const std::vector<std::string>& instrumentIds,
                            msr::render::ScoreEditState& output,
                            std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        if (instrumentIds.empty()) {
            errorMessage = "Select at least one instrument.";
            return false;
        }

        if (!mu::engraving::searchTemplate(u"piano")) {
            mu::engraving::loadInstrumentTemplates(":/engraving/instruments/instruments.xml");
        }

        std::vector<const mu::engraving::InstrumentTemplate*> templates;
        templates.reserve(instrumentIds.size());
        for (const std::string& instrumentId : instrumentIds) {
            const mu::engraving::InstrumentTemplate* instrumentTemplate = mu::engraving::searchTemplate(muse::String::fromUtf8(instrumentId.c_str()));
            if (!instrumentTemplate) {
                errorMessage = "MuseReader could not find the MuseScore instrument template: " + instrumentId;
                return false;
            }
            templates.push_back(instrumentTemplate);
        }

        // Instrument-list edits are structural. Always perform them on the
        // master score; applying this to an active excerpt only rewrites that
        // view and leaves the saved full score unchanged.
        mu::engraving::Score* score = m_masterScore.get();
        score->startCmd(muse::TranslatableString::untranslatable("MuseReader replace score instruments"));

        // The new instruments keep the score's key signatures, which go with the old staves.
        const mu::engraving::KeyList keyList = score->keyList();
        std::vector<mu::engraving::Part*> existingParts = score->parts();
        for (mu::engraving::Part* part : existingParts) {
            score->cmdRemovePart(part);
        }

        for (const mu::engraving::InstrumentTemplate* instrumentTemplate : templates) {
            appendPartLikeDesktop(score, *instrumentTemplate, keyList);
        }

        score->setBracketsAndBarlines();
        score->endCmd();
        m_activeScore = m_masterScore.get();
        m_activePartIndex.reset();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    // Instrument names as desktop writes them (notationtypes.h formatInstrumentTitle, used for the
    // part name, and NotationParts' formatInstrumentTitleOnScore, used for staff names).
    static muse::String instrumentTitle(const muse::String& name, const mu::engraving::Trait& trait)
    {
        switch (trait.type) {
        case mu::engraving::TraitType::Tuning:
            return trait.name + u" " + name;
        case mu::engraving::TraitType::Transposition:
            return name + u" in " + trait.name;
        case mu::engraving::TraitType::Course:
            return name + u" (" + trait.name + u")";
        case mu::engraving::TraitType::Unknown:
            break;
        }
        return name;
    }

    static muse::String instrumentTitleOnScore(const muse::String& name, const mu::engraving::Trait& trait, const int number)
    {
        muse::String title = name;
        if (trait.type == mu::engraving::TraitType::Transposition && !trait.isHiddenOnScore) {
            title += u" in " + trait.name;
        }
        if (number > 0) {
            title += u" " + muse::String::number(number);
        }
        return title;
    }

    // Desktop's NotationParts::insertNewParts + appendStaves: a numbered name when the instrument
    // is already in the score, the template's staff type and line count, and the score's keys.
    static void appendPartLikeDesktop(mu::engraving::Score* score, const mu::engraving::InstrumentTemplate& instrumentTemplate,
                                      const mu::engraving::KeyList& keyList)
    {
        const mu::engraving::Instrument instrument = mu::engraving::Instrument::fromTemplate(&instrumentTemplate);

        int number = 0;
        for (const mu::engraving::Part* existing : score->parts()) {
            if (existing->instrument()->id() == instrumentTemplate.id) {
                ++number;
            }
        }
        number = number > 0 ? number + 1 : 0;

        mu::engraving::Part* part = new mu::engraving::Part(score);
        part->setInstrument(instrument);
        const mu::engraving::StaffNameList& longNames = instrument.longNames();
        const mu::engraving::StaffNameList& shortNames = instrument.shortNames();
        const muse::String longName = instrumentTitleOnScore(longNames.empty() ? muse::String() : longNames.front().name(),
                                                             instrument.trait(), number);
        const muse::String shortName = instrumentTitleOnScore(shortNames.empty() ? muse::String() : shortNames.front().name(),
                                                              instrument.trait(), number);
        part->setPartName(longName);
        part->setLongName(longName);
        part->setShortName(shortName);
        score->undoInsertPart(part, score->parts().size());

        for (mu::engraving::staff_idx_t index = 0; index < instrumentTemplate.staffCount; ++index) {
            mu::engraving::Staff* staff = mu::engraving::Factory::createStaff(part);
            const mu::engraving::StaffType* staffType = instrumentTemplate.staffTypePreset
                ? instrumentTemplate.staffTypePreset
                : mu::engraving::StaffType::preset(mu::engraving::StaffTypes::STANDARD);
            mu::engraving::StaffType* staffTypeCopy = staff->setStaffType(mu::engraving::Fraction(0, 1), *staffType);
            if (index >= mu::engraving::MAX_STAVES) {
                staffTypeCopy->setSmall(false);
            } else {
                staffTypeCopy->setSmall(instrumentTemplate.smallStaff[index]);
                staffTypeCopy->setLines(instrumentTemplate.staffLines[index]);
                staff->setBracketType(0, instrumentTemplate.bracket[index]);
                staff->setBracketSpan(0, instrumentTemplate.bracketSpan[index]);
                staff->setBarLineSpan(instrumentTemplate.barlineSpan[index]);
            }
            staff->setDefaultClefType(instrumentTemplate.clefType(index));
            score->undoInsertStaff(staff, index);
        }

        if (part->nstaves() > 0) {
            const mu::engraving::staff_idx_t firstStaff = part->staff(0)->idx();
            score->adjustKeySigs(firstStaff, firstStaff + part->nstaves(), keyList);
        }
        score->setUpTempoMapLater();
        score->masterScore()->rebuildMidiMapping();
    }

    bool addInstrument(const std::string& instrumentId,
                       msr::render::ScoreEditState& output,
                       std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }
        if (instrumentId.empty()) {
            errorMessage = "Select an instrument to add.";
            return false;
        }

        if (!mu::engraving::searchTemplate(u"piano")) {
            mu::engraving::loadInstrumentTemplates(":/engraving/instruments/instruments.xml");
        }

        const mu::engraving::InstrumentTemplate* instrumentTemplate = mu::engraving::searchTemplate(muse::String::fromUtf8(instrumentId.c_str()));
        if (!instrumentTemplate) {
            errorMessage = "Aria could not find the MuseScore instrument template: " + instrumentId;
            return false;
        }

        mu::engraving::Score* score = m_masterScore.get();
        score->startCmd(muse::TranslatableString::untranslatable("Aria add instrument"));
        appendPartLikeDesktop(score, *instrumentTemplate, score->keyList());
        score->setBracketsAndBarlines();
        score->endCmd();

        m_activeScore = m_masterScore.get();
        m_activePartIndex.reset();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool removeSelectedInstrument(msr::render::ScoreEditState& output,
                                  std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        const mu::engraving::staff_idx_t staffIdx = activeStaffIndex(score);
        if (staffIdx == muse::nidx || staffIdx >= score->nstaves()) {
            errorMessage = "Select a staff before removing an instrument.";
            return false;
        }

        mu::engraving::Part* selectedPart = score->staff(staffIdx) ? score->staff(staffIdx)->part() : nullptr;
        if (!selectedPart) {
            errorMessage = "Aria could not find the selected instrument.";
            return false;
        }

        mu::engraving::Part* masterPart = m_masterScore->partById(selectedPart->id());
        if (!masterPart) {
            masterPart = selectedPart;
        }
        if (m_masterScore->parts().size() <= 1) {
            errorMessage = "Aria cannot remove the last instrument in the score.";
            return false;
        }

        m_masterScore->startCmd(muse::TranslatableString::untranslatable("Aria remove instrument"));
        m_masterScore->cmdRemovePart(masterPart);
        m_masterScore->setBracketsAndBarlines();
        m_masterScore->endCmd();

        m_activeScore = m_masterScore.get();
        m_activePartIndex.reset();
        refreshAfterEdit();
        output = makeEditState(m_masterScore.get());
        return true;
    }

    bool removeInstrumentAtIndex(int partIndex,
                                 msr::render::ScoreEditState& output,
                                 std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        std::vector<mu::engraving::Part*> parts = m_masterScore->parts();
        if (parts.size() <= 1) {
            errorMessage = "Aria cannot remove the last instrument in the score.";
            return false;
        }
        if (partIndex < 0 || partIndex >= static_cast<int>(parts.size())) {
            errorMessage = "Aria could not find that instrument in the score.";
            return false;
        }

        m_masterScore->startCmd(muse::TranslatableString::untranslatable("Aria remove instrument"));
        m_masterScore->cmdRemovePart(parts.at(static_cast<size_t>(partIndex)));
        m_masterScore->setBracketsAndBarlines();
        m_masterScore->endCmd();

        m_activeScore = m_masterScore.get();
        m_activePartIndex.reset();
        refreshAfterEdit();
        output = makeEditState(m_masterScore.get());
        return true;
    }

    bool moveInstrument(int sourceIndex,
                        int destinationIndex,
                        msr::render::ScoreEditState& output,
                        std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        std::vector<mu::engraving::Part*> parts = m_masterScore->parts();
        const int partCount = static_cast<int>(parts.size());
        if (sourceIndex < 0 || sourceIndex >= partCount || destinationIndex < 0 || destinationIndex > partCount) {
            errorMessage = "Aria could not move that instrument.";
            return false;
        }
        if (destinationIndex == sourceIndex || destinationIndex == sourceIndex + 1) {
            output = makeEditState(m_masterScore.get());
            return true;
        }

        mu::engraving::Part* sourcePart = parts.at(static_cast<size_t>(sourceIndex));
        std::vector<mu::engraving::Part*> remaining = parts;
        remaining.erase(remaining.begin() + sourceIndex);

        int insertionIndex = destinationIndex;
        if (destinationIndex > sourceIndex) {
            --insertionIndex;
        }
        insertionIndex = std::clamp(insertionIndex, 0, static_cast<int>(remaining.size()));

        const bool insertAfter = insertionIndex == static_cast<int>(remaining.size());
        mu::engraving::Part* destinationPart = insertAfter
            ? remaining.back()
            : remaining.at(static_cast<size_t>(insertionIndex));

        m_masterScore->startCmd(muse::TranslatableString::untranslatable("Aria move instrument"));
        mu::engraving::EditPart::moveParts(m_masterScore.get(), { sourcePart }, destinationPart, insertAfter);
        m_masterScore->endCmd();

        m_activeScore = m_masterScore.get();
        m_activePartIndex.reset();
        refreshAfterEdit();
        output = makeEditState(m_masterScore.get());
        return true;
    }

    bool setInstrumentVisible(int partIndex,
                              bool visible,
                              msr::render::ScoreEditState& output,
                              std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        std::vector<mu::engraving::Part*> parts = m_masterScore->parts();
        if (partIndex < 0 || partIndex >= static_cast<int>(parts.size())) {
            errorMessage = "Aria could not find that instrument in the score.";
            return false;
        }

        mu::engraving::Part* part = parts.at(static_cast<size_t>(partIndex));
        if (!part) {
            errorMessage = "Aria could not find that instrument in the score.";
            return false;
        }
        bool alreadyVisible = part->show() == visible;
        for (mu::engraving::Staff* staff : part->staves()) {
            if (staff && staff->visible() != visible) {
                alreadyVisible = false;
                break;
            }
        }
        if (alreadyVisible) {
            output = makeEditState(m_masterScore.get());
            return true;
        }

        m_masterScore->startCmd(muse::TranslatableString::untranslatable("Aria update instrument visibility"));
        mu::engraving::EditPart::setPartVisible(m_masterScore.get(), part, visible);
        for (mu::engraving::Staff* staff : part->staves()) {
            mu::engraving::EditPart::setStaffVisible(m_masterScore.get(), staff, visible);
        }
        m_masterScore->endCmd();

        m_activeScore = m_masterScore.get();
        m_activePartIndex.reset();
        relayoutActiveScore();
        refreshAfterEdit();
        output = makeEditState(m_masterScore.get());
        return true;
    }

    bool changeClef(const std::string& clefKind,
                    msr::render::ScoreEditState& output,
                    std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        const std::string key = normalizedCommandKey(clefKind);
        mu::engraving::ClefType clefType = mu::engraving::ClefType::INVALID;
        if (key == "treble" || key == "g") {
            clefType = mu::engraving::ClefType::G;
        } else if (key == "alto" || key == "c3") {
            clefType = mu::engraving::ClefType::C3;
        } else if (key == "tenor" || key == "c4") {
            clefType = mu::engraving::ClefType::C4;
        } else if (key == "bass" || key == "f") {
            clefType = mu::engraving::ClefType::F;
        }
        if (clefType == mu::engraving::ClefType::INVALID) {
            errorMessage = "Aria does not recognize that clef.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        const mu::engraving::staff_idx_t staffIdx = activeStaffIndex(score);
        if (staffIdx == muse::nidx || staffIdx >= score->nstaves()) {
            errorMessage = "Select a staff, note, rest, or measure before changing clef.";
            return false;
        }

        mu::engraving::Staff* staff = score->staff(staffIdx);
        mu::engraving::EngravingItem* anchor = currentSelectedItem(score);
        if (!anchor) {
            anchor = activeMeasure(score);
        }
        // As desktop does when a clef is dropped: on the first note of a bar, the clef belongs to
        // the bar. Anchored to that note, the first bar of the score got a second, small clef after
        // the time signature (clef, 4/4, clef) instead of a new starting clef.
        if (anchor && !anchor->isMeasure() && !anchor->isClef() && anchor->rtick().isZero()) {
            if (mu::engraving::Measure* measure = anchor->findMeasure()) {
                anchor = measure;
            }
        }
        // Scores saved with that bug keep a stray clef change at the very start of the bar, which
        // would go on overriding the bar's new clef; it is replaced too.
        mu::engraving::Clef* strayStartClef = nullptr;
        if (anchor && anchor->isMeasure()) {
            mu::engraving::Measure* measure = mu::engraving::toMeasure(anchor);
            if (mu::engraving::Segment* segment = measure->findSegmentR(mu::engraving::SegmentType::Clef, mu::engraving::Fraction(0, 1))) {
                mu::engraving::EngravingItem* element = segment->element(mu::engraving::staff2track(staffIdx));
                if (element && element->isClef()) {
                    strayStartClef = mu::engraving::toClef(element);
                }
            }
        }
        if (!staff || !anchor) {
            errorMessage = "Aria could not find a clef insertion point.";
            return false;
        }

        score->startCmd(muse::TranslatableString::untranslatable("Aria change clef"));
        if (strayStartClef) {
            score->undoRemoveElement(strayStartClef);
        }
        score->undoChangeClef(staff, anchor, clefType);
        score->endCmd();

        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }
