// Android side of AppResources (App/AppResources.swift in the iOS app): the iOS app's
// bundled files, copied out of the APK by AriaAssets.kt.

#if os(Android)
import Foundation
import SkipFuse

enum AndroidResourceFiles {
    nonisolated static func url(forResource name: String, withExtension ext: String?, subdirectory: String? = nil) -> URL? {
        let fileName = ext.map { $0.isEmpty ? name : "\(name).\($0)" } ?? name
        do {
            let assets = try AnyDynamicObject(className: "aria.skip.AriaAssets")
            // Kotlin reflection can't match a null argument, so "" means no subdirectory.
            guard let path: String = try assets.path(fileName, subdirectory ?? "") else {
                return nil
            }
            return URL(fileURLWithPath: path)
        } catch {
            print("Aria resource \(fileName) unavailable: \(error)")
            return nil
        }
    }
}
#endif
