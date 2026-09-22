import Foundation

struct ProxyObservation: Sendable {
    let requestedModelID: String?
    let responseModelID: String?
    let responseID: String?
    let upstreamHost: String
    let latencyMS: Int
    let observedAt: Date
}

enum ProxyRuntimeState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case failed(String)

    var label: String {
        switch self {
        case .stopped: "未运行"
        case .starting: "正在启动"
        case .running: "运行中"
        case .failed(let message): "启动失败：\(message)"
        }
    }
}
