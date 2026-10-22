// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
#if !SKIP
#if canImport(CoreGraphics)
import struct CoreGraphics.CGPoint
#endif
#endif

public enum HoverPhase : Equatable {
    case active(CGPoint)
    case ended
}

#endif
