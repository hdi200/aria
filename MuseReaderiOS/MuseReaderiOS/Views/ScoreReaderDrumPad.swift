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

    var body: some View {
        GeometryReader { geometry in
            let layout = PadLayout(
                padCount: pads.count,
                size: geometry.size,
                spacing: spacing,
                targetPadWidth: targetPadWidth
            )

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(
                        rows: Array(repeating: GridItem(.fixed(layout.padHeight), spacing: spacing), count: layout.rows),
                        spacing: spacing
                    ) {
                        ForEach(pads) { pad in
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
}

/// Pad sizes for the space the keyboard would take.
private struct PadLayout {
    let rows: Int
    let padWidth: CGFloat
    let padHeight: CGFloat
    let scrolls: Bool

    init(padCount: Int, size: CGSize, spacing: CGFloat, targetPadWidth: CGFloat) {
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
        let columns = Int(ceil(Double(count) / 2))
        // Stretch the pads to fill the strip when every column fits; otherwise show a partial
        // last column so the strip visibly scrolls.
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
private struct ScoreReaderDrumPadKey: View {
    let pad: ScoreDrumPad
    let isActive: Bool
    let isTall: Bool
    let showsShortcut: Bool
    let glyphHeight: CGFloat
    let addsToBeat: Bool
    let action: (Int) -> Void
    let addAction: (Int) -> Void

    /// Set when a long press added the drum, so the Button's release doesn't enter it again.
    @State private var longPressFired = false
    private let longPressDuration: Double = 0.45

    var body: some View {
        Button {
            if longPressFired {
                longPressFired = false
                return
            }
            action(pad.pitch)
        } label: {
            ScoreReaderDrumPadCell(
                pad: pad,
                isActive: isActive,
                isTall: isTall,
                showsShortcut: showsShortcut,
                glyphHeight: glyphHeight
            )
        }
        .buttonStyle(ScoreReaderDrumPadButtonStyle(isActive: isActive, addsToBeat: addsToBeat))
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
    }
}

private struct ScoreReaderDrumPadButtonStyle: ButtonStyle {
    let isActive: Bool
    let addsToBeat: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let fill: Color = configuration.isPressed
            ? Color(red: 0.80, green: 0.87, blue: 0.99)
            : (isActive ? Color(red: 0.88, green: 0.93, blue: 1.0) : Color.white)
        configuration.label
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
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(shape)
    }
}

private struct ScoreReaderDrumPadCell: View {
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
        Text(pad.name)
            .font(.system(size: isTall ? 13 : 11.5, weight: .medium))
            .lineLimit(2)
            .allowsTightening(true)
            .minimumScaleFactor(0.8)
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

    var body: some View {
        Canvas { context, size in
            let lineGap = size.height / 7
            let staffTop = size.height / 2 - 2 * lineGap
            let lineColor = GraphicsContext.Shading.color(.black.opacity(0.24))
            for index in 0..<5 {
                let y = staffTop + CGFloat(index) * lineGap
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: lineColor, lineWidth: 0.6)
            }

            // Drum-set lines count half spaces down from the top line; clamp to the glyph.
            let clampedLine = min(max(CGFloat(pad.line), -3), 11)
            let center = CGPoint(x: size.width / 2, y: staffTop + clampedLine * lineGap / 2)
            let headWidth = lineGap * 1.5
            let headHeight = lineGap * 1.05
            let ink = GraphicsContext.Shading.style(.foreground)

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
                context.stroke(ledgers, with: lineColor, lineWidth: 0.8)
            }

            let headRect = CGRect(
                x: center.x - headWidth / 2,
                y: center.y - headHeight / 2,
                width: headWidth,
                height: headHeight
            )
            switch pad.notehead {
            case .cross:
                context.stroke(crossPath(in: headRect.insetBy(dx: 0, dy: -0.5)), with: ink, lineWidth: 1.6)
            case .circleCross:
                context.stroke(Path(ellipseIn: headRect.insetBy(dx: -1, dy: -1)), with: ink, lineWidth: 1)
                context.stroke(crossPath(in: headRect.insetBy(dx: 1, dy: 1)), with: ink, lineWidth: 1)
            case .diamond:
                context.fill(diamondPath(in: headRect), with: ink)
            case .triangle:
                var triangle = Path()
                triangle.move(to: CGPoint(x: headRect.midX, y: headRect.minY - 1))
                triangle.addLine(to: CGPoint(x: headRect.maxX, y: headRect.maxY))
                triangle.addLine(to: CGPoint(x: headRect.minX, y: headRect.maxY))
                triangle.closeSubpath()
                context.fill(triangle, with: ink)
            case .slash:
                var slash = Path()
                slash.move(to: CGPoint(x: headRect.minX, y: headRect.maxY))
                slash.addLine(to: CGPoint(x: headRect.maxX, y: headRect.minY))
                context.stroke(slash, with: ink, lineWidth: 2.2)
            case .normal, .other:
                var head = context
                head.translateBy(x: center.x, y: center.y)
                head.rotate(by: .degrees(-20))
                head.fill(
                    Path(ellipseIn: CGRect(x: -headWidth / 2, y: -headHeight / 2, width: headWidth, height: headHeight)),
                    with: ink
                )
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
            context.stroke(stem, with: ink, lineWidth: 1.1)
        }
        .accessibilityHidden(true)
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
