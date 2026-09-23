import SwiftUI

struct AnimatedPercentText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double
    var duration: Double = 0.65

    @State private var displayedValue = 0.0

    var body: some View {
        InterpolatingPercentText(value: displayedValue)
            .monospacedDigit()
            .animation(
                reduceMotion ? nil : .easeInOut(duration: duration),
                value: displayedValue
            )
            .onAppear {
                displayedValue = normalizedValue
            }
            .onChange(of: value) { _, _ in
                displayedValue = normalizedValue
            }
            .accessibilityLabel(value.percentText)
    }

    private var normalizedValue: Double {
        max(0, min(value, 1))
    }
}

private struct InterpolatingPercentText: View, @MainActor Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(value.percentText)
    }
}
