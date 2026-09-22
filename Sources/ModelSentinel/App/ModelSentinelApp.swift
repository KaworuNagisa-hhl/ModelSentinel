import SwiftUI

@main
struct ModelSentinelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MonitorStore.shared

    var body: some Scene {
        MenuBarExtra {
            Button("展开状态岛") {
                store.showExpanded()
                appDelegate.showIsland()
            }

            Button("运行演示探针") {
                store.runDemoProbe()
                appDelegate.showIsland()
            }

            Button(store.isDetectingOrigin ? "正在扫描 AI 客户端…" : "重新扫描 AI 客户端") {
                store.detectRouteOrigin()
                appDelegate.showIsland()
            }
            .disabled(store.isDetectingOrigin)

            if !store.detectedClients.isEmpty {
                Divider()
                Text("检测到的客户端")
                ForEach(store.detectedClients) { client in
                    Button {
                        store.selectClient(id: client.id)
                        appDelegate.showIsland()
                    } label: {
                        HStack {
                            Text("\(client.displayName) · \(client.stateLabel)")
                            if store.snapshot.client?.id == client.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Button("模拟线路降级") {
                store.simulateMismatch()
                appDelegate.showIsland()
            }

            Divider()

            Toggle("监听本地状态文件", isOn: $store.isWatchingFile)

            Text("客户端：\(store.snapshot.client?.displayName ?? "待识别")")
            Text("来源：\(store.snapshot.origin?.displayName ?? "待识别")")

            if let error = store.lastReadError {
                Text("状态文件错误：\(error)")
            }

            Divider()

            Button(store.isVisible ? "隐藏状态岛" : "显示状态岛") {
                store.isVisible.toggle()
                appDelegate.refreshIsland()
            }

            Button("退出 ModelSentinel") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: store.snapshot.health.symbol)
        }
        .menuBarExtraStyle(.menu)
    }
}
