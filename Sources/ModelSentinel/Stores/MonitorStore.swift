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
        } else {
            snapshot.note = "已识别 \(route.client.displayName) 配置，等待真实响应验证"
        }
        snapshot.evidence = [
            EvidenceMetric(name: "客户端", value: route.client.isRunning ? 1 : 0.72),
            EvidenceMetric(name: "配置", value: route.client.hasConfiguration ? 1 : 0.55),
            EvidenceMetric(name: "线路", value: route.origin.confidence),
            EvidenceMetric(name: "模型", value: route.modelDetails.responseModelID == nil ? 0 : 1)
        ]
        snapshot.updatedAt = .now
    }

    private func runtimeContext() -> AIClientRuntimeContext {
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications.map {
            RunningApplicationDescriptor(
                bundleIdentifier: $0.bundleIdentifier,
                localizedName: $0.localizedName
            )
        }
        let frontmost = workspace.frontmostApplication.map {
            RunningApplicationDescriptor(
                bundleIdentifier: $0.bundleIdentifier,
                localizedName: $0.localizedName
            )
        }
        return AIClientRuntimeContext(
            runningApplications: running,
            frontmostApplication: frontmost
        )
    }
}
