import Foundation

struct ActiveProbeResult: Sendable {
    let modelID: String?
    let passedChecks: Int
    let totalChecks: Int
    let durationMS: Int
    let completedAt: Date

    var score: Double {
        guard totalChecks > 0 else { return 0 }
        return Double(passedChecks) / Double(totalChecks)
    }
}

enum ActiveProbeState: Equatable, Sendable {
    case idle
    case running
    case completed(score: Double)
    case failed(String)

    var label: String {
        switch self {
        case .idle: "尚未运行"
        case .running: "正在运行"
        case .completed(let score): "已完成 · \(score.percentText)"
        case .failed(let message): "失败：\(message)"
        }
    }
}
