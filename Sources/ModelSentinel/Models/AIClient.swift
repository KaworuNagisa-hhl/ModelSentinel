import Foundation

enum AIClientKind: String, Codable, Sendable {
    case codex
    case chatGPT
    case claudeDesktop
    case claudeCode
    case geminiCLI
    case aider
    case openCode
    case amp
    case qwenCode
    case cursor
    case windsurf
    case visualStudioCode
    case zed
    case qoder
}

enum AIClientSurface: String, Codable, Sendable {
    case desktopApp = "desktop_app"
    case commandLine = "command_line"
    case ide

    var label: String {
        switch self {
        case .desktopApp: "桌面客户端"
        case .commandLine: "命令行工具"
        case .ide: "IDE"
        }
    }
}

struct RunningApplicationDescriptor: Sendable {
    let bundleIdentifier: String?
    let localizedName: String?
}

struct AIClientRuntimeContext: Sendable {
    let runningApplications: [RunningApplicationDescriptor]
    let frontmostApplication: RunningApplicationDescriptor?

    func matches(
        _ application: RunningApplicationDescriptor?,
        bundleFragments: [String],
        nameFragments: [String]
    ) -> Bool {
        guard let application else { return false }
        let bundle = application.bundleIdentifier?.lowercased() ?? ""
        let name = application.localizedName?.lowercased() ?? ""
        if !bundle.isEmpty {
            return bundleFragments.contains(where: { bundle == $0.lowercased() })
        }
        return nameFragments.contains(where: { name == $0.lowercased() })
    }

    func isRunning(bundleFragments: [String], nameFragments: [String]) -> Bool {
        runningApplications.contains {
            matches($0, bundleFragments: bundleFragments, nameFragments: nameFragments)
        }
    }

    func isFrontmost(bundleFragments: [String], nameFragments: [String]) -> Bool {
        matches(frontmostApplication, bundleFragments: bundleFragments, nameFragments: nameFragments)
    }

    func isFrontmostHost(_ hostName: String?) -> Bool {
        guard let hostName, let frontmostApplication else { return false }
        let frontmostName = frontmostApplication.localizedName?.lowercased() ?? ""
        let frontmostBundle = frontmostApplication.bundleIdentifier?.lowercased() ?? ""
        let host = hostName.lowercased()
        return (!frontmostName.isEmpty && (frontmostName.contains(host) || host.contains(frontmostName))) ||
            frontmostBundle.contains(host.replacingOccurrences(of: " ", with: ""))
    }
}

struct AIClientDetection: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let kind: AIClientKind
    let displayName: String
    let surface: AIClientSurface
    let isInstalled: Bool
    let isRunning: Bool
    let isFrontmost: Bool
    let hasConfiguration: Bool
    let integrations: [String]
    let evidence: [String]
    var processID: Int? = nil
    var hostApplication: String? = nil

    var stateLabel: String {
        if isFrontmost, surface == .commandLine { return "当前终端会话" }
        if isFrontmost { return "当前前台" }
        if isRunning, surface == .commandLine { return "CLI 正在运行" }
        if isRunning { return "正在运行" }
        if hasConfiguration { return "已发现配置" }
        return "已安装"
    }
}

struct ClientRouteDetection: Sendable {
    let client: AIClientDetection
    let origin: RouteOrigin
    let modelDetails: ModelIdentityDetails
}

struct ClientEnvironmentDetection: Sendable {
    let matches: [ClientRouteDetection]
    let active: ClientRouteDetection?
}
