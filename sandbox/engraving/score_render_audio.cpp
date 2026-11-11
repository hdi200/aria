    bool playbackEventAudioData(const std::string& soundFontPath,
                                const double startTimeSeconds,
                                const double durationSeconds,
                                const bool metronomeEnabled,
                                msr::render::PlaybackAudioData& output,
                                std::string& errorMessage,
                                const bool includePartSamples,
                                const msr::render::PlaybackMix* mix) const
    {
        if (startTimeSeconds < 0.0) {
            errorMessage = "Playback chunk start time must be non-negative.";
            return false;
        }
        if (durationSeconds <= 0.0) {
            errorMessage = "Playback chunk duration must be positive.";
            return false;
        }

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

        return renderFluidSynthPlaybackEvents(presentationScore(),
                                              m_sessionContext->context(),
                                              soundFontPath,
                                              activePartId,
                                              startTimeSeconds,
                                              durationSeconds,
                                              metronomeEnabled,
                                              m_playbackStreamRevision,
                                              m_playbackStream,
                                              output,
                                              errorMessage,
                                              includePartSamples,
                                              mix);
    }

    bool playbackNotes(std::vector<msr::render::PlaybackNote>& output, std::string& errorMessage) const
    {
        if (blockDelayedSubsystemIfCorrupted(m_masterScore.get(), "playback notes", errorMessage)) {
            output.clear();
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
        return collectFluidSynthPlaybackNotes(presentationScore(), m_sessionContext->context(), activePartId,
                                              output, errorMessage);
    }

    //! Practice speed: a tempo multiplier on every tempo of the score, as desktop's playback
    //! speed (NotationPlayback::setTempoMultiplier). Playback only; never written to files.
    bool setPlaybackSpeed(const double multiplier, std::string& errorMessage)
    {
        if (!m_masterScore) {
            errorMessage = "Playback is unavailable because the score session is closed.";
            return false;
        }
        const double clamped = std::clamp(multiplier, 0.1, 4.0);
        m_playbackSpeed = clamped;
        applyPlaybackSpeed(m_masterScore.get());
        applyPlaybackSpeed(m_viewTransposeMasterScore.get());
        m_playbackStream.reset();
        ++m_playbackStreamRevision;
        return true;
    }

    double playbackSpeed() const
    {
        return m_playbackSpeed;
    }

    void applyPlaybackSpeed(mu::engraving::MasterScore* score)
    {
        if (!score || !score->tempomap()) {
            return;
        }
        if (score->tempomap()->setTempoMultiplier(mu::engraving::BeatsPerSecond(m_playbackSpeed))) {
            score->updateRepeatListTempo();
        }
    }

    bool playbackCountIn(const std::string& soundFontPath,
                         const double startTimeSeconds,
                         msr::render::PlaybackCountIn& output,
                         std::string& errorMessage,
                         const int bars = 1) const
    {
        if (blockDelayedSubsystemIfCorrupted(m_masterScore.get(), "count-in render", errorMessage)) {
            output = {};
            return false;
        }

        return renderFluidSynthCountIn(presentationScore(),
                                       m_sessionContext->context(),
                                       soundFontPath,
                                       startTimeSeconds,
                                       output,
                                       errorMessage,
                                       std::max(bars, 1));
    }
