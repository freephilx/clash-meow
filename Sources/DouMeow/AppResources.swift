import Foundation

enum AppResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    static func url(forResource name: String, withExtension ext: String?) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }
}
