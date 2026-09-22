import AppKit
import Foundation

@MainActor
final class ProxyStore: ObservableObject {
    static let shared = ProxyStore()

    @Published var isEnabled: Bool
    @Published var upstreamBaseURL: String
    @Published var listenPort: Int
    @Published private(set) var runtimeState: ProxyRuntimeState = .stopped
    @Published private(set) var lastObservation: ProxyObservation?
    @Published private(set) var activeProbeState: ActiveProbeState = .idle

    private let proxy = LocalResponseProxy()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "proxy.enabled"
        static let upstream = "proxy.upstreamBaseURL"
        static let port = "proxy.listenPort"
    }

    private init() {
        isEnabled = defaults.bool(forKey: Key.enabled)
        upstreamBaseURL = defaults.string(forKey: Key.upstream) ?? ""
        let savedPort = defaults.integer(forKey: Key.port)
        listenPort = savedPort == 0 ? 8765 : savedPort
    }

    var localBaseURL: String {
        "http://127.0.0.1:\(listenPort)"
    }

    var canStart: Bool {
        validatedUpstreamURL != nil && (1...65_535).contains(listenPort)
    }

    func startIfEnabled() {
        guard isEnabled else { return }
        start()
    }

    func applyAndRestart() {
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(upstreamBaseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.upstream)
        defaults.set(listenPort, forKey: Key.port)
        if isEnabled {
            start()
        } else {
            stop()
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        applyAndRestart()
    }

    func stop() {
        proxy.stop()
        runtimeState = .stopped
    }

    func copyLocalBaseURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(localBaseURL, forType: .string)
    }

    func runActiveProbe() {
        guard activeProbeState != .running else { return }
        activeProbeState = .running
        let modelID = MonitorStore.shared.snapshot.modelDetails?.requestedModelID
        Task {
            do {
                let result = try await ActiveProbeService.shared.run(modelID: modelID)
                activeProbeState = .completed(score: result.score)
                MonitorStore.shared.applyActiveProbeResult(result)
            } catch {
                activeProbeState = .failed(error.localizedDescription)
            }
        }
    }

    private func start() {
        guard let upstream = validatedUpstreamURL else {
            runtimeState = .failed("请填写有效的 HTTP(S) 上游地址")
            return
        }
        guard let port = UInt16(exactly: listenPort) else {
            runtimeState = .failed("监听端口无效")
            return
        }
        do {
            try proxy.start(
                port: port,
                upstreamBaseURL: upstream,
                onState: { state in
                    Task { @MainActor in
                        ProxyStore.shared.runtimeState = state
                    }
                },
                onObservation: { observation in
                    Task { @MainActor in
                        let store = ProxyStore.shared
                        store.lastObservation = observation
                        MonitorStore.shared.applyProxyObservation(observation)
                    }
                }
            )
        } catch {
            runtimeState = .failed(error.localizedDescription)
        }
    }

    private var validatedUpstreamURL: URL? {
        let value = upstreamBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        if ["127.0.0.1", "localhost", "::1"].contains(host.lowercased()),
           (url.port ?? (scheme == "https" ? 443 : 80)) == listenPort {
            return nil
        }
        return url
    }
}
