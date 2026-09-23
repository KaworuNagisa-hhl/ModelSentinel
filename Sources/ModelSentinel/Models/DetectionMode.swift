import Foundation

enum DetectionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case passive
    case active

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passive: "被动检测"
        case .active: "主动监测"
        }
    }

    var compactTitle: String {
        switch self {
        case .passive: "被动"
        case .active: "主动"
        }
    }

    var symbol: String {
        switch self {
        case .passive: "eye"
        case .active: "waveform.path.ecg"
        }
    }

    var summary: String {
        switch self {
        case .passive:
            "只读取本机运行、配置与正常响应证据，不额外消耗模型 Token。"
        case .active:
            "在支持的客户端上额外发起短探针；会计入账号额度或中转站账单。"
        }
    }
}
