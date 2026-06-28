import AppKit
import Foundation

@MainActor
final class ClashMeowStatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var iconTimer: Timer?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.toolTip = AppInfo.displayName
        updateStatusIcon()
        startIconObserver()
    }

    func invalidate() {
        iconTimer?.invalidate()
        iconTimer = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateStatusIcon()
        rebuildMenu(menu)
    }

    private var appState: AppState? {
        ClashMeowAppContext.shared.appState
    }

    private func startIconObserver() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusIcon()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        iconTimer = timer
    }

    private func updateStatusIcon() {
        let symbolName: String
        switch appState?.core.status ?? .stopped {
        case .running:
            symbolName = "pawprint.fill"
        case .starting:
            symbolName = "bolt.horizontal.circle"
        case .failed, .missingBinary:
            symbolName = "exclamationmark.triangle"
        case .stopped:
            symbolName = "pawprint"
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: AppInfo.displayName)?
            .withSymbolConfiguration(configuration)
            ?? NSImage(systemSymbolName: "cloud", accessibilityDescription: AppInfo.displayName)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        guard let appState else {
            menu.addItem(disabledItem("\(AppInfo.displayName) 正在启动..."))
            return
        }

        addStatusItems(to: menu, state: appState)
        menu.addItem(.separator())

        menu.addItem(actionItem("打开 \(AppInfo.displayName)", action: #selector(openApp), keyEquivalent: "0"))
        menu.addItem(coreToggleItem(state: appState))

        menu.addItem(.separator())
        menu.addItem(modeSubmenu(state: appState))
        menu.addItem(profilesSubmenu(state: appState))
        menu.addItem(proxyGroupsSubmenu(state: appState))

        menu.addItem(.separator())
        menu.addItem(actionItem("刷新", action: #selector(refreshApp), keyEquivalent: "r"))
        menu.addItem(actionItem("关于 \(AppInfo.displayName)", action: #selector(openAbout)))

        menu.addItem(.separator())
        menu.addItem(actionItem("退出 \(AppInfo.displayName)", action: #selector(quitApp), keyEquivalent: "q"))
    }

    private func addStatusItems(to menu: NSMenu, state: AppState) {
        menu.addItem(disabledItem("内核：\(state.core.status.title)"))
        menu.addItem(disabledItem("配置：\(state.currentProfileName)"))
        menu.addItem(disabledItem("模式：\(state.modeText)"))
        if state.core.status.isHealthy {
            menu.addItem(disabledItem("流量：\(state.trafficText)"))
        }
    }

    private func coreToggleItem(state: AppState) -> NSMenuItem {
        let title = state.core.status.isHealthy ? "停止内核" : "启动内核"
        let item = actionItem(title, action: #selector(toggleCore))
        if case .starting = state.core.status {
            item.isEnabled = false
        }
        if case .missingBinary = state.core.status {
            item.isEnabled = false
        }
        return item
    }

    private func modeSubmenu(state: AppState) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        for mode in MihomoMode.allCases {
            let item = actionItem(mode.title, action: #selector(selectMode(_:)), representedObject: mode.rawValue)
            item.state = state.forwardingMode == mode ? .on : .off
            item.isEnabled = state.core.status.isHealthy && state.forwardingMode != mode
            submenu.addItem(item)
        }

        let item = NSMenuItem(title: "出站模式（\(state.modeText)）", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func profilesSubmenu(state: AppState) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        if state.profiles.isEmpty {
            submenu.addItem(disabledItem("没有配置文件"))
        } else {
            for profile in state.profiles.prefix(8) {
                let item = actionItem(profile.name, action: #selector(selectProfile(_:)), representedObject: profile.id)
                item.state = profile.isCurrent ? .on : .off
                item.isEnabled = !profile.isCurrent
                submenu.addItem(item)
            }
        }

        let item = NSMenuItem(title: "配置文件", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func proxyGroupsSubmenu(state: AppState) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let groups = state.visibleProxyGroups.filter { !$0.all.isEmpty }

        if groups.isEmpty {
            submenu.addItem(disabledItem("没有节点组"))
        } else {
            for group in groups.prefix(6) {
                let groupMenu = NSMenu()
                groupMenu.autoenablesItems = false

                for proxy in group.all.prefix(18) {
                    let selection = ProxySelection(groupID: group.id, proxyName: proxy)
                    let item = actionItem(proxy, action: #selector(selectProxy(_:)), representedObject: selection)
                    item.state = group.now == proxy ? .on : .off
                    item.isEnabled = state.core.status.isHealthy && group.now != proxy
                    groupMenu.addItem(item)
                }

                let item = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
                item.submenu = groupMenu
                submenu.addItem(item)
            }
        }

        let item = NSMenuItem(title: "节点组", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String = "",
        representedObject: Any? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.representedObject = representedObject
        return item
    }

    @objc private func openApp() {
        ClashMeowAppContext.shared.openMainWindow()
    }

    @objc private func toggleCore() {
        guard let appState else { return }
        if appState.core.status.isHealthy {
            appState.disconnect()
        } else {
            appState.connect()
        }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = MihomoMode(rawValue: rawValue) else {
            return
        }
        appState?.setForwardingMode(mode)
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let profile = appState?.profiles.first(where: { $0.id == id }) else {
            return
        }
        Task { await appState?.selectProfile(profile) }
    }

    @objc private func selectProxy(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? ProxySelection else { return }
        Task {
            await appState?.selectProxy(groupID: selection.groupID, proxyName: selection.proxyName)
        }
    }

    @objc private func refreshApp() {
        Task { await appState?.refresh() }
    }

    @objc private func openAbout() {
        ClashMeowAppContext.shared.openAboutWindow()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

private final class ProxySelection: NSObject {
    let groupID: String
    let proxyName: String

    init(groupID: String, proxyName: String) {
        self.groupID = groupID
        self.proxyName = proxyName
    }
}
