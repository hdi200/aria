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
        if #available(iOS 16.4, *) {
            presentationCompactAdaptation(.popover)
        } else {
            self
        }
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
        if #available(iOS 16.4, *) {
            presentationBackground(.clear)
        } else {
            self
        }
    }
}

private struct OldNewOnChangeCompatibilityModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (Value, Value) -> Void

    @State private var previousValue: Value?

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
