    bool playbackMeasureRegions(std::vector<msr::render::PlaybackMeasureRegion>& output,
                                std::string& errorMessage) const
    {
        mu::engraving::Score* score = presentationScore();
        if (!score) {
            errorMessage = "Playback is unavailable because the score session is closed.";
            return false;
        }

        const SteadyClock::time_point started = SteadyClock::now();
        std::cout << "Aria corruption guard: playback measure extraction begin"
                  << " activeScore=\"" << corruptionScoreLabel(score) << "\""
                  << std::endl;
        output.clear();
        if (blockDelayedSubsystemIfCorrupted(m_masterScore.get(), "playback measure extraction", errorMessage)) {
            std::cout << "Aria corruption guard: playback measure extraction blocked"
                      << " elapsed=" << elapsedSecondsSince(started)
                      << "s" << std::endl;
            return false;
        }

        const auto& repeatList = score->repeatList(true);
        if (repeatList.empty()) {
            std::cout << "Aria corruption guard: playback measure extraction end"
                      << " regions=0"
                      << " elapsed=" << elapsedSecondsSince(started)
                      << "s" << std::endl;
            return true;
        }

        std::unordered_map<const mu::engraving::Measure*, int> measureIndices;
        measureIndices.reserve(static_cast<size_t>(score->nmeasures()));

        int measureIndex = 0;
        for (mu::engraving::Measure* measure = score->firstMeasureMM(); measure; measure = measure->nextMeasureMM()) {
            measureIndices.emplace(measure, measureIndex++);
        }

        output.reserve(static_cast<size_t>(measureIndex));

        for (const mu::engraving::RepeatSegment* repeatSegment : repeatList) {
            if (!repeatSegment) {
                continue;
            }

            const int startTick = repeatSegment->tick;
            const int endTick = repeatSegment->endTick();
            const int tickOffset = repeatSegment->utick - repeatSegment->tick;

            for (mu::engraving::Measure* measure = score->tick2measureMM(mu::engraving::Fraction::fromTicks(startTick));
                 measure;
                 measure = measure->nextMeasureMM()) {
                auto measureIndexIt = measureIndices.find(measure);
                if (measureIndexIt == measureIndices.end()) {
                    if (measure->endTick().ticks() >= endTick) {
                        break;
                    }
                    continue;
                }

                mu::engraving::System* system = measure->system();
                mu::engraving::Page* page = system ? system->page() : nullptr;
                if (system && page && page->width() > 0.0 && page->height() > 0.0) {
                    const double x = measure->pagePos().x();
                    const double y = system->pagePos().y();
                    const double width = measure->ldata()->bbox().width();
                    const double height = system->height();

                    if (width > 0.0 && height > 0.0) {
                        const double pageWidth = page->width();
                        const double pageHeight = page->height();
                        const double left = clampUnitInterval(x / pageWidth);
                        const double top = clampUnitInterval(y / pageHeight);
                        const double right = clampUnitInterval((x + width) / pageWidth);
                        const double bottom = clampUnitInterval((y + height) / pageHeight);

                        msr::render::PlaybackMeasureRegion region;
                        mu::engraving::EID measureEid = measure->eid();
                        if (!measureEid.isValid()) {
                            measureEid = measure->assignNewEID();
                        }
                        region.measureEid = measureEid.toStdString();
                        region.measureIndex = measureIndexIt->second;
                        region.pageIndex = static_cast<int>(score->pageIdx(page));
                        region.startTimeSeconds = std::max(repeatList.utick2utime(measure->tick().ticks() + tickOffset), 0.0);
                        region.endTimeSeconds = region.startTimeSeconds;
                        region.normalizedX = left;
                        region.normalizedY = top;
                        region.normalizedWidth = std::max(right - left, 0.0);
                        region.normalizedHeight = std::max(bottom - top, 0.0);
                        output.push_back(region);
                    }
                }

                if (measure->endTick().ticks() >= endTick) {
                    break;
                }
            }
        }

        for (size_t index = 0; index + 1 < output.size(); ++index) {
            output[index].endTimeSeconds = std::max(output[index + 1].startTimeSeconds, output[index].startTimeSeconds);
        }

        if (!output.empty()) {
            output.back().endTimeSeconds = std::max(repeatList.utick2utime(repeatList.ticks()), output.back().startTimeSeconds);
        }

        std::cout << "Aria corruption guard: playback measure extraction end"
                  << " regions=" << output.size()
                  << " elapsed=" << elapsedSecondsSince(started)
                  << "s" << std::endl;
        return true;
    }

    //! One point per beat, in playback order: where the beat falls on the line
    //! and when it sounds. A beat with no note of its own is placed between
    //! the notes around it, so the playhead is on the notes at every beat and
    //! moves steadily in between. Compound meters (6/8, 9/8, 12/8) beat in
    //! dotted quarters.
    bool playbackBeatPoints(std::vector<msr::render::PlaybackBeatPoint>& output, std::string& errorMessage) const
    {
        mu::engraving::Score* score = presentationScore();
        if (!score) {
            errorMessage = "Playback is unavailable because the score session is closed.";
            return false;
        }

        output.clear();
        if (blockDelayedSubsystemIfCorrupted(m_masterScore.get(), "playback beat extraction", errorMessage)) {
            return false;
        }

        struct LinePoint {
            int tick = 0;
            double x = 0.0;
            int pageIndex = 0;
        };

        const auto& repeatList = score->repeatList(true);
        const size_t trackCount = score->ntracks();
        // Notehead centre: noteheads start at the segment's x.
        const double noteheadOffset = score->style().spatium() * 0.6;
        std::vector<LinePoint> notes;
        std::vector<int> beats;
        int previousEndTick = -1;

        for (size_t segmentIndex = 0; segmentIndex < repeatList.size(); ++segmentIndex) {
            const mu::engraving::RepeatSegment* repeatSegment = repeatList.at(segmentIndex);
            if (!repeatSegment) {
                continue;
            }

            const int startTick = repeatSegment->tick;
            const int endTick = repeatSegment->endTick();
            const int tickOffset = repeatSegment->utick - repeatSegment->tick;
            const bool startsSegment = output.empty() || startTick != previousEndTick;
            notes.clear();
            beats.clear();
            mu::engraving::Measure* lastMeasure = nullptr;

            for (mu::engraving::Measure* measure = score->tick2measureMM(mu::engraving::Fraction::fromTicks(startTick));
                 measure && measure->tick().ticks() < endTick;
                 measure = measure->nextMeasureMM()) {
                mu::engraving::System* system = measure->system();
                mu::engraving::Page* page = system ? system->page() : nullptr;
                if (!page || page->width() <= 0.0) {
                    continue;
                }
                lastMeasure = measure;
                const int pageIndex = static_cast<int>(score->pageIdx(page));

                for (mu::engraving::Segment* segment = measure->first(mu::engraving::SegmentType::ChordRest);
                     segment;
                     segment = segment->next(mu::engraving::SegmentType::ChordRest)) {
                    bool hasItem = false;
                    for (size_t track = 0; track < trackCount && !hasItem; ++track) {
                        const mu::engraving::EngravingItem* item = segment->element(static_cast<mu::engraving::track_idx_t>(track));
                        hasItem = item && item->visible();
                    }
                    if (hasItem) {
                        notes.push_back({ segment->tick().ticks(),
                                          (segment->pagePos().x() + noteheadOffset) / page->width(), pageIndex });
                    }
                }

                const mu::engraving::Fraction timeSig = measure->timesig();
                const bool compound = timeSig.numerator() > 3 && timeSig.numerator() % 3 == 0 && timeSig.denominator() >= 8;
                const int beatTicks = std::max(mu::engraving::Fraction(compound ? 3 : 1, timeSig.denominator()).ticks(), 1);
                for (int tick = measure->tick().ticks(); tick < measure->endTick().ticks(); tick += beatTicks) {
                    beats.push_back(tick);
                }
            }
            if (!lastMeasure || notes.empty()) {
                previousEndTick = endTick;
                continue;
            }

            // The stretch ends at its last barline.
            mu::engraving::Page* lastPage = lastMeasure->system()->page();
            notes.push_back({ endTick,
                              (lastMeasure->pagePos().x() + lastMeasure->ldata()->bbox().width()) / lastPage->width(),
                              static_cast<int>(score->pageIdx(lastPage)) });

            size_t noteIndex = 0;
            bool first = true;
            for (const int beat : beats) {
                if (beat < notes.front().tick) {
                    continue;
                }
                while (noteIndex + 1 < notes.size() && notes[noteIndex + 1].tick <= beat) {
                    ++noteIndex;
                }
                const LinePoint& before = notes[noteIndex];
                const LinePoint& after = noteIndex + 1 < notes.size() ? notes[noteIndex + 1] : before;
                const double fraction = after.tick > before.tick
                    ? static_cast<double>(beat - before.tick) / static_cast<double>(after.tick - before.tick)
                    : 0.0;

                msr::render::PlaybackBeatPoint point;
                point.pageIndex = before.pageIndex;
                point.timeSeconds = std::max(repeatList.utick2utime(beat + tickOffset), 0.0);
                point.normalizedX = clampUnitInterval(before.x + (after.x - before.x) * fraction);
                point.startsSegment = startsSegment && first;
                first = false;
                output.push_back(point);
            }

            // Close the stretch unless playback carries straight on into the next one.
            const mu::engraving::RepeatSegment* next = segmentIndex + 1 < repeatList.size() ? repeatList.at(segmentIndex + 1) : nullptr;
            if (!(next && next->tick == endTick)) {
                msr::render::PlaybackBeatPoint point;
                point.pageIndex = notes.back().pageIndex;
                point.timeSeconds = std::max(repeatList.utick2utime(endTick + tickOffset), 0.0);
                point.normalizedX = clampUnitInterval(notes.back().x);
                output.push_back(point);
            }
            previousEndTick = endTick;
        }
        return true;
    }

    bool playbackTrackSummary(std::vector<msr::render::PlaybackTrackSummary>& output, std::string& errorMessage) const
    {
        mu::engraving::Score* score = presentationScore();
        if (!score) {
            errorMessage = "Playback is unavailable because the score session is closed.";
            return false;
        }

        if (blockDelayedSubsystemIfCorrupted(m_masterScore.get(), "playback track extraction", errorMessage)) {
            output.clear();
            return false;
        }

        score->updateSwing();
        mu::engraving::PlaybackModel playbackModel(m_sessionContext->context());
        const SteadyClock::time_point started = SteadyClock::now();
        playbackModel.load(score);

        output.clear();
        for (const mu::engraving::InstrumentTrackId& trackId : playbackModel.existingTrackIdSet()) {
            muse::mpe::PlaybackData& playbackData = playbackModel.resolveTrackPlaybackData(trackId);
            if (!playbackData.isValid()) {
                continue;
            }

            msr::render::PlaybackTrackSummary summary;
            summary.partId = std::to_string(trackId.partId.toUint64());
            summary.instrumentId = trackId.instrumentId.toStdString();
            summary.setupData = playbackData.setupData.toString().toStdString();

            bool hasTimestamp = false;
            muse::mpe::timestamp_t firstTimestamp = 0;
            muse::mpe::timestamp_t lastTimestamp = 0;

            for (const auto& pair : playbackData.originEvents) {
                const muse::mpe::timestamp_t timestamp = pair.first;
                if (!hasTimestamp) {
                    firstTimestamp = timestamp;
                    lastTimestamp = timestamp;
                    hasTimestamp = true;
                } else {
                    firstTimestamp = std::min(firstTimestamp, timestamp);
                    lastTimestamp = std::max(lastTimestamp, timestamp);
                }

                for (const muse::mpe::PlaybackEvent& event : pair.second) {
                    summary.eventCount += 1;
                    if (std::holds_alternative<muse::mpe::NoteEvent>(event)) {
                        summary.noteEventCount += 1;
                        const muse::mpe::NoteEvent& noteEvent = std::get<muse::mpe::NoteEvent>(event);
                        lastTimestamp = std::max(
                            lastTimestamp,
                            noteEvent.arrangementCtx().actualTimestamp + noteEvent.arrangementCtx().actualDuration
                        );
                    } else if (std::holds_alternative<muse::mpe::ControllerChangeEvent>(event)) {
                        summary.controllerEventCount += 1;
                    } else if (std::holds_alternative<muse::mpe::SoundPresetChangeEvent>(event)) {
                        summary.soundPresetEventCount += 1;
                    }
                }
            }

            if (hasTimestamp) {
                summary.firstTimestampSeconds = static_cast<double>(firstTimestamp) / 1000000.0;
                summary.lastTimestampSeconds = static_cast<double>(lastTimestamp) / 1000000.0;
            }

            output.push_back(std::move(summary));
        }

        int totalEvents = 0;
        int totalNoteEvents = 0;
        for (const msr::render::PlaybackTrackSummary& summary : output) {
            totalEvents += summary.eventCount;
            totalNoteEvents += summary.noteEventCount;
        }

        std::cout << "MuseReader playback model summary: tracks="
                  << output.size()
                  << " events=" << totalEvents
                  << " notes=" << totalNoteEvents
                  << " build=" << elapsedSecondsSince(started)
                  << "s" << std::endl;

        return true;
    }

    bool playbackMIDIData(std::vector<std::uint8_t>& output, std::string& errorMessage) const
    {
        mu::engraving::Score* score = activeScore();
        if (!score) {
            errorMessage = "Playback is unavailable because the score session is closed.";
            return false;
        }

        if (blockDelayedSubsystemIfCorrupted(m_masterScore.get(), "MIDI playback export", errorMessage)) {
            output.clear();
            return false;
        }

        QByteArray midiData;
        QBuffer buffer(&midiData);
        if (!buffer.open(QIODevice::WriteOnly)) {
            errorMessage = "The render core could not allocate a MIDI export buffer.";
            return false;
        }

        mu::iex::midi::ExportMidi exporter(score);
        const SteadyClock::time_point midiExportStarted = SteadyClock::now();
        const bool wroteMIDI = exporter.write(
            &buffer,
            true,
            false,
            score->synthesizerState()
        );
        const double midiExportTimeSeconds = elapsedSecondsSince(midiExportStarted);
        if (!wroteMIDI) {
            errorMessage = "The MuseScore render core could not export MIDI for this score.";
            return false;
        }

        output.assign(midiData.begin(), midiData.end());
        std::cout << "MuseReader MIDI export timing: bytes="
                  << output.size()
                  << " export=" << midiExportTimeSeconds
                  << "s" << std::endl;
        return true;
    }

    bool musicXMLData(std::vector<std::uint8_t>& output, std::string& errorMessage) const
    {
        mu::engraving::Score* score = activeScore();
        if (!score) {
            errorMessage = "MusicXML export is unavailable because the score session is closed.";
            return false;
        }

        muse::ByteArray xmlData;
        muse::io::Buffer buffer(&xmlData);
        if (!buffer.open(muse::io::IODevice::WriteOnly)) {
            errorMessage = "The render core could not allocate a MusicXML export buffer.";
            return false;
        }

        const SteadyClock::time_point musicXMLExportStarted = SteadyClock::now();
        const bool wroteMusicXML = mu::iex::musicxml::saveXml(score, &buffer);
        const double musicXMLExportTimeSeconds = elapsedSecondsSince(musicXMLExportStarted);
        if (!wroteMusicXML) {
            errorMessage = "The MuseScore render core could not export MusicXML for this score.";
            return false;
        }

        output.assign(xmlData.constData(), xmlData.constData() + xmlData.size());
        std::cout << "MuseReader MusicXML export timing: bytes="
                  << output.size()
                  << " export=" << musicXMLExportTimeSeconds
                  << "s" << std::endl;
        return true;
    }
