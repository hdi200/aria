// Android stand-ins for iOS pieces that are not ported yet, so the shared views build and
// run. Each says what is missing; replace it with a real port (see README).

// Not limited to Android: the Skip project's own iOS build (a build step only; the iOS
// app is MuseReaderiOS/Aria.xcodeproj) compiles it in place of the held-back iOS file.
import Foundation
import SwiftUI

/// iOS: Views/UpdateNoticeLoopingVideo.swift (AVPlayerLooper). Not ported: the update
/// notice clips show iOS screens, so Android shows no clip.
struct UpdateNoticeLoopingVideo: View {
    let url: URL

    var body: some View {
        Color.clear
    }
}

/// iOS: MuseReaderiOSApp.swift. The orientation lock the reader asks for.
enum MuseReaderAppDelegate {
    static func updateSupportedInterfaceOrientations(_ orientations: UIInterfaceOrientationMask) {
        #if os(Android)
        ariaRequestOrientations(orientations)
        #endif
    }
}
