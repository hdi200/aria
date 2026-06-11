    bool currentEditState(msr::render::ScoreEditState& output, std::string& errorMessage) const
    {
        if (!supportsEditing()) {
            errorMessage = "Editing is unavailable for this score session.";
            return false;
        }

        output = makeEditState(activeScore());
        return true;
    }

    bool selectElement(const int pageIndex,
                       const double normalizedX,
                       const double normalizedY,
                       const double hitRadiusScale,
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

        const mu::engraving::PointF pagePoint = pointForNormalizedPagePosition(page, normalizedX, normalizedY);
        const double clampedHitRadiusScale = std::clamp(hitRadiusScale, 0.35, 1.5);
        const double selectionRadius = std::max(page->spatium() * 1.25, 12.0) * clampedHitRadiusScale;
        mu::engraving::EngravingItem* selectedItem = directSelectableItemAtPoint(page, pagePoint);
        mu::engraving::EngravingItem* nearbyItem = selectedItem
            ? nullptr
            : nearbySelectableItemAtPoint(page,
                                          pagePoint,
                                          selectionRadius,
                                          std::max(page->spatium() * 0.9, 9.0) * clampedHitRadiusScale);

        if (selectedItem) {
            score->select(selectedItem, mu::engraving::SelectType::SINGLE, selectedItem->staffIdx());
        } else if (nearbyItem) {
            score->select(nearbyItem, mu::engraving::SelectType::SINGLE, nearbyItem->staffIdx());
        } else {
            const MeasureHit measureHit = measureAtPoint(page, pagePoint);
            if (measureHit.measure) {
                ::selectMeasureRange(score, measureHit.measure, measureHit.measure, measureHit.staffIdx);
            } else {
                score->deselectAll();
            }
        }

        output = makeEditState(score);
        return true;
    }

    bool selectMeasureRange(const int pageIndex,
                            const double startNormalizedX,
                            const double startNormalizedY,
                            const double endNormalizedX,
                            const double endNormalizedY,
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

        const mu::engraving::PointF startPoint = pointForNormalizedPagePosition(page, startNormalizedX, startNormalizedY);
        const mu::engraving::PointF endPoint = pointForNormalizedPagePosition(page, endNormalizedX, endNormalizedY);
        const MeasureHit startHit = measureAtPoint(page, startPoint);
        const MeasureHit endHit = measureAtPoint(page, endPoint);
        if (!startHit.measure || !endHit.measure) {
            errorMessage = "Drag across measures to select a measure range.";
            return false;
        }

        const mu::engraving::staff_idx_t staffStart = std::min(startHit.staffIdx, endHit.staffIdx);
        const mu::engraving::staff_idx_t staffEnd = std::max(startHit.staffIdx, endHit.staffIdx) + 1;
        const double dragDistance = std::hypot(endNormalizedX - startNormalizedX, endNormalizedY - startNormalizedY);
        if (dragDistance > 0.01) {
            const bool dragsForward = endHit.measure->tick() > startHit.measure->tick()
                || (endHit.measure == startHit.measure && endPoint.x() >= startPoint.x());
            mu::engraving::Segment* startSegment = dragsForward
                ? chordRestSegmentAtPointInMeasure(startHit.measure, startPoint)
                : chordRestSegmentAtPointInMeasure(endHit.measure, endPoint);
            mu::engraving::Segment* endSegment = dragsForward
                ? chordRestSegmentAtPointInMeasure(endHit.measure, endPoint)
                : chordRestSegmentEndingAtOrBeforePointInMeasure(startHit.measure, startPoint);
            if (startSegment && endSegment) {
                if (dragsForward && startSegment->tick() > endSegment->tick()) {
                    endSegment = startSegment;
                }
                ::selectSegmentRange(score, startSegment, endSegment, staffStart, staffEnd);
            } else {
                ::selectMeasureRange(score, startHit.measure, endHit.measure, staffStart, staffEnd);
            }
        } else {
            ::selectMeasureRange(score, startHit.measure, endHit.measure, staffStart, staffEnd);
        }
        output = makeEditState(score);
        return true;
    }

