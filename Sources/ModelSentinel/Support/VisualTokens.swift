import SwiftUI

extension RouteHealth {
    var color: Color {
        switch self {
        case .configured: .blue
        case .verified: .green
        case .probing: .cyan
        case .warning: .yellow
        case .mismatch: .red
        case .offline: .gray
        }
    }

    var symbol: String {
        switch self {
        case .configured: "shield.lefthalf.filled"
        case .verified: "checkmark.shield.fill"
        case .probing: "waveform.path.ecg"
        case .warning: "exclamationmark.triangle.fill"
        case .mismatch: "arrow.triangle.branch"
        case .offline: "wifi.slash"
        }
    }
}

extension Double {
    var percentText: String {
        "\(Int((self * 100).rounded()))%"
    }
}
