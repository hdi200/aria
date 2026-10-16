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
        // Android presents these as bottom sheets; there is no compact popover.
        self
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
