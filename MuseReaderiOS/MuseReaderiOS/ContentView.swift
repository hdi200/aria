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
            .onChangeCompatible(of: scenePhase) { phase in
                guard phase == .active else {
                    return
                }

                reviewRequestTracker.recordActiveSession()
            }
            .onChangeCompatible(of: appModel.currentSession?.id) { _ in
                guard appModel.currentSession != nil else {
                    return
                }

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard appModel.currentSession != nil,
                          !appModel.isLoading,
                          !appModel.isImportingPresented,
                          !appModel.isCreateScorePresented,
                          appModel.errorAlert == nil,
                          reviewRequestTracker.shouldRequestReviewAfterSuccessfulScoreOpen()
                    else {
                        return
                    }

                    requestReview()
                }
            }
            .onChangeCompatible(of: appModel.errorAlert?.id) { _ in
                guard appModel.errorAlert != nil else {
                    return
                }

                reviewRequestTracker.recordFrictionEvent()
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
