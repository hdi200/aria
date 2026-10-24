import SwiftUI
#if os(Android)
import Observation

/// Screen-space selection geometry is observed only by the small command overlay.
/// No view callback, page image or reader peer is stored here.
@MainActor
@Observable
final class AndroidSelectionCommandPresentation {
    private(set) var anchor: ScoreReaderSelectionCommandAnchor?
    private(set) var selection: ScoreSelectedElement?
    @ObservationIgnored let positioner = AndroidSelectionOverlayPosition()
    @ObservationIgnored private var lastPublished: ScoreReaderSelectionCommandAnchor?
    @ObservationIgnored private var dismissedIdentity: String?
    @ObservationIgnored private var ownerPageIndex: Int?

    func publish(_ next: ScoreReaderSelectionCommandAnchor?, from pageIndex: Int) {
        // A different, unselected page must not clear the active page's anchor.
        if next != nil {
            ownerPageIndex = pageIndex
        } else {
            guard ownerPageIndex == pageIndex else { return }
            ownerPageIndex = nil
        }
        if let dismissedIdentity, next?.identity == dismissedIdentity { return }
        guard next != lastPublished else { return }
        if let next { positioner.move(to: next.actionPosition) }
        let previousSelection = lastPublished?.selectedElement
        lastPublished = next
        anchor = next
        if previousSelection != next?.selectedElement { selection = next?.selectedElement }
    }

    func remove(identity: String, from pageIndex: Int) {
        guard ownerPageIndex == pageIndex, lastPublished?.identity == identity else { return }
        publish(nil, from: pageIndex)
    }

    func dismiss(identity: String) {
        dismissedIdentity = identity
        lastPublished = nil
        anchor = nil
        selection = nil
    }

    func reset() {
        ownerPageIndex = nil
        dismissedIdentity = nil
        lastPublished = nil
        anchor = nil
        selection = nil
    }
}

struct AndroidSelectionCommandOverlayHost: View {
    let presentation: AndroidSelectionCommandPresentation
    let overlay: (ScoreReaderSelectionCommandAnchor) -> AnyView

    var body: some View {
        if let selection = presentation.selection {
            // Actions are rebuilt only when the semantic selection changes. The
            // existing command view reads live position inside GeometryReader.
            overlay(ScoreReaderSelectionCommandAnchor(selectedElement: selection,
                actionPosition: .zero, selectionRects: []))
                .environment(presentation)
        }
    }
}
#endif
