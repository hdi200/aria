import SwiftUI

/// The drum pad that replaces the pitch keyboard on percussion staves. It shows the active
/// instrument's own drums (from its drum set) and fits in the keyboard's space.
///
/// A standard drum kit is shown as two rows that each scroll sideways: Essential Drums on top,
/// Additional Percussion underneath, folded away until the player opens it. With room for them
/// (the iPad, and a portrait phone) the rows have headings with Show more/Show less; in a short
/// strip (a landscape phone) the rows are bare, the folded essentials fill both rows, and a small
/// chip at the end of the second row folds or unfolds the extras. Other percussion keeps desktop's
/// order: one row of tall pads for a small kit, or two rows filled column by column.
struct ScoreReaderDrumPad: View {
    let pads: [ScoreDrumPad]
    let activePitch: Int?
    let isEnabled: Bool
    var showsShortcuts = false
    var targetPadWidth: CGFloat = 92
    /// Target width for a standard kit's tall pads, when it differs from `targetPadWidth`: a
    /// phone narrows them so more drums show in a row.
    var tallPadWidth: CGFloat? = nil
    /// The Add key is armed or locked: pads show a "+" because a tap adds to the current beat.
    var addsToBeat = false
    let action: (Int) -> Void
    /// A long press adds the drum to the current beat, like Shift-click in desktop MuseScore.
    var addAction: (Int) -> Void = { _ in }

    /// Whether the Additional Percussion row is open: closed until the player opens it, then
    /// remembered between scores.
    @AppStorage("drumPadShowsAdditional") private var showsAdditional = false

    private let spacing: CGFloat = 6
    /// Headings need this much height; below it (a landscape phone) the rows are bare.
    private let headingMinimumHeight: CGFloat = 130
    /// Rows shorter than this (both sections open on a phone) use the compact pads, with the
    /// glyph beside the name.
    private let tallPadMinimumHeight: CGFloat = 64
    /// Narrower than this (a phone), headings drop their description to keep Show more in view.
    private let headingDetailMinimumWidth: CGFloat = 520
    private let headingHeight: CGFloat = 16
    private let headingGap: CGFloat = 4
    private let sectionGap: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let arrangement = ScoreDrumPadArrangement(pads: pads)
            if arrangement.isSectioned {
                sectionedPad(arrangement, size: geometry.size)
            } else {
                gridPad(arrangement, size: geometry.size)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drum pad")
    }

    // MARK: Standard kits: Essential Drums and Additional Percussion

    @ViewBuilder
    private func sectionedPad(_ arrangement: ScoreDrumPadArrangement, size: CGSize) -> some View {
        let showsHeadings = size.height >= headingMinimumHeight
        let showsExtras = showsAdditional && !arrangement.extras.isEmpty
        if showsHeadings {
            // Heading, row, gap, heading, row (or just the heading while the extras are folded).
            let headings = 2 * headingHeight + sectionGap + (showsExtras ? 2 * headingGap : headingGap)
            let rowHeight = showsExtras ? (size.height - headings) / 2 : size.height - headings
            let isTall = rowHeight >= tallPadMinimumHeight
            let showsDetail = size.width >= headingDetailMinimumWidth
            VStack(alignment: .leading, spacing: 0) {
                sectionHeading("Essential Drums",
                               detail: showsDetail ? "Most used in rock, pop and modern styles" : nil)
                    .padding(.bottom, headingGap)
                drumRow(arrangement.essentials, width: size.width, height: rowHeight, isTall: isTall,
                        targetWidth: isTall ? tallPadWidth ?? targetPadWidth : targetPadWidth)
                sectionHeading(
                    "Additional Percussion",
                    detail: showsDetail ? "Cymbals, toms, cowbell and other drums" : nil,
                    toggle: arrangement.extras.isEmpty ? nil : showsExtras
                )
                .padding(.top, sectionGap)
                if showsExtras {
                    drumRow(arrangement.extras, width: size.width, height: rowHeight, isTall: isTall,
                            targetWidth: isTall ? tallPadWidth ?? targetPadWidth : targetPadWidth)
                        .padding(.top, headingGap)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        } else if showsExtras {
            let rowHeight = (size.height - spacing) / 2
            VStack(spacing: spacing) {
                drumRow(arrangement.essentials, width: size.width, height: rowHeight, isTall: false)
                drumRow(arrangement.extras, width: size.width, height: rowHeight, isTall: false, foldChip: true)
            }
        } else {
            // Folded in a short strip (a landscape phone): the essentials fill both rows in
            // order, so more drums show at once than one row of tall pads would allow.
            let rowHeight = (size.height - spacing) / 2
            let split = (arrangement.essentials.count + 1) / 2
            VStack(spacing: spacing) {
                drumRow(Array(arrangement.essentials.prefix(split)), width: size.width, height: rowHeight, isTall: false)
                drumRow(Array(arrangement.essentials.dropFirst(split)), width: size.width, height: rowHeight, isTall: false,
                        foldChip: !arrangement.extras.isEmpty)
            }
        }
    }

    private func sectionHeading(_ title: String, detail: String?, toggle isOpen: Bool? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.78))
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let isOpen {
                Button {
                    showsAdditional.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                        Text(isOpen ? "Show less" : "Show more")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.black.opacity(0.62))
                    .padding(.horizontal, 9)
                    .frame(height: headingHeight + 4)
                    .background(Color.black.opacity(0.05), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: headingHeight)
        .accessibilityElement(children: .contain)
    }

    /// One row of pads that scrolls sideways when it doesn't fit. On a phone the row can end
    /// with a chip that folds the Additional row away or brings it back.
    private func drumRow(_ rowPads: [ScoreDrumPad], width: CGFloat, height: CGFloat,
                         isTall: Bool, foldChip: Bool = false, targetWidth: CGFloat? = nil) -> some View {
        let chipWidth: CGFloat = foldChip ? 44 : 0
        let layout = RowLayout(padCount: rowPads.count, width: width, reservedWidth: foldChip ? chipWidth + spacing : 0,
                               spacing: spacing, targetPadWidth: targetWidth ?? targetPadWidth)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(rowPads) { pad in
                        key(for: pad, width: layout.padWidth, height: height, isTall: isTall)
                    }
                    if foldChip {
                        foldButton()
                            .frame(width: chipWidth, height: height)
                    }
                }
                .frame(height: height)
            }
            .scrollDisabled(!layout.scrolls)
            .mask { fadeMask(scrolls: layout.scrolls) }
            .onChangeCompatible(of: activePitch) { pitch in
                guard let pitch, layout.scrolls, rowPads.contains(where: { $0.pitch == pitch }) else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(pitch)
                }
            }
        }
        .frame(width: width, height: height)
    }

    private func foldButton() -> some View {
        Button {
            showsAdditional.toggle()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: showsAdditional ? "chevron.up" : "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                Text(showsAdditional ? "Less" : "More")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(Color.black.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsAdditional ? "Show fewer drums" : "Show more drums")
    }

    // MARK: Other percussion: desktop's order

    private func gridPad(_ arrangement: ScoreDrumPadArrangement, size: CGSize) -> some View {
        let layout = PadLayout(
            padCount: pads.count,
            columnCount: arrangement.columns.count,
            size: size,
            spacing: spacing,
            targetPadWidth: targetPadWidth
        )
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    if layout.rows == 1 {
                        ForEach(arrangement.orderedPads) { pad in
                            key(for: pad, width: layout.padWidth, height: layout.padHeight, isTall: true)
                        }
                    } else {
                        ForEach(arrangement.columns) { column in
                            VStack(spacing: spacing) {
                                slot(column.top, layout: layout)
                                slot(column.bottom, layout: layout)
                            }
                        }
                    }
                }
                .frame(height: size.height)
            }
            .scrollDisabled(!layout.scrolls)
            .mask { fadeMask(scrolls: layout.scrolls) }
            .onChangeCompatible(of: activePitch) { pitch in
                guard let pitch, layout.scrolls else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(pitch)
                }
            }
        }
    }

    @ViewBuilder
    private func slot(_ pad: ScoreDrumPad?, layout: PadLayout) -> some View {
        if let pad {
            key(for: pad, width: layout.padWidth, height: layout.padHeight, isTall: false)
        } else {
            Color.clear
                .frame(width: layout.padWidth, height: layout.padHeight)
        }
    }

    // MARK: Shared

    private func key(for pad: ScoreDrumPad, width: CGFloat, height: CGFloat, isTall: Bool) -> some View {
        ScoreReaderDrumPadKey(
            pad: pad,
            isActive: pad.pitch == activePitch,
            isTall: isTall,
            showsShortcut: showsShortcuts,
            glyphHeight: isTall
                ? min(max(height - (showsShortcuts ? 31 : 24), 20), 40)
                : min(max(height - 10, 24), 44),
            addsToBeat: addsToBeat,
            action: action,
            addAction: addAction
        )
        .frame(width: width, height: height)
        .id(pad.pitch)
    }

    @ViewBuilder
    private func fadeMask(scrolls: Bool) -> some View {
        if scrolls {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.9),
                    .init(color: .black.opacity(0.25), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Rectangle()
        }
    }
}

/// The order the drum pad shows a kit in. A drum kit as MuseScore ships it (its pads where a
/// built-in kit puts them in desktop's percussion panel, or with no panel places at all) is
/// split into two rows:
///
/// - Essential Drums: Bass Drum, Snare, Closed, Open and Pedal Hi-Hat, High, Mid and Floor Tom,
///   Crash, Ride.
/// - Additional Percussion: second bass drum, side stick, splash, second crash, ride bell,
///   china, the other toms, cowbell, then anything else in desktop's order.
///
/// Every other percussion instrument, and a kit someone rearranged in desktop, keeps desktop's
/// order, filled into the strip column by column.
struct ScoreDrumPadArrangement {
    struct Column: Identifiable {
        let index: Int
        let top: ScoreDrumPad?
        let bottom: ScoreDrumPad?
        var id: Int { index }
    }

    /// True for a standard kit, shown as the Essential Drums and Additional Percussion rows.
    let isSectioned: Bool
    let essentials: [ScoreDrumPad]
    let extras: [ScoreDrumPad]
    /// Every pad in strip order (a small kit uses it as one row).
    let orderedPads: [ScoreDrumPad]
    /// Desktop's order filled into two rows column by column, for kits that aren't sectioned.
    let columns: [Column]

    init(pads: [ScoreDrumPad]) {
        guard Self.isStandardDrumKit(pads) else {
            isSectioned = false
            essentials = []
            extras = []
            orderedPads = pads
            columns = stride(from: 0, to: pads.count, by: 2).map { offset in
                Column(index: offset / 2, top: pads[offset], bottom: offset + 1 < pads.count ? pads[offset + 1] : nil)
            }
            return
        }

        let byPitch = Dictionary(pads.map { ($0.pitch, $0) }, uniquingKeysWith: { first, _ in first })
        var used = Set<Int>()
        func pick(_ candidates: [Int]) -> ScoreDrumPad? {
            guard let pitch = candidates.first(where: { byPitch[$0] != nil && !used.contains($0) }) else {
                return nil
            }
            used.insert(pitch)
            guard let pad = byPitch[pitch] else { return nil }
            return Self.shortened(pad)
        }

        // Pick the drums before the cymbals, and the toms high to low, so a fallback never
        // takes another slot's drum.
        let bassDrum = pick([36, 35])
        let snare = pick([38, 40])
        let highTom = pick([50, 48])
        let midTom = pick([47, 48, 45])
        let floorTom = pick([43, 41])
        let closedHiHat = pick([42])
        let openHiHat = pick([46])
        let pedalHiHat = pick([44])
        let crash = pick([49, 57])
        let ride = pick([51, 59])
        let essentialPads = [bassDrum, snare, closedHiHat, openHiHat, pedalHiHat,
                             highTom, midTom, floorTom, crash, ride].compactMap { $0 }

        let extraOrder = [35, 37, 55, 57, 53, 52, 50, 48, 47, 45, 43, 41, 56]
        var extraPads: [ScoreDrumPad] = []
        for pitch in extraOrder where !used.contains(pitch) {
            if let pad = byPitch[pitch] {
                extraPads.append(pad)
                used.insert(pitch)
            }
        }
        extraPads += pads.filter { !used.contains($0.pitch) }

        isSectioned = true
        essentials = essentialPads
        extras = extraPads
        orderedPads = essentialPads + extraPads
        columns = []
    }

    /// The General MIDI names the built-in kits use, trimmed to fit a pad. A name the user
    /// changed is left alone.
    private static func shortened(_ pad: ScoreDrumPad) -> ScoreDrumPad {
        var pad = pad
        switch pad.name {
        case "Bass Drum 1": pad.name = "Bass Drum"
        case "Acoustic Snare": pad.name = "Snare"
        default: break
        }
        return pad
    }

    /// Where desktop's percussion panel puts each drum in MuseScore's built-in drum kits
    /// (share/instruments/instruments.xml: drumset, drum-kit-4, drum-kit-5): pitch → row, column.
    private static let builtInKitPanels: [[Int: [Int]]] = [
        [35: [1, 0], 36: [0, 0], 37: [1, 1], 38: [0, 1], 40: [2, 0], 41: [1, 7], 42: [0, 2], 43: [0, 7],
         44: [1, 2], 45: [1, 6], 46: [0, 3], 47: [1, 5], 48: [0, 6], 49: [0, 4], 50: [1, 4], 51: [0, 5],
         52: [2, 3], 53: [2, 5], 54: [2, 1], 55: [2, 4], 56: [2, 2], 57: [1, 3], 59: [2, 6]],
        [36: [0, 0], 37: [1, 1], 38: [0, 1], 41: [0, 7], 42: [0, 2], 44: [1, 0], 46: [0, 3], 49: [0, 4],
         50: [0, 6], 51: [0, 5], 53: [1, 2]],
        [35: [1, 0], 36: [0, 0], 37: [1, 1], 38: [0, 1], 41: [0, 7], 42: [0, 2], 44: [1, 3], 46: [0, 3],
         47: [1, 6], 49: [0, 4], 50: [0, 6], 51: [0, 5], 52: [1, 7], 53: [1, 5], 55: [1, 2], 57: [1, 4]]
    ]

    /// A drum kit (bass drum, snare and hi-hat) whose pads are where a built-in kit puts them,
    /// or that has no panel places at all (files from before MuseScore 4.4).
    private static func isStandardDrumKit(_ pads: [ScoreDrumPad]) -> Bool {
        let pitches = Set(pads.map(\.pitch))
        guard !pitches.isDisjoint(with: [35, 36]), !pitches.isDisjoint(with: [38, 40]), pitches.contains(42) else {
            return false
        }
        if pads.allSatisfy({ $0.panelRow < 0 || $0.panelColumn < 0 }) {
            return true
        }
        return builtInKitPanels.contains { panel in
            pads.allSatisfy { pad in panel[pad.pitch] == [pad.panelRow, pad.panelColumn] }
        }
    }
}

/// Pad widths for one scrolling row: stretched to fill the row when every pad fits, otherwise
/// with a partly visible last pad so the row visibly scrolls.
private struct RowLayout {
    let padWidth: CGFloat
    let scrolls: Bool

    init(padCount: Int, width: CGFloat, reservedWidth: CGFloat, spacing: CGFloat, targetPadWidth: CGFloat) {
        let count = max(padCount, 1)
        let area = max(width - reservedWidth, 1)
        let fit = max(Int(((area + spacing) / (targetPadWidth + spacing)).rounded(.down)), 1)
        if count <= fit {
            padWidth = min((area - CGFloat(count - 1) * spacing) / CGFloat(count), targetPadWidth * 1.8)
            scrolls = false
        } else {
            let visible = CGFloat(fit) + 0.45
            padWidth = (width - CGFloat(fit) * spacing) / visible
            scrolls = true
        }
    }
}

/// Pad sizes for a kit that keeps desktop's order, in the space the keyboard would take.
private struct PadLayout {
    let rows: Int
    let padWidth: CGFloat
    let padHeight: CGFloat
    let scrolls: Bool

    init(padCount: Int, columnCount: Int, size: CGSize, spacing: CGFloat, targetPadWidth: CGFloat) {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let count = max(padCount, 1)
        // A small kit (a snare, a triangle) gets one row of tall pads that fill the strip.
        let oneRowFits = CGFloat(count) * targetPadWidth * 0.8 + CGFloat(count - 1) * spacing <= width
        if oneRowFits {
            rows = 1
            padHeight = height
            padWidth = min((width - CGFloat(count - 1) * spacing) / CGFloat(count), targetPadWidth * 1.8)
            scrolls = false
            return
        }

        rows = 2
        padHeight = (height - spacing) / 2
        let columns = max(columnCount, 1)
        let fitColumns = max(Int(((width + spacing) / (targetPadWidth + spacing)).rounded(.down)), 1)
        if columns <= fitColumns {
            padWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            scrolls = false
        } else {
            let visible = CGFloat(fitColumns) + 0.45
            padWidth = (width - CGFloat(fitColumns) * spacing) / visible
            scrolls = true
        }
    }
}

/// One pad: a Button, so the strip scrolls when a finger drags across it. A press held for
/// half a second adds the drum to the current beat instead (like Shift-click in desktop
/// MuseScore); the long press gives way as soon as the finger moves, so dragging still scrolls.
struct ScoreReaderDrumPadKey: View {
    let pad: ScoreDrumPad
    let isActive: Bool
    let isTall: Bool
    let showsShortcut: Bool
    let glyphHeight: CGFloat
    let addsToBeat: Bool
    let action: (Int) -> Void
    let addAction: (Int) -> Void

    #if !os(Android)
    /// Set when a long press added the drum, so the Button's release doesn't enter it again.
    @State private var longPressFired = false
    #endif
    private let longPressDuration: Double = 0.45

    private var cell: some View {
        ScoreReaderDrumPadCell(
            pad: pad,
            isActive: isActive,
            isTall: isTall,
            showsShortcut: showsShortcut,
            glyphHeight: glyphHeight
        )
    }

    var body: some View {
        let style = ScoreReaderDrumPadButtonStyle(isActive: isActive, addsToBeat: addsToBeat)
        #if os(Android)
        // Construct the traits directly to avoid Skip's recursive OptionSet initializer
        // and keep the gesture target stable when the active pad changes.
        let button = AccessibilityTraits.isButton.rawValue
        let selected = isActive ? AccessibilityTraits.isSelected.rawValue : 0
        let traits = AccessibilityTraits(rawValue: button | selected)
        // Skip combines both callbacks in one tap detector, so scrolling cancels both.
        style.surface(cell, isPressed: false)
            .onTapGesture { action(pad.pitch) }
            .onLongPressGesture(minimumDuration: longPressDuration) { addAction(pad.pitch) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pad.name)
            .accessibilityAddTraits(traits)
        #else
        Button {
            if longPressFired {
                longPressFired = false
                return
            }
            action(pad.pitch)
        } label: {
            cell
        }
        .buttonStyle(style)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: longPressDuration, maximumDistance: 10)
                .onEnded { _ in
                    longPressFired = true
                    addAction(pad.pitch)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pad.name)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action(pad.pitch) }
        .accessibilityAction(named: "Add to beat") { addAction(pad.pitch) }
        #endif
    }
}

private struct ScoreReaderDrumPadButtonStyle: ButtonStyle {
    let isActive: Bool
    let addsToBeat: Bool

    func makeBody(configuration: Configuration) -> some View {
        surface(configuration.label, isPressed: configuration.isPressed)
    }

    func surface<Label: View>(_ label: Label, isPressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let fill: Color = isPressed
            ? Color(red: 0.80, green: 0.87, blue: 0.99)
            : (isActive ? Color(red: 0.88, green: 0.93, blue: 1.0) : Color.white)
        return label
            .background { shape.fill(fill) }
            .overlay {
                shape.strokeBorder(
                    isActive ? Color.accentColor.opacity(0.85) : Color.black.opacity(0.1),
                    lineWidth: isActive ? 1.5 : 0.75
                )
            }
            .overlay(alignment: .topTrailing) {
                if addsToBeat {
                    Image(systemName: "plus")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .frame(width: 12, height: 12)
                        .background(Color.accentColor, in: Circle())
                        .padding(3)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .contentShape(shape)
    }
}

struct ScoreReaderDrumPadCell: View {
    let pad: ScoreDrumPad
    let isActive: Bool
    let isTall: Bool
    let showsShortcut: Bool
    let glyphHeight: CGFloat

    var body: some View {
        Group {
            if isTall {
                VStack(spacing: glyphHeight < 30 ? 3 : 6) {
                    ScoreReaderDrumNoteGlyph(pad: pad)
                        .frame(width: glyphHeight, height: glyphHeight)
                    nameText
                        .multilineTextAlignment(.center)
                    shortcutText
                }
                .padding(.horizontal, 6)
            } else {
                HStack(spacing: 5) {
                    ScoreReaderDrumNoteGlyph(pad: pad)
                        .frame(width: max(glyphHeight * 0.5, 14), height: glyphHeight)
                    VStack(alignment: .leading, spacing: 1) {
                        nameText
                        shortcutText
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 6)
                .padding(.trailing, 3)
            }
        }
        .foregroundStyle(isActive ? Color.accentColor : Color.black.opacity(0.78))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var nameText: some View {
        let name = Text(pad.name)
            .font(.system(size: isTall ? 13 : 11.5, weight: .medium))
            .lineLimit(isTall && glyphHeight < 30 ? 1 : 2)
        #if os(Android)
        return name.minimumScaleFactor(0.8)
        #else
        return name.allowsTightening(true).minimumScaleFactor(0.8)
        #endif
    }

    @ViewBuilder
    private var shortcutText: some View {
        if showsShortcut, isTall {
            // Every tall pad keeps the badge's space, so names line up whether or not the
            // drum has a shortcut.
            Text(pad.shortcut.isEmpty ? " " : pad.shortcut)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.45))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.black.opacity(pad.shortcut.isEmpty ? 0 : 0.06),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(pad.shortcut.isEmpty)
        } else if showsShortcut, !pad.shortcut.isEmpty {
            Text(pad.shortcut)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.38))
        }
    }
}

/// A tiny staff excerpt: the drum's notehead on roughly its own line, with its stem direction,
/// so a drummer can recognize the pad the way they read the part.
struct ScoreReaderDrumNoteGlyph: View {
    let pad: ScoreDrumPad

    private enum GlyphPart {
        case staff(Path, width: CGFloat)
        case stroke(Path, width: CGFloat)
        case fill(Path)
    }

    private let staffColor = Color.black.opacity(0.24)

    var body: some View {
        #if os(Android)
        GeometryReader { geometry in
            let parts = glyphParts(in: geometry.size)
            ZStack {
                ForEach(parts.indices, id: \.self) { index in
                    switch parts[index] {
                    case let .staff(path, width):
                        path.stroke(staffColor, lineWidth: width)
                    case let .stroke(path, width):
                        path.stroke(.foreground, lineWidth: width)
                    case let .fill(path):
                        path.fill(.foreground)
                    }
                }
            }
        }
        .accessibilityHidden(true)
        #else
        Canvas { context, size in
            for part in glyphParts(in: size) {
                switch part {
                case let .staff(path, width):
                    context.stroke(path, with: .color(staffColor), lineWidth: width)
                case let .stroke(path, width):
                    context.stroke(path, with: .style(.foreground), lineWidth: width)
                case let .fill(path):
                    context.fill(path, with: .style(.foreground))
                }
            }
        }
        .accessibilityHidden(true)
        #endif
    }

    private func glyphParts(in size: CGSize) -> [GlyphPart] {
        let lineGap = size.height / 7
        let staffTop = size.height / 2 - 2 * lineGap
        var staffLines = Path()
        for index in 0..<5 {
            let y = staffTop + CGFloat(index) * lineGap
            staffLines.move(to: CGPoint(x: 0, y: y))
            staffLines.addLine(to: CGPoint(x: size.width, y: y))
        }
        var parts: [GlyphPart] = [.staff(staffLines, width: 0.6)]

        // Drum-set lines count half spaces down from the top line; clamp to the glyph.
        let clampedLine = min(max(CGFloat(pad.line), -3), 11)
        let center = CGPoint(x: size.width / 2, y: staffTop + clampedLine * lineGap / 2)
        let headWidth = lineGap * 1.5
        let headHeight = lineGap * 1.05

        // Ledger lines above and below the staff.
        if clampedLine <= -2 || clampedLine >= 10 {
            var ledgers = Path()
            let step: CGFloat = clampedLine < 0 ? -2 : 2
            var ledgerLine: CGFloat = clampedLine < 0 ? -2 : 10
            while clampedLine < 0 ? ledgerLine >= clampedLine : ledgerLine <= clampedLine {
                let y = staffTop + ledgerLine * lineGap / 2
                ledgers.move(to: CGPoint(x: center.x - headWidth, y: y))
                ledgers.addLine(to: CGPoint(x: center.x + headWidth, y: y))
                ledgerLine += step
            }
            parts.append(.staff(ledgers, width: 0.8))
        }

        let headRect = CGRect(
            x: center.x - headWidth / 2,
            y: center.y - headHeight / 2,
            width: headWidth,
            height: headHeight
        )
        switch pad.notehead {
        case .cross:
            parts.append(.stroke(crossPath(in: headRect.insetBy(dx: 0, dy: -0.5)), width: 1.6))
        case .circleCross:
            parts.append(.stroke(Path(ellipseIn: headRect.insetBy(dx: -1, dy: -1)), width: 1))
            parts.append(.stroke(crossPath(in: headRect.insetBy(dx: 1, dy: 1)), width: 1))
        case .diamond:
            parts.append(.fill(diamondPath(in: headRect)))
        case .triangle:
            var triangle = Path()
            triangle.move(to: CGPoint(x: headRect.midX, y: headRect.minY - 1))
            triangle.addLine(to: CGPoint(x: headRect.maxX, y: headRect.maxY))
            triangle.addLine(to: CGPoint(x: headRect.minX, y: headRect.maxY))
            triangle.closeSubpath()
            parts.append(.fill(triangle))
        case .slash:
            var slash = Path()
            slash.move(to: CGPoint(x: headRect.minX, y: headRect.maxY))
            slash.addLine(to: CGPoint(x: headRect.maxX, y: headRect.minY))
            parts.append(.stroke(slash, width: 2.2))
        case .normal, .other:
            let head = Path(ellipseIn: CGRect(x: -headWidth / 2, y: -headHeight / 2, width: headWidth, height: headHeight))
            let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: -.pi / 9)
            parts.append(.fill(head.applying(transform)))
        }

        var stem = Path()
        let stemLength = lineGap * 3.2
        if pad.stemUp {
            let x = headRect.maxX - 0.4
            stem.move(to: CGPoint(x: x, y: center.y))
            stem.addLine(to: CGPoint(x: x, y: center.y - stemLength))
        } else {
            let x = headRect.minX + 0.4
            stem.move(to: CGPoint(x: x, y: center.y))
            stem.addLine(to: CGPoint(x: x, y: center.y + stemLength))
        }
        parts.append(.stroke(stem, width: 1.1))
        return parts
    }

    private func crossPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }

    private func diamondPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY - 1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY + 1))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// The drum pad's Add key, in the toolbar where the accidentals sit on pitched staves. It works
/// like Shift on the iPhone keyboard: tap to add the next drum to the current beat, double-tap to
/// keep adding, tap again to stop.
struct ScoreReaderDrumAddKey: View {
    enum Style {
        /// iPad toolbar row: icon over a title, like Dot, Rest and Tie.
        case column
        /// Phone grid and grouped rows: icon and title side by side.
        case wide
    }

    let mode: ScoreDrumAddMode
    var style: Style = .wide
    var height: CGFloat = 46
    let action: () -> Void

    private var isOn: Bool { mode != .off }

    private var symbolName: String {
        switch mode {
        case .off: return "shift"
        case .once: return "shift.fill"
        case .locked: return "capslock.fill"
        }
    }

    private var tint: Color {
        isOn ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color.black.opacity(0.82)
    }

    var body: some View {
        Button(action: action) {
            Group {
                switch style {
                case .column:
                    VStack(spacing: 3) {
                        Image(systemName: symbolName)
                            .font(.system(size: 20, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 11, weight: .medium))
                    }
                case .wide:
                    HStack(spacing: 7) {
                        Image(systemName: symbolName)
                            .font(.system(size: 18, weight: .semibold))
                        Text(mode == .locked ? "Adding" : "Add to beat")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                isOn ? Color(red: 0.86, green: 0.93, blue: 1.0) : Color.white.opacity(style == .wide ? 0.58 : 0),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if style == .wide || isOn {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isOn ? Color.blue.opacity(mode == .locked ? 0.55 : 0.24) : Color.black.opacity(0.08),
                                lineWidth: mode == .locked ? 1.4 : 0.7)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Add to beat")
        .accessibilityValue(mode == .off ? "Off" : mode == .once ? "Next drum" : "Locked")
        .accessibilityHint("The next drum goes on the current beat. Double-tap quickly to keep adding.")
    }
}
