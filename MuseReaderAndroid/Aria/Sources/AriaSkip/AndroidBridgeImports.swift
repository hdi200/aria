// The iOS app sees its bridge classes (MSRRenderSession, MuseScorePackageBridge, ...)
// through its bridging header; here they come from AriaEngine, exported to the whole
// module so shared iOS files need no import.
@_exported import AriaEngine

#if os(Android)
// On iOS, SwiftUI brings UIKit with it; shared files that use UIDevice and friends
// without importing UIKit rely on that.
@_exported import UIKit
// Skip's Observation bridge: the @Observable macro registers through a type named
// Observation, and SkipFuse's (which also tells Compose to redraw) only wins over Apple's
// Observation module where SkipFuse is imported. Shared iOS files import Observation.
@_exported import SkipFuse
#endif

#if os(Android)
/// Starts the render engine (Qt thread, stdout to the Android log). Safe to call again.
nonisolated func aria_startEngineInBackground() {
    MuseScoreRenderCoreBridge.initializeRenderRuntimeIfNeeded()
}
#endif
