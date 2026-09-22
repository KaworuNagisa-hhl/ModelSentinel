import CoreGraphics

struct IslandDisplayLayout: Equatable {
    var isNotched: Bool
    var compactHeight: CGFloat
    var leftWingWidth: CGFloat
    var notchGapWidth: CGFloat
    var rightWingWidth: CGFloat

    var compactWidth: CGFloat {
        leftWingWidth + notchGapWidth + rightWingWidth
    }

    static let standard = IslandDisplayLayout(
        isNotched: false,
        compactHeight: 32,
        leftWingWidth: 176,
        notchGapWidth: 0,
        rightWingWidth: 0
    )
}
