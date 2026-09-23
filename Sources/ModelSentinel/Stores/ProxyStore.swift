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
    private let activeProbeCooldown: TimeInterval = 6 * 60 * 60

    private enum Key {
        static let enabled = "proxy.enabled"
        static let upstream = "proxy.upstreamBaseURL"
        static let port = "proxy.listenPort"
        static let lastAutomaticProbeKey = "probe.lastAutomaticKey"
        static let lastAutomaticProbeAt = "probe.lastAutomaticAt"
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

    func runActiveProbeNow() {
        let snapshot = MonitorStore.shared.snapshot
        if supportsActiveProbe(snapshot: snapshot) {
            recordAutomaticProbeAttempt(snapshot: snapshot)
        }
        runActiveProbe(snapshot: snapshot)
    }

    func considerActiveMonitoring(snapshot: RouteSnapshot) {
        guard MonitorStore.shared.detectionMode == .active,
              activeProbeState != .running,
              supportsActiveProbe(snapshot: snapshot),
              snapshot.modelDetails?.responseModelID == nil else { return }

        let key = activeProbeKey(snapshot: snapshot)
        let lastKey = defaults.string(forKey: Key.lastAutomaticProbeKey)
        let lastDate = defaults.object(forKey: Key.lastAutomaticProbeAt) as? Date
        if lastKey == key,
           let lastDate,
           Date().timeIntervalSince(lastDate) < activeProbeCooldown {
            return
        }

        recordAutomaticProbeAttempt(snapshot: snapshot)
        runActiveProbe(snapshot: snapshot)
    }

    func supportsActiveProbe(snapshot: RouteSnapshot) -> Bool {
        snapshot.client?.kind == .codex
    }

    func activeProbeAvailability(snapshot: RouteSnapshot) -> String {
        if supportsActiveProbe(snapshot: snapshot) {
            return "当前 Codex 支持主动探针"
        }
        if let client = snapshot.client?.displayName {
            return "\(client) 暂不支持独立主动探针"
        }
        return "请先启动受支持的客户端"
    }

    private func runActiveProbe(snapshot: RouteSnapshot) {
        guard activeProbeState != .running else { return }
        guard supportsActiveProbe(snapshot: snapshot) else {
            activeProbeState = .failed(activeProbeAvailability(snapshot: snapshot))
            return
        }
        activeProbeState = .running
        let modelID = snapshot.modelDetails?.requestedModelID
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

    private func activeProbeKey(snapshot: RouteSnapshot) -> String {
        let client = snapshot.client?.id ?? "unknown"
        let model = snapshot.modelDetails?.requestedModelID ?? snapshot.claimedModel
        let route = snapshot.origin?.host ?? snapshot.origin?.displayName ?? snapshot.provider
        return [client, model, route].joined(separator: "|").lowercased()
    }

    private func recordAutomaticProbeAttempt(snapshot: RouteSnapshot) {
        defaults.set(activeProbeKey(snapshot: snapshot), forKey: Key.lastAutomaticProbeKey)
        defaults.set(Date(), forKey: Key.lastAutomaticProbeAt)
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
