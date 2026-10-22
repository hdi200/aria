// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE

public enum Visibility : Int, Hashable, CaseIterable {
    case automatic = 0 // For bridging
    case visible = 1 // For bridging
    case hidden = 2 // For bridging
}

#endif
