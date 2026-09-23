import Foundation

enum RouteHealth: String, Codable, CaseIterable, Sendable {
    case configured
    case verified
    case probing
    case warning
    case mismatch
    case offline

    var label: String {
        switch self {
        case .configured: "配置已识别"
        case .verified: "线路可信"
        case .probing: "正在验证"
        case .warning: "能力波动"
        case .mismatch: "疑似降级"
        case .offline: "线路离线"
        }
    }
}

struct EvidenceMetric: Identifiable, Codable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let value: Double
}

struct ModelIdentityDetails: Codable, Equatable, Sendable {
    var requestedModelID: String?
    var responseModelID: String?
    var responseObserved: Bool? = nil
    var behavioralMatch: String?
    var reasoningEffort: String?
    var wireAPI: String?
    var providerID: String?
    var contextWindowTokens: Int?
}

struct RouteSnapshot: Codable, Equatable, Sendable {
    var client: AIClientDetection?
    var claimedModel: String
    var matchedFamily: String
    var provider: String
    var origin: RouteOrigin?
    var modelDetails: ModelIdentityDetails?
    var health: RouteHealth
    var confidence: Double
    var latencyMS: Int
    var toolAgreement: Double
    var textAgreement: Double
    var routeChangedAt: Date?
    var updatedAt: Date
    var note: String
    var evidence: [EvidenceMetric]

    static let initial = RouteSnapshot(
        client: nil,
        claimedModel: "正在扫描",
        matchedFamily: "等待响应证据",
        provider: "正在识别 AI 客户端",
        origin: nil,
        modelDetails: nil,
        health: .probing,
        confidence: 0,
        latencyMS: 0,
        toolAgreement: 0,
        textAgreement: 0,
        routeChangedAt: nil,
        updatedAt: .now,
        note: "正在扫描桌面客户端、IDE 与 CLI",
        evidence: [
            EvidenceMetric(name: "客户端", value: 0),
            EvidenceMetric(name: "配置", value: 0),
            EvidenceMetric(name: "来源", value: 0),
            EvidenceMetric(name: "模型", value: 0)
        ]
    )

    static let preview = RouteSnapshot(
        client: AIClientDetection(
            id: "codex",
            kind: .codex,
            displayName: "Codex",
            surface: .desktopApp,
            isInstalled: true,
            isRunning: true,
            isFrontmost: true,
            hasConfiguration: true,
            integrations: [],
            evidence: ["检测到 Codex 客户端"]
        ),
        claimedModel: "GPT-5.6 Codex",
        matchedFamily: "GPT-5.x Codex",
        provider: "Sub2API · 主线路",
        origin: .sub2APIPreview,
        modelDetails: ModelIdentityDetails(
            requestedModelID: "gpt-5.6-codex",
            responseModelID: nil,
            behavioralMatch: "GPT-5.x Codex",
            reasoningEffort: "high",
            wireAPI: "responses",
            providerID: "openai",
            contextWindowTokens: nil
        ),
        health: .verified,
        confidence: 0.92,
        latencyMS: 1_240,
        toolAgreement: 0.96,
        textAgreement: 0.88,
        routeChangedAt: nil,
        updatedAt: .now,
        note: "工具行为与可信基线一致",
        evidence: [
            EvidenceMetric(name: "工具", value: 0.96),
            EvidenceMetric(name: "文本", value: 0.88),
            EvidenceMetric(name: "协议", value: 1.0),
            EvidenceMetric(name: "稳定", value: 0.91)
        ]
    )
}
