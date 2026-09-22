import Foundation

enum RouteOriginKind: String, Codable, Sendable {
    case officialSubscription = "official_subscription"
    case officialAPI = "official_api"
    case enterpriseCloud = "enterprise_cloud"
    case managedService = "managed_service"
    case localGateway = "local_gateway"
    case remoteRelay = "remote_relay"
    case localModel = "local_model"
    case unknown

    var label: String {
        switch self {
        case .officialSubscription: "官方个人订阅"
        case .officialAPI: "官方 API"
        case .enterpriseCloud: "企业云"
        case .managedService: "客户端托管"
        case .localGateway: "本地网关"
        case .remoteRelay: "第三方中转"
        case .localModel: "本地模型"
        case .unknown: "来源待确认"
        }
    }
}

enum RouteCredentialKind: String, Codable, Sendable {
    case chatGPTSubscription = "chatgpt_subscription"
    case claudeSubscription = "claude_subscription"
    case copilotSubscription = "copilot_subscription"
    case officialAPIKey = "official_api_key"
    case providerAPIKey = "provider_api_key"
    case relayKey = "relay_key"
    case vendorAccount = "vendor_account"
    case enterpriseIdentity = "enterprise_identity"
    case noAuthentication = "no_authentication"
    case unknown

    var label: String {
        switch self {
        case .chatGPTSubscription: "ChatGPT 个人订阅"
        case .claudeSubscription: "Claude 订阅"
        case .copilotSubscription: "GitHub Copilot"
        case .officialAPIKey: "官方 API Key"
        case .providerAPIKey: "Provider API Key"
        case .relayKey: "中转 / 网关 Key"
        case .vendorAccount: "客户端账号"
        case .enterpriseIdentity: "企业云身份"
        case .noAuthentication: "本地免鉴权"
        case .unknown: "凭据待确认"
        }
    }
}

struct RouteOrigin: Codable, Equatable, Sendable {
    var kind: RouteOriginKind
    var credentialKind: RouteCredentialKind?
    var displayName: String
    var host: String?
    var confidence: Double
    var evidence: [String]

    static let sub2APIPreview = RouteOrigin(
        kind: .remoteRelay,
        credentialKind: .relayKey,
        displayName: "Sub2API（配置声明）",
        host: "relay.example.com",
        confidence: 0.80,
        evidence: ["自定义 API Base URL", "Provider 名称声明为 Sub2API"]
    )
}
