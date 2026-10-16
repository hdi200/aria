//
//  OwnedState.swift
//  MuseReaderiOS
//

import Observation
import SwiftUI

/// A view's own @Observable object, created once like @StateObject.
///
/// `@State` with an @Observable class evaluates the initial value every time the view is
/// recreated (SwiftUI keeps the first object and discards the others), which would run
/// initializers with side effects again. This keeps the creation closure and calls it
/// only the first time the kept storage is read. `$name.property` gives bindings, as
/// with @Bindable.
@MainActor
@propertyWrapper
struct OwnedState<Value: AnyObject & Observable>: DynamicProperty {
    private final class Storage {
        var value: Value?
    }

    @State private var storage = Storage()
    private let makeValue: () -> Value

    init(wrappedValue: @autoclosure @escaping () -> Value) {
        makeValue = wrappedValue
    }

    var wrappedValue: Value {
        if let value = storage.value {
            return value
        }
        let value = makeValue()
        storage.value = value
        return value
    }

    var projectedValue: Bindable<Value> {
        Bindable(wrappedValue)
    }
}
