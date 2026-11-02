import SwiftUI

/// 轻按时纸面向内倾斜，释放后回到原位；不改变控件命中区。
struct DepthPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .rotation3DEffect(
                .degrees(configuration.isPressed && !reduceMotion ? 5 : 0),
                axis: (x: 1, y: -0.35, z: 0), perspective: 0.45
            )
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.74), value: configuration.isPressed)
    }
}
