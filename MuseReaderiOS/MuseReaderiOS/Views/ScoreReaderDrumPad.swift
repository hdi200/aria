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
    let action: (Int) -> Void

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
                                action: action
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

/// One pad. It tracks its own touch instead of being a Button: Buttons inside a horizontal
/// ScrollView delay and sometimes drop quick taps, and drummers tap fast. A touch that moves
/// is left to the scroll view, so the strip still scrolls.
private struct ScoreReaderDrumPadKey: View {
    let pad: ScoreDrumPad
    let isActive: Bool
    let isTall: Bool
    let showsShortcut: Bool
    let glyphHeight: CGFloat
    let action: (Int) -> Void

    @GestureState private var isPressed = false
    private let tapSlop: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        ScoreReaderDrumPadCell(
            pad: pad,
            isActive: isActive,
            isTall: isTall,
            showsShortcut: showsShortcut,
            glyphHeight: glyphHeight
        )
        .background { shape.fill(fill) }
        .overlay {
            shape.strokeBorder(
                isActive ? Color.accentColor.opacity(0.85) : Color.black.opacity(0.1),
                lineWidth: isActive ? 1.5 : 0.75
            )
        }
        .scaleEffect(isPressed ? 0.95 : 1)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .contentShape(shape)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($isPressed) { value, pressed, _ in
                    pressed = isTap(value.translation)
                }
                .onEnded { value in
                    if isTap(value.translation) {
                        action(pad.pitch)
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pad.name)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action(pad.pitch) }
    }

    private func isTap(_ translation: CGSize) -> Bool {
        abs(translation.width) < tapSlop && abs(translation.height) < tapSlop
    }

    private var fill: Color {
        if isPressed {
            return Color(red: 0.80, green: 0.87, blue: 0.99)
        }
        return isActive ? Color(red: 0.88, green: 0.93, blue: 1.0) : Color.white
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
