import AppKit
import Foundation

@MainActor
final class ClashMeowAppContext {
    static let shared = ClashMeowAppContext()

    private(set) var appState: AppState?
    private var openMainWindowAction: (() -> Void)?
    private var openAboutWindowAction: (() -> Void)?

    private init() {}

    func attach(appState: AppState) {
        self.appState = appState
    }

    func attachWindowActions(
        openMainWindow: @escaping () -> Void,
        openAboutWindow: @escaping () -> Void
    ) {
        openMainWindowAction = openMainWindow
        openAboutWindowAction = openAboutWindow
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }
        openMainWindowAction?()
    }

    func openAboutWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title.localizedCaseInsensitiveContains("About") }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }
        openAboutWindowAction?()
    }

    func prepareForTermination() async {
        await appState?.prepareForTermination()
    }

    func shutdown() {
        appState?.shutdown()
    }
}
