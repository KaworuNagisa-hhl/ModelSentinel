import Foundation
import Combine
import AppKit

@MainActor
final class MonitorStore: ObservableObject {
    static let shared = MonitorStore()

    @Published var snapshot = RouteSnapshot.initial
    @Published var isExpanded = false
    @Published var isVisible = true
    @Published var isWatchingFile = true
    @Published var lastReadError: String?
    @Published var displayLayout = IslandDisplayLayout.standard
    @Published var isDetectingOrigin = false
    @Published private(set) var detectedClients: [AIClientDetection] = []

    private var probeTask: Task<Void, Never>?
    private var detectedRoutes: [ClientRouteDetection] = []

    private init() {}

    func toggleExpanded() {
        isExpanded.toggle()
    }

    func showExpanded() {
        isVisible = true
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
                let hasLiveEvidence = snapshot.health == .verified &&
                    snapshot.modelDetails?.responseModelID != nil &&
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
        } else if route.client.isRunning {
            snapshot.note = "已检测到 \(route.client.displayName) 正在运行，等待首个响应验证"
        } else {
            snapshot.note = "已识别 \(route.client.displayName) 配置，等待真实响应验证"
        }
        snapshot.evidence = [
            EvidenceMetric(name: route.client.isRunning ? "运行" : "客户端", value: route.client.isRunning ? 1 : 0.72),
            EvidenceMetric(name: "配置", value: route.client.hasConfiguration ? 1 : 0.55),
            EvidenceMetric(name: "线路", value: route.origin.confidence),
            EvidenceMetric(name: "模型", value: route.modelDetails.responseModelID == nil ? 0 : 1)
        ]
        snapshot.updatedAt = .now
    }

    private func applyCodexSession(_ observation: CodexSessionObservation) {
        guard snapshot.client?.kind == .codex else { return }
        if var details = snapshot.modelDetails {
            details.requestedModelID = observation.modelID ?? details.requestedModelID
            details.reasoningEffort = observation.reasoningEffort ?? details.reasoningEffort
            details.contextWindowTokens = observation.contextWindowTokens ?? details.contextWindowTokens
            snapshot.modelDetails = details
        }
        if let modelID = observation.modelID {
            snapshot.claimedModel = modelID
        }
        snapshot.note = observation.isTaskActive
            ? "Codex 正在处理请求 · 会话模型 \(observation.modelID ?? "待识别")"
            : "Codex 正在运行 · 最近会话模型 \(observation.modelID ?? "待识别")"
        if snapshot.evidence.indices.contains(3) {
            snapshot.evidence[3] = EvidenceMetric(
                name: "会话",
                value: observation.modelID == nil ? 0 : 1
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
            "com.apple.terminal", "com.googlecode.iterm2", "dev.warp.warp-stable",
            "com.google.android.studio", "com.huawei.devecostudio.ds", "com.jetbrains.intellij"
        ]
        let supportedNames = [
            "codex", "chatgpt", "claude", "cursor", "windsurf", "zed",
            "visual studio code", "code", "terminal", "iterm2", "warp",
            "android studio", "deveco studio", "intellij idea"
        ]
        return supportedBundleIdentifiers.contains(bundle) || supportedNames.contains(name)
    }
}
