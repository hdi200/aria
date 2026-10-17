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
    /// Android: an adaptive grid doesn't leave one cell alone on its last row (a short,
    /// fixed set such as the New Score templates). iOS lays out as LazyVGrid does.
    var avoidsLoneLastItem = false
    @ViewBuilder let cell: (Item) -> Cell

    init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
         items: [Item], id: KeyPath<Item, ID>, avoidsLoneLastItem: Bool = false,
         @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.items = items
        self.id = id
        self.avoidsLoneLastItem = avoidsLoneLastItem
        self.cell = cell
    }

    #if os(Android)
    @State var width: CGFloat = UIScreen.main.bounds.width

    var body: some View {
        let layout = AriaGridRowLayout(columns: columns, width: width,
                                       itemCount: avoidsLoneLastItem ? items.count : nil)
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
         items: [Item], avoidsLoneLastItem: Bool = false, @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.init(columns: columns, alignment: alignment, spacing: spacing, items: items, id: \.id,
                  avoidsLoneLastItem: avoidsLoneLastItem, cell: cell)
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

    /// `itemCount`: when given, an adaptive grid avoids a lone cell on its last row, by
    /// fitting one more column if the cells stay at least 85% of their minimum width, or
    /// else by spreading the cells evenly over the rows.
    init(columns: [GridItem], width: CGFloat, itemCount: Int? = nil) {
        let spacing = columns.first?.spacing ?? 8
        columnSpacing = spacing
        if columns.count == 1, case .adaptive(let minimum, let maximum) = columns[0].size {
            var count = max(1, Int((width + spacing) / (minimum + spacing)))
            if let itemCount, count > 1, itemCount > count, itemCount % count == 1 {
                let oneMore = (width - spacing * CGFloat(count)) / CGFloat(count + 1)
                if oneMore >= minimum * 0.85 {
                    count += 1
                } else {
                    let rows = (itemCount + count - 1) / count
                    count = (itemCount + rows - 1) / rows
                }
            }
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
