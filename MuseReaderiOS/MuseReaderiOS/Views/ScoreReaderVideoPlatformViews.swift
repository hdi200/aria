//
//  ScoreReaderVideoPlatformViews.swift
//  MuseReaderiOS
//
//  The video export sheet's UIKit and iPad presentation pieces: the system player, the
//  window size reader, the panel sizing and layout, and sharing several videos.
//

import SwiftUI
import UIKit
import AVKit

/// Shares the finished videos.
struct ScoreReaderVideoShareLink<Label: View>: View {
    let items: [URL]
    @ViewBuilder let label: () -> Label

    var body: some View {
        ShareLink(items: items, label: label)
    }
}

/// A centered iPad panel with enough height for the preview and all settings.
struct ScoreReaderVideoSheetSizing: ViewModifier {
    let preferredSize: CGSize?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            content.presentationSizing(ScoreReaderVideoPanelSizing(preferredSize: preferredSize))
        } else {
            content.presentationDetents([.large])
        }
    }
}

@available(iOS 18.0, *)
struct ScoreReaderVideoPanelSizing: PresentationSizing {
    let preferredSize: CGSize?

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        if let preferredSize { return ProposedViewSize(preferredSize) }
        return PagePresentationSizing.page.proposedSize(for: root, context: context)
    }
}

/// Read the presenting window, including Split View and Stage Manager resizing.
struct ScoreReaderVideoWindowSizeReader: UIViewRepresentable {
    let onChange: (CGSize) -> Void

    func makeUIView(context: Context) -> WindowSizeView {
        let view = WindowSizeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: WindowSizeView, context: Context) {
        view.onChange = onChange
        view.publishSize()
    }

    final class WindowSizeView: UIView {
        var onChange: ((CGSize) -> Void)?
        private var lastSize = CGSize.zero

        override func didMoveToWindow() {
            super.didMoveToWindow()
            publishSize()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            publishSize()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            publishSize()
        }

        func publishSize() {
            guard let window else { return }
            let size = CGSize(width: window.bounds.width,
                              height: window.bounds.height - window.safeAreaInsets.top - window.safeAreaInsets.bottom)
            guard size != lastSize else { return }
            lastSize = size
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.onChange?(size)
            }
        }
    }
}

/// Measure the controls first and give the preview the remaining height.
struct ScoreReaderVideoSettingsLayout: Layout {
    let spacing: CGFloat

    private func heights(proposal: ProposedViewSize, subviews: Subviews) -> (preview: CGFloat, controls: CGFloat) {
        let width = proposal.width ?? 592
        let controls = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let remaining = proposal.height.map { max(0, $0 - controls - spacing) }
        let preview = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: remaining)).height
        return (preview, controls)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let heights = heights(proposal: proposal, subviews: subviews)
        return CGSize(width: proposal.width ?? 592, height: heights.preview + spacing + heights.controls)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let heights = heights(proposal: ProposedViewSize(bounds.size), subviews: subviews)
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: heights.preview))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + heights.preview + spacing),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: heights.controls))
    }
}

/// The system player inline, with its standard controls.
struct ScoreReaderVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}
