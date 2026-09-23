import SwiftUI

struct MetricBar: View {
    let metric: EvidenceMetric
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(metric.name)
                    .foregroundStyle(.secondary)
                Spacer()
                AnimatedPercentText(value: metric.value)
                    .foregroundStyle(.primary)
            }
            .font(.caption)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.09))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: proxy.size.width * max(0, min(metric.value, 1)))
                        .animation(.easeInOut(duration: 0.65), value: metric.value)
                }
            }
            .frame(height: 5)
        }
    }
}
