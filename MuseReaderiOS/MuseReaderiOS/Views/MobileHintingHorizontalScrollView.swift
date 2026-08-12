import SwiftUI
import UIKit

/// A horizontal scroll view that gives phone users a one-time visual cue when
/// content extends beyond the visible width.
struct MobileHintingHorizontalScrollView<Content: View>: View {
    var showsIndicators = false
    var hintHeight: CGFloat = 46
    var hintTint: Color = .blue

    @State private var viewportWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var hasInteracted = false

    private let content: Content

    init(
        showsIndicators: Bool = false,
        hintHeight: CGFloat = 46,
        hintTint: Color = .blue,
        @ViewBuilder content: () -> Content
    ) {
        self.showsIndicators = showsIndicators
        self.hintHeight = hintHeight
        self.hintTint = hintTint
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: showsIndicators) {
            content
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: MobileHorizontalScrollContentWidthPreferenceKey.self,
                                value: proxy.size.width
                            )
                    }
                }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: MobileHorizontalScrollViewportWidthPreferenceKey.self,
                        value: proxy.size.width
                    )
            }
        }
        .onPreferenceChange(MobileHorizontalScrollContentWidthPreferenceKey.self) { contentWidth = $0 }
        .onPreferenceChange(MobileHorizontalScrollViewportWidthPreferenceKey.self) { viewportWidth = $0 }
        .overlay(alignment: .trailing) {
            if showsOverflowHint {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color(uiColor: .systemBackground).opacity(0), Color(uiColor: .systemBackground).opacity(0.96)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 20)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(hintTint.opacity(0.72))
                        .frame(width: 24, height: hintHeight)
                        .background(Color(uiColor: .systemBackground).opacity(0.96))
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    guard !hasInteracted else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        hasInteracted = true
                    }
                }
        )
    }

    private var showsOverflowHint: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
        && contentWidth > viewportWidth + 8
        && !hasInteracted
    }
}

private struct MobileHorizontalScrollContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MobileHorizontalScrollViewportWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
