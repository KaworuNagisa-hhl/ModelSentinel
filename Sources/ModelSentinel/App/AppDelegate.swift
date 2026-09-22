import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandController: FloatingIslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        islandController = FloatingIslandController(store: .shared)

        if ProcessInfo.processInfo.arguments.contains("--expanded") {
            MonitorStore.shared.showExpanded()
        }

        Task {
            await StatusFileMonitor.shared.start()
            await MainActor.run { MonitorStore.shared.detectRouteOrigin() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
        MonitorStore.shared.detectRouteOrigin()
    }
}
