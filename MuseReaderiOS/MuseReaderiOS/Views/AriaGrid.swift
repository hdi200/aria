//
//  AriaGrid.swift
//  MuseReaderiOS
//
//  A grid of cells built from data, for grids placed inside a scroll view.
//

import SwiftUI

/// `LazyVGrid { ForEach(items) { cell } }` on iOS.
///
/// On Android, Skip's lazy grids take over scrolling from an enclosing ScrollView, and the
/// content after the grid then overlaps it. There the cells are laid out in rows instead.
struct AriaGrid<Item, ID: Hashable, Cell: View>: View {
    let columns: [GridItem]
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat? = nil
    let items: [Item]
    let id: KeyPath<Item, ID>
    @ViewBuilder let cell: (Item) -> Cell

    init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
         items: [Item], id: KeyPath<Item, ID>, @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.items = items
        self.id = id
        self.cell = cell
    }

    #if os(Android)
    @State var width: CGFloat = UIScreen.main.bounds.width

    var body: some View {
        let layout = AriaGridRowLayout(columns: columns, width: width)
        let rows = stride(from: 0, to: items.count, by: max(layout.columnCount, 1)).map { start in
            Array(items[start..<min(start + max(layout.columnCount, 1), items.count)])
        }
        VStack(alignment: alignment, spacing: spacing ?? 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: layout.columnSpacing) {
                    ForEach(row, id: id) { item in
                        cell(item)
                            .frame(width: layout.cellWidth, alignment: .top)
                            .frame(maxWidth: layout.cellWidth == nil ? .infinity : nil, alignment: .top)
                    }
                    if layout.cellWidth == nil, row.count < layout.columnCount {
                        ForEach(row.count..<layout.columnCount, id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .top))
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
            }
        )
    }
    #else
    var body: some View {
        LazyVGrid(columns: columns, alignment: alignment, spacing: spacing) {
            ForEach(items, id: id) { item in
                cell(item)
            }
        }
    }
    #endif
}

extension AriaGrid where Item: Identifiable, ID == Item.ID {
    init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
         items: [Item], @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.init(columns: columns, alignment: alignment, spacing: spacing, items: items, id: \.id, cell: cell)
    }
}

#if os(Android)
/// How LazyVGrid would size the columns: fixed and flexible items are one column each; an
/// adaptive item fits as many columns of at least its minimum width as the width allows.
struct AriaGridRowLayout {
    let columnCount: Int
    let columnSpacing: CGFloat
    /// nil: the cells share the row width.
    let cellWidth: CGFloat?

    init(columns: [GridItem], width: CGFloat) {
        let spacing = columns.first?.spacing ?? 8
        columnSpacing = spacing
        if columns.count == 1, case .adaptive(let minimum, let maximum) = columns[0].size {
            let count = max(1, Int((width + spacing) / (minimum + spacing)))
            columnCount = count
            let fitted = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
            cellWidth = maximum.isFinite ? min(fitted, maximum) : nil
        } else {
            columnCount = max(columns.count, 1)
            if case .fixed(let value) = columns.first?.size, columns.allSatisfy({ if case .fixed = $0.size { return true }; return false }) {
                cellWidth = value
            } else {
                cellWidth = nil
            }
        }
    }
}
#endif
