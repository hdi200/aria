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
            if (!inputState.isValid()) {
                errorMessage = "Tap a standard staff position before inserting a rest.";
                return false;
            }

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

        commandScore->startCmd(muse::TranslatableString::untranslatable("MuseReader add text"));
        mu::engraving::TextBase* text = commandScore->addText(type, commandItem);
        if (!text) {
            commandScore->endCmd(true);
            errorMessage = "MuseReader could not add that text at the current selection.";
            return false;
        }

        if (!defaultText.empty()) {
            text->setPlainText(defaultText);
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
        commandItem->undoChangeProperty(mu::engraving::Pid::TEXT, newText);
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

    bool addLyricsText(const std::string& text,
                       const bool advanceToNextChord,
                       msr::render::ScoreEditState& output,
                       std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        muse::String lyricText = muse::String::fromUtf8(text.c_str()).trimmed();
        if (lyricText.empty()) {
            errorMessage = "Lyrics cannot be empty.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        mu::engraving::EngravingItem* selectedItem = currentSelectedItem(score);
        mu::engraving::Lyrics* selectedLyrics = selectedItem && selectedItem->isLyrics()
            ? mu::engraving::toLyrics(selectedItem)
            : nullptr;
        mu::engraving::ChordRest* chordRest = selectedLyrics
            ? selectedLyrics->chordRest()
            : mu::engraving::InputState::chordRest(selectedItem);
        if (!chordRest || !chordRest->isChord()) {
            errorMessage = "Select a note before adding lyrics.";
            return false;
        }

        const int verse = selectedLyrics ? selectedLyrics->verse() : 0;
        const mu::engraving::PlacementV placement = selectedLyrics
            ? selectedLyrics->placement()
            : mu::engraving::PlacementV::BELOW;
        mu::engraving::Lyrics* lyrics = selectedLyrics ? selectedLyrics : chordRest->lyrics(verse, placement);
        bool createdLyrics = false;
        if (!lyrics) {
            lyrics = mu::engraving::Factory::createLyrics(chordRest);
            lyrics->setTrack(chordRest->track());
            lyrics->setParent(chordRest);
            lyrics->setVerse(verse);
            lyrics->setPlacement(placement);
            lyrics->setSyllabic(mu::engraving::LyricsSyllabic::SINGLE);
            createdLyrics = true;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader edit lyrics"));
        if (createdLyrics) {
            lyrics->setPlainText(lyricText);
            score->undoAddElement(lyrics);
        } else {
            lyrics->undoChangeProperty(mu::engraving::Pid::TEXT, lyricText);
        }

        mu::engraving::EngravingItem* selectedAfterEdit = lyrics;
        if (advanceToNextChord) {
            mu::engraving::Segment* nextSegment = chordRest->segment();
            while ((nextSegment = nextSegment ? nextSegment->next1(mu::engraving::SegmentType::ChordRest) : nullptr)) {
                mu::engraving::EngravingItem* nextItem = nextSegment->element(chordRest->track());
                if (!nextItem || !nextItem->isChord()) {
                    continue;
                }

                mu::engraving::ChordRest* nextChordRest = mu::engraving::toChordRest(nextItem);
                if (!nextChordRest) {
                    continue;
                }

                mu::engraving::Lyrics* nextLyrics = nextChordRest->lyrics(verse, placement);
                selectedAfterEdit = nextLyrics ? static_cast<mu::engraving::EngravingItem*>(nextLyrics) : noteOrRestSelectionItem(nextChordRest);
                break;
            }
        }

        score->endCmd();
        refreshAfterEdit();
        if (selectedAfterEdit) {
            score->select(selectedAfterEdit, mu::engraving::SelectType::SINGLE, selectedAfterEdit->staffIdx());
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

        mu::engraving::Harmony* movedHarmony = harmony->clone();
        movedHarmony->setScore(score);
        movedHarmony->setParent(targetSegment);
        movedHarmony->setTrack(mu::engraving::trackZeroVoice(targetChordRest->track()));

        const double spatium = std::max(page->spatium(), 1.0);
        const mu::engraving::PointF anchor = chordTextAttachmentAnchorForChordRest(targetChordRest);
        const mu::engraving::PointF currentCenter = harmony->pageBoundingRect().center();
        const mu::engraving::PointF offset(
            (pagePoint.x() - anchor.x()) / spatium,
            harmony->offset().y() + ((pagePoint.y() - currentCenter.y()) / spatium)
        );
        movedHarmony->setOffset(offset);

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader drag chord symbol"));
        score->undoRemoveElement(harmony);
        score->undoAddElement(movedHarmony);
        score->endCmd();

        refreshAfterEdit();
        score->select(movedHarmony, mu::engraving::SelectType::SINGLE, movedHarmony->staffIdx());
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
        } else if (key == "coda" || key == "segno") {
            mu::engraving::Marker* marker = mu::engraving::Factory::createMarker(measure);
            marker->setMarkerType(key == "segno" ? mu::engraving::MarkerType::SEGNO : mu::engraving::MarkerType::CODA);
            marker->resetProperty(mu::engraving::Pid::LABEL);
            marker->setTrack(0);
            marker->setParent(measure);
            score->doUndoAddElement(marker);
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
            score->doUndoAddElement(jump);
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

            dynamic->setDynamicType(muse::String::fromUtf8(dynamicType->second));
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
                mu::engraving::EditChord::toggleArticulation(score, symId);
                addedItem = rangeFirstChord;
            } else {
                mu::engraving::Articulation* articulation = mu::engraving::Factory::createArticulation(score->dummy()->chord());
                articulation->setSymId(symId);
                if (!mu::engraving::EditChord::toggleArticulation(score, item, articulation)) {
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
        mu::engraving::Spanner* spanner = currentSelectedExpressionSpanner(score);
        if (!spanner) {
            errorMessage = "Select an expression line before moving an endpoint.";
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
            if (startEndpoint) {
                start = target;
            } else {
                end = target;
            }
            if (start->tick() > end->tick()) {
                score->endCmd(true);
                errorMessage = "Slur start must stay before its end.";
                return false;
            }
            score->undo(new mu::engraving::ChangeStartEndSpanner(spanner, start, end));
        } else {
            const mu::engraving::Fraction targetTick = startEndpoint ? target->tick() : target->endTick();
            const mu::engraving::Fraction oldStartTick = spanner->tick();
            const mu::engraving::Fraction oldEndTick = spanner->tick2();
            const mu::engraving::Fraction newStartTick = startEndpoint ? targetTick : oldStartTick;
            const mu::engraving::Fraction newEndTick = startEndpoint ? oldEndTick : targetTick;
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
        mu::engraving::Measure* measure = activeLayoutBreakMeasure(score);
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

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader add layout break"));
        if (isNoBreak) {
            score->cmdToggleLayoutBreak(breakType);
        } else {
            measure->undoSetBreak(true, breakType);
            measure->undoSetBreak(false, isPageBreak ? mu::engraving::LayoutBreakType::LINE : mu::engraving::LayoutBreakType::PAGE);
        }
        score->endCmd();
        refreshAfterEdit();
        score->select(measure, mu::engraving::SelectType::SINGLE, 0);
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
        mu::engraving::Measure* measure = activeMeasure(score);
        if (!measure) {
            errorMessage = "Select a measure or barline before removing a layout break.";
            return false;
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader remove layout break"));
        measure->undoSetBreak(false, mu::engraving::LayoutBreakType::LINE);
        measure->undoSetBreak(false, mu::engraving::LayoutBreakType::PAGE);
        measure->undoSetBreak(false, mu::engraving::LayoutBreakType::NOBREAK);
        score->endCmd();
        refreshAfterEdit();
        score->select(measure, mu::engraving::SelectType::SINGLE, 0);
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

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader replace with rhythmic slashes"));
        score->cmdSlashRhythm();
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
        score->startCmd(muse::TranslatableString::untranslatable("MuseReader update staff spacing"));
        score->undoChangeStyleVal(mu::engraving::Sid::staffDistance, mu::engraving::PropertyValue(mu::engraving::Spatium(staffDistanceSpatium)));
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }

    bool updatePageLayout(const double pageWidthMillimeters,
                          const double pageHeightMillimeters,
                          const double marginMillimeters,
                          const double staffSizeMillimeters,
                          const double systemSpacingSpatium,
                          msr::render::ScoreEditState& output,
                          std::string& errorMessage)
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        if (pageWidthMillimeters < 100.0 || pageHeightMillimeters < 100.0) {
            errorMessage = "Page size is too small.";
            return false;
        }

        if (marginMillimeters < 0.0 || marginMillimeters * 2.0 >= pageWidthMillimeters) {
            errorMessage = "Page margins do not fit within the selected page size.";
            return false;
        }

        if (staffSizeMillimeters < 1.2 || staffSizeMillimeters > 2.4) {
            errorMessage = "Staff size must be between 1.2 mm and 2.4 mm.";
            return false;
        }

        if (systemSpacingSpatium < 4.0 || systemSpacingSpatium > 24.0) {
            errorMessage = "System spacing must be between 4 and 24 spaces.";
            return false;
        }

        const double pageWidth = pageWidthMillimeters / mu::engraving::INCH;
        const double pageHeight = pageHeightMillimeters / mu::engraving::INCH;
        const double margin = marginMillimeters / mu::engraving::INCH;
        const double printableWidth = std::max(0.0, pageWidth - (margin * 2.0));
        const double staffSize = staffSizeMillimeters / mu::engraving::INCH * mu::engraving::DPI;

        std::unordered_map<mu::engraving::Sid, mu::engraving::PropertyValue> styleValues;
        styleValues.emplace(mu::engraving::Sid::pageWidth, mu::engraving::PropertyValue(pageWidth));
        styleValues.emplace(mu::engraving::Sid::pageHeight, mu::engraving::PropertyValue(pageHeight));
        styleValues.emplace(mu::engraving::Sid::pagePrintableWidth, mu::engraving::PropertyValue(printableWidth));
        styleValues.emplace(mu::engraving::Sid::pageEvenLeftMargin, mu::engraving::PropertyValue(margin));
        styleValues.emplace(mu::engraving::Sid::pageOddLeftMargin, mu::engraving::PropertyValue(margin));
        styleValues.emplace(mu::engraving::Sid::pageEvenTopMargin, mu::engraving::PropertyValue(margin));
        styleValues.emplace(mu::engraving::Sid::pageOddTopMargin, mu::engraving::PropertyValue(margin));
        styleValues.emplace(mu::engraving::Sid::pageEvenBottomMargin, mu::engraving::PropertyValue(margin));
        styleValues.emplace(mu::engraving::Sid::pageOddBottomMargin, mu::engraving::PropertyValue(margin));
        styleValues.emplace(mu::engraving::Sid::spatium, mu::engraving::PropertyValue(staffSize));
        styleValues.emplace(mu::engraving::Sid::minSystemDistance, mu::engraving::PropertyValue(mu::engraving::Spatium(systemSpacingSpatium)));

        mu::engraving::Score* score = activeScore();
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

        score->startCmd(muse::TranslatableString::untranslatable(tempo ? "MuseReader edit tempo" : "MuseReader add tempo"));
        if (!tempo) {
            tempo = mu::engraving::Factory::createTempoText(segment);
            tempo->setParent(segment);
            tempo->setTrack(0);
            score->undoAddElement(tempo);
        }

        static_cast<mu::engraving::EngravingItem*>(tempo)->undoChangeProperty(mu::engraving::Pid::TEXT, tempoText);
        tempo->setTempo(mu::engraving::BeatsPerSecond::fromBPM(mu::engraving::BeatsPerMinute(static_cast<double>(bpm))));
        tempo->setFollowText(true);
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
        if (!score->getPosition(&position, pagePoint, inputState.voice())) {
            return true;
        }

        mu::engraving::Staff* staff = score->staff(position.staffIdx);
        if (!staff || !isStandardStaff(staff, position.segment ? position.segment->tick() : mu::engraving::Fraction(0, 1))) {
            return true;
        }
        normalizePointInputPositionForPutNote(staff, position);
        biasDuplicatePointInputAwayFromExistingChord(score, page, staff, pagePoint, position);

        mu::engraving::Segment* segment = position.segment;
        if (segment) {
            if (mu::engraving::Segment* actualSegment = segment->prev1enabled()) {
                segment = actualSegment;
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
            shadowNote.setState(symNotehead, duration, true, position.beyondScore);
            delete previewRest;
        } else {
            symNotehead = mu::engraving::Note::noteHead(0, mu::engraving::NoteHeadGroup::HEAD_NORMAL, duration.headType());
            const std::optional<mu::engraving::AccidentalType> accidentalType = accidentalKind >= 0
                ? accidentalTypeForKind(accidentalKind)
                : std::nullopt;
            shadowNote.setState(
                symNotehead,
                duration,
                false,
                position.beyondScore,
                accidentalType.value_or(inputState.accidentalType()),
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
        position.pos.rx() -= std::min(relX - score->style().styleAbsolute(mu::engraving::Sid::barNoteDistance), 0.0);

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

        mu::engraving::Measure* selectedMeasure = nullptr;
        mu::engraving::staff_idx_t selectedStaffStart = 0;
        mu::engraving::staff_idx_t selectedStaffEnd = 1;
        if (requestedVoice == 0 && selectedSingleMeasureRange(score, &selectedMeasure, &selectedStaffStart, &selectedStaffEnd)) {
            score->startCmd(muse::TranslatableString::untranslatable("MuseReader replace measure with keyboard note"));
            ::selectMeasureRange(score, selectedMeasure, selectedMeasure, selectedStaffStart, selectedStaffEnd);
            score->cmdDeleteSelection();

            mu::engraving::ChordRest* replacementRest = firstStandardChordRestInMeasure(score, selectedMeasure, selectedStaffStart);
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

        msr::render::ScoreEditState intermediateState;
        for (size_t index = 0; index < midiPitches.size(); ++index) {
            const int midiPitch = midiPitches.at(index);
            if (!mu::engraving::pitchIsValid(midiPitch)) {
                errorMessage = "MuseReader received an unsupported MIDI pitch.";
                return false;
            }

            if (!insertMIDIPitchAtCursor(midiPitch, preferFlats, index > 0, true, intermediateState, errorMessage)) {
                return false;
            }
        }

        mu::engraving::Score* score = activeScore();
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
        if (!score->getPosition(&position, pagePoint, inputState.voice())) {
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

        std::optional<mu::engraving::AccidentalType> requestedAccidentalType;
        const mu::engraving::AccidentalType previousAccidentalType = inputState.accidentalType();
        if (accidentalKind.has_value() && !inputState.rest()) {
            requestedAccidentalType = accidentalTypeForKind(*accidentalKind);
            if (!requestedAccidentalType.has_value()) {
                errorMessage = "MuseReader does not recognize that accidental.";
                return false;
            }
            inputState.setAccidentalType(*requestedAccidentalType);
        }

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader insert note"));
        const muse::Ret insertResult = score->putNote(pagePoint, false, false);
        const bool insertSucceeded = static_cast<bool>(insertResult);
        if (!insertSucceeded) {
            if (requestedAccidentalType.has_value()) {
                inputState.setAccidentalType(previousAccidentalType);
            }
            score->endCmd(true);
            errorMessage = insertResult.text().empty() ? "MuseReader could not place a note at that position." : insertResult.text();
            return false;
        }
        if (requestedAccidentalType.has_value()) {
            inputState.setAccidentalType(previousAccidentalType);
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
        const bool hasPickup = first->excludeFromNumbering() || (first->ticks() < first->timesig());
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
        output.isPickup = measure->excludeFromNumbering() || (actual < nominal);
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
                 first->excludeFromNumbering() ? 1 : 0,
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
        measure->undoChangeProperty(mu::engraving::Pid::EXCLUDE_FROM_NUMBERING, true);
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

        insertedMeasure->undoChangeProperty(mu::engraving::Pid::EXCLUDE_FROM_NUMBERING, true);
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
                 first->excludeFromNumbering() ? 1 : 0,
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
        measure->undoChangeProperty(mu::engraving::Pid::EXCLUDE_FROM_NUMBERING, false);
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

        mu::engraving::Score* score = activeScore();
        const bool transposesCurrentListSelection = score->selection().isList();
        mu::engraving::Measure* startMeasure = nullptr;
        mu::engraving::Measure* endMeasure = nullptr;
        if (!transposesCurrentListSelection && !selectedMeasureRange(score, &startMeasure, &endMeasure)) {
            startMeasure = currentSelectedMeasure(score);
            endMeasure = startMeasure;
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
        if (transposeMode == mu::engraving::TransposeMode::TO_KEY) {
            mu::engraving::Key currentKey = mu::engraving::Key::C;
            const mu::engraving::Fraction keyTick = startMeasure ? startMeasure->tick() : score->selection().tickStart();
            for (mu::engraving::staff_idx_t staffIdx = 0; staffIdx < score->nstaves(); ++staffIdx) {
                mu::engraving::Staff* staff = score->staff(staffIdx);
                if (staff && staff->isPitchedStaff(keyTick)) {
                    currentKey = staff->concertKey(keyTick);
                    break;
                }
            }
            if (currentKey == key) {
                output = makeEditState(score);
                return true;
            }
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

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader transpose selection"));
        if (!transposesCurrentListSelection) {
            ::selectMeasureRange(score, startMeasure, endMeasure, staffStart, staffEnd);
        }
        const bool transposeExistingKeySignatures = transposeMode != mu::engraving::TransposeMode::TO_KEY;
        if (!mu::engraving::Transpose::transpose(score, transposeMode, transposeDirection, key, interval, transposeExistingKeySignatures, true, true)) {
            score->endCmd(true);
            errorMessage = "MuseScore could not transpose the current selection.";
            return false;
        }
        if (!transposesCurrentListSelection && transposeMode == mu::engraving::TransposeMode::TO_KEY) {
            mu::engraving::KeySigEvent keyEvent;
            keyEvent.setConcertKey(key);
            keyEvent.setKey(key);
            const mu::engraving::Fraction tick = startMeasure->tick();
            for (size_t staffIndex = 0; staffIndex < score->nstaves(); ++staffIndex) {
                mu::engraving::Staff* staff = score->staff(staffIndex);
                if (!staff || staff->isDrumStaff(tick)) {
                    continue;
                }

                score->undoChangeKeySig(staff, tick, keyEvent);
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
            mu::engraving::EditNote::upDown(score, movingUp, mode);
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
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        mu::engraving::Score* score = activeScore();
        if (semitoneDelta == 0) {
            output = makeEditState(score);
            return true;
        }

        if (score->selection().isRange()) {
            return shiftRangeSelectionPitch(semitoneDelta, mu::engraving::UpDownMode::CHROMATIC, output, errorMessage);
        }

        mu::engraving::Note* targetNote = currentSelectedNote(score);
        if (!targetNote && score->inputState().noteEntryMode()) {
            targetNote = lastInputNote(score);
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

        score->startCmd(muse::TranslatableString::untranslatable("MuseReader change pitch"));
        score->select(targetNote, mu::engraving::SelectType::SINGLE, targetNote->staffIdx());
        const bool movingUp = semitoneDelta > 0;
        for (int i = 0; i < std::abs(semitoneDelta); ++i) {
            mu::engraving::EditNote::upDown(score, movingUp, mu::engraving::UpDownMode::CHROMATIC);
        }
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
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

        if (score->selection().isRange()) {
            // OCTAVE mode preserves each note's spelling, like desktop Cmd+Up/Down.
            return shiftRangeSelectionPitch(octaveDelta, mu::engraving::UpDownMode::OCTAVE, output, errorMessage);
        }

        return shiftSelectionPitchBySemitones(octaveDelta * 12, output, errorMessage);
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
            mu::engraving::EditNote::undoChangePitch(score, selectedNote, noteValue.pitch, noteValue.tpc1, noteValue.tpc2);
        } else if (selectionState.isMeasure && selectionState.isSingleMeasure) {
            mu::engraving::Measure* selectedMeasure = nullptr;
            mu::engraving::staff_idx_t selectedStaffStart = 0;
            mu::engraving::staff_idx_t selectedStaffEnd = 1;
            if (!selectedSingleMeasureRange(score, &selectedMeasure, &selectedStaffStart, &selectedStaffEnd)) {
                score->endCmd(true);
                errorMessage = "Select one measure before using the keyboard.";
                return false;
            }

            ::selectMeasureRange(score, selectedMeasure, selectedMeasure, selectedStaffStart, selectedStaffEnd);
            score->cmdDeleteSelection();
            selectedChordRestItem = firstStandardChordRestInMeasure(score, selectedMeasure, selectedStaffStart);
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
        if (!score->getPosition(&position, pagePoint, selectedChordRestItem->track() % mu::engraving::VOICES)) {
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
        mu::engraving::EditNote::undoChangePitch(score, selectedNote, noteValue.pitch, noteValue.tpc1, noteValue.tpc2);
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

        mu::engraving::EngravingItem* selectableTarget = noteOrRestSelectionItem(targetChordRest);
        if (!selectableTarget) {
            output = makeEditState(score);
            return true;
        }

        score->select(selectableTarget, mu::engraving::SelectType::SINGLE, selectableTarget->staffIdx());
        output = makeEditState(score);
        return true;
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
        refreshAfterEdit();
        output = makeEditState(score);
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

        mu::engraving::Score* score = activeScore();
        score->startCmd(muse::TranslatableString::untranslatable("MuseReader replace score instruments"));

        std::vector<mu::engraving::Part*> existingParts = score->parts();
        for (mu::engraving::Part* part : existingParts) {
            score->cmdRemovePart(part);
        }

        for (const mu::engraving::InstrumentTemplate* instrumentTemplate : templates) {
            score->appendPart(instrumentTemplate);
        }

        score->setBracketsAndBarlines();
        score->endCmd();
        refreshAfterEdit();
        output = makeEditState(score);
        return true;
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
        score->appendPart(instrumentTemplate);
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
        if (!staff || !anchor) {
            errorMessage = "Aria could not find a clef insertion point.";
            return false;
        }

        score->startCmd(muse::TranslatableString::untranslatable("Aria change clef"));
        score->undoChangeClef(staff, anchor, clefType);
        score->endCmd();

        refreshAfterEdit();
        output = makeEditState(score);
        return true;
    }
