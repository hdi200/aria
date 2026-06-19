//
//  ContentView.swift
//  MuseReaderiOS
//
//  Created by Jack Gruber on 4/13/26.
//

import SwiftUI
import StoreKit

struct ContentView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appModel = MuseReaderAppModel()
    @State private var reviewRequestTracker = ReviewRequestTracker()

    var body: some View {
        LibraryView(model: appModel)
            .onOpenURL { url in
                appModel.handleOpenURL(url)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active,
                      reviewRequestTracker.shouldRequestReviewAfterAppOpen()
                else {
                    return
                }

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    requestReview()
                }
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
