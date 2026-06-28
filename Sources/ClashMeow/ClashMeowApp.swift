import SwiftUI

@main
struct ClashMeowApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(ClashMeowAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            AppRootView(appState: appState)
        }
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppInfo.displayName)") {
                    ClashMeowAppContext.shared.openAboutWindow()
                }
            }

            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }

        Window("About \(AppInfo.displayName)", id: "about") {
            AboutPanelView()
                .environmentObject(appState)
        }
        .defaultSize(width: 360, height: 260)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

private struct AppRootView: View {
    @Environment(\.openWindow) private var openWindow

    let appState: AppState

    var body: some View {
        RootView()
            .environmentObject(appState)
            .frame(minWidth: 820, minHeight: 560)
            .background(WindowTitleConfigurator())
            .task {
                ClashMeowAppContext.shared.attach(appState: appState)
                ClashMeowAppContext.shared.attachWindowActions {
                    openWindow(id: "main")
                } openAboutWindow: {
                    openWindow(id: "about")
                }
                await appState.bootstrap()
                if ModeSwitchSelfTest.isEnabled {
                    let passed = await ModeSwitchSelfTest.run(state: appState)
                    appState.disconnect(recordPreference: false)
                    exit(passed ? 0 : 1)
                }
                if let url = DashboardDemoMode.screenshotURL {
                    let exported = DashboardDemoMode.exportRenderedScreenshot(to: url, state: appState)
                    exit(exported ? 0 : 1)
                }
            }
    }
}

private struct AboutPanelView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(AppInfo.displayName)
                .font(.system(size: 22, weight: .bold))

            Text(appState.version?.version.map { "内核 \($0)" } ?? "网络内核")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("网络工具与配置管理")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WindowTitleConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window, retry: true)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window, retry: true)
        }
    }

    private func configure(_ window: NSWindow?, retry: Bool = false) {
        window?.title = ""
        window?.titleVisibility = .hidden

        if retry {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                configure(window)
            }
        }
    }
}
