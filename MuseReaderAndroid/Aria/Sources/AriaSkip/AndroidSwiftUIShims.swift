import SkipFuse
import SwiftUI
import UniformTypeIdentifiers

// SwiftUI APIs the iOS code uses that Skip's Android SwiftUI doesn't provide yet, so the
// iOS view files compile unchanged. Each one notes what Android does instead.
#if os(Android)
extension View {
    /// Android hit-tests a view's whole frame already, which is what the iOS code uses
    /// `contentShape(Rectangle())` for. Other shapes fall back to the frame.
    func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View {
        self
    }
}

// Drag and drop: iOS uses it to reorder instruments and parts, to move scores into
// setlists, and to drop files onto the library. Skip doesn't bridge it, so reordering
// (onReorderDrag + onDrop delegates) runs on an in-app drag session here: the row is
// dragged by its grip, and the delegates are called as the finger crosses the rows.
// Scores are dragged onto setlists on the same session (a sideways drag on a score, with
// a chip under the finger). Dropping files from other apps isn't available.

final class NSItemProvider {
    var suggestedName: String?
    let text: String?

    init(object: NSString) {
        text = String(object)
    }

    func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
        text != nil && typeIdentifier == UTType.plainText.identifier
    }

    @discardableResult
    func loadFileRepresentation(forTypeIdentifier typeIdentifier: String,
                                completionHandler: @escaping @Sendable (URL?, Error?) -> Void) -> Progress {
        completionHandler(nil, nil)
        return Progress(totalUnitCount: 0)
    }

    @discardableResult
    func loadItem(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]? = nil,
                  completionHandler: (@Sendable (Any?, Error?) -> Void)? = nil) -> Progress {
        completionHandler?(text?.data(using: .utf8), nil)
        return Progress(totalUnitCount: 1)
    }
}

enum DropOperation: Sendable {
    case cancel, forbidden, copy, move
}

struct DropProposal: Sendable {
    let operation: DropOperation

    init(operation: DropOperation) {
        self.operation = operation
    }
}

struct DropInfo {
    let location: CGPoint
    var provider: NSItemProvider? = nil

    func hasItemsConforming(to contentTypes: [UTType]) -> Bool { provider != nil }
    func itemProviders(for contentTypes: [UTType]) -> [NSItemProvider] { provider.map { [$0] } ?? [] }
}

protocol DropDelegate {
    func validateDrop(info: DropInfo) -> Bool
    func dropEntered(info: DropInfo)
    func dropUpdated(info: DropInfo) -> DropProposal?
    func dropExited(info: DropInfo)
    func performDrop(info: DropInfo) -> Bool
}

extension DropDelegate {
    func validateDrop(info: DropInfo) -> Bool { true }
    func dropEntered(info: DropInfo) {}
    func dropUpdated(info: DropInfo) -> DropProposal? { nil }
    func dropExited(info: DropInfo) {}
}

/// The drag in progress and the drop targets on screen, in global coordinates.
@Observable
final class AndroidDragSession {
    static let shared = AndroidDragSession()

    private struct Target {
        var frame: CGRect
        var delegate: any DropDelegate
    }

    @ObservationIgnored private var targets: [UUID: Target] = [:]
    @ObservationIgnored private var provider: NSItemProvider?
    @ObservationIgnored private var current: UUID?
    /// Where to draw the dragged item's chip (AndroidDragPreviewLayer); nil when there is none.
    var previewLocation: CGPoint?
    @ObservationIgnored private var showsPreview = false

    var isDragging: Bool { provider != nil }

    func register(_ id: UUID, frame: CGRect, delegate: any DropDelegate) {
        targets[id] = Target(frame: frame, delegate: delegate)
    }

    func unregister(_ id: UUID) {
        targets[id] = nil
        if current == id { current = nil }
    }

    func begin(_ provider: NSItemProvider, showsPreview: Bool = false) {
        self.provider = provider
        self.showsPreview = showsPreview
        current = nil
    }

    func move(to location: CGPoint) {
        guard provider != nil else { return }
        if showsPreview {
            previewLocation = location
        }
        let info = DropInfo(location: location, provider: provider)
        let hit = targets.first { $0.value.frame.contains(location) }?.key
        if hit != current {
            if let current, let target = targets[current] { target.delegate.dropExited(info: info) }
            current = hit
            if let hit, let target = targets[hit], target.delegate.validateDrop(info: info) {
                target.delegate.dropEntered(info: info)
            }
        } else if let hit, let target = targets[hit] {
            _ = target.delegate.dropUpdated(info: info)
        }
    }

    func end(at location: CGPoint) {
        move(to: location)
        let info = DropInfo(location: location, provider: provider)
        if let current, let target = targets[current] {
            _ = target.delegate.performDrop(info: info)
        }
        provider = nil
        current = nil
        showsPreview = false
        previewLocation = nil
    }
}

/// Drags an item (a score) to drop targets. A sideways drag starts it: inside a vertical
/// scroll view Skip's drag gesture only claims sideways moves, so vertical drags still
/// scroll. On a tablet the setlists are in the sidebar beside the scores.
struct AndroidItemDrag: ViewModifier {
    let data: () -> NSItemProvider

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .global)
                    .onChanged { value in
                        let session = AndroidDragSession.shared
                        if !session.isDragging {
                            session.begin(data(), showsPreview: true)
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        session.move(to: value.location)
                    }
                    .onEnded { value in
                        AndroidDragSession.shared.end(at: value.location)
                    }
            )
    }
}

/// The chip under the finger while a score is dragged. Placed over the screen that holds
/// the drag's source and targets (the library).
struct AndroidDragPreviewLayer: View {
    var body: some View {
        GeometryReader { proxy in
            if let location = AndroidDragSession.shared.previewLocation {
                let origin = proxy.frame(in: .global).origin
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Score")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color(red: 0.12, green: 0.45, blue: 0.95), in: Capsule())
                .shadow(color: Color.black.opacity(0.2), radius: 8, y: 3)
                .position(x: location.x - origin.x, y: location.y - origin.y - 28)
            }
        }
        .allowsHitTesting(false)
    }
}

/// onDrop(of:isTargeted:perform:) as a drag-session target.
struct AndroidClosureDropDelegate: DropDelegate {
    let isTargeted: Binding<Bool>?
    let action: ([NSItemProvider]) -> Bool

    func dropEntered(info: DropInfo) {
        isTargeted?.wrappedValue = true
    }

    func dropExited(info: DropInfo) {
        isTargeted?.wrappedValue = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted?.wrappedValue = false
        return action(info.itemProviders(for: []))
    }
}

/// Drags the row by a strip over its leading grip. The strip takes its touches at once,
/// so the rest of the row still scrolls the list and takes taps. The rows move under the
/// finger as the delegates reorder them. (No per-row state: Skip's ForEach moves it with
/// the rows' positions.)
struct AndroidReorderDrag: ViewModifier {
    let data: () -> NSItemProvider

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: 52)
                    .frame(maxHeight: .infinity)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                let session = AndroidDragSession.shared
                                if !session.isDragging {
                                    session.begin(data())
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                                session.move(to: value.location)
                            }
                            .onEnded { value in
                                AndroidDragSession.shared.end(at: value.location)
                            }
                    )
            }
    }
}

/// A drop target: its global frame is kept current for the drag session.
struct AndroidDropTarget: ViewModifier {
    let delegate: any DropDelegate
    @State var id = UUID()

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            AndroidDragSession.shared.register(id, frame: proxy.frame(in: .global), delegate: delegate)
                        }
                        .onChange(of: proxy.frame(in: .global)) { _, frame in
                            AndroidDragSession.shared.register(id, frame: frame, delegate: delegate)
                        }
                }
            )
            .onDisappear { AndroidDragSession.shared.unregister(id) }
    }
}

extension View {
    func onReorderDrag(_ data: @escaping () -> NSItemProvider) -> some View {
        modifier(AndroidReorderDrag(data: data))
    }

    /// Scores dragged onto setlists.
    func onDrag(_ data: @escaping () -> NSItemProvider) -> some View {
        modifier(AndroidItemDrag(data: data))
    }

    func onDrop(of supportedContentTypes: [UTType], delegate: any DropDelegate) -> some View {
        modifier(AndroidDropTarget(delegate: delegate))
    }

    /// In-app drags carry text (a score's setlist key): only text targets take part. Files
    /// from other apps can't be dropped.
    @ViewBuilder
    func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?,
                perform action: @escaping ([NSItemProvider]) -> Bool) -> some View {
        if supportedContentTypes.contains(.plainText) {
            modifier(AndroidDropTarget(delegate: AndroidClosureDropDelegate(isTargeted: isTargeted, action: action)))
        } else {
            self
        }
    }
}

// MARK: - Modifiers Skip lacks or marks unavailable

/// Popovers show as sheets on Android (as compact popovers do on iPhone).
enum PopoverAttachmentAnchor {
    enum Source {
        case bounds
        case rect(CGRect)
    }

    case rect(Source)
    case point(UnitPoint)
}

extension View {
    func popover<Content: View>(isPresented: Binding<Bool>,
                                attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                arrowEdge: Edge? = nil,
                                @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, content: content)
    }

    func popover<Item: Identifiable, Content: View>(item: Binding<Item?>,
                                                     attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                                     arrowEdge: Edge? = nil,
                                                     @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, content: content)
    }

    /// Liquid Glass is iOS 26 only. Android draws a frosted fill in its place, so what is
    /// behind (the score, under the reader's floating bars) doesn't show through the text.
    func glassEffect<S: Shape>(_ glass: Glass = .regular, in shape: S, isEnabled: Bool = true) -> some View {
        background(Color.white.opacity(isEnabled ? 0.9 : 0), in: shape)
    }

    /// Compose sizes controls itself.
    func controlSize(_ controlSize: ControlSize) -> some View {
        self
    }

    func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View {
        self
    }

    func accessibilityLabel(_ label: String) -> some View {
        accessibilityLabel(Text(label))
    }

    /// Skip has no accessibility hints; TalkBack reads the label.
    func accessibilityHint(_ hint: String) -> some View {
        self
    }

    func accessibilityValue(_ value: String) -> some View {
        accessibilityValue(Text(value))
    }

    /// Skip ignores baseline offsets; a vertical offset raises the glyph the same way.
    func baselineOffset(_ baselineOffset: CGFloat) -> some View {
        offset(y: -baselineOffset)
    }

    /// Named coordinate spaces: positions are read in the global space instead.
    func coordinateSpace(name: some Hashable) -> some View {
        self
    }

    /// Places the inset content above or below the view instead of over its safe area.
    func safeAreaInset<V: View>(edge: VerticalEdge, alignment: HorizontalAlignment = .center,
                                spacing: CGFloat? = nil, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: alignment, spacing: spacing ?? 0) {
            if edge == .top {
                content()
            }
            self
            if edge == .bottom {
                content()
            }
        }
    }
}

extension PresentationBackgroundInteraction {
    /// Android sheets don't let the view behind take touches.
    static var enabled: PresentationBackgroundInteraction {
        .automatic
    }
}

extension Text {
    func baselineOffset(_ baselineOffset: CGFloat) -> Text {
        self
    }

    func monospacedDigit() -> Text {
        self
    }
}

extension View {
    func monospacedDigit() -> some View {
        self
    }
}

extension ListStyle where Self == InsetGroupedListStyle {
    static var insetGrouped: InsetGroupedListStyle { InsetGroupedListStyle() }
}

/// iOS's inset grouped list is Android's default grouped list.
typealias InsetGroupedListStyle = PlainListStyle

// MARK: - More modifiers and views

/// The list edit state (reordering in setlists). Skip's lists reorder with onMove.
enum EditMode: Sendable {
    case inactive, transient, active

    var isEditing: Bool { self != .inactive }
}

struct AndroidEditModeKey: EnvironmentKey {
    static let defaultValue: Binding<EditMode>? = nil
}

extension EnvironmentValues {
    var editMode: Binding<EditMode>? {
        get { self[AndroidEditModeKey.self] }
        set { self[AndroidEditModeKey.self] = newValue }
    }
}

extension SearchFieldPlacement {
    enum NavigationBarDrawerDisplayMode: Sendable {
        case automatic, always
    }

    static func navigationBarDrawer(displayMode: NavigationBarDrawerDisplayMode) -> SearchFieldPlacement {
        .automatic
    }
}

/// iOS 17's empty-state view.
struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    let label: Label
    let description: Description
    let actions: Actions

    init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description = { EmptyView() },
         @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            label
                .font(.title2.weight(.semibold))
            description
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text, Actions == EmptyView {
    init(_ title: String, systemImage name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, systemImage: name) }, description: { description ?? Text("") })
    }

    static func search(text: String) -> ContentUnavailableView<SwiftUI.Label<Text, Image>, Text, EmptyView> {
        ContentUnavailableView("No Results for “\(text)”", systemImage: "magnifyingglass",
                               description: Text("Check the spelling or try a new search."))
    }

    static var search: ContentUnavailableView<SwiftUI.Label<Text, Image>, Text, EmptyView> {
        ContentUnavailableView("No Results", systemImage: "magnifyingglass",
                               description: Text("Check the spelling or try a new search."))
    }
}

/// The pre-iOS 15 alert value, shown through the shared code's alert(item:content:).
struct Alert {
    let title: Text
    let message: Text?

    init(title: Text, message: Text? = nil, dismissButton: Any? = nil) {
        self.title = title
        self.message = message
    }
}

extension View {
    func alert<Item: Identifiable>(item: Binding<Item?>, content: @escaping (Item) -> Alert) -> some View {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )
        let alert = item.wrappedValue.map(content)
        return self.alert(alert?.title ?? Text(""), isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            alert?.message ?? Text("")
        }
    }

    func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> some View {
        self
    }

    func layoutPriority(_ value: Double) -> some View {
        self
    }

    func highPriorityGesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View {
        self.gesture(gesture)
    }

    func truncationMode(_ mode: Text.TruncationMode) -> some View {
        self
    }

    func glassEffect(_ glass: Glass = .regular) -> some View {
        background(Color.white.opacity(0.9), in: Capsule())
    }
}

extension Glass {
    func interactive(_ isEnabled: Bool = true) -> Glass {
        self
    }
}

// MARK: - Layout and accessibility

/// The measured size of a view, for alignment guides.
struct ViewDimensions {
    let width: CGFloat
    let height: CGFloat

    subscript(guide: HorizontalAlignment) -> CGFloat { 0 }
    subscript(guide: VerticalAlignment) -> CGFloat { 0 }
}

enum AccessibilityAdjustmentDirection: Sendable {
    case increment, decrement
}

extension View {
    /// Skip has no adjustable actions; sliders adjust with TalkBack's own gestures.
    func accessibilityAdjustableAction(_ handler: @escaping (AccessibilityAdjustmentDirection) -> Void) -> some View {
        self
    }

    /// Custom alignment guides aren't bridged; views keep their default alignment.
    func alignmentGuide(_ g: HorizontalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
        self
    }

    func alignmentGuide(_ g: VerticalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
        self
    }

    func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View {
        self
    }

    func contentTransition(_ transition: ContentTransition) -> some View {
        self
    }

    func gridCellColumns(_ count: Int) -> some View {
        self
    }
}

extension View {
    /// Skip only applies its built-in button styles. Other custom styles show as plain
    /// buttons.
    func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        ariaSkipPlainButtonStyle()
    }

    /// Aria's own styles (export footer, transpose panel, video sheet) put their look
    /// around the label; here it goes around the plain button, which is only its label.
    /// Android shows no pressed state for them.
    func buttonStyle<S: AriaLabelButtonStyle>(_ style: S) -> some View {
        style.styled(AnyView(ariaSkipPlainButtonStyle()), isPressed: false)
    }
}

/// iOS's third and fourth label levels, which Skip doesn't have.
extension ShapeStyle where Self == Color {
    static var tertiary: Color { Color(UIColor.tertiaryLabel) }
    static var quaternary: Color { Color(UIColor.quaternaryLabel) }
}

// Skip's Color.opacity and ShapeStyle.opacity tie where Apple's SwiftUI prefers the Color
// one; concrete Color overloads settle it (and pass the color on to Skip's own modifier).
extension InsettableShape {
    func strokeBorder(_ content: Color, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View {
        androidStrokeBorder(content, lineWidth: lineWidth, antialiased: antialiased)
    }

    private func androidStrokeBorder<S: ShapeStyle>(_ content: S, lineWidth: CGFloat, antialiased: Bool) -> some View {
        strokeBorder(content, lineWidth: lineWidth, antialiased: antialiased)
    }
}

extension View {
    /// The same tie for a Color background in an insettable shape (Skip has a Shape and
    /// an InsettableShape version, which some expressions can't choose between).
    func background<T: InsettableShape>(_ color: Color, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
        androidBackground(color, in: shape, fillStyle: fillStyle)
    }

    private func androidBackground<S: ShapeStyle, T: InsettableShape>(_ style: S, in shape: T, fillStyle: FillStyle) -> some View {
        background(style, in: shape, fillStyle: fillStyle)
    }
}

extension View {
    /// Android sheets keep their own surface and corners.
    func presentationBackground<S: ShapeStyle>(_ style: S) -> some View {
        self
    }

    func presentationCornerRadius(_ cornerRadius: CGFloat?) -> some View {
        self
    }
}

/// Materials: iOS blurs what is behind them, so even a "translucent" one reads as nearly
/// solid. Skip draws them as the background color at 30-80% opacity with no blur, which
/// shows the score through panels (the tablet mixer). Without a blur, an opaque fill is
/// the closer match; only the thin materials stay slightly see-through.
enum AndroidMaterialFill {
    static func color(_ material: Material) -> Color {
        let opacity: Double
        switch material {
        case .ultraThin: opacity = 0.96
        case .thin: opacity = 0.97
        default: opacity = 1
        }
        return Color(uiColor: .systemBackground).opacity(opacity)
    }
}

extension View {
    /// Skip doesn't extend backgrounds into the safe area by default (iOS's `.all`); pass
    /// the edges explicitly where a bar should reach the screen edge.
    func background(_ material: Material, ignoresSafeAreaEdges edges: Edge.Set = []) -> some View {
        background(AndroidMaterialFill.color(material), ignoresSafeAreaEdges: edges)
    }

    func background<T: InsettableShape>(_ material: Material, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
        background(AndroidMaterialFill.color(material), in: shape, fillStyle: fillStyle)
    }
}

/// Skip opens a sheet at one detent, the first of the Set it is given (in no particular
/// order), so `[.height(285), .large]` could open full screen. iOS opens at the smallest;
/// so does this. (An Array parameter: array literals prefer it to Skip's Set version.)
extension View {
    func presentationDetents(_ detents: [PresentationDetent]) -> some View {
        ariaSkipPresentationDetents(AndroidPresentationDetents.smallest(Set(detents)).map { [$0] } ?? Set(detents))
    }
}

enum AndroidPresentationDetents {
    /// Skip keeps a detent's kind and value private; they are read by reflection.
    static func height(of detent: PresentationDetent) -> CGFloat {
        let mirror = Mirror(reflecting: detent)
        let kind = mirror.descendant("identifier") as? Int ?? 1
        let value = mirror.descendant("value") as? CGFloat ?? 0
        let screen = UIScreen.main.bounds.height
        switch kind {
        case 0: return screen / 2
        case 2: return screen * value
        case 3: return value
        default: return screen
        }
    }

    static func smallest(_ detents: Set<PresentationDetent>) -> PresentationDetent? {
        detents.min { height(of: $0) < height(of: $1) }
    }
}

/// iPhone shows Aria's small panels (export, parts, metronome settings) as compact
/// popovers; Android shows them as bottom sheets just tall enough for their content.
/// A panel whose content scrolls reports its content's natural height
/// (popoverPanelScrollContent); otherwise the sheet's content is measured as laid out.
struct AndroidCompactPopoverSizing: ViewModifier {
    @State var measuredHeight: CGFloat = 0
    let store = AndroidPopoverSizingStore.shared

    private var detent: PresentationDetent {
        let height = store.contentHeight > 0 ? store.contentHeight + store.footerHeight : measuredHeight
        guard height > 0 else { return .medium }
        return .height(min(height.rounded(.up), UIScreen.main.bounds.height * 0.88))
    }

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { measuredHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, newHeight in
                            if abs(newHeight - measuredHeight) > 1 { measuredHeight = newHeight }
                        }
                }
            )
            .ariaSkipPresentationDetents([detent])
            .onDisappear {
                store.contentHeight = 0
                store.footerHeight = 0
            }
    }
}

/// The natural height of the open panel's scrolling content.
@Observable
final class AndroidPopoverSizingStore {
    static let shared = AndroidPopoverSizingStore()
    var contentHeight: CGFloat = 0
    /// A footer below the scrolling content (popoverPanelFixedFooter).
    var footerHeight: CGFloat = 0
}

struct AndroidPopoverFooterMeasure: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { AndroidPopoverSizingStore.shared.footerHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newHeight in
                        if abs(newHeight - AndroidPopoverSizingStore.shared.footerHeight) > 1 {
                            AndroidPopoverSizingStore.shared.footerHeight = newHeight
                        }
                    }
            }
        )
    }
}

struct AndroidPopoverContentMeasure: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { AndroidPopoverSizingStore.shared.contentHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newHeight in
                        if abs(newHeight - AndroidPopoverSizingStore.shared.contentHeight) > 1 {
                            AndroidPopoverSizingStore.shared.contentHeight = newHeight
                        }
                    }
            }
        )
    }
}

extension Font {
    func monospacedDigit() -> Font {
        self
    }
}

extension Alignment {
    /// Skip's Alignment has no public memberwise initializer.
    init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        switch (horizontal, vertical) {
        case (.leading, .top): self = .topLeading
        case (.trailing, .top): self = .topTrailing
        case (_, .top): self = .top
        case (.leading, .bottom): self = .bottomLeading
        case (.trailing, .bottom): self = .bottomTrailing
        case (_, .bottom): self = .bottom
        case (.leading, _): self = .leading
        case (.trailing, _): self = .trailing
        default: self = .center
        }
    }
}

/// SwiftUI's Grid as rows of HStacks: columns line up when cells share a width, as in
/// Aria's keypads.
struct Grid<Content: View>: View {
    let alignment: Alignment
    let horizontalSpacing: CGFloat?
    let verticalSpacing: CGFloat?
    let content: Content

    init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil,
         @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    var body: some View {
        VStack(spacing: verticalSpacing) {
            content
        }
        .environment(\.androidGridHorizontalSpacing, horizontalSpacing)
    }
}

struct GridRow<Content: View>: View {
    let alignment: VerticalAlignment
    let content: Content
    @Environment(\.androidGridHorizontalSpacing) var spacing

    init(alignment: VerticalAlignment = .center, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: spacing) {
            content
        }
    }
}

struct AndroidGridSpacingKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var androidGridHorizontalSpacing: CGFloat? {
        get { self[AndroidGridSpacingKey.self] }
        set { self[AndroidGridSpacingKey.self] = newValue }
    }
}

/// Xcode previews; nothing on Android shows them.
protocol PreviewProvider {
    associatedtype Previews: View
    @MainActor static var previews: Previews { get }
}
#endif

/// Runs `action` on the system Back gesture while `isEnabled`, for panels that aren't
/// presentations (iOS has no Back gesture; shared code calls this under os(Android)).
struct AndroidBackAction: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        #if os(Android)
        content
            .background {
                if isEnabled, let capture = try? AnyDynamicObject(className: "aria.skip.AriaBackCapture") {
                    ComposeView { capture }
                }
            }
            .task(id: isEnabled) {
                guard isEnabled, let back = try? AnyDynamicObject(className: "aria.skip.AriaBack") else { return }
                let _: Int = (try? back.takePresses()) ?? 0
                while !Task.isCancelled {
                    let presses: Int = (try? back.takePresses()) ?? 0
                    if presses > 0 {
                        action()
                    }
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
        #else
        content
        #endif
    }
}

extension View {
    func androidBackAction(isEnabled: Bool, perform action: @escaping () -> Void) -> some View {
        modifier(AndroidBackAction(isEnabled: isEnabled, action: action))
    }
}

/// A counter a view reads so that bumping it redraws the view: for views whose own state
/// changes from a gesture didn't redraw them on Android (the note-entry piano keyboard).
@Observable
final class AndroidRedrawTrigger {
    static let pitchKeyboard = AndroidRedrawTrigger()
    var count = 0
}
