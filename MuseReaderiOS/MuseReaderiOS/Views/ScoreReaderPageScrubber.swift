//
//  ScoreReaderPageScrubber.swift
//  MuseReaderiOS
//

import SwiftUI
import UIKit

/// Maps positions on the page slider to pages. The track spans the whole
/// score, so a position is a fraction of the way through it.
struct ScoreReaderPageScrubMapping: Equatable {
    let pageCount: Int
    let trackWidth: CGFloat

    func pageIndex(atX x: CGFloat) -> Int {
        guard pageCount > 1, trackWidth > 0 else { return 0 }
        let fraction = min(max(x / trackWidth, 0), 1)
        return Int((fraction * CGFloat(pageCount - 1)).rounded())
    }

    func x(forPageIndex pageIndex: Int) -> CGFloat {
        guard pageCount > 1 else { return 0 }
        let clamped = min(max(pageIndex, 0), pageCount - 1)
        return trackWidth * CGFloat(clamped) / CGFloat(pageCount - 1)
    }
}

/// View-mode page slider: "3 of 65" next to a track whose knob marks the
/// current page. Drag the knob, or touch anywhere on the track, to move
/// through the score; the page turns on release.
struct ScoreReaderPageScrubber: View {
    let pageCount: Int
    let currentPageIndex: Int
    let usesTwoPageSpread: Bool
    let commitAction: (Int) -> Void

    @State private var scrubPageIndex: Int?
    @State private var selectionFeedback = UISelectionFeedbackGenerator()

    private let knobSize: CGFloat = 14
    private let trackHeight: CGFloat = 4

    var body: some View {
        VStack(spacing: 1) {
            Text(label(for: currentPageIndex))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.black.opacity(0.62))
                .lineLimit(1)
                .fixedSize()

            track
                .frame(height: 18)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 5)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.10), radius: 10, y: 4)
        .accessibilityElement()
        .accessibilityLabel("Page")
        .accessibilityValue(label(for: currentPageIndex))
        .accessibilityAdjustableAction { direction in
            let step = usesTwoPageSpread ? 2 : 1
            switch direction {
            case .increment:
                commitAction(min(currentPageIndex + step, pageCount - 1))
            case .decrement:
                commitAction(max(currentPageIndex - step, 0))
            @unknown default:
                break
            }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let mapping = ScoreReaderPageScrubMapping(
                pageCount: pageCount,
                trackWidth: max(proxy.size.width - knobSize, 1)
            )
            let shownIndex = displayedIndex(scrubPageIndex ?? currentPageIndex)
            let knobX = mapping.x(forPageIndex: shownIndex)
            let isScrubbing = scrubPageIndex != nil

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.14))
                    .frame(height: trackHeight)
                    .padding(.horizontal, knobSize / 2)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: knobX + knobSize / 2, height: trackHeight)
                    .padding(.leading, knobSize / 2)
                    .opacity(pageCount > 1 ? 1 : 0)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: Color.black.opacity(0.22), radius: 2, y: 1)
                    .frame(width: knobSize, height: knobSize)
                    .scaleEffect(isScrubbing ? 1.35 : 1)
                    .offset(x: knobX)
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if isScrubbing {
                    Text("Page " + label(for: shownIndex, includesTotal: false))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.black.opacity(0.84))
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: Color.black.opacity(0.14), radius: 10, y: 3)
                        .alignmentGuide(.leading) { dimensions in
                            dimensions.width / 2 - knobX - knobSize / 2
                        }
                        .offset(y: -62)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture(mapping: mapping))
            .animation(.easeOut(duration: 0.12), value: isScrubbing)
        }
        .frame(minWidth: 44)
    }

    private func scrubGesture(mapping: ScoreReaderPageScrubMapping) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let pageIndex = mapping.pageIndex(atX: value.location.x - knobSize / 2)
                guard let previous = scrubPageIndex else {
                    selectionFeedback.prepare()
                    scrubPageIndex = pageIndex
                    return
                }
                if displayedIndex(pageIndex) != displayedIndex(previous) {
                    selectionFeedback.selectionChanged()
                    selectionFeedback.prepare()
                }
                scrubPageIndex = pageIndex
            }
            .onEnded { _ in
                let target = scrubPageIndex ?? currentPageIndex
                scrubPageIndex = nil
                if displayedIndex(target) != displayedIndex(currentPageIndex) {
                    commitAction(target)
                }
            }
    }

    /// The first page of the spread a page belongs to, or the page itself.
    private func displayedIndex(_ pageIndex: Int) -> Int {
        usesTwoPageSpread ? pageIndex - (pageIndex % 2) : pageIndex
    }

    private func label(for pageIndex: Int, includesTotal: Bool = true) -> String {
        let total = includesTotal ? " of \(pageCount)" : ""
        guard usesTwoPageSpread else {
            return "\(pageIndex + 1)\(total)"
        }
        let start = displayedIndex(pageIndex)
        let end = min(start + 1, pageCount - 1)
        let range = start == end ? "\(start + 1)" : "\(start + 1)–\(end + 1)"
        return "\(range)\(total)"
    }
}
