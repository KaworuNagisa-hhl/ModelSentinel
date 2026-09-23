import Foundation
import Combine
import AppKit

@MainActor
final class MonitorStore: ObservableObject {
    static let shared = MonitorStore()

    @Published var snapshot = RouteSnapshot.initial
    @Published var isExpanded = false
    @Published private(set) var isExpansionPinned = false
    @Published var isVisible = true
    @Published var isWatchingFile = true
    @Published var lastReadError: String?
    @Published var displayLayout = IslandDisplayLayout.standard
    @Published var isDetectingOrigin = false
    @Published private(set) var detectedClients: [AIClientDetection] = []

    private var probeTask: Task<Void, Never>?
    private var detectedRoutes: [ClientRouteDetection] = []
    private var lastActiveProbeResult: ActiveProbeResult?

    private init() {}

    func togglePinnedExpansion() {
        if isExpanded {
            if isExpansionPinned {
                isExpansionPinned = false
                isExpanded = false
            } else {
                isExpansionPinned = true
            }
        } else {
            isExpansionPinned = true
            isExpanded = true
        }
    }

    func showExpanded() {
        isVisible = true
        isExpansionPinned = true
        isExpanded = true
    }

    func runDemoProbe() {
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            guard let self else { return }
            var probing = snapshot
            probing.health = .probing
            probing.confidence = 0.38
            probing.note = "正在采集文本与工具行为探针"
            probing.updatedAt = .now
            snapshot = probing
            isVisible = true

            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            probing.confidence = 0.71
            probing.note = "正在与可信基线进行对比"
            snapshot = probing

            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            snapshot = .preview
        }
    }

    func detectRouteOrigin(preserveLiveEvidence: Bool = false) {
        guard !isDetectingOrigin else { return }
        isDetectingOrigin = true
        let runtime = runtimeContext()
        Task { [weak self] in
            let environment = await RouteOriginDetector.shared.detectEnvironment(runtime: runtime)
            let codexSession = await CodexSessionDetector.shared.latestObservation()
            guard let self else { return }
            detectedRoutes = environment.matches
            detectedClients = environment.matches.map(\.client)
            if let active = environment.active {
                let hasLiveEvidence = (
                    snapshot.modelDetails?.responseModelID != nil || hasFreshActiveProbe
                ) &&
                    snapshot.client?.id == active.client.id
                if !preserveLiveEvidence || !hasLiveEvidence {
                    applyDetectedRoute(active)
                }
                if active.client.kind == .codex, let codexSession {
                    applyCodexSession(codexSession)
                }
            } else {
                snapshot.client = nil
                snapshot.origin = nil
                snapshot.provider = "未检测到支持的 AI 客户端"
                snapshot.health = .offline
                snapshot.confidence = 0
                snapshot.note = "请启动 AI 客户端或检查本机配置"
                snapshot.updatedAt = .now
            }
            isDetectingOrigin = false
        }
    }

    func selectClient(id: String) {
        guard let route = detectedRoutes.first(where: { $0.client.id == id }) else { return }
        applyDetectedRoute(route)
    }

    func simulateMismatch() {
        snapshot = RouteSnapshot(
            client: snapshot.client,
            claimedModel: "GPT-5.6 Codex",
            matchedFamily: "未知 / 较弱模型",
            provider: "Sub2API · 主线路",
            origin: .sub2APIPreview,
            modelDetails: ModelIdentityDetails(
                requestedModelID: "gpt-5.6-codex",
                responseModelID: "gpt-5.1-codex-mini",
                behavioralMatch: "较弱 Codex 变体",
                reasoningEffort: "high",
                wireAPI: "responses",
                providerID: "relay",
                contextWindowTokens: nil
            ),
            health: .mismatch,
            confidence: 0.31,
            latencyMS: 3_840,
            toolAgreement: 0.42,
            textAgreement: 0.36,
            routeChangedAt: .now,
            updatedAt: .now,
            note: "工具选择分布与目标模型明显不一致",
            evidence: [
                EvidenceMetric(name: "工具", value: 0.42),
                EvidenceMetric(name: "文本", value: 0.36),
                EvidenceMetric(name: "协议", value: 0.74),
                EvidenceMetric(name: "稳定", value: 0.29)
            ]
        )
        isVisible = true
        isExpanded = true
    }

    func apply(_ newSnapshot: RouteSnapshot) {
        var mergedSnapshot = newSnapshot
        if mergedSnapshot.client == nil {
            mergedSnapshot.client = snapshot.client
        }
        if mergedSnapshot.origin == nil {
            mergedSnapshot.origin = snapshot.origin
            mergedSnapshot.provider = snapshot.origin?.displayName ?? snapshot.provider
        }
        if mergedSnapshot.modelDetails == nil {
            mergedSnapshot.modelDetails = snapshot.modelDetails
        }
        snapshot = mergedSnapshot
        lastReadError = nil
        if mergedSnapshot.health == .mismatch || mergedSnapshot.health == .warning {
            isVisible = true
            isExpanded = true
        }
    }


    func applyDetectedModelDetails(_ details: ModelIdentityDetails) {
        mergeDetectedModelDetails(details)
        snapshot.updatedAt = .now
    }

    func applyProxyObservation(_ observation: ProxyObservation) {
        var details = snapshot.modelDetails ?? ModelIdentityDetails(
            requestedModelID: observation.requestedModelID,
            responseModelID: observation.responseModelID,
            responseObserved: true,
            behavioralMatch: nil,
            reasoningEffort: nil,
            wireAPI: "responses",
            providerID: snapshot.origin?.host,
            contextWindowTokens: nil
        )
        details.requestedModelID = observation.requestedModelID ?? details.requestedModelID
        details.responseModelID = observation.responseModelID
        details.responseObserved = true
        snapshot.modelDetails = details
        snapshot.latencyMS = observation.latencyMS
        snapshot.updatedAt = observation.observedAt

        guard let requested = details.requestedModelID,
              let returned = details.responseModelID else {
            snapshot.health = .warning
            snapshot.matchedFamily = "真实响应未提供模型声明"
            snapshot.note = "已通过本地代理确认响应 · 上游未返回 model 字段"
            updateResponseEvidence(value: 0.5, name: "声明")
            return
        }

        if Self.modelsAreCompatible(requested: requested, returned: returned) {
            snapshot.health = .verified
            snapshot.matchedFamily = "响应声明与请求模型一致"
            snapshot.note = "本地代理已读取真实响应 · model 声明一致"
            updateResponseEvidence(value: 1, name: "声明")
        } else {
            snapshot.health = .mismatch
            snapshot.matchedFamily = "请求 \(requested) · 返回 \(returned)"
            snapshot.note = "本地代理发现响应 model 与请求不一致"
            snapshot.routeChangedAt = .now
            updateResponseEvidence(value: 0, name: "声明")
            isVisible = true
            isExpanded = true
        }
    }

    func applyActiveProbeResult(_ result: ActiveProbeResult) {
        lastActiveProbeResult = result
        if var details = snapshot.modelDetails {
            details.behavioralMatch = "主动探针 \(result.passedChecks)/\(result.totalChecks)"
            snapshot.modelDetails = details
        }
        snapshot.toolAgreement = result.score
        snapshot.textAgreement = result.score
        snapshot.updatedAt = result.completedAt
        snapshot.latencyMS = result.durationMS
        updateResponseEvidence(value: result.score, name: "行为")

        if result.score == 1 {
            if snapshot.modelDetails?.responseModelID == nil {
                snapshot.health = .warning
                snapshot.note = "主动行为探针全部通过 · 服务端身份仍无直接证明"
            } else if snapshot.health != .mismatch {
                snapshot.health = .verified
                snapshot.note = "响应 model 声明一致 · 主动行为探针全部通过"
            }
        } else {
            snapshot.health = .warning
            snapshot.note = "主动行为探针仅通过 \(result.passedChecks)/\(result.totalChecks) · 建议复测"
            isVisible = true
            isExpanded = true
        }
    }

    private func mergeDetectedModelDetails(_ details: ModelIdentityDetails) {
        var merged = snapshot.modelDetails ?? details
        merged.requestedModelID = details.requestedModelID ?? merged.requestedModelID
        merged.reasoningEffort = details.reasoningEffort ?? merged.reasoningEffort
        merged.wireAPI = details.wireAPI ?? merged.wireAPI
        merged.providerID = details.providerID ?? merged.providerID
        merged.behavioralMatch = merged.behavioralMatch ?? snapshot.matchedFamily
        snapshot.modelDetails = merged

        if let requestedModelID = merged.requestedModelID {
            snapshot.claimedModel = requestedModelID
        }
    }

    private func updateResponseEvidence(value: Double, name: String) {
        if snapshot.evidence.indices.contains(3) {
            snapshot.evidence[3] = EvidenceMetric(name: name, value: value)
        }
    }

    private static func normalizedModelID(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "_", with: "-")
    }

    private static func modelsAreCompatible(requested: String, returned: String) -> Bool {
        let requested = normalizedModelID(requested)
        let returned = normalizedModelID(returned)
        if requested == returned { return true }

        let snapshotSuffix = /^-(?:20\d{2})-\d{2}-\d{2}$/
        if returned.hasPrefix(requested) {
            return returned.dropFirst(requested.count).wholeMatch(of: snapshotSuffix) != nil
        }
        if requested.hasPrefix(returned) {
            return requested.dropFirst(returned.count).wholeMatch(of: snapshotSuffix) != nil
        }
        return false
    }

    private var hasFreshActiveProbe: Bool {
        guard let result = lastActiveProbeResult else { return false }
        return Date().timeIntervalSince(result.completedAt) < 30 * 60
    }

    private func applyDetectedRoute(_ route: ClientRouteDetection) {
        snapshot.client = route.client
        snapshot.origin = route.origin
        snapshot.provider = route.origin.displayName
        snapshot.modelDetails = route.modelDetails
        snapshot.claimedModel = route.modelDetails.requestedModelID ?? "等待会话模型"
        snapshot.matchedFamily = route.modelDetails.behavioralMatch ?? "等待响应证据"
        snapshot.health = .configured
        snapshot.confidence = route.origin.confidence
        snapshot.latencyMS = 0
        snapshot.toolAgreement = 0
        snapshot.textAgreement = 0
        if let processID = route.client.processID {
            let host = route.client.hostApplication.map { " · \($0)" } ?? ""
            snapshot.note = "CLI 运行中 · PID \(processID)\(host)，等待响应验证"
        } else if route.client.isFrontmost {
            snapshot.note = "\(route.client.displayName) 当前位于前台 · 尚未观察到 AI 请求"
        } else if route.client.isRunning {
            snapshot.note = "\(route.client.displayName) 正在后台运行 · 等待首个 AI 请求"
        } else {
            snapshot.note = "已识别 \(route.client.displayName) 配置，等待真实响应验证"
        }
        snapshot.evidence = [
            EvidenceMetric(name: route.client.isRunning ? "运行" : "客户端", value: route.client.isRunning ? 1 : 0.72),
            EvidenceMetric(name: "配置", value: route.client.hasConfiguration ? 1 : 0.55),
            EvidenceMetric(name: "来源", value: route.origin.confidence),
            EvidenceMetric(name: "模型", value: route.modelDetails.responseModelID == nil ? 0 : 1)
        ]
        snapshot.updatedAt = .now
    }

    private func applyCodexSession(_ observation: CodexSessionObservation) {
        guard snapshot.client?.kind == .codex else { return }
        let hasProxyModelEvidence = snapshot.modelDetails?.responseModelID != nil
        if let probe = lastActiveProbeResult,
           let probedModel = probe.modelID,
           let currentModel = observation.modelID,
           Self.normalizedModelID(probedModel) != Self.normalizedModelID(currentModel) {
            lastActiveProbeResult = nil
        }
        if var details = snapshot.modelDetails {
            details.requestedModelID = observation.modelID ?? details.requestedModelID
            details.reasoningEffort = observation.reasoningEffort ?? details.reasoningEffort
            details.contextWindowTokens = observation.contextWindowTokens ?? details.contextWindowTokens
            details.responseObserved = observation.hasResponseEvidence
            snapshot.modelDetails = details
        }
        if let modelID = observation.modelID {
            snapshot.claimedModel = modelID
        }
        if hasProxyModelEvidence || hasFreshActiveProbe {
            snapshot.updatedAt = observation.updatedAt
            return
        }
        if observation.hasResponseEvidence {
            snapshot.health = .configured
            snapshot.matchedFamily = "真实响应已确认 · 服务端未提供模型字段"
            snapshot.note = observation.isTaskActive
                ? "最近一轮响应已确认 · 当前请求继续采集"
                : "最近一轮响应已确认 · 服务端未提供模型字段"
        } else if observation.isTaskActive {
            snapshot.health = .probing
            snapshot.matchedFamily = "正在采集首轮响应证据"
            snapshot.note = "Codex 正在处理请求 · 自动验证会话模型 \(observation.modelID ?? "待识别")"
        } else {
            snapshot.health = .configured
            snapshot.note = "Codex 正在运行 · 等待下一次请求自动验证"
        }
        if snapshot.evidence.indices.contains(3) {
            snapshot.evidence[3] = EvidenceMetric(
                name: "响应",
                value: observation.hasResponseEvidence ? 1 : (observation.isTaskActive ? 0.5 : 0)
            )
        }
        snapshot.updatedAt = observation.updatedAt
    }

    private func runtimeContext() -> AIClientRuntimeContext {
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications.map {
            RunningApplicationDescriptor(
                bundleIdentifier: $0.bundleIdentifier,
                localizedName: $0.localizedName
            )
        }.filter(isRelevantRuntimeApplication)
        let frontmost = workspace.frontmostApplication.map {
            RunningApplicationDescriptor(
                bundleIdentifier: $0.bundleIdentifier,
                localizedName: $0.localizedName
            )
        }.flatMap { isRelevantRuntimeApplication($0) ? $0 : nil }
        return AIClientRuntimeContext(
            runningApplications: running,
            frontmostApplication: frontmost
        )
    }

    private func isRelevantRuntimeApplication(_ application: RunningApplicationDescriptor) -> Bool {
        let bundle = application.bundleIdentifier?.lowercased() ?? ""
        let name = application.localizedName?.lowercased() ?? ""
        let supportedBundleIdentifiers = [
            "com.openai.codex", "com.openai.chat", "com.openai.chatgpt",
            "com.anthropic.claudefordesktop",
            "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
            "com.microsoft.vscode", "dev.zed.zed",
            "com.qoder.app",
            "com.apple.terminal", "com.googlecode.iterm2", "dev.warp.warp-stable",
            "com.google.android.studio", "com.huawei.devecostudio.ds", "com.jetbrains.intellij"
        ]
        let supportedNames = [
            "codex", "chatgpt", "claude", "cursor", "windsurf", "zed",
            "visual studio code", "code", "terminal", "iterm2", "warp",
            "android studio", "deveco studio", "intellij idea", "qoder"
        ]
        return supportedBundleIdentifiers.contains(bundle) || supportedNames.contains(name)
    }
}
