import SwiftUI

/// The drum pad that replaces the pitch keyboard on percussion staves. It shows the active
/// instrument's own drums (from its drum set), in the order desktop MuseScore's percussion
/// panel uses, and fits in the keyboard's height: one row of tall pads for small kits, two
/// rows that scroll sideways for a full drum kit.
struct ScoreReaderDrumPad: View {
    let pads: [ScoreDrumPad]
    let activePitch: Int?
    let isEnabled: Bool
    var showsShortcuts = false
    var targetPadWidth: CGFloat = 92
    /// The Add key is armed or locked: pads show a "+" because a tap adds to the current beat.
    var addsToBeat = false
    let action: (Int) -> Void
    /// A long press adds the drum to the current beat, like Shift-click in desktop MuseScore.
    var addAction: (Int) -> Void = { _ in }

    private let spacing: CGFloat = 6
    /// The line between a standard kit's essential drums and the rest.
    private let dividerWidth: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let arrangement = ScoreDrumPadArrangement(pads: pads)
            let layout = PadLayout(
                padCount: pads.count,
                columnCount: arrangement.columns.count,
                dividerWidth: arrangement.hasDivider ? dividerWidth + spacing : 0,
                size: geometry.size,
                spacing: spacing,
                targetPadWidth: targetPadWidth
            )

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        if layout.rows == 1 {
                            ForEach(arrangement.orderedPads) { pad in
                                key(for: pad, layout: layout)
                            }
                        } else {
                            ForEach(arrangement.columns) { column in
                                HStack(spacing: spacing) {
                                    if arrangement.hasDivider && column.index == arrangement.essentialColumnCount {
                                        Rectangle()
                                            .fill(Color.black.opacity(0.14))
                                            .frame(width: dividerWidth, height: geometry.size.height * 0.7)
                                    }
                                    VStack(spacing: spacing) {
                                        slot(column.top, layout: layout)
                                        slot(column.bottom, layout: layout)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: geometry.size.height)
                }
                .scrollDisabled(!layout.scrolls)
                .mask {
                    if layout.scrolls {
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
                .onChangeCompatible(of: activePitch) { pitch in
                    guard let pitch, layout.scrolls else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(pitch)
                    }
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drum pad")
    }

    private func key(for pad: ScoreDrumPad, layout: PadLayout) -> some View {
        ScoreReaderDrumPadKey(
            pad: pad,
            isActive: pad.pitch == activePitch,
            isTall: layout.rows == 1,
            showsShortcut: showsShortcuts,
            glyphHeight: min(max(layout.padHeight - 10, 24), 44),
            addsToBeat: addsToBeat,
            action: action,
            addAction: addAction
        )
        .frame(width: layout.padWidth, height: layout.padHeight)
        .id(pad.pitch)
    }

    @ViewBuilder
    private func slot(_ pad: ScoreDrumPad?, layout: PadLayout) -> some View {
        if let pad {
            key(for: pad, layout: layout)
        } else {
            Color.clear
                .frame(width: layout.padWidth, height: layout.padHeight)
        }
    }
}

/// The order the drum pad shows a kit in. A drum kit as MuseScore ships it (its pads where the
/// built-in kit puts them in desktop's percussion panel) starts with the drums most parts use,
/// cymbals over drums the way they sit on the staff:
///
///     Closed Hi-Hat  Open Hi-Hat  Crash  Ride      Pedal Hi-Hat
///     Bass Drum      Snare        High   Mid Tom   Floor Tom
///
/// then a divider and the rest: second bass drum, side stick, splash, second crash, ride bell,
/// china, the other toms, cowbell, then anything else in desktop's order. Every other
/// percussion instrument, and a kit someone rearranged in desktop, keeps desktop's order.
struct ScoreDrumPadArrangement {
    struct Column: Identifiable {
        let index: Int
        let top: ScoreDrumPad?
        let bottom: ScoreDrumPad?
        var id: Int { index }
    }

    /// Pads in strip order (used as is when a small kit fits one row).
    let orderedPads: [ScoreDrumPad]
    /// The two-row strip, column by column.
    let columns: [Column]
    /// How many leading columns hold the essential drums; the divider follows them.
    let essentialColumnCount: Int

    var hasDivider: Bool { essentialColumnCount > 0 && essentialColumnCount < columns.count }

    init(pads: [ScoreDrumPad]) {
        guard Self.isStandardDrumKit(pads) else {
            orderedPads = pads
            columns = Self.pairedColumns(pads, startingAt: 0)
            essentialColumnCount = 0
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

        // Pick the drums before the cymbals so a tom's fallback never takes another's slot.
        let bottom = [
            pick([36, 35]),          // bass drum
            pick([38, 40]),          // snare
            pick([50, 48]),          // high tom
            pick([47, 48, 45]),      // mid tom
            pick([43, 41])           // floor tom
        ]
        let top = [
            pick([42]),              // closed hi-hat
            pick([46]),              // open hi-hat
            pick([49, 57]),          // crash
            pick([51, 59]),          // ride
            pick([44])               // pedal hi-hat
        ]
        var essentialColumns: [Column] = []
        for slot in 0..<5 where top[slot] != nil || bottom[slot] != nil {
            essentialColumns.append(Column(index: essentialColumns.count, top: top[slot], bottom: bottom[slot]))
        }

        let extraOrder = [35, 37, 55, 57, 53, 52, 50, 48, 47, 45, 43, 41, 56]
        var extras: [ScoreDrumPad] = []
        for pitch in extraOrder where !used.contains(pitch) {
            if let pad = byPitch[pitch] {
                extras.append(pad)
                used.insert(pitch)
            }
        }
        extras += pads.filter { !used.contains($0.pitch) }

        let essentials = essentialColumns.flatMap { [$0.top, $0.bottom].compactMap { $0 } }
        orderedPads = essentials + extras
        columns = essentialColumns + Self.pairedColumns(extras, startingAt: essentialColumns.count)
        essentialColumnCount = essentialColumns.count
    }

    private static func pairedColumns(_ pads: [ScoreDrumPad], startingAt firstIndex: Int) -> [Column] {
        stride(from: 0, to: pads.count, by: 2).map { offset in
            Column(
                index: firstIndex + offset / 2,
                top: pads[offset],
                bottom: offset + 1 < pads.count ? pads[offset + 1] : nil
            )
        }
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

/// Pad sizes for the space the keyboard would take.
private struct PadLayout {
    let rows: Int
    let padWidth: CGFloat
    let padHeight: CGFloat
    let scrolls: Bool

    init(padCount: Int, columnCount: Int, dividerWidth: CGFloat, size: CGSize, spacing: CGFloat, targetPadWidth: CGFloat) {
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
        let padArea = max(width - dividerWidth, 1)
        // Stretch the pads to fill the strip when every column fits; otherwise show a partial
        // last column so the strip visibly scrolls.
        let fitColumns = max(Int(((padArea + spacing) / (targetPadWidth + spacing)).rounded(.down)), 1)
        if columns <= fitColumns {
            padWidth = (padArea - CGFloat(columns - 1) * spacing) / CGFloat(columns)
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
                VStack(spacing: 6) {
                    ScoreReaderDrumNoteGlyph(pad: pad)
                        .frame(width: 40, height: 40)
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
            .lineLimit(2)
        #if os(Android)
        return name.minimumScaleFactor(0.8)
        #else
        return name.allowsTightening(true).minimumScaleFactor(0.8)
        #endif
    }

    @ViewBuilder
    private var shortcutText: some View {
        if showsShortcut, !pad.shortcut.isEmpty {
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
