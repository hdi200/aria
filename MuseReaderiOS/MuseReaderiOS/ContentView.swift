//
//  ContentView.swift
//  MuseReaderiOS
//
//  Created by Jack Gruber on 4/13/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appModel = MuseReaderAppModel()

    var body: some View {
        LibraryView(model: appModel)
            .onOpenURL { url in
                appModel.handleOpenURL(url)
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
