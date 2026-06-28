import AppKit
import Foundation

@MainActor
private final class TerminationGate {
    private var resumed = false

    func claim() -> Bool {
        guard !resumed else { return false }
        resumed = true
        return true
    }
}

@MainActor
final class ClashMeowAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: ClashMeowStatusItemController?
    private var isPerformingTerminationCleanup = false
    private var didCompleteTerminationCleanup = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLoginManager.bootstrap()
        statusItemController = ClashMeowStatusItemController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.invalidate()
        statusItemController = nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !didCompleteTerminationCleanup else {
            return .terminateNow
        }
        guard !isPerformingTerminationCleanup else {
            return .terminateLater
        }

        isPerformingTerminationCleanup = true
        Task { @MainActor in
            await self.runTerminationCleanupWithTimeout(seconds: 5)
            self.didCompleteTerminationCleanup = true
            self.isPerformingTerminationCleanup = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func runTerminationCleanupWithTimeout(seconds: TimeInterval) async {
        let cleanup = Task { @MainActor in
            await ClashMeowAppContext.shared.prepareForTermination()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = TerminationGate()
            Task { @MainActor in
                _ = await cleanup.value
                if gate.claim() {
                    continuation.resume()
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                if gate.claim() {
                    continuation.resume()
                }
            }
        }
    }
}
