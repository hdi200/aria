//
//  CompatibilityViewModifiers.swift
//  MuseReaderiOS
//
//

import SwiftUI

extension View {
    @ViewBuilder
    func onChangeCompatible<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value, perform: action)
        }
    }

    @ViewBuilder
    func onChangeCompatible<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value, Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            onChange(of: value) { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            modifier(OldNewOnChangeCompatibilityModifier(value: value, action: action))
        }
    }

    @ViewBuilder
    func presentationCompactPopoverWhenAvailable() -> some View {
        #if os(Android)
        // Android has no compact popover: a sheet sized to the content (AndroidSwiftUIShims).
        modifier(AndroidCompactPopoverSizing())
        #else
        if #available(iOS 16.4, *) {
            presentationCompactAdaptation(.popover)
        } else {
            self
        }
        #endif
    }

    @ViewBuilder
    func presentationCompactPopoverWhenAvailable(_ enabled: Bool) -> some View {
        if enabled {
            presentationCompactPopoverWhenAvailable()
        } else {
            self
        }
    }

    @ViewBuilder
    func clearPresentationBackgroundWhenAvailable() -> some View {
        #if os(Android)
        // Not available on Android (Skip); keeps the default sheet background.
        self
        #else
        if #available(iOS 16.4, *) {
            presentationBackground(.clear)
        } else {
            self
        }
        #endif
    }
}

struct OldNewOnChangeCompatibilityModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (Value, Value) -> Void

    @State var previousValue: Value?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if previousValue == nil {
                    previousValue = value
                }
            }
            .onChange(of: value) { newValue in
                let oldValue = previousValue ?? newValue
                previousValue = newValue
                action(oldValue, newValue)
            }
    }
}

extension View {
    /// Tells VoiceOver whether this control is the selected one.
    @ViewBuilder
    func accessibilitySelected(_ isSelected: Bool) -> some View {
        #if os(Android)
        // Skip's empty AccessibilityTraits (`[]`) recurses until the stack overflows, so the
        // trait is only added when it applies.
        if isSelected {
            accessibilityAddTraits(.isSelected)
        } else {
            self
        }
        #else
        accessibilityAddTraits(isSelected ? .isSelected : [])
        #endif
    }
}

/// A button style whose look is modifiers around the label. Android's SwiftUI (Skip) runs
/// only its built-in styles, so there the same look goes around a plain button.
protocol AriaLabelButtonStyle: ButtonStyle {
    associatedtype StyledLabel: View
    @ViewBuilder func styled(_ label: AnyView, isPressed: Bool) -> StyledLabel
}

extension AriaLabelButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        styled(AnyView(configuration.label), isPressed: configuration.isPressed)
    }
}

#if !os(Android)
extension View {
    /// A row the user drags to reorder its list, with `onDrop` delegates on the rows. iOS
    /// drags the whole row after a long press; Android drags it by the grip at its
    /// leading edge (AndroidSwiftUIShims.swift), so the list still scrolls.
    func onReorderDrag(_ data: @escaping () -> NSItemProvider) -> some View {
        onDrag(data)
    }
}
#endif

extension View {
    /// The card a popover panel sits on: iOS shows these panels as popovers. Android shows
    /// them as bottom sheets, which have their own surface, so there the panel fills the
    /// sheet's width with no card.
    @ViewBuilder
    func popoverPanelCard(width: CGFloat, maxHeight: CGFloat, alignment: Alignment = .center,
                          cornerRadius: CGFloat, stroke: Color, shadowOpacity: Double, shadowY: CGFloat) -> some View {
        #if os(Android)
        frame(maxWidth: .infinity, alignment: .top)
        #else
        frame(width: width)
            .frame(maxHeight: maxHeight, alignment: alignment)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 28, y: shadowY)
        #endif
    }

    /// Marks all of a popover panel's content inside its scroll view, so Android can size
    /// the panel's sheet to it (a scroll view itself takes whatever height it is given).
    @ViewBuilder
    func popoverPanelScrollContent() -> some View {
        #if os(Android)
        modifier(AndroidPopoverContentMeasure())
        #else
        self
        #endif
    }
}
