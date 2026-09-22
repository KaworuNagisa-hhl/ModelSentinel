import Foundation

enum AIClientKind: String, Codable, Sendable {
    case codex
    case chatGPT
    case claudeDesktop
    case claudeCode
    case cursor
    case windsurf
    case visualStudioCode
    case zed
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
        return bundleFragments.contains(where: { bundle.contains($0.lowercased()) }) ||
            nameFragments.contains(where: { name.contains($0.lowercased()) })
    }

    func isRunning(bundleFragments: [String], nameFragments: [String]) -> Bool {
        runningApplications.contains {
            matches($0, bundleFragments: bundleFragments, nameFragments: nameFragments)
        }
    }

    func isFrontmost(bundleFragments: [String], nameFragments: [String]) -> Bool {
        matches(frontmostApplication, bundleFragments: bundleFragments, nameFragments: nameFragments)
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

    var stateLabel: String {
        if isFrontmost { return "当前前台" }
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
