//
//  DuoReaderRegions.swift
//  MuseReaderiOS
//
//  Places the reader's own views on one side of an iPhone Duo's fold.
//

import SwiftUI

enum DuoReaderRegion {
    /// The left page, or the upright half in stand pose.
    case leading
    /// The right page, or the flat half in stand pose.
    case trailing
}

extension View {
    /// Lays this view out inside one region of an unfolded Duo, aligned within it. With no
    /// region it is returned unchanged, so other devices lay out exactly as before.
    @ViewBuilder
    func duoRegion(_ region: DuoReaderRegion?, of layout: DuoReaderLayout?, alignment: Alignment = .center) -> some View {
        if let region, let layout {
            modifier(DuoReaderRegionModifier(region: region, layout: layout, alignment: alignment))
        } else {
            self
        }
    }
}

struct DuoReaderRegionModifier: ViewModifier {
    let region: DuoReaderRegion
    let layout: DuoReaderLayout
    let alignment: Alignment

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            // The layout is in window coordinates; this view may be inset (safe area).
            let frame = proxy.frame(in: .global)
            let windowRect = region == .leading ? layout.leadingRect : layout.trailingRect
            let local = windowRect
                .offsetBy(dx: -frame.minX, dy: -frame.minY)
                .intersection(CGRect(origin: .zero, size: proxy.size))
            let rect = local.isNull ? .zero : local

            content
                .frame(width: rect.width, height: rect.height, alignment: alignment)
                .position(x: rect.midX, y: rect.midY)
        }
    }
}

extension View {
    /// One of the cards a Duo's right page is built from in book pose.
    func duoCard() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 3)
    }

    /// An unfolded Duo's inner display is shorter than any iPad's, so a panel sized for an
    /// iPad scrolls within `maxHeight` there. Elsewhere it is returned unchanged.
    @ViewBuilder
    func scrollsVerticallyOnDuo(_ isDuo: Bool, maxHeight: CGFloat) -> some View {
        if isDuo {
            ScrollView(.vertical, showsIndicators: false) {
                self
            }
            .frame(maxHeight: max(maxHeight, 120))
            .fixedSize(horizontal: true, vertical: false)
        } else {
            self
        }
    }
}
