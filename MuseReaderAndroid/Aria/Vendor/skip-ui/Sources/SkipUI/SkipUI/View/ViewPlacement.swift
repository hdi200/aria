// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if SKIP

/// Allow views to specialize based on their placement.
struct ViewPlacement: RawRepresentable, OptionSet {
    let rawValue: Int

    static let listItem = ViewPlacement(rawValue: 1)
    static let systemTextColor = ViewPlacement(rawValue: 2)
    static let onPrimaryColor = ViewPlacement(rawValue: 4)
    static let toolbar = ViewPlacement(rawValue: 8)
}

#endif
