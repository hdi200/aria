import SwiftUI

/// A real native View boundary: evaluate the supplied section in this child's
/// Compose observation scope, rather than eagerly reading its model in the reader.
/// The closure captures the reader's stable state boxes/actions, not copied models.
struct AndroidReaderObservationScope<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    // Skip flattens ordinary View bodies during Evaluate. A concrete container
    // must own a deferred child; evaluating content() here would still observe
    // the model in the caller's Render scope.
    var body: some View {
        ZStack { AndroidReaderObservationContent(content: content) }
    }
}

struct AndroidReaderObservationContent<Content: View>: View {
    let content: () -> Content
    var body: some View { content() }
}

/// Mode and selection-kind observers must read editing state in their own scope.
/// Pitch/artwork changes then cannot invalidate the reader's presentation tree.
struct AndroidReaderEditObservers: View {
    let reader: ScoreReaderState
    @Binding var selectedToolCategory: ScoreReaderToolCategory
    let clearSelectionMenu: () -> Void
    let anchorAnnotations: ([ScorePlaybackMeasureRegion]) -> Void

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChangeCompatible(of: reader.playbackMeasureRegions, perform: anchorAnnotations)
            .onChangeCompatible(of: reader.editingState.noteInputEnabled) { enabled in
                selectedToolCategory = ScoreReaderToolModePolicy.category(
                    afterSettingNoteInputEnabled: enabled, currentCategory: selectedToolCategory)
            }
            .onChangeCompatible(of: reader.editingState.selection?.kind) { kind in
                if kind == nil { clearSelectionMenu() }
                if selectedToolCategory == .repeats && kind == nil { selectedToolCategory = .select }
            }
    }
}
