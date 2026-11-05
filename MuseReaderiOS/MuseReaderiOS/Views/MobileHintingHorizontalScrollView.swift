import SwiftUI
import UIKit

/// A horizontal scroll view that gives phone users a one-time visual cue when
/// content extends beyond the visible width.
struct MobileHintingHorizontalScrollView<Content: View>: View {
    var showsIndicators = false
    var hintHeight: CGFloat = 46
    var hintTint: Color = .blue

    @State var viewportWidth: CGFloat = 0
    @State var contentTrailingEdge: CGFloat = 0
    @State var hasInteracted = false
    #if os(iOS)
    @Namespace private var viewportSpace
    #endif

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
                                key: MobileHorizontalScrollContentTrailingEdgePreferenceKey.self,
                                value: trailingEdge(of: proxy)
                            )
                    }
                }
        }
        #if os(iOS)
        .coordinateSpace(name: viewportSpace)
        #endif
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: MobileHorizontalScrollViewportWidthPreferenceKey.self,
                        value: proxy.size.width
                    )
            }
        }
        .onPreferenceChange(MobileHorizontalScrollContentTrailingEdgePreferenceKey.self) { contentTrailingEdge = $0 }
        .onPreferenceChange(MobileHorizontalScrollViewportWidthPreferenceKey.self) { viewportWidth = $0 }
        .overlay(alignment: .trailing) {
            if showsOverflowHint {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color(.systemBackground).opacity(0), Color(.systemBackground).opacity(0.96)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 20)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(hintTint.opacity(0.72))
                        .frame(width: 24, height: hintHeight)
                        .background(Color(.systemBackground).opacity(0.96))
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

    private func trailingEdge(of proxy: GeometryProxy) -> CGFloat {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            // Follow the actual scroll position, including scrolls that don't trigger a drag gesture.
            return proxy.frame(in: .named(viewportSpace)).maxX
        }
        #endif
        return proxy.size.width
    }

    private var showsOverflowHint: Bool {
        AriaWindowLayout.shared.usesPhoneLayout
        && contentTrailingEdge > viewportWidth + 8
        && !hasInteracted
    }
}

struct MobileHorizontalScrollContentTrailingEdgePreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MobileHorizontalScrollViewportWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
