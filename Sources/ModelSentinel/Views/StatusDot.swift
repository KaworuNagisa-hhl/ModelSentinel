import SwiftUI

struct StatusDot: View {
    let health: RouteHealth
    var tint: Color? = nil

    @State private var pulse = false

    private var color: Color {
        tint ?? health.color
    }

    var body: some View {
        ZStack {
            if health == .probing || health == .mismatch {
                Circle()
                    .fill(color.opacity(0.28))
                    .frame(width: 18, height: 18)
                    .scaleEffect(pulse ? 1.45 : 0.75)
                    .opacity(pulse ? 0.05 : 0.9)
            }

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.8), radius: 5)
        }
        .frame(width: 20, height: 20)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
