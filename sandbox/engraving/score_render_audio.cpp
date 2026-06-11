    bool playbackEventAudioData(const std::string& soundFontPath,
                                const double startTimeSeconds,
                                const double durationSeconds,
                                const bool metronomeEnabled,
                                msr::render::PlaybackAudioData& output,
                                std::string& errorMessage) const
    {
        if (startTimeSeconds < 0.0) {
            errorMessage = "Playback chunk start time must be non-negative.";
            return false;
        }
        if (durationSeconds <= 0.0) {
            errorMessage = "Playback chunk duration must be positive.";
            return false;
        }

        std::cout << "MuseReader event playback request: activeScore="
                  << (m_activePartIndex.has_value() ? "part" : "full")
                  << " partIndex=" << (m_activePartIndex.has_value() ? *m_activePartIndex : -1)
                  << " start=" << startTimeSeconds
                  << " duration=" << durationSeconds
                  << " metronome=" << (metronomeEnabled ? "on" : "off")
                  << std::endl;

        if (blockDelayedSubsystemIfCorrupted(m_masterScore.get(), "event playback render", errorMessage)) {
            output = {};
            return false;
        }

        std::optional<std::uint64_t> activePartId;
        if (m_activePartIndex.has_value() && m_masterScore) {
            const std::vector<mu::engraving::Part*>& parts = m_masterScore->parts();
            if (*m_activePartIndex >= 0 && *m_activePartIndex < static_cast<int>(parts.size())) {
                if (const mu::engraving::Part* part = parts.at(static_cast<size_t>(*m_activePartIndex))) {
                    activePartId = part->id().toUint64();
                }
            }
        }

        std::cout << "MuseReader event playback part filter: "
                  << (activePartId.has_value() ? std::to_string(*activePartId) : std::string("full"))
                  << std::endl;

        return renderFluidSynthPlaybackEvents(activeScore(),
                                              m_sessionContext->context(),
                                              soundFontPath,
                                              activePartId,
                                              startTimeSeconds,
                                              durationSeconds,
                                              metronomeEnabled,
                                              output,
                                              errorMessage);
    }
