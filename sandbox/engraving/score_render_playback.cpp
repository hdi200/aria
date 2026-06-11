    bool playbackMeasureRegions(std::vector<msr::render::PlaybackMeasureRegion>& output,
                                std::string& errorMessage) const
    {
        mu::engraving::Score* score = activeScore();
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

    bool playbackTrackSummary(std::vector<msr::render::PlaybackTrackSummary>& output, std::string& errorMessage) const
    {
        mu::engraving::Score* score = activeScore();
        if (!score) {
            errorMessage = "Playback is unavailable because the score session is closed.";
            return false;
        }

        if (blockDelayedSubsystemIfCorrupted(m_masterScore.get(), "playback track extraction", errorMessage)) {
            output.clear();
            return false;
        }

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

