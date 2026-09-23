import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandController: FloatingIslandController?
    private var runtimeScanTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        islandController = FloatingIslandController(store: .shared)

        if ProcessInfo.processInfo.arguments.contains("--expanded") {
            MonitorStore.shared.showExpanded()
        }

        Task {
            await StatusFileMonitor.shared.start()
            await MainActor.run {
                ProxyStore.shared.startIfEnabled()
                MonitorStore.shared.detectRouteOrigin()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        runtimeScanTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                MonitorStore.shared.detectRouteOrigin(preserveLiveEvidence: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        runtimeScanTask?.cancel()
        ProxyStore.shared.stop()
        Task {
            await StatusFileMonitor.shared.stop()
        }
    }

    func showIsland() {
        islandController?.show()
    }

    func hideIsland() {
        islandController?.hide()
    }

    func refreshIsland() {
        islandController?.refresh()
    }

    @objc private func activeApplicationChanged(_ notification: Notification) {
        MonitorStore.shared.detectRouteOrigin(preserveLiveEvidence: true)
    }
}
