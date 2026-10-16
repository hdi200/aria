//
//  AppResources.swift
//  MuseReaderiOS
//

import Foundation

/// Files bundled with the app (sound font, score templates, fonts). On Android they stay in
/// the APK and each is copied to app storage the first time it is asked for, because the
/// engine and FileManager need real file paths.
enum AppResources {
    nonisolated static func url(forResource name: String, withExtension ext: String?, subdirectory: String? = nil) -> URL? {
        #if os(Android)
        return AndroidResourceFiles.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
        #else
        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
        #endif
    }
}
